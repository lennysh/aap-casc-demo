#!/usr/bin/env bash

_repo_scripts_autocomplete() {
    local cur prev cword
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cword="$COMP_CWORD"

    # Locate the orgs_vars directory relative to this script
    local repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local orgs_vars_dir="$repo_dir/orgs_vars"

    # If the orgs_vars directory doesn't exist yet, there is nothing to complete
    [[ ! -d "$orgs_vars_dir" ]] && return 0

    # Case 1: Completing the 1st argument (ORG)
    if [ "$cword" -eq 1 ]; then
        # Dynamically list only the top-level directories inside orgs_vars
        local orgs
        orgs=$(find "$orgs_vars_dir" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)
        COMPREPLY=( $(compgen -W "${orgs}" -- "$cur") )
        return 0
    fi

    # Case 2: Completing the 2nd argument (ENV)
    if [ "$cword" -eq 2 ]; then
        # The previous argument typed by the user is the selected ORG
        local org_dir="$orgs_vars_dir/$prev"

        # If that ORG folder actually exists, dynamically list its subfolders (envs)
        if [ -d "$org_dir" ]; then
            local envs
            envs=$(find "$org_dir" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)
            COMPREPLY=( $(compgen -W "${envs}" -- "$cur") )
        fi
        return 0
    fi
}

# Automatically register this autocomplete logic for all .sh scripts in this folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for script in "$SCRIPT_DIR"/*.sh; do
    basename_script=$(basename "$script")
    case "$basename_script" in
        start_here.sh|autocomplete.sh) continue ;;
    esac
    complete -F _repo_scripts_autocomplete "$basename_script"
    complete -F _repo_scripts_autocomplete "./$basename_script"
done