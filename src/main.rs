// cdenv - main.rs
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

extern crate regex;
extern crate clap;

use std::env;
use clap::{App, Arg, SubCommand};

mod environment;
mod file;

const VERSION: &'static str = env!("CARGO_PKG_VERSION");

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
            file::list_delta_paths(global, &oldpwd, &pwd, &file);
        } else {
            file::list_all_paths(global, &pwd, &file);
        }

    } else if let Some(matches) = matches.subcommand_matches("compare") {
        let input = matches.value_of("path").unwrap();
        let restore = matches.value_of("restore").unwrap();
        environment::compare_environments(&input, &restore);

    } else if matches.is_present("version") {
        println!("{}", VERSION);
    }
}
