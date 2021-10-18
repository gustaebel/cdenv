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
use std::fs;
use std::time::UNIX_EPOCH;
use std::path::Path;
use std::iter::Iterator;
use glob::glob;
use Context;


pub fn list_paths(context: Context, pwd: &str, loaded: &[String]) {
    let (unload, load) = list_dirs(context, pwd, loaded);

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

fn get_mtime(path: &str) -> u64 {
    let metadata = fs::metadata(path).unwrap();

    if let Ok(time) = metadata.modified() {
        time.duration_since(UNIX_EPOCH).unwrap().as_secs()
    } else {
        0
    }
}

fn list_dirs(context: Context, pwd: &str, loaded: &[String]) -> (Vec<String>, Vec<String>) {
    let home = env::var("HOME").unwrap_or_else(|_| String::from("/"));

    let mut found: Vec<String> = Vec::new();

    // Collect files from CDENV_PATH.
    let paths:Vec<_> = context.path.split(':').collect();
    for path in paths {
        for path in glob(format!("{}/*.sh", path).as_str()).unwrap().flatten() {
            let p = path.display().to_string();
            found.push(p);
        }
    }

    // Add ~/.cdenv.sh if global is true.
    if context.global && file_exists(&home, &context.file) {
        let mut f = home.clone();
        f.push('/');
        f.push_str(&context.file);
        found.push(f);
    }

    // Collect files the root to the current working directory.
    let mut pwd = pwd.trim_end_matches('/').to_string();
    pwd.push('/');
    for (i, _) in pwd.match_indices('/').collect::<Vec<_>>() {
        if (!context.global || pwd[..i] != home) && file_exists(&pwd[..i], &context.file) {
            let mut f = pwd[..i].to_string();
            f.push('/');
            f.push_str(&context.file);
            found.push(f);
        }
    }

    // Print the new CDENV_STACK value with all found filenames.
    println!("CDENV_STACK=(");
    for name in &found {
        println!("  {:?}", name);
    }
    println!(")");

    // Compare the list of found filenames with the list of loaded filenames.
    let mut unload: Vec<String> = Vec::new();
    let mut load: Vec<String> = Vec::new();

    if context.reload {
        // If a reload is requested we just unload all loaded and load all found filenames.
        // XXX We could just return reversed(loaded) and found directly.
        for name in &found {
            load.push(name.to_string());
        }
        for name in loaded {
            unload.insert(0, name.to_string());
        }

    } else {
        if context.autoreload {
            // Print some helpful debug messages about which files changed.
            println!("removed=(");
            for b in loaded {
                if !Path::new(&b).exists() {
                    println!("  {:?}", b);
                }
            }
            println!(")");

            println!("changed=(");
            for a in &found {
                if context.tag > 0 && get_mtime(a) > context.tag {
                    println!("  {:?}", a);
                }
            }
            println!(")");
        }

        // Find the point at which the stack of loaded files and the stack of found files diverge.
        // Or in case of autoreload the point where a loaded file has been changed. Unload all
        // loaded files leading to that point and load all found files from there.
        let mut new_tag = 0;
        let mut i = 0;
        let mut j = 0;

        loop {
            if let Some(a) = found.get(i) {
                if context.autoreload {
                    let mtime = get_mtime(a);
                    if context.tag > 0 && mtime > context.tag {
                        // The file has been changed in the meantime.
                        break;
                    }
                    if mtime > new_tag {
                        new_tag = mtime;
                    }
                }

                if let Some(b) = loaded.get(j) {
                    if a == b {
                        i += 1;
                        j += 1;
                        continue;
                    }
                }
            }
            break;
        }

        while let Some(b) = loaded.get(j) {
            unload.insert(0, b.to_string());
            j += 1
        }

        while let Some(a) = found.get(i) {
            load.push(a.to_string());
            if context.autoreload {
                let mtime = get_mtime(a);
                if mtime > new_tag {
                    new_tag = mtime;
                }
            }
            i += 1;
        }

        if context.autoreload {
            println!("CDENV_TAG={}", new_tag);
        }
    }

    (unload, load)
}

fn file_exists(path: &str, file: &str) -> bool {
    let mut path = path.to_string();
    path.push('/');
    path.push_str(file);
    Path::new(&path).exists()
}
