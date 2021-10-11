// 2021-09-26 lars@gustaebel.de
//
// This is my first small project in Rust. Please bear with me ;-)
//

use std::env;
use std::io::{self, BufRead, BufReader};
use std::path::Path;
use std::collections::HashMap;
use std::collections::HashSet;
use std::iter::Iterator;
use std::fs::File;
use std::io::prelude::*;

extern crate regex;
use regex::{Regex,Captures};

extern crate clap;
use clap::{App, Arg, SubCommand};

const VERSION: &'static str = env!("CARGO_PKG_VERSION");

#[derive(PartialEq)]
enum LineState {
    Default,
    InVariableDef,
    InArrayDef,
    InFunctionDef
}

enum Change {
    NewVar,
    RemovedVar,
    ChangedVar,
    NewFunc,
    RemovedFunc,
    ChangedFunc
}

fn main() {
    let matches = App::new("cdenv")
                    .subcommand(SubCommand::with_name("list")
                                .arg(Arg::with_name("global")
                                     .long("--global")
                                     .takes_value(true)
                                     .required(true))
                                .arg(Arg::with_name("file")
                                     .long("--file")
                                     .takes_value(true))
                                .arg(Arg::with_name("oldpwd")
                                     .long("--oldpwd")
                                     .takes_value(true))
                                .arg(Arg::with_name("pwd")
                                     .takes_value(true)
                                     .required(true)))
                    .subcommand(SubCommand::with_name("compare")
                                .arg(Arg::with_name("path")
                                     .takes_value(true)
                                     .required(true))
                                .arg(Arg::with_name("restore")
                                     .takes_value(true)
                                     .required(true)))
                    .subcommand(SubCommand::with_name("version"))
                    .get_matches();

    if let Some(matches) = matches.subcommand_matches("list") {
        let global = match matches.value_of("global").unwrap() {
            "0" => false,
            "1" => true,
            _ => false // simply default to false
        };
        let file = matches.value_of("file").unwrap_or(".cdenv.sh");
        let pwd = matches.value_of("pwd").unwrap();

        if let Some(oldpwd) = matches.value_of("oldpwd") {
            list_delta_paths(global, &oldpwd, &pwd, &file);
        } else {
            list_all_paths(global, &pwd, &file);
        }

    } else if let Some(matches) = matches.subcommand_matches("compare") {
        let path = matches.value_of("path").unwrap();
        let restore = matches.value_of("restore").unwrap();
        compare_environments(&path, &restore);

    } else if matches.is_present("version") {
        println!("{}", VERSION);
    }
}

// Print shell code with all directories in unload and load.
fn list_all_paths(global: bool, pwd: &str, file: &str) {
    let (unload, load) = enum_dirs(global, &file, &pwd, &pwd);
    print_paths(&unload, &load);
}

// Print shell code which directories to unload and which to load.
fn list_delta_paths(global: bool, oldpwd: &str, pwd: &str, file: &str) {
    let (mut unload, mut load) = enum_dirs(global, &file, &oldpwd, &pwd);

    // Filter out paths that are both in unload and load.
    let mut index;
    for name in load.clone() {
        if unload.contains(&name) {
            index = unload.iter().position(|x| x == &name).unwrap();
            unload.remove(index);
            index = load.iter().position(|x| x == &name).unwrap();
            load.remove(index);
        }
    }

    print_paths(&unload, &load);
}

fn print_paths(unload: &Vec<String>, load: &Vec<String>) {
    println!("local unload=(");
    for name in unload {
        println!("  {:?}", name);
    }
    println!(")");

    println!("local load=(");
    for name in load {
        println!("  {:?}", name);
    }
    println!(")");
}

fn record(file: &mut File, change: Change, name: &String, body: &String) {
    match change {
        Change::NewVar => {
            println!("__cdenv_debug '+ {}'", name);
            write(file, format!("__cdenv_debug undo '+ {}'\n", name));
            write(file, format!("unset {}\n", name));
        },
        Change::RemovedVar => {
            println!("__cdenv_debug '- {}'", name);
            write(file, format!("__cdenv_debug undo '- {}'\n", name));
            write(file, body.to_string());
        },
        Change::ChangedVar => {
            println!("__cdenv_debug '~ {}'", name);
            write(file, format!("__cdenv_debug undo '~ {}'\n", name));
            write(file, format!("unset {}\n", name));
            write(file, body.to_string());
        },
        Change::NewFunc => {
            println!("__cdenv_debug '+ {}()'", name);
            write(file, format!("__cdenv_debug undo '+ {}()'\n", name));
            write(file, format!("unset -f {}\n", name));
        },
        Change::RemovedFunc => {
            println!("__cdenv_debug '- {}()'", name);
            write(file, format!("__cdenv_debug undo '- {}()'\n", name));
            write(file, body.to_string());
        },
        Change::ChangedFunc => {
            println!("__cdenv_debug '~ {}()'", name);
            write(file, format!("__cdenv_debug undo '~ {}()'\n", name));
            write(file, format!("unset -f {}\n", name));
            write(file, body.to_string());
        },
    }
}

