#!/bin/bash
#
# cdenv - cdenv.sh
#
# Copyright (C) 2021  Lars Gustäbel <lars@gustaebel.de>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

CDENV_RCFILE=.cdenvrc.sh

# Defaults.
CDENV_VERBOSE=0
CDENV_GLOBAL=1
CDENV_FILE=.cdenv.sh
CDENV_SH="$(realpath "${BASH_SOURCE[0]}")"
CDENV_EXEC="$(dirname "$CDENV_SH")/cdenv"
CDENV_PATH="$(dirname "$CDENV_SH")/libs"
CDENV_CACHE="$HOME/.cache/cdenv"
CDENV_BASE=
declare -a CDENV_CALLBACK=()
declare -a CDENV_STACK=()
CDENV_AUTORELOAD=0
CDENV_TAG=0

CDENV_COLOR=1
CDENV_COLOR_ERR=$(tput setaf 1)
CDENV_COLOR_MSG=$(tput setaf 4)
CDENV_COLOR_DEBUG=$(tput setaf 8)
CDENV_COLOR_RESET=$(tput setaf sgr0)

# Load the settings file selectively replacing the defaults from above.
[[ -e $HOME/$CDENV_RCFILE ]] && source "$HOME/$CDENV_RCFILE"

# Create a directory for the restore files which will be removed in the EXIT
# trap handler.
mkdir -p "${CDENV_CACHE:?}/$$"

c:exit() {
    rm -r "${CDENV_CACHE:?}/$$"
}
trap c:exit EXIT

# Switch off all colors if requested.
if [[ ! -t 1 || $CDENV_COLOR -ne 1 ]]; then
    unset CDENV_COLOR_ERR
    unset CDENV_COLOR_MSG
    unset CDENV_COLOR_DEBUG
    unset CDENV_COLOR_RESET
fi

c.err() {
    # Print an error message to stderr.
    echo "${CDENV_COLOR_ERR}ERROR: $*${CDENV_COLOR_RESET}" >&2
}

c.msg() {
    # Print a message to stderr.
    [[ $CDENV_VERBOSE -ge 1 ]] && echo "${CDENV_COLOR_MSG}$*${CDENV_COLOR_RESET}" >&2
}

c.debug() {
    # Print a debug message to stderr.
    [[ $CDENV_VERBOSE -ge 2 ]] && echo "${CDENV_COLOR_DEBUG}cdenv: $*${CDENV_COLOR_RESET}" >&2
}

c.translate() {
    # Translate /home/user/foo to ~/foo.
    local path="$(realpath --relative-base "$HOME" "$1")"
    if [[ ${path:0:1} != / ]]; then
        if [[ $path = . ]]; then
            echo \~
        else
            echo \~/"$path"
        fi
    else
        echo "$path"
    fi
}

c:restore_path() {
    # Save restore files in ~/.cache/cdenv/<pid>/<path>.sh.
    echo "$CDENV_CACHE/$$/${1//\//%2F}.sh"
}

c:safe_source() {
    # Source a file in the context of a specific directory.
    local directory="$1"
    local path="$2"
    local oldpwd="$OLDPWD"
    local savedir="$PWD"

    builtin cd "$directory" || return 1
    # Check the script for errors before sourcing.
    if $BASH -n "$path"; then
        source "$path"
    fi
    builtin cd "$savedir" || return 1
    OLDPWD="$oldpwd"
}

