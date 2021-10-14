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

CDENV_VERBOSE=0
CDENV_GLOBAL=1
CDENV_FILE=.cdenv.sh
CDENV_RCFILE=.cdenvrc.sh
CDENV_INSTALL="${BASH_SOURCE[0]}"
CDENV_EXEC="$(dirname "$CDENV_INSTALL")/cdenv"
CDENV_PATH="$(dirname "$CDENV_INSTALL")/libs"
CDENV_CACHE="$HOME/.cache/cdenv"
declare -a CDENV_CALLBACK=()

[[ -e $HOME/$CDENV_RCFILE ]] && source "$HOME/$CDENV_RCFILE"

# Create a directory for the restore files which will be removed in the EXIT
# trap handler.
mkdir -p "${CDENV_CACHE:?}/$$"

c.exit() {
    rm -r "${CDENV_CACHE:?}/$$"
}
trap c.exit EXIT


c.err() {
    # Print an error message to stderr.
    echo "ERROR: $*" >&2
}

c.msg() {
    # Print a message to stderr.
    [[ $CDENV_VERBOSE -ge 1 ]] && echo "$*" >&2
}

c.debug() {
    # Print a debug message to stderr.
    [[ $CDENV_VERBOSE -ge 2 ]] && echo "cdenv: $*" >&2
}

