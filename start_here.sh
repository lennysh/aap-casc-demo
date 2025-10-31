#!/bin/bash

# Get the directory of the script
parent_dir=$(dirname "$(readlink -f "$0")")

# --- Function to display usage ---
usage() {
    echo "Usage: $0 <environment_name>"
    echo ""
    echo "This script initializes a new environment by:"
    echo "  1. Creating the directory structure (aap_vars/<env_name>/imports, aap_vars/<env_name>/exports)"
    echo "  2. Copying 'vault_template.yml' to 'aap_vars/<env_name>/vault.yml'"
    echo "  3. Encrypting the new 'vault.yml' with ansible-vault"
    echo "  4. Opening the new vault file for editing"
    exit 1
}

# --- Initial Argument Validation ---
if [[ $# -lt 1 ]]; then
    echo "Error: Missing environment name."
    echo ""
    usage
fi

env=$1
base_dir="$parent_dir/aap_vars"
env_dir="$base_dir/$env"
vault_file="$env_dir/vault.yml"
template_file="$parent_dir/templates/vault.yml"

# --- 1. Check for existing environment ---
if [[ -d "$env_dir" ]]; then
    echo "Error: Environment '$env' already exists at '$env_dir'."
    echo "If you want to edit the existing vault, use: ./aapvault-edit.sh $env"
    exit 1
fi

# --- 2. Check for vault template ---
if [[ ! -f "$template_file" ]]; then
    echo "Error: Vault template not found at '$template_file'."
    echo "Cannot create new environment."
    exit 1
fi

echo "🚀 Initializing new environment: $env"

# --- 3. Create directories ---
echo "  -> Creating directory structure..."
mkdir -p "$base_dir/common"
mkdir -p "$env_dir/imports"
mkdir -p "$env_dir/exports"
echo "     ...done: $env_dir/{imports, exports}"

# --- 4. Create and encrypt vault ---
echo "  -> Creating new vault file from template..."
cp "$template_file" "$vault_file"
echo "     ...done: $vault_file"

echo "  -> Encrypting vault file..."
ansible-vault encrypt "$vault_file"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to encrypt vault. Cleaning up."
    rm -rf "$env_dir"
    exit 1
fi
echo "     ...vault encrypted."

# --- 5. Open vault for editing ---
echo ""
echo "✅ Environment '$env' created successfully."
echo "Opening vault file for you to edit. If prompted, please enter the vault password you just created."

ansible-vault edit "$vault_file"

echo ""
echo "🎉 Setup complete! You can now use '$env' with the export/import scripts."