#!/bin/bash
#
# List Ansible collections installed for a single AAP version.
# Collections are installed per version under collections/<version>/ by
# install_collections.sh; this script lists only what is in that directory.
#

set -euo pipefail

parent_dir=$(dirname "$(readlink -f "$0")")
collections_base="$parent_dir/collections"

usage() {
    echo "Usage: $0 <version>"
    echo "  List collections installed for AAP <version> in collections/<version>/"
    echo "  Example: $0 2.6"
    exit 1
}

[[ $# -eq 1 ]] || usage
case "$1" in
    -h|--help) usage ;;
esac

ver="$1"
install_dir="$collections_base/$ver"

if [[ ! -d "$install_dir" ]]; then
    echo "No collections directory for AAP $ver: $install_dir" >&2
    exit 1
fi

# Restrict galaxy to this path only (same as install_collections.sh).
ANSIBLE_COLLECTIONS_PATH="$install_dir" ansible-galaxy collection list -p "$install_dir"
