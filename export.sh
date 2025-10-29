#!/bin/bash

# Get the directory of the script and source common functions
parent_dir=$(dirname "$(readlink -f "$0")")
script_vars_dir="$parent_dir/script_vars"
# shellcheck source=common_functions.sh
source "$parent_dir/common_functions.sh"

# --- Main usage function ---
usage() {
    local casc_aap_version_context=$1
    local script_vars_file="$script_vars_dir/${casc_aap_version_context:-2.6}/vars.yml"

    echo "Usage: $0 <aap version> <env> [-a|--all] [-t|--tags <tags>]"
    echo ""

    if [[ -z "$casc_aap_version_context" ]]; then
        exit 1
    fi

    if [[ ! -f "$script_vars_file" ]]; then
        echo "Warning: Tag definition file not found for version '$casc_aap_version_context'."
        exit 1
    fi

    if yq -e '.export_category_tags' "$script_vars_file" >/dev/null; then
        echo "Category Tags: $(yq '.export_category_tags | join(", ")' "$script_vars_file")"
        echo ""
    fi
    
    echo "Specific Tags Supported:"
    yq '(.export_specific_tags | keys)[]' "$script_vars_file" | while read -r category; do
        echo "  $category:"
        tags=$(yq ".export_specific_tags[\"$category\"] | join(\", \")" "$script_vars_file")
        echo "    $tags" | fold -s -w 70 | sed 's/^/    /' | sed '1s/    //'
        echo ""
    done
    exit 1
}

# --- Initialize and Validate ---
# Pass "export" to build the correct yq keys, and pass all script arguments with "$@"
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