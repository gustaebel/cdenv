#!/bin/bash
#
# cdenv
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
CDENV_CACHE="$HOME/.cache/cdenv"

[[ -e $HOME/$CDENV_RCFILE ]] && source "$HOME/$CDENV_RCFILE"

# Create a directory for the restore files which will be removed in the EXIT
# trap handler.
mkdir -p "$CDENV_CACHE/$$"

__cdenv_exit() {
    rm -r "$CDENV_CACHE/$$"
}
trap __cdenv_exit EXIT


__cdenv_msg() {
    # Print a message to stderr.
    [[ $CDENV_VERBOSE -ge 1 ]] && echo $@ >&2
}

__cdenv_debug() {
    # Print a debug message to stderr.
    [[ $CDENV_VERBOSE -ge 2 ]] && echo "cdenv: $@" >&2
}

__cdenv_safe_source() {
    # Make sure to source every file with its parent directory as the current
    # working directory. We must save OLDPWD too because it is implicitly set
    # by cd.
    local oldpwd="$OLDPWD"
    local savedir="$PWD"
    builtin cd "$(dirname "$1")"
    source "$(basename "$1")"
    builtin cd "$savedir"
    OLDPWD="$oldpwd"
}

__cdenv_translate() {
    # Translate /home/user/foo to ~/foo/.
    local path="$(realpath --relative-base "$HOME" "$1")"
    if [[ ${path:0:1} != / ]]; then
        if [[ $path = . ]]; then
            echo "~/"
        else
            echo "~/$path/"
        fi
    else
        echo "$path/"
    fi
}

__cdenv_restore_path() {
    # Save restore files in ~/.cache/cdenv/<pid>/<path>.sh.
    echo "$CDENV_CACHE/$$/$(echo ${1:1} | tr / _).sh"
}

__cdenv_load() {
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
            [[ $oldpwd = $pwd ]] && return;
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
        __cdenv_unsource "$directory"
    done

    # Source the needed cdenv files.
    for directory in "${load[@]}"; do
        __cdenv_source "$directory"
    done
}

__cdenv_unsource() {
    # Undo the changes from a single cdenv file.
    local directory="$1"
    local path="$(__cdenv_restore_path "$directory")"
    __cdenv_msg "unsource $(__cdenv_translate "$directory")"
    if [[ -e $path ]]; then
        __cdenv_safe_source "$path"
        rm "$path"
    fi
}

__cdenv_source() {
    # Source a single cdenv file and keep track of the changes to the
    # environment.
    local directory="$1"
    local path="$directory/$CDENV_FILE"
    local tmp="$CDENV_CACHE/$$.tmp"

    # Save a snapshot of the environment.
    { declare -p; declare -f; alias; } > "$tmp"

    # Source the cdenv file.
    __cdenv_msg "source $(__cdenv_translate "$directory")"
    __cdenv_safe_source "$path"

    # Save another snapshot of the environment and compare both. Create a
    # restore file that can be used to undo all changes to the environment when
    # changing to another directory.
    { declare -p; declare -f; alias; } | eval "$($CDENV_EXEC compare "$tmp" "$(__cdenv_restore_path "$directory")")"
    rm "$tmp"
}

cdenv() {
    case "$1" in
        init)
            __cdenv_load init
            CDENV_LAST="$PWD"
            ;;

        load)
            __cdenv_load update "${CDENV_LAST:-/}"
            CDENV_LAST="$PWD"
            ;;

        reload)
            # reload rc file
            [[ -e $HOME/$CDENV_RCFILE ]] && source "$HOME/$CDENV_RCFILE"
            # reload self
            source "$CDENV_INSTALL" noinit
            __cdenv_load reload
            ;;

        edit)
            # unload
            local path="$(__cdenv_restore_path "$directory")"
            [[ -e "$path" ]] && __cdenv_unsource "$directory"
            # edit
            ${EDITOR:-vi} $CDENV_FILE
            # reload
            [[ -e "$CDENV_FILE" ]] && __cdenv_source "$PWD"
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

commands:
    help        this help message
    reload      reload the complete cdenv environment and all $CDENV_FILE
                in the current directory traversal
    edit        edit the $CDENV_FILE in the current working directory
                and reload it
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
    found=0
    for x in "${PROMPT_COMMAND[@]}"; do
        [[ $x = "cdenv load" ]] && found=1
    done

    if [[ $found -eq 1 ]]; then
        __cdenv_debug "cdenv is already installed, reloading"
    else
        # Using +=() should always work regardless of whether PROMPT_COMMAND is
        # unset, a normal variable or an array. The result however will be an
        # array.
        __cdenv_debug "add to \$PROMPTCOMMAND"
        PROMPT_COMMAND+=("cdenv load")
    fi
    unset found

    __cdenv_debug "executable: $CDENV_EXEC"
    __cdenv_debug "cache directory: $(__cdenv_translate "$CDENV_CACHE/$$")"

    [[ $1 = noinit ]] || cdenv init
fi
