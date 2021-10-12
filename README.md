# cdenv

Manage different bash environments for different directories.


## About

*cdenv* is similar to such tools as
[autoenv](https://github.com/kennethreitz/autoenv),
[direnv](https://direnv.net), [smartcd](https://github.com/cxreg/smartcd), and
[funky](https://github.com/bbugyi200/funky).
It tries to find the right balance between being very powerful while being
still easy to use, and follows the
[Principle of Least Surprise](https://en.wikipedia.org/wiki/Principle_of_least_astonishment).


## How it works

*cdenv* will be triggered before each prompt and check for the existence of a
shell script called `.cdenv.sh` in the current working directory. If there is
one, *cdenv* makes a snapshot of the current environment, sources the
`.cdenv.sh` script and makes another snapshot. *cdenv* then compares the two
snapshots of the environment and creates a file in `~/.cache/cdenv` which can
later be used to undo the changes when you leave the directory.

As you would expect, changes to the environment stack on top of each other the
deeper you go in the directory tree. Besides adding new shell definitions,
existing definitions may be removed or overwritten by `.cdenv.sh` files further
down the tree. All changes applied by `.cdenv.sh` files are automatically
undone when you leave their respective directory, there is no need to write
separate code that does that.

A `.cdenv.sh` file is a plain shell script, that is only sourced once when you
enter the directory it is in. All the definitions of environment variables,
functions, aliases and the rest of the code it contains are executed in the
exact order and manner you would expect. There is no need to modify your code
to work with *cdenv*.

All changes that are made to the environment are specific to current shell
process, e.g. it is possible to define a certain function only if certain
conditions are met. Only the things that were changed are being restored to
their old values, when you leave the directory.

*cdenv* installs itself by appending to bash's `PROMPT_COMMAND` array variable.


## Features

* Keeps track of all environment changes and undoes them selectively when you
  leave the directory later.
* Supports adding, removing and modifying:
    * Environment variables
    * Shell functions
    * Aliases
* Supports oneshot shell code that is executed once when the directory is entered.
* Uses plain shell code, no imposed quirky constraints.
* Support for bash >= 4.0 only.


## Settings

Some of *cdenv*'s settings can be customized with a file called `~/.cdenvrc.sh`.

* `CDENV_VERBOSE={0|1|2}`

    Produce verbose output useful for debugging, default is `0`.

* `CDENV_GLOBAL={0|1}`

    If set to `1`, the changes in `~/.cdenv.sh` apply globally, regardless of
    whether the current working directory is located inside the home directory,
    default is `1`.

* `CDENV_FILE`

    Use a script filename different from the default `.cdenv.sh` to prevent
    accidentally executing other people's shell code from a tar file or source
    repo.


## Prerequisites

* bash >= 4.0
* rust
* make


## Installation

Installation for the current user only:

```console
$ git clone https://github.com/gustaebel/cdenv.git ~/.cdenv
$ cd ~/.cdenv
$ make install-user
```

System-wide installation (in case your bash was built with `-DSYS_BASHRC="/etc/bash.bashrc"`):

```console
$ git clone https://github.com/gustaebel/cdenv.git
$ cd cdenv
$ make
$ sudo make install
$ sudo bash -c 'echo source /usr/lib/cdenv/cdenv.sh >> /etc/bash.bashrc'
```