# shellcheck disable=SC2154
c:update() {
    local path

    local -a args=()
    [[ $1 = reload ]] && args+=(--reload)
    [[ $CDENV_AUTORELOAD -eq 1 ]] && args+=(--autoreload)

    # shellcheck disable=SC2086
    eval "$($CDENV_EXEC list --global=$CDENV_GLOBAL --path="$CDENV_PATH" --file=$CDENV_FILE --tag=$CDENV_TAG ${args[*]} "$PWD" "${CDENV_STACK[@]}")"

    for path in "${removed[@]}"; do
        c.msg "$(c.translate "$path") was removed"
    done
    for path in "${changed[@]}"; do
        c.msg "$(c.translate "$path") was changed"
    done

    # First undo the changes made to the environment.
    for path in "${unload[@]}"; do
        c:unsource "$path"
    done

    if [[ $1 = reload ]]; then
        # Reload the settings file.
        if [[ -e $HOME/$CDENV_RCFILE ]]; then
            c.msg "reloading ~/$CDENV_RCFILE"
            if $BASH -n "$HOME/$CDENV_RCFILE"; then
                source "$HOME/$CDENV_RCFILE"
            fi
        fi
        # Reload this bash module.
        c.msg "reloading $(c.translate "$CDENV_SH")"
        source "$CDENV_SH" init
    fi

    # Source the needed cdenv files.
    for path in "${load[@]}"; do
        c:source "$path"
    done
}

c:unsource() {
    # Undo the changes from a single cdenv file.
    local path="$1"
    local directory="$(dirname "$path")"
    local restore="$(c:restore_path "$directory")"
    c.msg "unsource $(c.translate "$path")"
    if [[ -e $restore ]]; then
        c:safe_source "$directory" "$restore"
        rm "$restore"
    fi
}

c:source() {
    # Source a single cdenv file and keep track of the changes to the
    # environment.
    local directory="$(dirname "$1")"
    c:source_many "$directory" "$1"
    CDENV_BASE="$directory"
}

c:source_many() {
    # Source multiple cdenv files from the same directory and keep track of the
    # changes to the environment. Try to avoid collisions with names from the
    # sources.
    local __directory="$1"
    local __path
    local __restore="$(c:restore_path "$__directory")"
    shift

    # Save a snapshot of the environment.
    local __tmp="$CDENV_CACHE/$$.tmp"
    { declare -p; declare -f; alias; } > "$__tmp"

    # Source the cdenv file.
    for __path; do
        [[ -e "$__path" ]] || { c.err "no such file: $__path"; continue; }
        c.msg "source $(c.translate "$__path")"
        c:safe_source "$__directory" "$__path"
    done
    unset __path

    # Save another snapshot of the environment and compare both. Create a
    # restore file that can be used to undo all changes to the environment when
    # changing to another directory.
    eval "$({ declare -p; declare -f; alias; } | $CDENV_EXEC compare "$__tmp" "$__restore")"
    rm "$__tmp"

    echo "CDENV_BASE=\"$CDENV_BASE\"" >> "$__restore"
}

cdenv() {
    case "$1" in
        update)
            [[ $CDENV_AUTORELOAD -ne 1 && $PWD = "$CDENV_LAST" ]] && return
            c:update
            CDENV_LAST="$PWD"
            local cb
            for cb in "${CDENV_CALLBACK[@]}"; do
                $cb
            done
            ;;

        reload)
            c:update reload
            ;;

        edit)
            local base
            case "$2" in
                -b|--base)
                    base="$CDENV_BASE"
                    ;;
                "")
                    base="$PWD"
                    ;;
                *)
                    c.err "invalid option $2"
                    return 1
                    ;;
            esac

            # unload
            local path="$(c:restore_path "$base")"
            [[ $CDENV_AUTORELOAD -ne 1 && -e "$path" ]] && c:unsource "$base/$CDENV_FILE"
            # edit
            ${EDITOR:-vi} "$base/$CDENV_FILE"
            # reload
            [[ $CDENV_AUTORELOAD -ne 1 && -e "$base/$CDENV_FILE" ]] && c:source "$base/$CDENV_FILE"
            ;;

        version)
            $CDENV_EXEC version
            ;;

        help|"")
            cat >&2 <<EOF
usage: cdenv <command> [<argument> ...]

cdenv will check for a file called $CDENV_FILE every time you cd into a
directory. This file will be sourced in the current environment. This way you
can easily add variables, functions and aliases to the environment or simply
echo a text message each time you enter this directory. The changes to the
environment are cumulative, i.e. the deeper you go in the directory tree each
new $CDENV_FILE's changes are put on top of the others. Once you go back up in
the tree the changes are undone one by one.

Settings are stored in ~/$CDENV_RCFILE:

