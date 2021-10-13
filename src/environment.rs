// cdenv
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
use std::iter::Iterator;
use std::fs::File;
use std::io::prelude::*;

use regex::{Regex,Captures};

const ENTER_FUNC: &'static str = "cdenv_enter";
const LEAVE_FUNC: &'static str = "cdenv_leave";

const EXCLUDE_VARS: &'static [&'static str] = &["_", "OLDPWD"];
const EXCLUDE_FUNCS: &'static [&'static str] = &[ENTER_FUNC, LEAVE_FUNC];

#[derive(PartialEq)]
enum LineState {
    Default,
    InVariableDef,
    InArrayDef,
    InFunctionDef
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

    let mut file = File::create(restore).unwrap();

    if funcs_b.contains_key(ENTER_FUNC) {
        // Feed cdenv_enter() back to the calling shell, so that it is called
        // and immediately removed from the environment.
        println!("{}", ENTER_FUNC);
        println!("unset -f {}", ENTER_FUNC);
    }

    if funcs_b.contains_key(LEAVE_FUNC) {
        // Register cdenv_leave() in the restore file, so that it is called
        // and removed from the environment when the directory is left.
        write(&mut file, funcs_b.get(LEAVE_FUNC).unwrap().to_string());
        write(&mut file, format!("{}\n", LEAVE_FUNC));
        write(&mut file, format!("unset -f {}\n", LEAVE_FUNC));
        println!("unset -f {}", LEAVE_FUNC);
    }

    // Remove some names from the environment.
    prune_unwanted_names(EXCLUDE_VARS, &mut vars_a);
    prune_unwanted_names(EXCLUDE_VARS, &mut vars_b);
    prune_unwanted_names(EXCLUDE_FUNCS, &mut funcs_a);
    prune_unwanted_names(EXCLUDE_FUNCS, &mut funcs_b);

