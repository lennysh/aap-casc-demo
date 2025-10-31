#!/bin/bash

# Get the directory of the script and source common functions
parent_dir=$(dirname "$(readlink -f "$0")")
script_vars_dir="$parent_dir/script_vars"

# --- Main usage function ---
usage() {
    local casc_aap_version_context=$1
    # Use .env extension
    local script_vars_file="$script_vars_dir/${casc_aap_version_context:-2.6}/vars.env"

    echo "Usage: $0 <aap version> <env> [-a|--all] [-t|--tags <tags>]"
    echo ""

    if [[ -z "$casc_aap_version_context" ]]; then
        exit 1
    fi

    if [[ ! -f "$script_vars_file" ]]; then
        echo "Warning: Tag definition file not found for version '$casc_aap_version_context'."
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
    
    echo "Specific Tags Supported:"
    for category in "${export_specific_tags_categories[@]}"; do
        echo "  $category:"
        # Read the space-separated string into a temp array
        read -ra tags_array <<< "${export_specific_tags[$category]}"
        
        # Use printf to join the array with ", " after each item
        local tags_string
        tags_string=$(printf '%s, ' "${tags_array[@]}")
        
        # Pipe the string to fold, removing the trailing ", " from the very end
        # The string now has spaces, so "fold -s" will work correctly
        echo "${tags_string%, }" | fold -s -w 70 | sed 's/^/    /'
        echo "" # Add a blank line for spacing between categories
    done
    exit 1
}

# shellcheck source=common_functions.sh
source "$parent_dir/common_functions.sh"

# --- Initialize and Validate ---
# Pass "export" to build the correct keys, and pass all script arguments with "$@"
initialize_and_validate "export" "$@"

# --- Build and Execute Command ---
dest_folder="aapexport_$(date +%Y%m%d_%H%M%S)"
cd "$parent_dir" || { echo "Failed to change directory to $parent_dir"; exit 1; }

playbook_args=(
    "export.yml"
    "-e" "casc_aap_version=$casc_aap_version"
    "-e" "{output_path: $parent_dir/aap_vars/$env/exports/$dest_folder}"
    "-e" "@$parent_dir/aap_vars/$env/vault.yml"
)

if [ -n "$tags" ]; then
    quoted_tags="\"${tags//,/'","'}\""
    extra_vars=$(printf '{"input_tag": [%s]}' "$quoted_tags")
    playbook_args+=("-e" "$extra_vars")
fi

echo "Running playbook for AAP version: $casc_aap_version"
ansible-navigator run "${playbook_args[@]}" \
    --mode stdout \
    --pae false \
    --pull-policy missing \
    --execution-environment-image "$execution_environment" \
    --execution-environment-volume-mounts "$(pwd):/home/user:Z"