CDENV_VERBOSE={0|1|2}
    (current: $CDENV_VERBOSE)
    Produce verbose output useful for debugging, default is 0.

CDENV_GLOBAL={0|1}
    (current: $CDENV_GLOBAL)
    If set to 1, the changes in ~/$CDENV_FILE apply globally, regardless of
    whether the current working directory is located inside the home directory,
    default is 1.

CDENV_AUTORELOAD={0|1}
    (current: $CDENV_AUTORELOAD)
    If set to 1, shell scripts from CDENV_PATH and .cdenv.sh files are
    automatically reloaded if they are changed, loaded if they are added and
    unloaded if they are removed. If set to 0, you have to use 'cdenv edit' or
    'cdenv reload' if you want changes to your shell scripts appear in your
    current shell environment. Default is 0.

CDENV_FILE={basename}
    (current: $CDENV_FILE)
    Use a script filename different from the default .cdenv.sh to prevent
    accidentally executing other people's shell code from a tar file or source
    repo.

CDENV_PATH={directory}[:{directory}]
    (current: $CDENV_PATH)
    A colon-separated list of directories (similar to PATH) with shell scripts
    to load on startup. The files must end with '.sh' and are loaded in
    alphabetical order.

CDENV_COLOR={0|1}
    (current: $CDENV_COLOR)
    If set to 1, use colored output for error messages and debug messages
    (if CDENV_VERBOSE > 0), default is 1.


commands:
    help        This help message.
    reload      Unload and reload the complete cdenv environment and all
                $CDENV_FILE in the current directory hierarchy.
    edit [-b]   Load the $CDENV_FILE from the current working directory (or the
                nearest base if -b/--base is given) in the EDITOR (${EDITOR:-vi})
                and reload it after that.
EOF
            ;;

        *)
            echo "unknown cdenv command '$1'" >&2
            return 2
            ;;
    esac
}

c:install() {
    if ! command -v git >/dev/null; then
        c.err "'git' command not found, do you have Git installed?"
        return 1
    fi
    if ! command -v cargo >/dev/null; then
        c.err "'cargo' command not found, do you have Rust installed?"
        return 1
    fi

    CDENV_VERBOSE=1
    local oldpwd="$PWD"
    cd "$(dirname "$CDENV_SH")"

    case "$1" in
        update)
            c.msg "Fetching updates for cdenv ..."
            git pull
            ;;&
        install|update|"")
            c.msg "Building cdenv ..."
            cargo build --release
            cp target/release/cdenv .
            cd "$oldpwd"
            ;;&
        update)
            c.msg "Now type 'cdenv reload'"
            ;;
        install|"")
            if ! grep -qE '^source ".+cdenv.sh"$' $HOME/.bashrc; then
                c.msg "Installing cdenv.sh in ~/.bashrc"
                echo -e "\nsource \"$PWD/cdenv.sh\"" >> $HOME/.bashrc
            fi

            c.msg "Now source \"$(c.translate "$PWD/cdenv.sh")\" or open a new shell"
            ;;
        *)
            c.err "invalid command '$1'"
            return 1;
            ;;
    esac
}

if [ -z "$BASH_VERSION" ] || [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    echo "CDENV ERROR: only bash >= 4 is supported!" >&2

else
    if [[ $CDENV_SH != "$(realpath "$0")" || $1 = init ]]; then
        # cdenv.sh is sourced.
        if [[ ${PROMPT_COMMAND[*]} =~ "cdenv update" ]]; then
            c.debug "cdenv is already installed"
        else
            # Using +=() should always work regardless of whether PROMPT_COMMAND is
            # unset, a normal variable or an array. The result however will be an
            # array.
            c.debug "add to \$PROMPTCOMMAND"
            PROMPT_COMMAND+=("cdenv update")
        fi

        c.debug "executable: $CDENV_EXEC"
        c.debug "cache directory: $(c.translate "$CDENV_CACHE/$$")"
        c.debug "autoreload is $(if [[ $CDENV_AUTORELOAD -eq 1 ]]; then echo on; else echo off; fi)"
    else
        # cdenv.sh is called.
        c:install "$@"
    fi
fi

unset c:install
