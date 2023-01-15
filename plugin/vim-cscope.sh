#!/bin/bash

# Copyright: Copyright (C) 2019 Andrey Shvetsov
# License: The MIT License
#
# This script is the part of the vim-cscope plugin - cscope helper for vim.

# TODO: Add support of spaces and double-quotes in filenames.
#
# See also cscope man:
#
# Filenames in the namefile that contain whitespace have to be enclosed in
# "double quotes".  Inside such quoted filenames, any double-quote and
# backslash characters have to be escaped by backslashes.
#
# Hint: sed -r -e "s,([\"\\]),\\\\\1,g" -e "s,^,\"," -e "s,$,\","
#

only_sources_() {
    grep -iE "\.[ch](|pp|\+\+)$|\.cc$"
}

get_root_dir_() {
    echo "$1" |sed -r "s,/\.cscope$,,;s,/\.(git|svn|hg)$,,"
}

track_all_new_() {
    local pp="$1"
    local rd="$(get_root_dir_ "$pp")"
    local t=$(mktemp)

    mkdir -p "$pp"

    {
        cat # from stdin
        cat "$pp"/tmp.files{,}
        [ -e "$pp"/cscope.files ] && cat "$pp"/cscope.files{,}
    } |sort |uniq -u |tee "$t" |while read -r s; do
        echo "${s#"$rd"/}"
    done >>"$pp"/files

    cat "$t" >>"$pp"/tmp.files

    [ -s "$t" ] || { rm -f "$t"; return 1; }

    rm -f "$t"
    return 0
}

# Add name of existing c/cpp file to the namefile tmp.files
# unless it is already tracked in tmp.files or cscope.files.
#
# If the 1st parameter is the directory name then adds all files from this
# directory and their subdirectories according to the rules above.
#
# Returns with the status 0 iif at least one file is added.
#
cs_track_project() {
    local pp="$1"
    local filter="${2:-cat}"
    local rd="$(get_root_dir_ "$pp")"
    find -L "$rd"/* -type f |only_sources_ |$filter |track_all_new_ "$pp"
}

cs_track_file() {
    local pp="$1"
    local file="$2"
    readlink -f "$(find -L "$file" -type f)" |track_all_new_ "$pp"
}

# Check if the file is tracked by the tmp.files
#
# Return with the status 0 iif file is tracked.
#
cs_is_file_tracked() {
    local pp="$1"
    local file="$2"
    [ -e "$pp"/tmp.files ] &&
        grep -m 1 -q "^${file}$" "$pp"/tmp.files
}

# Rebuild cross-references for the files in the tmp.files
#
async_rebuild_() {
    local pp_id="$1"
    local wd="$2"

    # initialize the tmp.files
    local pp="$pp_id/.."
    if [ -f "$pp"/files ] && [ ! -f "$pp"/tmp.files ]; then
        cd "$wd"
        {
            cat "$pp"/files
            [ -e "$pp"/cscope.files ] && cat "$pp"/cscope.files
        } |while read -r s; do
            readlink -f "$(find -L "$s" -type f)"
        done |sort |uniq >"$pp"/tmp.files
    fi

    mkdir -p "$pp_id"
    cd "$pp_id" || return
    while :; do
        rm -f ../.rebuild
        rm -f tmp.xref*
        cscope -b -q -k -i ../tmp.files -f tmp.xref ||
            rm -f tmp.xref*
        [ -e ../.rebuild ] || break
    done
    rm ../.locked
}

cs_reset() {
    local pp="$1"
    rm -f "$pp"/tmp.files
}

cs_rebuild() {
    local pp="$1"
    local id="$2"
    local pwd="$(pwd)"

    cd "$pp" || return
    :>.rebuild
    [ ! -e .locked ] || return
    :>.locked
    "$0" async_rebuild_ "$pp/$id" "$pwd" &
}

cs_is_file_ready() {
    [ ! -e "$1/.locked" ]
}

cs_get_xref_file() {
    printf "%s" "$1/tmp.xref"
}

init_() {
    local pp="$1/.cscope"
    rm -f "$pp"/.locked
    # remove "tmp.files" if it's not newer than "files"
    [ -f "$pp"/files ] &&
        ! find "$pp"/tmp.files -cnewer "$pp"/files |grep -q ^ &&
        rm -f "$pp"/tmp.files
    printf "%s" "$pp"
}

# Return s:pp like "/path/.git/.cscope" or "/path/.cscope"
#
cs_init() {
    local pwd="$(pwd)"
    local p="$pwd"
    while [ "$p" != "/" ]; do
        [ -d "$p/.cscope" ] && { init_ "$p"; return 0; }
        [ -d "$p/.git" ] && { init_ "$p/.git"; return 0; }
        [ -d "$p/.hg" ] && { init_ "$p/.hg"; return 0; }
        [ -d "$p/.svn" ] && { init_ "$p/.svn"; return 0; }
        p="$(dirname "$p")"
    done
    init_ "$pwd"
    return 0
}

log_() {
    echo "$(date +%T)" "${1:-}" "$(echo "${2:-}" |sed "s,/home/\S*/.cscope\>,\~,")" "${@:3}" >>"$(readlink -f "$0").log"
}

# log_ "${@:-}"

"$@"
