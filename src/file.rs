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
use glob::glob;
use std::cmp::Ordering;


pub fn list_paths(global: bool, reload: bool, path: &str, pwd: &str, file: &str, loaded: &Vec<String>) {
    let (unload, load) = list_dirs(global, reload, &path, &file, &pwd, &loaded);

    println!("local -a unload=(");
    for name in unload {
        println!("  {:?}", name);
    }
    println!(")");

    println!("local -a load=(");
    for name in load {
        println!("  {:?}", name);
    }
    println!(")");
}

fn list_dirs(global: bool, reload: bool, path: &str, file: &str, pwd: &str, loaded: &Vec<String>) -> (Vec<String>, Vec<String>) {
    let home = env::var("HOME").unwrap_or(String::from("/"));

    let mut found: Vec<String> = Vec::new();

    let paths:Vec<_> = path.split(':').collect();
    for path in paths {
        for entry in glob(format!("{}/*.sh", path).as_str()).unwrap() {
            if let Ok(path) = entry {
                let p = path.display().to_string();
                found.push(p);
            }
        }
    }

    // Make sure there is a slash at the end of each directory.
    let mut pwd = pwd.trim_end_matches('/').to_string();
    pwd.push_str("/");

    if global && file_exists(&home, file) {
        let mut f = home.clone();
        f.push('/');
        f.push_str(file);
        found.push(f);
    }

    for (i, _) in pwd.match_indices('/').collect::<Vec<_>>() {
        if (!global || pwd[..i] != home) && file_exists(&pwd[..i], file) {
            let mut f = pwd[..i].to_string();
            f.push('/');
            f.push_str(file);
            found.push(f);
        }
    }

    println!("CDENV_STACK=(");
    for name in &found {
        println!("  {:?}", name);
    }
    println!(")");

    let mut unload: Vec<String> = Vec::new();
    let mut load: Vec<String> = Vec::new();

    if reload {
        // XXX We could just return loaded reversed and found.
        for name in loaded {
            unload.insert(0, name.to_string());
        }
        for name in &found {
            load.push(name.to_string());
        }

    } else {
        let mut i = 0;
        let mut j = 0;

        loop {
            if let Some(a) = found.get(i) {
                if let Some(b) = loaded.get(j) {
                    match a.cmp(&b.to_string()) {
                        Ordering::Less => {
                            load.push(a.to_string());
                            i += 1;
                        },
                        Ordering::Greater => {
                            unload.insert(0, b.to_string());
                            j += 1;
                        },
                        Ordering::Equal => {
                            i += 1;
                            j += 1;
                        }
                    }
                } else {
                    load.push(a.to_string());
                    i += 1
                }
            } else {
                if let Some(b) = loaded.get(j) {
                    unload.insert(0, b.to_string());
                    j += 1
                } else {
                    break;
                }
            }
        }
    }

    return (unload, load);
}

fn file_exists(path: &str, file: &str) -> bool {
    let mut path = path.to_string();
    path.push('/');
    path.push_str(file);
    Path::new(&path).exists()
}
