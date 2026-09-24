#!/bin/bash

set -euo pipefail

# Get the directory of the script
parent_dir=$(dirname "$(readlink -f "$0")")

# --- Function to display usage ---
usage() {
    echo "Usage: $0 <org> <env>"
    echo ""
    echo "Decrypts and prints the vault for <org>/<env>, omitting lines that"
    echo "contain (case-insensitive): password, token, or sensitive."
    echo "Mark additional secret lines with #sensitive so they are filtered too."
    exit 1
}

orgs_vars_dir="$parent_dir/orgs_vars"

# --- Initial Argument Validation ---
if [[ $# -lt 2 ]]; then
    echo "Error: Missing organization or environment argument."
    echo ""
    if [[ $# -eq 0 ]]; then
        usage
    elif [[ $# -eq 1 ]]; then
        org=$1
        org_base_dir="$orgs_vars_dir/$org"
        if [[ -d "$org_base_dir" ]]; then
            available_envs=$(find "$org_base_dir" -mindepth 1 -maxdepth 1 -type d -not -name "common" -printf "%f|" | sed 's/|$//')
            echo "Available environments in '$org': {$available_envs}"
        else
            if [[ -d "$orgs_vars_dir" ]]; then
                available_orgs=$(find "$orgs_vars_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f|" | sed 's/|$//')
                echo "Available organizations: {$available_orgs}"
            fi
        fi
    fi
    usage
fi

org=$1
env=$2
org_base_dir="$orgs_vars_dir/$org"

# --- Validate Organization ---
if [[ ! -d "$org_base_dir" ]]; then
    echo "Error: Organization '$org' not found or is invalid."
    echo ""
    if [[ -d "$orgs_vars_dir" ]]; then
        available_orgs=$(find "$orgs_vars_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f|" | sed 's/|$//')
        echo "Available organizations: {$available_orgs}"
    fi
    exit 1
fi

# --- Validate Environment ---
if [[ "$env" != "common" ]] && [[ ! -d "$org_base_dir/$env" ]]; then
    echo "Error: Environment '$env' not found or is invalid in organization '$org'."
    echo ""
    available_envs=$(find "$org_base_dir" -mindepth 1 -maxdepth 1 -type d -not -name "common" -printf "%f|" | sed 's/|$//')
    echo "Available environments in '$org': {$available_envs}"
    exit 1
fi

cd "$parent_dir" || { echo "Failed to change directory to $parent_dir"; exit 1; }

vault_file="${org_base_dir}/${env}/vault.yml"

if [[ ! -f "$vault_file" ]]; then
    echo "Error: Vault file not found: $vault_file"
    echo "Create it first with: ./vault-edit.sh $org $env"
    exit 1
fi

# Patterns that mark a line as sensitive (case-insensitive).
# Matches key names (password/token), #sensitive markers, and similar wording.
sensitive_pattern='password|token|sensitive'

echo "=== Vault (redacted): $vault_file ==="
echo ""

# ansible-vault view decrypts to stdout; filter out sensitive lines.
# grep exits 1 when nothing matches — treat that as success so an all-redacted
# vault does not fail the script under set -e.
ansible-vault view "$vault_file" | grep -viE "$sensitive_pattern" || true

echo ""
echo "=== End of redacted vault (lines matching: $sensitive_pattern) ==="
