// cdenv - environment.rs
//
// Copyright (C) 2021  Lars Gustäbel <lars@gustaebel.de>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

use std::io::{self, BufRead, BufReader};
use std::collections::HashMap;
use std::fs::File;
use std::fs::OpenOptions;
use std::io::prelude::*;

use regex::{Regex,Captures};

const EXCLUDE_VARS: &[&str] = &["_", "OLDPWD"];

enum LineState {
    Default,
    InVariableDef,
    InArrayDef,
    InFunctionDef
}

enum NameType {
    Variable,
    Function,
    Alias
}

// Parse and compare two sets of shell environments.
pub fn compare_environments(input: &str, restore: &str) {
    let mut vars_a: HashMap<String, String> = HashMap::new();
    let mut funcs_a: HashMap<String, String> = HashMap::new();
    let mut alias_a: HashMap<String, String> = HashMap::new();

    let mut vars_b: HashMap<String, String> = HashMap::new();
    let mut funcs_b: HashMap<String, String> = HashMap::new();
    let mut alias_b: HashMap<String, String> = HashMap::new();

    parse_environment(Some(input), &mut vars_a, &mut funcs_a, &mut alias_a);
    parse_environment(None, &mut vars_b, &mut funcs_b, &mut alias_b);

    // We open the restore file in append mode, so that e.g. the on_leave()
    // stdlib function can put code in it in advance.
    let mut restore_file = OpenOptions::new().append(true).create(true).open(restore).unwrap();

    // Remove some names from the environment.
    prune_unwanted_names(EXCLUDE_VARS, &mut vars_a);
    prune_unwanted_names(EXCLUDE_VARS, &mut vars_b);

    // Compare the vars, funcs and alias sets and write statements to stdout
    // and the restore file.
    compare_sets(&vars_a, &vars_b, &mut restore_file, NameType::Variable);
    compare_sets(&funcs_a, &funcs_b, &mut restore_file, NameType::Function);
    compare_sets(&alias_a, &alias_b, &mut restore_file, NameType::Alias);

}

// Remove a set of names from the environment that change uncontrollably between invocations or
// that are not wanted in the result.
fn prune_unwanted_names(exclude: &'static [&'static str], set: &mut HashMap<String, String>) {
    for key in exclude {
        if set.contains_key(&key.to_string()) {
            set.remove(&key.to_string());
        }
    }
}

// Parse output of { declare -p; declare -f; alias; }.
// Notes:
// Here we create shell code that is later used to be sourced to restore the environment
// prior to the changes. Because we source this code inside the c.load function we
// have to add -g explicitly to declare all variables global.
fn parse_environment(input: Option<&str>, set_var: &mut HashMap<String, String>,
                     set_func: &mut HashMap<String, String>, set_alias: &mut HashMap<String, String>) {
    let re_declare = Regex::new("^declare\\s+-+([iaAfxr]*)\\s+([a-zA-Z_][a-zA-Z0-9_]*)$").unwrap();
    let re_var_start = Regex::new("^declare\\s+-+([ixr]*)\\s+([a-zA-Z_][a-zA-Z0-9_]*)=\"(.*)$").unwrap();
    let re_array_start = Regex::new("^declare\\s+-([aAxr]+)\\s+([a-zA-Z_][a-zA-Z0-9_]*)=\\((.*)$").unwrap();
    let re_function_start = Regex::new("^([a-zA-Z0-9_\\-:.]+)\\s*\\(\\)\\s*$").unwrap();
    let re_function_end = Regex::new("^}\\s*$").unwrap();
    let re_alias = Regex::new("^alias\\s+([a-zA-Z_][a-zA-Z0-9_\\-]*)='(.*)'$").unwrap();

    let mut line_state = LineState::Default;
    let mut name = String::new();
    let mut body = String::new();

    let reader: Box<dyn BufRead> = match input {
        None => Box::new(BufReader::new(io::stdin())),
        Some(filename) => Box::new(BufReader::new(File::open(filename).unwrap()))
    };

    let lines = reader.lines();

    fn get_group(groups: &Captures, group: usize) -> String {
        groups.get(group).unwrap().as_str().to_string()
    }

    for line in lines {
        let mut line = line.unwrap().trim_end().to_string();

        if let Some(groups) = re_declare.captures(&line) {
            let opts = get_group(&groups, 1);
            name = get_group(&groups, 2);
            set_var.insert(name.clone(), format!("declare -g{} {}\n", opts, name));

        } else if let Some(groups) = re_var_start.captures(&line) {
            let opts = get_group(&groups, 1);
            name = get_group(&groups, 2);
            let value = get_group(&groups, 3);
            if name == "BASHOPTS" || name == "SHELLOPTS" {
                set_var.insert(name.clone(), value[..value.len()-1].to_string());
                line_state = LineState::Default;
            } else {
                line = format!("declare -g{} {}=\"{}\n", opts, name, value);
                if value.ends_with('"') && !value.ends_with("\\\"") {
                    set_var.insert(name.clone(), line);
                    line_state = LineState::Default;
                } else {
                    body.push_str(&line);
                    line_state = LineState::InVariableDef;
                }
            }

        } else if let Some(groups) = re_array_start.captures(&line) {
            let opts = get_group(&groups, 1);
            name = get_group(&groups, 2);
            let value = get_group(&groups, 3);
            line = format!("declare -g{} {}=({}\n", opts, name, value);
            if value.ends_with(')') && !value.ends_with("\\)") {
                set_var.insert(name.clone(), line);
                line_state = LineState::Default;
            } else {
                body.push_str(&line);
                line_state = LineState::InArrayDef;
            }

        } else if let Some(groups) = re_function_start.captures(&line) {
            // Parse the first line of a function definition.
            name = get_group(&groups, 1);
            body.push_str(&line);
            body.push('\n');
            line_state = LineState::InFunctionDef;

        } else if let Some(groups) = re_alias.captures(&line) {
            name = get_group(&groups, 1);
            body = get_group(&groups, 2);
            set_alias.insert(name.clone(), format!("alias {}='{}'\n", name, body));

        } else if re_function_end.is_match(&line) {
            // Parse the terminating line of a function definition.
            body.push_str(&line);
            body.push('\n');
            set_func.insert(name.clone(), body.clone());
            body.clear();
            line_state = LineState::Default;

        } else {
            match line_state {
                LineState::InVariableDef => {
                    // Collect the lines of a multiline variable.
                    body.push_str(&line);
                    body.push('\n');
                    if line.ends_with('"') && !line.ends_with("\\\"") {
                        set_var.insert(name.clone(), body.clone());
                        body.clear();
                        line_state = LineState::Default;
                    }
                },
                LineState::InArrayDef => {
                    // Collect the lines of a multiline variable.
                    body.push_str(&line);
                    body.push('\n');
                    if line.ends_with(')') && !line.ends_with("\\)") {
                        set_var.insert(name.clone(), body.clone());
                        body.clear();
                        line_state = LineState::Default;
                    }
                },
                LineState::InFunctionDef => {
                    // Collect the lines in the function body.
                    body.push_str(&line);
                    body.push('\n');
                },
                LineState::Default => {
                    let mut line = line.trim_end().to_string();
                    // Escape backslashes.
                    line = line.replace("\\", "\\\\");
                    // You can't use a single quote in a single-quoted string even if it is
                    // escaped with a backslash. The work-around is to close the single-quoted
                    // string, add a single-quote and open it again: 'foo'\''bar' or
                    // 'foo'"'"'bar'.
                    line = line.replace("'", "'\\''");
                    println!("c.debug 'unable to parse: {}'", line);
                }
            }
        }
    }
}

