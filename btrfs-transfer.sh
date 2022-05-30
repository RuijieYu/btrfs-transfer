#!/bin/bash -e
#
# transfer all available btrfs subvolumes in a btrfs filesystem
# (NOTE: cannot do it for root subvolume, i.e., subvolid=5) into a
# new btrfs filesystem.
#
# dependencies:
# - btrfs-list
# - sudo

help() {
    cat <<EOF
Usage:
    $0 <src-fs> <dest-path>

Options:
    <src-fs>:    Source btrfs filesystem mounted as subvolid=5.
    <dest-path>: Dest btrfs filesystem, assuming different from
                 the filesystem in <src-fs>, and does not need to
                 exist.  The parents of this path will be created
                 using \$(mkdir -p), and this very path will be
                 created as a subvolume.
EOF
    exit
} >&2

# $1 = src-fs
collect_subvols() {
    # must be btrfs subvolume at id=5
    findmnt -n "$1" | grep -q 'subvolid=5,'
    # use tail to get rid of fs and root subvol
    sudo btrfs-list -H --show-toplevel "$1" 2>/dev/null |
        tail -n+3 |
        awk '{print $1}' |
        sort
}

# $1 = src-fs
# stdin = stdout = result of `collect_subvols`
set_readonly() {
    while read sub; do
        sudo btrfs property set "$1/$sub" ro true >/dev/null
        echo "$sub"
    done
}

# $1 = subvol-path
ensure_parent() {
    sudo mkdir -p "$(dirname "$1")"
}

# $1 = subvol-path
subvol_dest() {
    test -d "$1" || sudo btrfs subvolume create "$1"
}

# $1 = src-fs
# $2 = subvol
# $3 = dest-path
# $4 = pipe
transfer() {
    local src_subvol="$1/$2" dest_subvol="$3/$2" pipe="$4"
    for arg; do test -n "$arg"; done

    # it may have already been sent
    test -d "$dest_subvol" || {
        ensure_parent "$dest_subvol"
        (sudo btrfs send -f "$pipe" "$src_subvol" &)
        sudo btrfs receive -f "$pipe" \
            "$(dirname "$dest_subvol")"
    }

    # in any case, make sure it is no longer RO to allow recursive
    sudo btrfs property set -f "$dest_subvol" ro false
}

# $1 = src-fs
# $2 = dest-path
main() {
    # set -vx
    local src="$1" dest="$2" pipe="$(mktemp -u)"
    mkfifo "$pipe"
    echo "pipe: $pipe"

    case "$src" in
    '' | -h | --help) help ;;
    esac

    ensure_parent "$dest"
    subvol_dest "$dest"

    for sub in $(collect_subvols "$src" | set_readonly "$src"); do
        transfer \
            "$src" "$sub" \
            "$dest" "$pipe"
    done
}

main "$@"
