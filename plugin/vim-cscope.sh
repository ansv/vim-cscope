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
    egrep -i "\.[ch](|pp|\+\+)$|\.cc$"
}

get_wd_() {
    echo "$1" |sed -r "s,/\.cscope$,,;s,/\.(git|svn|hg)$,,"
}

track_all_new_() {
    local pp="$1"
    local wd="$(get_wd_ "$pp")"
    local t=$(mktemp)

    mkdir -p "$pp"

    {
        cat
        [ -e "$pp"/tmp.files ] && cat "$pp"/tmp.files{,}
        [ -e "$pp"/cscope.files ] && cat "$pp"/cscope.files{,}
    } |sort |uniq -u |tee $t |while read s; do
        echo "${s#"$wd"/}"
    done >>"$pp/files"

    [ -s $t ] || { rm -f $t; return 1; }

    cat $t >>"$pp"/tmp.files
    rm -f $t
    return 0
}

# Adds the name of an existing c/cpp file into the cscope namefile tmp.files
# unless it is already there or in the namefile cscope.files
#
# If the 1st parameter is the directory name then adds all files from this
# directory and their subdirectories according to the rules above.
#
# Returns with the status 0 iif at least one file is added.
#

track_project() {
    local pp="$1"
    local filter="${2:-cat}"
    local wd="$(get_wd_ "$pp")"
    find -L "$wd"/* -type f |only_sources_ |$filter |track_all_new_ "$pp"
}

track_file() {
    local pp="$1"
    local file="$2"
    readlink -f "$(find -L "$file" -type f)" |track_all_new_ "$pp"
}

# Checks if the file is tracked by the tmp.files
#
# Returns with the status 0 iif file is tracked.
#
is_tracked() {
    local pp="$1"
    local file="$2"
    [ -e "$pp"/tmp.files ] &&
        grep -m 1 -q "^${file}$" "$pp"/tmp.files
}

# Rebuilds the cross-references for the files in the tmp.files
#
rebuild() {
    local pp="$1"
    cd "$pp"
    [ -e tmp.files ] &&
        cscope -b -q -k -i tmp.files -f tmp.xref ||
        rm -f "$pp"/tmp.xref*
}

cscope_file() {
    printf "%s" "$1/tmp.xref"
}

convert_() {
    local p="$1"
    local wd="$2"

    if [ -d "$p/.cscope" ]; then
        # move from wd to a .repo/ directory if possible
        for repo in .git .hg .svn; do
            [ -d "$p/$repo" ] || continue

            [ ! -e "$p/$repo/.cscope" ] || break # cannot move to a .repo/

            mv "$p/.cscope" "$p/$repo"
            printf "%s" "$p/$repo"
            return
        done
    elif [ -e "$p/.cboss.files" ]; then
        # convert from legacy format
        mkdir "$p/.cscope"

        cat "$p/.cboss.files" |while read s; do
            echo "${s#"$wd"/}"
        done >"$p/.cscope/files"

        rm -f "$p"/.cboss*
    fi

    printf "%s" "$p"
}

init_() {
    local p="$1"
    local wd="$(get_wd_ "$p")"
    local pp="$(convert_ "$p" "$wd")/.cscope"
    cat "$pp/files" |sed "/^[^/]/s,^,$wd/," >"$pp/tmp.files"

    #for d in {0..3}; do
    #    find -L "$wd"/* -maxdepth $d -type f |only_sources_
    #done |head -n 42 |track_all_new_ "$pp"

    printf "%s" "$pp"
}

get_path() {
    local pwd="$(pwd)"
    local p="$pwd"
    while :; do
        [ -d "$p/.cscope" ] && { init_ "$p"; return 0; }
        [ -f "$p/.cboss.files" ] && { init_ "$p"; return 0; }
        [ -d "$p/.git" ] && { init_ "$p/.git"; return 0; }
        [ -d "$p/.hg" ] && { init_ "$p/.hg"; return 0; }
        [ -d "$p/.svn" ] && { init_ "$p/.svn"; return 0; }
        p="$(dirname "$p")"
        [ "$p" = "/" ] && { printf "%s" "$pwd"; return 0; }
    done
}

"$@"