// Compare the two sets set_a and set_b and write debug statements to stdout
// and restore statements to the restore file.
fn compare_sets(set_a: &HashMap<String, String>, set_b: &HashMap<String, String>,
              restore_file: &mut File, name_type: NameType) {

    let suffix;
    let unset;
    match name_type {
        NameType::Variable => {
            suffix = "";
            unset = "unset";
        },
        NameType::Function => {
            suffix = "()";
            unset = "unset -f";
        },
        NameType::Alias => {
            suffix = "*";
            unset = "unalias";
        }
    }

    // Create a sorted list of all keys. There may be more idiomatic ways to do this.
    let mut keys: Vec<String> = vec![];
    for key in set_a.keys() {
        keys.push(key.to_string());
    }
    for key in set_b.keys() {
        if !keys.contains(key) {
            keys.push(key.to_string());
        }
    }
    keys.sort();

    for key in keys {
        if !set_a.contains_key(&key) {
            // A name was added.
            println!("c.debug 'add     {}{}'", key, suffix);
            write(restore_file, format!("# {}\n", key));
            write(restore_file, format!("c.debug 'remove  {}{}'\n", key, suffix));
            write(restore_file, format!("{} {}\n", unset, key));

        } else if !set_b.contains_key(&key) {
            // A name was removed.
            println!("c.debug 'remove  {}{}'", key, suffix);
            write(restore_file, format!("c.debug 'restore {}{}'\n", key, suffix));
            write(restore_file, set_a.get(&key).unwrap().to_string());

        } else if set_a.get(&key) != set_b.get(&key) {
            if matches!(name_type, NameType::Variable) && (key == "BASHOPTS" || key == "SHELLOPTS") {
                let old:Vec<_> = set_a.get(&key).unwrap().split(':').collect();
                let new:Vec<_> = set_b.get(&key).unwrap().split(':').collect();
                for key in &old {
                    if !new.contains(&key) {
                        println!("c.debug 'set off {}{}'", key, suffix);
                        write(restore_file, format!("# {}\n", key));
                        write(restore_file, format!("c.debug 'set on  {}{}'\n", key, suffix));
                        write(restore_file, format!("shopt -s {} 2>/dev/null || shopt -so {}\n", key, key));
                    }
                }
                for key in &new {
                    if !old.contains(&key) {
                        println!("c.debug 'set on  {}{}'", key, suffix);
                        write(restore_file, format!("# {}\n", key));
                        write(restore_file, format!("c.debug 'set off {}{}'\n", key, suffix));
                        write(restore_file, format!("shopt -u {} 2>/dev/null || shopt -uo {}\n", key, key));
                    }
                }
            } else {
                // The value of a name was modified.
                println!("c.debug 'modify  {}{}'", key, suffix);
                write(restore_file, format!("# {}\n", key));
                write(restore_file, format!("c.debug 'restore {}{}'\n", key, suffix));
                write(restore_file, format!("{} {}\n", unset, key));
                write(restore_file, set_a.get(&key).unwrap().to_string());
            }
        }
    }
}

fn write(file: &mut File, message: String) {
    file.write_all(message.as_bytes()).expect("write failed!");
}
