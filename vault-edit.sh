#!/bin/bash

# Get the directory of the script
parent_dir=$(dirname "$(readlink -f "$0")")

# --- Function to display usage ---
# Moved to the top and made generic for better script structure.
usage() {
    echo "Usage: $0 <env>"
    exit 1
}

base_dir="$parent_dir/aap_vars"

# --- Initial Argument Validation ---
# Ensure the two mandatory arguments are provided.
if [[ $# -lt 1 ]]; then
    echo "Error: Missing environment argument."
    echo ""
    # List available environments for the given organization.
    available_envs=$(find "$base_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f|" | sed 's/|$//')
    echo "Available environments: {$available_envs}"
    usage
fi

env=$1

# --- Validate Environment ---
# Check if the environment exists and is not the 'common' directory.
if [[ ! -d "$base_dir/$env" ]]; then
    echo "Error: Environment '$env' not found or is invalid."
    echo ""
    # List available environments for the given organization.
    available_envs=$(find "$base_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f|" | sed 's/|$//')
    echo "Available environments: {$available_envs}"
    exit 1
fi

# Change to the playbooks directory.
cd "$parent_dir" || { echo "Failed to change directory to $parent_dir"; exit 1; }

# --- Define the file to edit and execute the command ---
file_to_edit="${base_dir}/${env}/vault.yml"

echo "Opening vault file: $file_to_edit"
ansible-vault edit "$file_to_edit"