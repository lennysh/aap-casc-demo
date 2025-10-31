#!/bin/bash

set -euo pipefail

# Get the directory of the script and source common functions
parent_dir=$(dirname "$(readlink -f "$0")")
aap_vars_dir="$parent_dir/aap_vars"
script_vars_dir="$parent_dir/script_vars"

# --- Main usage function ---
# MUST be defined *before* sourcing common_functions.sh
usage() {
    local env_context=$1
    echo "Usage: $0 <env> [-a|--all] [-t|--tags <tags>]"
    echo ""

    if [[ -z "$env_context" ]]; then
        # No env provided, just exit with simple usage
        exit 1
    fi

    # --- Env was provided, so try to show context-specific tags ---
    local env_vars_file="$aap_vars_dir/$env_context/vars.env"
    if [[ ! -f "$env_vars_file" ]]; then
        echo "Warning: Could not load vars for env '$env_context' to show available tags."
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$env_vars_file" # Loads $CASC_AAP_VERSION

    local script_vars_file="$script_vars_dir/$CASC_AAP_VERSION/vars.env"
    if [[ ! -f "$script_vars_file" ]]; then
        echo "Warning: Tag definition file not found for version '$CASC_AAP_VERSION'."
        exit 1
    fi

    # Source the env file to get the arrays
    # shellcheck source=/dev/null
    source "$script_vars_file"

    if [[ ${#export_category_tags[@]} -gt 0 ]]; then
        # Use printf to join the array with ", "
        local category_tags_string
        category_tags_string=$(printf '%s, ' "${export_category_tags[@]}")
        
        # Echo the string, removing the final trailing ", "
        echo "Category Tags: ${category_tags_string%, }"
        echo ""
    fi
    
    echo "Specific Tags Supported (for AAP $CASC_AAP_VERSION):"
    for category in "${export_specific_tags_categories[@]}"; do
        echo "  $category:"
        read -ra tags_array <<< "${export_specific_tags[$category]}"
        local tags_string
        tags_string=$(printf '%s, ' "${tags_array[@]}")
        echo "${tags_string%, }" | fold -s -w 70 | sed 's/^/    /'
        echo ""
    done
    exit 1
}

# Source common functions *after* usage() is defined
# shellcheck source=common_functions.sh
source "$parent_dir/common_functions.sh"

# --- Initialize and Validate ---
# Pass "export" to build the correct yq keys, and pass all script arguments with "$@"
# common_functions.sh will parse $env and load the $CASC_AAP_VERSION from it.
initialize_and_validate "export" "$@"

# --- Build and Execute Command ---
dest_folder="aapexport_${env,,}_$(date +%Y%m%d_%H%M%S)"
cd "$parent_dir" || { echo "Failed to change directory to $parent_dir"; exit 1; }

playbook_args=(
    "export.yml"
    "-e" "casc_aap_version=$CASC_AAP_VERSION" # Note: $CASC_AAP_VERSION is set in common_functions.sh
    "-e" "{output_path: $aap_vars_dir/$env/exports/$dest_folder}"
    "-e" "@$aap_vars_dir/$env/vault.yml"
    "-e" "@$aap_vars_dir/$env/vars.yml"
)

if [ -n "$tags" ]; then
    quoted_tags="\"${tags//,/'","'}\""
    extra_vars=$(printf '{"input_tag": [%s]}' "$quoted_tags")
    playbook_args+=("-e" "$extra_vars")
fi

echo "Running playbook for AAP version: $CASC_AAP_VERSION"
ansible-navigator run "${playbook_args[@]}" \
    --mode stdout \
    --pae false \
    --pull-policy missing \
    --execution-environment-image "$execution_environment" \
    --execution-environment-volume-mounts "$(pwd):/home/user:Z"