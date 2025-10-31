#!/bin/bash

# Get the directory of the script
parent_dir=$(dirname "$(readlink -f "$0")")
script_vars_dir="$parent_dir/script_vars"

# --- Function to display usage ---
usage() {
    echo "Usage: $0 <environment_name>"
    echo ""
    echo "This script initializes a new environment by:"
    echo "  1. Prompting you to select an AAP version."
    echo "  2. Creating the directory structure (aap_vars/<env_name>/...)"
    echo "  3. Saving your version choice to 'aap_vars/<env_name>/vars.env'"
    echo "  4. Copying 'vault_template.yml' to 'aap_vars/<env_name>/vault.yml'"
    echo "  5. Encrypting the new 'vault.yml' with ansible-vault"
    echo "  6. Opening the new vault file for editing"
    echo ""
    echo "If the environment directory exists but is missing 'vars.env', this script"
    echo "will repair it by prompting for the version and creating the file."
    exit 1
}

# --- Function to prompt for and save the version ---
# This is now a function so we can call it for "new" and "repair" scenarios
prompt_and_save_version() {
    local target_env_vars_file=$1

    # Get available AAP versions
    mapfile -t available_versions < <(find "$script_vars_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort -rV)
    if [[ ${#available_versions[@]} -eq 0 ]]; then
        echo "Error: No AAP versions found in '$script_vars_dir'."
        echo "Please add a version folder (e.g., 'script_vars/2.6/')."
        exit 1
    fi

    # Prompt user to select a version
    echo "Please select the AAP version for this environment:"
    PS3="Enter a number: "
    select casc_aap_version in "${available_versions[@]}"; do
        if [[ -n "$casc_aap_version" ]]; then
            echo "✅ You selected AAP version: $casc_aap_version"
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done

    # Create env vars file
    echo "  -> Saving version to $target_env_vars_file..."
    echo "CASC_AAP_VERSION=\"$casc_aap_version\"" > "$target_env_vars_file"
    echo "     ...done."
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
env_vars_file="$env_dir/vars.env"
template_file="$parent_dir/templates/vault.yml"

# --- 1. Check for existing environment ---
if [[ -d "$env_dir" ]]; then
    # Environment directory exists.
    if [[ ! -f "$env_vars_file" ]]; then
        # --- REPAIR LOGIC ---
        echo "Warning: Environment '$env' exists but is missing its 'vars.env' version file."
        echo "Attempting to repair..."
        prompt_and_save_version "$env_vars_file"
        echo "✅ Environment '$env' repaired successfully."
        echo "You can now run your export/import commands."
        exit 0
    else
        # --- ALREADY EXISTS (NO REPAIR NEEDED) ---
        echo "Error: Environment '$env' already exists at '$env_dir'."
        echo "If you want to edit the existing vault, use: ./vault-edit.sh $env"
        exit 1
    fi
fi

# --- 2. Check for vault template ---
# (This only runs for NEW environments)
if [[ ! -f "$template_file" ]]; then
    echo "Error: Vault template not found at '$template_file'."
    echo "Cannot create new environment."
    exit 1
fi

echo "🚀 Initializing new environment: $env"

# --- 3. Prompt for version ---
# (This only runs for NEW environments)
prompt_and_save_version "$env_vars_file"

# --- 4. Create directories ---
echo "  -> Creating directory structure..."
mkdir -p "$base_dir/common"
mkdir -p "$env_dir/imports"
mkdir -p "$env_dir/exports"
echo "     ...done: $env_dir/{imports, exports}"

# --- 5. Create and encrypt vault ---
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

# --- 6. Open vault for editing ---
echo ""
echo "✅ Environment '$env' created successfully."
echo "Opening vault file for you to edit. If prompted, please enter the vault password you just created."

ansible-vault edit "$vault_file"

echo ""
echo "🎉 Setup complete! You can now use '$env' with the export/import scripts."