// Parse and compare two sets of shell environments.
fn compare_environments(path: &str, restore: &str) {
    let mut vars_a: HashMap<String, String> = HashMap::new();
    let mut funcs_a: HashMap<String, String> = HashMap::new();
    let mut vars_b: HashMap<String, String> = HashMap::new();
    let mut funcs_b: HashMap<String, String> = HashMap::new();

    parse_environment(Some(path), &mut vars_a, &mut funcs_a);
    parse_environment(None, &mut vars_b, &mut funcs_b);

    let mut file = File::create(restore).unwrap();
    let empty = "".to_string();

    for key in vars_b.keys() {
        if !vars_a.contains_key(key) {
            record(&mut file, Change::NewVar, key, &empty);
        }
    }
    for key in vars_a.keys() {
        if !vars_b.contains_key(key) {
            record(&mut file, Change::RemovedVar, key, &vars_a.get(key).unwrap());
        }
    }
    for key in vars_b.keys() {
        if vars_a.contains_key(key) && vars_a.get(key) != vars_b.get(key) {
            record(&mut file, Change::ChangedVar, key, &vars_a.get(key).unwrap());
        }
    }

    for key in funcs_b.keys() {
        if !funcs_a.contains_key(key) {
            record(&mut file, Change::NewFunc, key, &empty);
        }
    }
    for key in funcs_a.keys() {
        if !funcs_b.contains_key(key) {
            record(&mut file, Change::RemovedFunc, key, &funcs_a.get(key).unwrap());
        }
    }
    for key in funcs_b.keys() {
        if funcs_a.contains_key(key) && funcs_a.get(key) != funcs_b.get(key) {
            record(&mut file, Change::ChangedFunc, key, &funcs_a.get(key).unwrap());
        }
    }
}

fn file_exists(path: &str, file: &str) -> bool {
    let mut path = path.to_string();
    path.push('/');
    path.push_str(file);
    Path::new(&path).exists()
}

// Take a start and a stop directory and calculate which cdenv.sh files
// must be "unloaded" and which to load.
fn enum_dirs(global: bool, file: &str, start: &str, stop: &str) -> (Vec<String>, Vec<String>) {
    let home = env::var("HOME").unwrap_or(String::from("/"));

    let mut unload: Vec<String> = Vec::new();
    let mut load: Vec<String> = Vec::new();

    // Make sure there is a slash at the end of each directory.
    let mut start = start.trim_end_matches('/').to_string();
    start.push_str("/");
    let mut stop = stop.trim_end_matches('/').to_string();
    stop.push_str("/");

    for (i, _) in start.match_indices('/').collect::<Vec<_>>() {
        if (!global || start[..i] != home) && file_exists(&start[..i], file) {
            unload.insert(0, start[..i].to_string());
        }
    }

    for (i, _) in stop.match_indices('/').collect::<Vec<_>>() {
        if (!global || stop[..i] != home) && file_exists(&stop[..i], file) {
            load.push(stop[..i].to_string());
        }
    }

    if global && file_exists(&home, file) {
        unload.push(home.clone());
        load.insert(0, home);
    }

    return (unload, load);
}

fn write(file: &mut File, message: String) {
    file.write_all(message.as_bytes()).expect("write failed!");
}

// Parse output of { declare -p; declare -f; }.
// Notes:
// Here we create shell code that is later used to be sourced to restore the environment
// prior to the changes. Because we source this code inside the __cdenv_load function we
// have to add -g explicitly to declare all variables global.
fn parse_environment(input: Option<&str>, set_var: &mut HashMap<String, String>, set_func: &mut HashMap<String, String>) {
    // FIXME check characters for var/func names, a-zA-Z0-9_ might not be enough.
    let re_declare = Regex::new("^declare\\s+-+([iaAfxr]*)\\s+([a-zA-Z_][a-zA-Z0-9_]*)$").unwrap();
    let re_var_start = Regex::new("^declare\\s+-+([ixr]*)\\s+([a-zA-Z_][a-zA-Z0-9_]*)=\"(.*)$").unwrap();
    let re_array_start = Regex::new("^declare\\s+-([aAxr]+)\\s+([a-zA-Z_][a-zA-Z0-9_]*)=\\((.*)$").unwrap();
    let re_function_start = Regex::new("^([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(\\)\\s*$").unwrap();
    let re_function_end = Regex::new("^}\\s*$").unwrap();

    let mut line_state = LineState::Default;
    let mut name = String::new();
    let mut body = String::new();

    let mut exclude = HashSet::new();
    exclude.insert("_".to_string());
    exclude.insert("OLDPWD".to_string());

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
                if !exclude.contains(&name) {
                    line = format!("declare -g{} {}=\"{}\n", opts, name, value);
                    if value.ends_with("\"") && !value.ends_with("\\\"") {
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
