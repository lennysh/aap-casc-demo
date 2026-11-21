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
    echo "Usage: $0 <workspace> <env> (-a|--all | -t|--tags <tags> | -f|--file <path>...) [--playbook|--navigator] [--check|-C] [--allow-duplicates] [--skip-preflight]"
    echo "  -a, --all     Import everything."
    echo "  -t, --tags    Import only these object types (comma-separated tags, listed below)."
    echo "  -f, --file    Import only the objects defined in this file or folder (repeatable). Relative to"
    echo "                the workspace (e.g. common/controller_projects.d/x.yml) or the current directory."
    echo "                Can be combined with -t."
    echo "  --playbook    Use ansible-playbook with versioned collections (default). Overrides CASC_USE_PLAYBOOK."
    echo "  --navigator   Use ansible-navigator with the EE from script_vars. Overrides CASC_USE_PLAYBOOK."
    echo "  --check, -C   Run in Ansible check mode (dry-run; no changes)."
    echo "  --allow-duplicates  Import even if an object is defined more than once with different values."
    echo "  --skip-preflight    Don't check that every object resolves (all variables defined) before connecting to AAP."
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
CHECK_MODE=false
ALLOW_DUPLICATES=false
SKIP_PREFLIGHT=false
ONLY_FILES=()
invocation_dir=$PWD
filtered_args=()
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    arg=${args[i]}
    if [[ "$arg" == "-f" || "$arg" == "--file" ]]; then
        if (( i + 1 >= ${#args[@]} )) || [[ -z "${args[i+1]}" ]]; then
            echo "Error: $arg requires a file or folder path."
            usage
        fi
        i=$((i + 1))
        ONLY_FILES+=("${args[i]}")
    elif [[ "$arg" == --file=* ]]; then
        ONLY_FILES+=("${arg#--file=}")
    elif [[ "$arg" == "--playbook" ]]; then
        USE_ANSIBLE_PLAYBOOK=true
    elif [[ "$arg" == "--navigator" ]]; then
        USE_ANSIBLE_PLAYBOOK=false
    elif [[ "$arg" == "--check" ]] || [[ "$arg" == "-C" ]]; then
        CHECK_MODE=true
    elif [[ "$arg" == "--allow-duplicates" ]]; then
        ALLOW_DUPLICATES=true
    elif [[ "$arg" == "--skip-preflight" ]]; then
        SKIP_PREFLIGHT=true
    else
        filtered_args+=("$arg")
    fi
done

# -f on its own needs neither -a nor -t (the file list is the filter).
if [[ ${#ONLY_FILES[@]} -gt 0 ]]; then
    has_scope=false
    for arg in "${filtered_args[@]:2}"; do
        [[ "$arg" == "-a" || "$arg" == "--all" || "$arg" == "-t" || "$arg" == "--tags" ]] && has_scope=true
    done
    [[ "$has_scope" == "true" ]] || filtered_args+=("-a")
fi

# --- Initialize and Validate ---
# Pass "import" to build the correct yq keys, and pass script arguments (without --playbook).
# scripts/common_functions.sh will parse $env and load the $CASC_AAP_VERSION from it.
initialize_and_validate "import" "${filtered_args[@]}"

# --- Resolve -f paths: absolute, relative to the current directory, or relative to the workspace ---
only_files_json=""
if [[ ${#ONLY_FILES[@]} -gt 0 ]]; then
    for path in "${ONLY_FILES[@]}"; do
        if [[ "$path" == /* ]]; then
            candidate=$path
        elif [[ -e "$invocation_dir/$path" ]]; then
            candidate="$invocation_dir/$path"
        else
            candidate="$orgs_vars_dir/$org/$path"
        fi
        if [[ ! -e "$candidate" ]]; then
            echo "Error: -f '$path' not found (looked in $invocation_dir/ and $orgs_vars_dir/$org/)."
            exit 1
        fi
        if [[ -d "$candidate" ]]; then
            candidate=$(cd "$candidate" && pwd)
        else
            candidate="$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
        fi
        escaped=${candidate//\\/\\\\}
        escaped=${escaped//\"/\\\"}
        only_files_json+="${only_files_json:+, }\"$escaped\""
    done
fi

# --- Vault password (prompt if no vault password file is configured/present) ---
ensure_vault_password "$orgs_vars_dir/$org/$env/vault.yml" "$orgs_vars_dir/$org/common/vault.yml"

# --- Build and Execute Command ---
cd "$parent_dir" || { echo "Failed to change directory to $parent_dir"; exit 1; }

playbook_args=(
    "import_export.yml"
    "-e" "import_export_mode=import"
    "-e" "casc_aap_version=$CASC_AAP_VERSION" # Note: $CASC_AAP_VERSION is set in scripts/common_functions.sh
    "-e" "{orgs: $org, dir_orgs_vars: orgs_vars, env: $env}"
    "-e" "{env_dir: $orgs_vars_dir/$org/$env}"
    "-e" "{common_dir: $orgs_vars_dir/$org/common}"
    "-e" "@$orgs_vars_dir/$org/$env/vault.yml"
    "-e" "@$orgs_vars_dir/$org/$env/vars.yml"
)

if [ -n "$tags" ]; then
    playbook_args+=("--tags" "$tags")
fi

if [[ "$CHECK_MODE" == "true" ]]; then
    playbook_args+=("--check")
fi

if [[ "$ALLOW_DUPLICATES" == "true" ]]; then
    playbook_args+=("-e" "import_export_allow_duplicates=true")
fi

if [[ -n "$only_files_json" ]]; then
    playbook_args+=("-e" "{\"import_export_only_files\": [$only_files_json]}")
fi

if [[ "$SKIP_PREFLIGHT" == "true" ]]; then
    playbook_args+=("-e" "import_export_preflight=false")
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
    # Use only this path for this run (override; no export so caller's env is untouched).
    ANSIBLE_COLLECTIONS_PATH="$collections_dir" ansible-playbook "${playbook_args[@]}"
else
    mapfile -t navigator_vault_args < <(vault_navigator_args)
    ansible-navigator run "${playbook_args[@]}" "${navigator_vault_args[@]}" \
        --mode stdout \
        --pae false \
        --pull-policy missing \
        --execution-environment-image "$execution_environment" \
        --execution-environment-volume-mounts "$(pwd):/home/user:Z"
fi