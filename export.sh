#!/usr/bin/env bash

set -euo pipefail

# Get the directory of the script and source common functions
parent_dir=$(dirname "$(readlink -f "$0")")
orgs_vars_dir="$parent_dir/orgs_vars"
script_vars_dir="$parent_dir/script_vars"

# --- Main usage function ---
# MUST be defined *before* sourcing scripts/common_functions.sh
usage() {
    local org_context=$1
    local env_context=$2
    echo "Usage: $0 <workspace> <env> [--playbook|--navigator] [--check|-C] [-o|--export-path <dir>] [--clean] [-a|--all] [-t|--tags <tags>]"
    echo "  --playbook    Use ansible-playbook with versioned collections (default). Overrides CASC_USE_PLAYBOOK."
    echo "  --navigator   Use ansible-navigator with the EE from script_vars. Overrides CASC_USE_PLAYBOOK."
    echo "  --check, -C   Run in Ansible check mode (dry-run; no changes)."
    echo "  -o, --export-path <dir>  Write export to this directory instead of orgs_vars/.../exports/<timestamp>."
    echo "  --clean       Before exporting, delete flat_version/ and filetree_version/ in the export directory,"
    echo "                so objects removed from AAP don't linger from a previous export. Other files in the"
    echo "                directory (e.g. .git) are kept. Use it when re-exporting into the same -o directory."
    echo "  Default: CASC_USE_PLAYBOOK env (unset/1/true/yes = playbook; anything else = navigator)."
    echo ""

    if [[ -z "$org_context" ]] || [[ -z "$env_context" ]]; then
        # No workspace or env provided, just exit with simple usage
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
# shellcheck source=scripts/common_functions.sh
source "$parent_dir/scripts/common_functions.sh"
# shellcheck source=scripts/vault_functions.sh
source "$parent_dir/scripts/vault_functions.sh"

# --- Parse --playbook / --navigator / --check (must be done before initialize_and_validate) ---
# Default from env: CASC_USE_PLAYBOOK unset, 1, true or yes → playbook; anything else → navigator.
case "${CASC_USE_PLAYBOOK:-1}" in
    1|true|yes|TRUE|YES) USE_ANSIBLE_PLAYBOOK=true ;;
    *)                   USE_ANSIBLE_PLAYBOOK=false ;;
esac
CUSTOM_EXPORT_PATH=""
CHECK_MODE=false
CLEAN_EXPORT=false
filtered_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --playbook)
            USE_ANSIBLE_PLAYBOOK=true
            shift
            ;;
        --navigator)
            USE_ANSIBLE_PLAYBOOK=false
            shift
            ;;
        --check|-C)
            CHECK_MODE=true
            shift
            ;;
        -o|--export-path)
            if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                echo "Error: $1 requires a directory path argument."
                exit 1
            fi
            CUSTOM_EXPORT_PATH=$2
            shift 2
            ;;
        --clean)
            CLEAN_EXPORT=true
            shift
            ;;
        *)
            filtered_args+=("$1")
            shift
            ;;
    esac
done

# --- Initialize and Validate ---
# Pass "export" to build the correct yq keys, and pass script arguments (without --playbook).
# scripts/common_functions.sh will parse $env and load the $CASC_AAP_VERSION from it.
initialize_and_validate "export" "${filtered_args[@]}"

# --- Vault password (prompt if no vault password file is configured/present) ---
ensure_vault_password "$orgs_vars_dir/$org/$env/vault.yml"

# --- Build and Execute Command ---
if [[ -n "${CUSTOM_EXPORT_PATH:-}" ]]; then
    export_dest=$CUSTOM_EXPORT_PATH
else
    dest_folder="${org,,}_${env,,}_export_$(date +%Y%m%d_%H%M%S)"
    export_dest="$orgs_vars_dir/$org/$env/exports/$dest_folder"
fi
cd "$parent_dir" || { echo "Failed to change directory to $parent_dir"; exit 1; }

# --- --clean: remove the previous export's layout folders before writing a new one ---
# Called right before the playbook runs (after all validation), so a failed check never
# deletes the last export. Runs after the cd above, so a relative -o path resolves the same
# way it does for the playbook. Only the two folders the export writes are removed; anything
# else in the directory (e.g. a .git folder) is left alone.
clean_export_dest() {
    [[ "$CLEAN_EXPORT" == "true" ]] || return 0
    if [[ "$CHECK_MODE" == "true" ]]; then
        echo "Note: --clean skipped in check mode (nothing is written, so the previous export is kept)."
        return 0
    fi
    local sub target
    for sub in flat_version filetree_version; do
        target="$export_dest/$sub"
        if [[ -d "$target" ]]; then
            echo "Cleaning previous export: $target"
            rm -rf -- "$target"
        fi
    done
}

playbook_args=(
    "import_export.yml"
    "-e" "import_export_mode=export"
    "-e" "casc_aap_version=$CASC_AAP_VERSION" # Note: $CASC_AAP_VERSION is set in scripts/common_functions.sh
    "-e" "export_path=$export_dest"
    "-e" "@$orgs_vars_dir/$org/$env/vault.yml"
    "-e" "@$orgs_vars_dir/$org/$env/vars.yml"
    # filetree_create option: write the flat_version/ export (filetree_version/ is built from it).
    # Passed last so an old flatten_output in vars.yml can't override it.
    "-e" "flatten_output=true"
)

if [ -n "$tags" ]; then
    quoted_tags="\"${tags//,/'","'}\""
    extra_vars=$(printf '{"input_tag": [%s]}' "$quoted_tags")
    playbook_args+=("-e" "$extra_vars")
fi

if [[ "$CHECK_MODE" == "true" ]]; then
    playbook_args+=("--check")
fi

echo "Running playbook for AAP version: $CASC_AAP_VERSION ($( [[ "$USE_ANSIBLE_PLAYBOOK" == "true" ]] && echo 'ansible-playbook' || echo 'ansible-navigator/EE' ))$( [[ "$CHECK_MODE" == "true" ]] && echo ', check mode' )"

if [[ "$USE_ANSIBLE_PLAYBOOK" == "true" ]]; then
    # Use ansible-playbook with a version-specific collections path (no EE).
    # Collections must be installed per AAP version via install_collections.sh.
    collections_dir="$parent_dir/collections/$CASC_AAP_VERSION"
    if [[ ! -d "$collections_dir" ]] || [[ ! -d "$collections_dir/ansible_collections" ]]; then
        echo "Error: Collections not found for AAP $CASC_AAP_VERSION at $collections_dir"
        echo "Run ./install_collections.sh to install collections for each AAP version."
        exit 1
    fi
    clean_export_dest
    # Use only this path for this run (override; no export so caller's env is untouched).
    ANSIBLE_COLLECTIONS_PATH="$collections_dir" CONTROLLER_REQUEST_TIMEOUT="${CONTROLLER_REQUEST_TIMEOUT:-60}" ansible-playbook "${playbook_args[@]}"
else
    mapfile -t navigator_vault_args < <(vault_navigator_args)
    clean_export_dest
    ansible-navigator run "${playbook_args[@]}" "${navigator_vault_args[@]}" \
        --mode stdout \
        --pae false \
        --pull-policy missing \
        --execution-environment-image "$execution_environment" \
        --execution-environment-volume-mounts "$(pwd):/home/user:Z"
fi
