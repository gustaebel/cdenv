# cdenv - variables.sh
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

c.array_contains() {
    local x="${2:?}"
    local -n __cdenv_array_contains=${1:?}
    local a
    for a in "${__cdenv_array_contains[@]}"; do
        [[ $a == "$x" ]] && return 0
    done
    return 1
}

c.array_prepend() {
    local -n __cdenv_array_prepend=${1:?}
    __cdenv_array_prepend=("$2" "${__cdenv_array_prepend[@]}")
}

c.array_append() {
    local -n __cdenv_array_append=${1:?}
    __cdenv_array_append+=("$2")
}

c.array_remove() {
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

c.set_prepend() {
    c.array_contains ${1:?} "${2:?}" && return 1
    c.array_prepend $1 "$2"
}

c.set_append() {
    c.array_contains ${1:?} "${2:?}" && return 1
    c.array_append $1 "$2"
}

c.set_remove() {
    c.array_contains ${1:?} "${2:?}" || return 1
    c.array_remove $1 "$2"
}

c.var_contains() {
    local -n var=${1:?}
    local x="${2:-:}"
    local sep="${3:-:}"
    local -a __cdenv_var_contains
    IFS="$sep" read -ra __cdenv_var_contains <<< "$var"
    c.array_contains __cdenv_var_contains "$x"
}

c.var_prepend() {
    c.var_action c.array_prepend ${1:?} "${2:?}" "$3"
}

c.var_append() {
    c.var_action c.array_append ${1:?} "${2:?}" "$3"
}

c.var_remove() {
    c.var_action c.array_remove ${1:?} "${2:?}" "$3"
}

c.setvar_prepend() {
    c.var_action c.set_prepend ${1:?} "${2:?}" "$3"
}

c.setvar_append() {
    c.var_action c.set_append ${1:?} "${2:?}" "$3"
}

c.setvar_remove() {
    c.var_action c.set_remove ${1:?} "${2:?}" "$3"
}

c.var_action() {
    local action=${1:?}
    local -n var=${2:?}
    local x="${3:?}"
    local sep="${4:-:}"

    local -a __cdenv_var_action
    IFS="$sep" read -ra __cdenv_var_action <<< "$var"
    $action __cdenv_var_action "$x" && IFS="$sep" eval 'var="${__cdenv_var_action[*]}"'
}

