#!/bin/bash

# Get the directory of the script
parent_dir=$(dirname "$(readlink -f "$0")")

# --- Function to display usage ---
# Moved to the top and made generic for better script structure.
usage() {
    echo "Usage: $0 <env>"
    exit 1
}

# --- Initial Argument Validation ---
# Ensure the two mandatory arguments are provided.
if [[ $# -lt 1 ]]; then
    echo "Error: Missing environment argument."
    echo ""
    usage
fi

env=$1
base_dir="$parent_dir/aap_vars"

# --- Validate Environment ---
# Check if the environment exists and is not the 'common' directory.
if [[ ! -d "$base_dir/$env" ]]; then
    echo "Error: Environment '$env' not found or is invalid for organization '$org'."
    echo ""
    # List available environments for the given organization.
    available_envs=$(find "$base_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f|" | sed 's/|$//')
    echo "Available environments for '$org': {$available_envs}"
    exit 1
fi

# Change to the playbooks directory.
cd "$parent_dir" || { echo "Failed to change directory to $parent_dir"; exit 1; }

# --- Define the file to edit and execute the command ---
file_to_edit="${base_dir}/${env}/vault.yml"

# Check if the vault file already exists before doing anything.
if [[ -f "$file_to_edit" ]]; then
    echo "Error: Vault file '$file_to_edit' already exists."
    echo "Exiting to prevent overwrite. Use './aapvault-edit.sh $env' to modify it."
    exit 1
fi

echo "Creating vault file '$file_to_edit' from template..."
cp "$parent_dir/vault_template.yml" "$file_to_edit"

echo "Encrypting vault file..."
ansible-vault encrypt "$file_to_edit"

echo "Opening vault file for editing..."
ansible-vault edit "$file_to_edit"