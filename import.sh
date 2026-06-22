#!/usr/bin/env bash

set -euo pipefail

# Get the directory of the script and source common functions
parent_dir=$(dirname "$(readlink -f "$0")")
orgs_vars_dir="$parent_dir/orgs_vars"
script_vars_dir="$parent_dir/script_vars"

# --- Main usage function ---
# MUST be defined *before* sourcing common_functions.sh
usage() {
    local org_context=$1
    local env_context=$2
    echo "Usage: $0 <org> <env> [--playbook|--navigator] [-a|--all] [-t|--tags <tags>]"
    echo "  --playbook    Use ansible-playbook (versioned collections). Overrides CASC_USE_PLAYBOOK."
    echo "  --navigator   Use ansible-navigator with EE (default). Overrides CASC_USE_PLAYBOOK."
    echo "  Default: use CASC_USE_PLAYBOOK env (1/true/yes = playbook); else navigator."
    echo ""

    if [[ -z "$org_context" ]] || [[ -z "$env_context" ]]; then
        # No org or env provided, just exit with simple usage
        exit 1
    fi

    # --- Env was provided, so try to show context-specific tags ---
    local env_vars_file="$orgs_vars_dir/$org_context/$env_context/vars.env"
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

    if [[ ${#import_category_tags[@]} -gt 0 ]]; then
        # Use printf to join the array with ", "
        local category_tags_string
        category_tags_string=$(printf '%s, ' "${import_category_tags[@]}")

        # Echo the string, removing the final trailing ", "
        echo "Category Tags: ${category_tags_string%, }"
        echo ""
    fi

    echo "Specific Tags Supported (for AAP $CASC_AAP_VERSION):"
    for category in "${import_specific_tags_categories[@]}"; do
        echo "  $category:"
        read -ra tags_array <<< "${import_specific_tags[$category]}"
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

# --- Parse --playbook / --navigator (must be done before initialize_and_validate) ---
# Default from env: CASC_USE_PLAYBOOK=1 or true or yes → playbook; else navigator.
case "${CASC_USE_PLAYBOOK:-1}" in
    1|true|yes|TRUE|YES) USE_ANSIBLE_PLAYBOOK=true ;;
    *)                   USE_ANSIBLE_PLAYBOOK=false ;;
esac
filtered_args=()
for arg in "$@"; do
    if [[ "$arg" == "--playbook" ]]; then
        USE_ANSIBLE_PLAYBOOK=true
    elif [[ "$arg" == "--navigator" ]]; then
        USE_ANSIBLE_PLAYBOOK=false
    else
        filtered_args+=("$arg")
    fi
done

# --- Initialize and Validate ---
# Pass "import" to build the correct yq keys, and pass script arguments (without --playbook).
# common_functions.sh will parse $env and load the $CASC_AAP_VERSION from it.
initialize_and_validate "import" "${filtered_args[@]}"

# --- Build and Execute Command ---
cd "$parent_dir" || { echo "Failed to change directory to $parent_dir"; exit 1; }

playbook_args=(
    "import_export.yml"
    "-e" "import_export_mode=import"
    "-e" "casc_aap_version=$CASC_AAP_VERSION" # Note: $CASC_AAP_VERSION is set in common_functions.sh
    "-e" "{orgs: $org, dir_orgs_vars: orgs_vars, env: $env}"
    "-e" "{env_dir: $orgs_vars_dir/$org/$env}"
    "-e" "{common_dir: $orgs_vars_dir/$org/common}"
    "-e" "@$orgs_vars_dir/$org/$env/vault.yml"
    "-e" "@$orgs_vars_dir/$org/$env/vars.yml"
)

if [ -n "$tags" ]; then
    playbook_args+=("--tags" "$tags")
fi

echo "Running playbook for AAP version: $CASC_AAP_VERSION ($( [[ "$USE_ANSIBLE_PLAYBOOK" == "true" ]] && echo 'ansible-playbook' || echo 'ansible-navigator/EE' ))"

if [[ "$USE_ANSIBLE_PLAYBOOK" == "true" ]]; then
    # Use ansible-playbook with a version-specific collections path (no EE).
    # Collections must be installed per AAP version via install_collections.sh.
    collections_dir="$parent_dir/collections/$CASC_AAP_VERSION"
    if [[ ! -d "$collections_dir" ]] || [[ ! -d "$collections_dir/ansible_collections" ]]; then
        echo "Error: Collections not found for AAP $CASC_AAP_VERSION at $collections_dir"
        echo "Run ./install_collections.sh to install collections for each AAP version."
        exit 1
    fi
    # Use only this path for this run (override; no export so caller's env is untouched).
    ANSIBLE_COLLECTIONS_PATH="$collections_dir" ansible-playbook "${playbook_args[@]}"
else
    ansible-navigator run "${playbook_args[@]}" \
        --mode stdout \
        --pae false \
        --pull-policy missing \
        --execution-environment-image "$execution_environment" \
        --execution-environment-volume-mounts "$(pwd):/home/user:Z"
fi