    // Compare the vars, funcs and alias sets and write statements to stdout
    // and the restore file.
    compare_sets(&vars_a, &vars_b, &mut file, "", "unset");
    compare_sets(&funcs_a, &funcs_b, &mut file, "()", "unset -f");
    compare_sets(&alias_a, &alias_b, &mut file, "*", "unalias");

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
// prior to the changes. Because we source this code inside the __cdenv_load function we
// have to add -g explicitly to declare all variables global.
fn parse_environment(input: Option<&str>, set_var: &mut HashMap<String, String>,
                     set_func: &mut HashMap<String, String>, set_alias: &mut HashMap<String, String>) {
    // FIXME check characters for var/func names, a-zA-Z0-9_ might not be enough.
    let re_declare = Regex::new("^declare\\s+-+([iaAfxr]*)\\s+([a-zA-Z_][a-zA-Z0-9_]*)$").unwrap();
    let re_var_start = Regex::new("^declare\\s+-+([ixr]*)\\s+([a-zA-Z_][a-zA-Z0-9_]*)=\"(.*)$").unwrap();
    let re_array_start = Regex::new("^declare\\s+-([aAxr]+)\\s+([a-zA-Z_][a-zA-Z0-9_]*)=\\((.*)$").unwrap();
    let re_function_start = Regex::new("^([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(\\)\\s*$").unwrap();
    let re_function_end = Regex::new("^}\\s*$").unwrap();
    let re_alias = Regex::new("^alias\\s+([a-zA-Z_][a-zA-Z0-9_\\-]*)='(.*)'$").unwrap();

    let mut line_state = LineState::Default;
    let mut name = String::new();
    let mut body = String::new();

    let reader: Box<dyn BufRead> = match input {
        None => Box::new(BufReader::new(io::stdin())),
        Some(filename) => Box::new(BufReader::new(File::open(filename).unwrap()))
    };

    let mut lines = reader.lines();

    fn get_group(groups: &Captures, group: usize) -> String {
        groups.get(group).unwrap().as_str().to_string()
    }

    loop {
        if let Some(line) = lines.next() {
            let mut line = line.unwrap().trim_end().to_string();

            if let Some(groups) = re_declare.captures(&line) {
                let opts = get_group(&groups, 1);
                name = get_group(&groups, 2);
                set_var.insert(name.clone(), format!("declare -g{} {}\n", opts, name));

            } else if let Some(groups) = re_var_start.captures(&line) {
                let opts = get_group(&groups, 1);
                name = get_group(&groups, 2);
                let value = get_group(&groups, 3);
                line = format!("declare -g{} {}=\"{}\n", opts, name, value);
                if value.ends_with("\"") && !value.ends_with("\\\"") {
                    set_var.insert(name.clone(), line);
                    line_state = LineState::Default;
                } else {
                    body.push_str(&line);
                    line_state = LineState::InVariableDef;
                }

            } else if let Some(groups) = re_array_start.captures(&line) {
                let opts = get_group(&groups, 1);
                name = get_group(&groups, 2);
                let value = get_group(&groups, 3);
                line = format!("declare -g{} {}=({}\n", opts, name, value);
                if value.ends_with(")") && !value.ends_with("\\)") {
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
                body.push_str("\n");
                line_state = LineState::InFunctionDef;

            } else if let Some(groups) = re_alias.captures(&line) {
                name = get_group(&groups, 1);
                body = get_group(&groups, 2);
                set_alias.insert(name.clone(), format!("alias {}='{}'\n", name, body));

            } else if re_function_end.is_match(&line) {
                // Parse the terminating line of a function definition.
                body.push_str(&line);
                body.push_str("\n");
                set_func.insert(name.clone(), body.clone());
                body.clear();
                line_state = LineState::Default;

            } else {
                match line_state {
                    LineState::InVariableDef => {
                        // Collect the lines of a multiline variable.
                        body.push_str(&line);
                        body.push_str("\n");
                        if line.ends_with("\"") && !line.ends_with("\\\"") {
                            set_var.insert(name.clone(), body.clone());
                            body.clear();
                            line_state = LineState::Default;
                        }
                    },
                    LineState::InArrayDef => {
                        // Collect the lines of a multiline variable.
                        body.push_str(&line);
                        body.push_str("\n");
                        if line.ends_with(")") && !line.ends_with("\\)") {
                            set_var.insert(name.clone(), body.clone());
                            body.clear();
                            line_state = LineState::Default;
                        }
                    },
                    LineState::InFunctionDef => {
                        // Collect the lines in the function body.
                        body.push_str(&line);
                        body.push_str("\n");
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
                        println!("__cdenv_debug 'unable to parse: {}'", line);
                    }
                }
            }

        } else {
            break;
        }
    }
}

// Compare the two sets set_a and set_b and write debug statements to stdout
// and restore statements to the restore file.
fn compare_sets(set_a: &HashMap<String, String>, set_b: &HashMap<String, String>,
              file: &mut File, suffix: &str, unset: &str) {
    for key in set_b.keys() {
        if !set_a.contains_key(key) {
            println!("__cdenv_debug '+ {}{}'", key, suffix);
            write(file, format!("__cdenv_debug undo '+ {}{}'\n", key, suffix));
            write(file, format!("{} {}\n", unset, key));
        }
    }

    for key in set_a.keys() {
        if !set_b.contains_key(key) {
            println!("__cdenv_debug '- {}{}'", key, suffix);
            write(file, format!("__cdenv_debug undo '- {}{}'\n", key, suffix));
            write(file, set_a.get(key).unwrap().to_string());
        }
    }

    for key in set_b.keys() {
        if set_a.contains_key(key) && set_a.get(key) != set_b.get(key) {
            println!("__cdenv_debug '~ {}{}'", key, suffix);
            write(file, format!("__cdenv_debug undo '~ {}{}'\n", key, suffix));
            write(file, format!("{} {}\n", unset, key));
            write(file, set_a.get(key).unwrap().to_string());
        }
    }
}

fn write(file: &mut File, message: String) {
    file.write_all(message.as_bytes()).expect("write failed!");
}
