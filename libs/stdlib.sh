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

::leave() {
    local funcname=${1:?}
    local path="$(::restore_path "$(pwd)")"
    if [[ $(type -t $funcname) != function ]]; then
        echo "no function named $funcname" >&2
        return 1
    fi
    ::debug "register leave function $funcname"
    declare -f $funcname >> "$path"
    echo $funcname >> "$path"
    echo "unset -f $funcname" >> "$path"
    unset -f $funcname
}

::copy() {
    local src=${1:?}
    local dst=${2:?}
    if [[ $(type -t $src) != function ]]; then
        echo "no function named $src" >&2
        return 1
    fi
    eval "$(echo $dst'()'; declare -f $src | tail +2; )"
}

::rename() {
    copy_function ${1:?} ${2:?}
    unset -f $1
}

::array_contains() {
    local x="${2:?}"
    local -n __cdenv_array_contains=${1:?}
    local a
    for a in "${__cdenv_array_contains[@]}"; do
        [[ $a == "$x" ]] && return 0
    done
    return 1
}

::array_prepend() {
    ::array_contains ${1:?} "${2:?}" && return 1
    local -n __cdenv_array_prepend=${1:?}
    __cdenv_array_prepend=("$2" "${__cdenv_array_prepend[@]}")
}

::array_append() {
    ::array_contains ${1:?} "${2:?}" && return 1
    local -n __cdenv_array_append=${1:?}
    __cdenv_array_append+=("$2")
}

::array_remove() {
    ::array_contains ${1:?} "${2:?}" || return 1
    local x="$2"
    local -n __cdenv_array_remove=$1
    local i
    for i in "${!__cdenv_array_remove[@]}"; do
        if [[ ${__cdenv_array_remove[$i]} == "$x" ]]; then
            unset '__cdenv_array_remove[i]'
            return 0
        fi
    done
    return 1
}

::set_prepend() {
    ::array_contains ${1:?} "${2:?}" && return 1
    ::array_prepend $1 "$2"
}

::set_append() {
    ::array_contains ${1:?} "${2:?}" && return 1
    ::array_append $1 "$2"
}

::set_remove() {
    ::array_contains ${1:?} "${2:?}" || return 1
    ::array_remove $1 "$2"
}

::var_contains() {
    local -n var=${1:?}
    local sep=${2:-:}
    local -a __cdenv_var_contains
    IFS="$sep" read -ra __cdenv_var_contains <<< "$var"
    ::array_contains __cdenv_var_contains "${2:?}"
}

::var_prepend() {
    ::var_action ::array_prepend ${1:?} "${2:?}" "$3"
}

::var_append() {
    ::var_action ::array_append ${1:?} "${2:?}" "$3"
}

::var_remove() {
    ::var_action ::array_remove ${1:?} "${2:?}" "$3"
}

::setvar_prepend() {
    ::var_action ::set_prepend ${1:?} "${2:?}" "$3"
}

::setvar_append() {
    ::var_action ::set_append ${1:?} "${2:?}" "$3"
}

::setvar_remove() {
    ::var_action ::set_remove ${1:?} "${2:?}" "$3"
}

::var_action() {
    local action=${1:?}
    local -n var=${2:?}
    local x="${3:?}"
    local sep="${4:-:}"

    local -a __cdenv_var_action
    IFS="$sep" read -ra __cdenv_var_action <<< "$var"
    $action __cdenv_var_action "$x" && IFS="$sep" eval 'var="${__cdenv_var_action[*]}"'
}

