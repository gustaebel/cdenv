# cdenv - stdlib.sh
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

c.leave() {
    local funcname=${1:?}
    local path="$(c.restore_path "$(pwd)")"
    if [[ $(type -t $funcname) != function ]]; then
        echo "no function named $funcname" >&2
        return 1
    fi
    c.debug "register leave function $funcname"
    declare -f $funcname >> "$path"
    echo $funcname >> "$path"
    echo "unset -f $funcname" >> "$path"
    unset -f $funcname
}

c.copy() {
    local src=${1:?}
    local dst=${2:?}
    if [[ $(type -t $src) != function ]]; then
        echo "no function named $src" >&2
        return 1
    fi
    eval "$(echo $dst'()'; declare -f $src | tail +2; )"
}

c.rename() {
    copy_function ${1:?} ${2:?}
    unset -f $1
}