c.safe_source() {
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

c.restore_path() {
    # Save restore files in ~/.cache/cdenv/<pid>/<path>.sh.
    echo "$CDENV_CACHE/$$/$(echo "${1:1}" | sed 's@/@%2F@g').sh"
}

c.load() {
    # There are three modes of operation:
    #
    # init:     All cdenv files from every directory leading up from / to $PWD
    #           are sourced. If CDENV_GLOBAL -eq 1 the cdenv file from $HOME is
    #           always sourced first, regardless of whether $HOME is part of
    #           the directory chain.
    # update:   When the $PWD has been changed, unsource all cdenv files that
    #           are no longer part of the directory chain and source all cdenv
    #           files that have not yet been sourced.
    # reload:   Unsource all loaded cdenv files from the directory chain and
    #           re-source them again.
    local directories
    local directory
    local i
    local -a load=()
    local -a unload=()
    local cmd="$1"
    local pwd="$PWD"

    case "$cmd" in
        init)
            eval "$($CDENV_EXEC list --global=$CDENV_GLOBAL --file=$CDENV_FILE "$pwd")"
            unload=() # There is nothing yet to unload.
            ;;
        update)
            local oldpwd="$2"
            # The current working directory has not been changed, do nothing.
            [[ $oldpwd = "$pwd" ]] && return;
            eval "$($CDENV_EXEC list --global=$CDENV_GLOBAL --file=$CDENV_FILE --oldpwd="$oldpwd" "$pwd")"
            ;;
        reload)
            local oldpwd="$pwd"
            eval "$($CDENV_EXEC list --global=$CDENV_GLOBAL --file=$CDENV_FILE "$pwd")"
            ;;
        *)
            return;
            ;;
    esac

    # First undo the changes made to the environment.
    for directory in "${unload[@]}"; do
        c.unsource "$directory"
    done

    # Handle library files from CDENV_PATH and reloading the settings
    # file and the bash module.
    IFS=: read -a directories <<< "$CDENV_PATH"
    case "$cmd" in
        reload)
            # Unsource all files from CDENV_PATH in reverse order.
            for (( i=${#directories[@]} - 1; i >= 0; i-- )); do
                c.unsource "${directories[i]}"
            done

            # Reload the settings file.
            if [[ -e $HOME/$CDENV_RCFILE ]]; then
                c.msg "reloading ~/$CDENV_RCFILE"
                if $BASH -n "$HOME/$CDENV_RCFILE"; then
                    source "$HOME/$CDENV_RCFILE"
                fi
            fi
            # Reload this bash module.
            c.msg "reloading $(c.translate "$CDENV_INSTALL")"
            source "$CDENV_INSTALL" noinit
            ;;&

        init|reload)
            # Source all files from CDENV_PATH.
            for directory in "${directories[@]}"; do
                c.source_many "$directory" "$directory"/*.sh
            done
            ;;
    esac

    # Source the needed cdenv files.
    for directory in "${load[@]}"; do
        c.source "$directory"
    done
}

c.unsource() {
    # Undo the changes from a single cdenv file.
    local directory="$1"
    local path="$(c.restore_path "$directory")"
    c.msg "unsource $(c.translate "$directory")/"
    if [[ -e $path ]]; then
        c.safe_source "$directory" "$path"
        rm "$path"
    fi
}

c.source() {
    # Source a single cdenv file and keep track of the changes to the
    # environment.
    c.source_many "$1" "$1/$CDENV_FILE"
}

c.source_many() {
    # Source multiple cdenv files from the same directory and keep track of the
    # changes to the environment. Try to avoid collisions with names from the
    # sources.
    local cdenv_directory="$1"
    local cdenv_path
    shift

    # Save a snapshot of the environment.
    local cdenv_tmp="$CDENV_CACHE/$$.tmp"
    { declare -p; declare -f; alias; } > "$cdenv_tmp"

    # Source the cdenv file.
    c.msg "source $(c.translate "$cdenv_directory")/"
    for cdenv_path; do
        [[ -e "${cdenv_path}" ]] || { c.msg "ERROR: no such file: ${cdenv_path}"; continue; }
        c.safe_source "$cdenv_directory" "${cdenv_path}"
    done
    unset cdenv_path

    # Save another snapshot of the environment and compare both. Create a
    # restore file that can be used to undo all changes to the environment when
    # changing to another directory.
    eval "$({ declare -p; declare -f; alias; } | $CDENV_EXEC compare "$cdenv_tmp" "$(c.restore_path "$cdenv_directory")")"
    rm "$cdenv_tmp"
}

cdenv() {
    case "$1" in
        init)
            c.load init
            CDENV_LAST="$PWD"
            ;;

        load)
            c.load update "${CDENV_LAST:-/}"
            CDENV_LAST="$PWD"
            local cb
            for cb in ${CDENV_CALLBACK[@]}; do
                $cb
            done
            ;;

        reload)
            c.load reload
            ;;

        edit)
            # unload
            local path="$(c.restore_path "$PWD")"
            [[ -e "$path" ]] && c.unsource "$PWD"
            # edit
            ${EDITOR:-vi} $CDENV_FILE
            # reload
            [[ -e "$CDENV_FILE" ]] && c.source "$PWD"
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


commands:
    help        this help message
    reload      unload and reload the complete cdenv environment and all
                $CDENV_FILE in the current directory hierarchy
    edit        load the $CDENV_FILE from the current working directory in the
                EDITOR (${EDITOR:-vi}) and reload it after that
EOF
            ;;

        *)
            echo "unknown cdenv command '$1'" >&2
            return 2
            ;;
    esac
}

if [ -z "$BASH_VERSION" ] || [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    echo "CDENV ERROR: only bash >= 4 is supported!" >&2
else
    __found=0
    for x in "${PROMPT_COMMAND[@]}"; do
        [[ $x = "cdenv load" ]] && __found=1
    done

    if [[ $__found -eq 1 ]]; then
        c.debug "cdenv is already installed"
    else
        # Using +=() should always work regardless of whether PROMPT_COMMAND is
        # unset, a normal variable or an array. The result however will be an
        # array.
        c.debug "add to \$PROMPTCOMMAND"
        PROMPT_COMMAND+=("cdenv load")
    fi
    unset __found

    c.debug "executable: $CDENV_EXEC"
    c.debug "cache directory: $(c.translate "$CDENV_CACHE/$$")"

    [[ $1 != noinit ]] && cdenv init
fi
