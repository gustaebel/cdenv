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
    local cb
    for cb in "${CDENV_EXIT_CALLBACK[@]}"; do
        $cb
    done
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
    echo "$CDENV_CACHE/$$/${1//\//%2F}"
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
        source "$CDENV_SH" ""
    fi

    # Source the needed cdenv files.
    for path in "${load[@]}"; do
        c:source "$path"
    done
}

c:unsource() {
    # Undo the changes from a single cdenv file.
    local path="$1"
    local restore="$(c:restore_path "$path")"
    c.msg "unsource $(c.translate "$path")"
    if [[ -e $restore ]]; then
        source "$restore"
        rm "$restore"
    fi
}

c:source() {
    # Source a single cdenv file and keep track of the changes to the
    # environment. Try to avoid collisions with names from the sources.
    local __path="$1"
    local __directory="$(dirname "$__path")"
    local __restore="$(c:restore_path "$__path")"

    # Save a snapshot of the environment.
    local __tmp="$CDENV_CACHE/$$.tmp"
    { declare -p; declare -f; alias; } > "$__tmp"

    # Source the cdenv file.
    c.msg "source $(c.translate "$__path")"
    c:safe_source "$__directory" "$__path"

    # Save another snapshot of the environment and compare both. Create a
    # restore file that can be used to undo all changes to the environment when
    # changing to another directory.
    eval "$({ declare -p; declare -f; alias; } | $CDENV_EXEC compare "$__tmp" "$__restore")"
    rm "$__tmp"
}

c:find_file() {
    # Go through the stack in reverse looking for a variable, function or alias
    # definition.
    local a="$1"
    local i
    for ((i = ${#CDENV_STACK[@]}-1; i >= 0; i--)); do
        local f="${CDENV_STACK[$i]}"
        local p="$(c:restore_path "$f")"
        if grep -q "^# $a\$" "$p"; then
            echo "$f"
            return
        fi
    done
}

c:line_number() {
    # Return the line number of a specific variable / function / alias
    # definition in a file.
    local n="$1"
    local f="$2"
    local p

    for p in "${n}=" \
             "${n}[[:space:]]*([[:space:]]*)" \
             "alias[[:space:]]\+${n}="; do
        awk "/^[^#]/ && /$p/ { print \"+\" NR; ex = 1; exit 0; } \
             END { if (!ex) exit 1; }" \
            "$f" && break
    done
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
            local path lineno
            case "$2" in
                -b|--base)
                    path="${CDENV_STACK[${#CDENV_STACK[@]}-1]}"
                    ;;
                "")
                    path="$PWD/$CDENV_FILE"
                    ;;
                *)
                    path="$(c:find_file "$2")"
                    if [[ -z "$path" ]]; then
                        c.err "no such variable / function / alias: $2"
                        return 1
                    fi
                    lineno="$(c:line_number "$2" "$path")"
                    ;;
            esac

            # unload
            [[ $CDENV_AUTORELOAD -ne 1 && -e "$(c:restore_path "$path")" ]] && c:unsource "$path"
            # edit
            # shellcheck disable=SC2086
            ${EDITOR:-vi} $lineno "$path"
            # reload
            [[ $CDENV_AUTORELOAD -ne 1 && -e "$path" ]] && c:source "$path"
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
    edit [-b|<name>]
                Load the $CDENV_FILE from the current working directory in the
                EDITOR (${EDITOR:-vi}) for editing and reload it after that. If
                -b/--base is given, the $CDENV_FILE from the nearest base is
                opened. If a <name> is given, open the script file where this
                name has most recently been defined.
EOF
            ;;

        *)
            echo "unknown cdenv command '$1'" >&2
            return 2
            ;;
    esac
}

c:install() {
    local fetch
    if ! command -v curl >/dev/null; then
        if ! command -v wget >/dev/null; then
            c.err "neither 'curl' nor 'wget' command found!"
            return 1
        else
            fetch="wget -qO -"
        fi
    else
        fetch="curl -sL"
    fi

    CDENV_VERBOSE=1
    local oldpwd="$PWD"
    cd "$(dirname "$CDENV_SH")" || true

    case "$1" in
        update)
            c.msg "Fetching update for cdenv ..."
            $fetch https://github.com/gustaebel/cdenv/releases/latest/download/cdenv.shar | $BASH

            c.msg "Reloading installation ..."
            c:update reload
            ;;&

        install|"")
            if ! grep -q "^source \"$PWD/cdenv.sh\"$" "$HOME/.bashrc"; then
                c.msg "Installing cdenv.sh in ~/.bashrc"
                echo -e "\nsource \"$PWD/cdenv.sh\"" >> "$HOME/.bashrc"
            fi

            c.msg "Sourcing \"$(c.translate "$PWD/cdenv.sh")\""
            source "cdenv.sh" ""
            ;;&

        install|update|"")
            cd "$oldpwd" || true
            ;;

    esac
}

if [ -z "$BASH_VERSION" ] || [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    echo "CDENV ERROR: only bash >= 4 is supported!" >&2

else
    if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
        case "$1" in
            "")
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
                ;;
            install)
                c:install install
                ;;
            update)
                c:install update
                ;;
            *)
                c.err "invalid command '$1'"
                return 1;
                ;;
        esac
    else
        c.err "cdenv.sh is supposed to be sourced!"
        echo "usage: source cdenv.sh [install|update]"
    fi
fi

unset c:install
