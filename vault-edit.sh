#!/bin/bash

set -euo pipefail

# Get the directory of the script
parent_dir=$(dirname "$(readlink -f "$0")")

# --- Function to display usage ---
# Moved to the top and made generic for better script structure.
usage() {
    echo "Usage: $0 <workspace> <env|common>"
    exit 1
}

orgs_vars_dir="$parent_dir/orgs_vars"
# shellcheck source=scripts/vault_functions.sh
source "$parent_dir/scripts/vault_functions.sh"

# --- Initial Argument Validation ---
# Ensure the two mandatory arguments are provided.
if [[ $# -lt 2 ]]; then
    echo "Error: Missing workspace or environment argument."
    echo ""
    if [[ $# -eq 0 ]]; then
        # No arguments provided, show usage
        usage
    elif [[ $# -eq 1 ]]; then
        # Only workspace provided, list available environments for that workspace
        org=$1
        org_base_dir="$orgs_vars_dir/$org"
        if [[ -d "$org_base_dir" ]]; then
            available_envs=$(find "$org_base_dir" -mindepth 1 -maxdepth 1 -type d -not -name "common" -printf "%f|" | sed 's/|$//')
            echo "Available environments in '$org': {$available_envs}"
        else
            if [[ -d "$orgs_vars_dir" ]]; then
                available_orgs=$(find "$orgs_vars_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f|" | sed 's/|$//')
                echo "Available workspaces: {$available_orgs}"
            fi
        fi
    fi
    usage
fi

org=$1
VAULT_WORKSPACE=$org
env=$2
org_base_dir="$orgs_vars_dir/$org"

# --- Validate Workspace ---
if [[ ! -d "$org_base_dir" ]]; then
    echo "Error: Workspace '$org' not found under orgs_vars/."
    echo ""
    if [[ -d "$orgs_vars_dir" ]]; then
        available_orgs=$(find "$orgs_vars_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f|" | sed 's/|$//')
        echo "Available workspaces: {$available_orgs}"
    fi
    exit 1
fi

# --- Validate Environment (only for non-common; common may not exist yet) ---
if [[ "$env" != "common" ]] && [[ ! -d "$org_base_dir/$env" ]]; then
    echo "Error: Environment '$env' not found in workspace '$org'."
    echo ""
    available_envs=$(find "$org_base_dir" -mindepth 1 -maxdepth 1 -type d -not -name "common" -printf "%f|" | sed 's/|$//')
    echo "Available environments in '$org': {$available_envs}"
    exit 1
fi

# Change to the playbooks directory.
cd "$parent_dir" || { echo "Failed to change directory to $parent_dir"; exit 1; }

# --- Define the file to edit ---
file_to_edit="${org_base_dir}/${env}/vault.yml"
vault_template_dir="$parent_dir/templates"

# --- Create vault from template if it doesn't exist ---
if [[ ! -f "$file_to_edit" ]]; then
    mkdir -p "$(dirname "$file_to_edit")"
    if [[ "$env" == "common" ]]; then
        template="$vault_template_dir/vault_common.yml"
    else
        template="$vault_template_dir/vault.yml"
    fi
    if [[ ! -f "$template" ]]; then
        echo "Error: Vault template not found: $template"
        exit 1
    fi
    # A new vault must use the same password as the workspace's existing vaults.
    reference_vault=$(find "$org_base_dir" -mindepth 2 -maxdepth 2 -name vault.yml 2>/dev/null | head -1)
    ensure_vault_password --confirm ${reference_vault:+"$reference_vault"}
    echo "Creating new vault from template: $template"
    cp "$template" "$file_to_edit"
    echo "Encrypting new vault..."
    if ! ansible-vault encrypt "$file_to_edit"; then
        rm -f "$file_to_edit"
        echo "Error: Failed to encrypt $file_to_edit"
        exit 1
    fi
else
    ensure_vault_password "$file_to_edit"
fi

echo "Opening vault file: $file_to_edit"
ansible-vault edit "$file_to_edit"