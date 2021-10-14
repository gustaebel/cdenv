// cdenv - file.rs
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

use std::env;
use std::path::Path;
use std::iter::Iterator;

// Print shell code with all directories in unload and load.
pub fn list_all_paths(global: bool, pwd: &str, file: &str) {
    let (unload, load) = enum_dirs(global, &file, &pwd, &pwd);
    print_paths(&unload, &load);
}

// Print shell code which directories to unload and which to load.
pub fn list_delta_paths(global: bool, oldpwd: &str, pwd: &str, file: &str) {
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
