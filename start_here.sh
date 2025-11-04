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
    echo "If the environment directory or any of its files are missing, this script"
    echo "will repair it by creating only the missing components."
    exit 1
}

# --- Function to prompt for and save the version ---
# This is now a function so we can call it for "new" and "repair" scenarios
prompt_and_save_version() {
    local target_env_vars_file=$1
    # --- START FIX: Use relative path for display ---
    local relative_target_file="aap_vars/$(basename "$(dirname "$target_env_vars_file")")/$(basename "$target_env_vars_file")"
    # --- END FIX ---

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
    echo "  -> Saving version to $relative_target_file..."
    echo "CASC_AAP_VERSION=\"$casc_aap_version\"" > "$target_env_vars_file"
    # --- START FIX: Align ...done. ---
    echo "  ...done."
    # --- END FIX ---
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
imports_dir="$env_dir/imports"
exports_dir="$env_dir/exports"
vault_file="$env_dir/vault.yml"
vars_file="$env_dir/vars.yml"
env_vars_file="$env_dir/vars.env"

# --- START FIX: Use relative path for display ---
relative_env_dir="aap_vars/$env"
# --- END FIX ---

vars_template_file="$parent_dir/templates/vars.yml"
vault_template_file="$parent_dir/templates/vault.yml"

# --- 1. Check for required templates ---
if [[ ! -f "$vault_template_file" ]]; then
    echo "Error: Vault template not found at '$vault_template_file'."
    echo "Cannot create new environment."
    exit 1
fi
if [[ ! -f "$vars_template_file" ]]; then
    echo "Error: Ansible Vars template not found at '$vars_template_file'."
    echo "Cannot create new environment."
    exit 1
fi

# --- 2. Check if environment is already 100% complete ---
if [[ -d "$env_dir" && \
      -d "$imports_dir" && \
      -d "$exports_dir" && \
      -f "$env_vars_file" && \
      -f "$vars_file" && \
      -f "$vault_file" ]]; then
    
    echo "Error: Environment '$env' already exists and appears complete."
    echo "If you want to edit the existing vault, use: ./vault-edit.sh $env"
    exit 1
fi

# --- 3. If not complete, run "create if not exists" logic ---
if [[ ! -d "$env_dir" ]]; then
    echo "🚀 Initializing new environment: $env"
else
    echo "🔧 Repairing environment: $env"
fi

# Set a flag to track if we create a *new* vault, so we know to open the editor
new_vault_created=false

# --- Component 1: Directories ---
if [[ ! -d "$imports_dir" ]]; then
    echo "  -> Creating missing directory: $relative_env_dir/imports"
    mkdir -p "$imports_dir"
fi
if [[ ! -d "$exports_dir" ]]; then
    echo "  -> Creating missing directory: $relative_env_dir/exports"
    mkdir -p "$exports_dir"
fi
# Also ensure common dir exists
mkdir -p "$base_dir/common"

# --- START FIX: Move version prompt to the top ---
# --- Component 0: vars.env (Version File) ---
if [[ ! -f "$env_vars_file" ]]; then
    echo "  -> Creating missing 'vars.env' file..."
    prompt_and_save_version "$env_vars_file"
else
    echo "  -> 'vars.env' file already exists."
fi
# --- END FIX ---


# --- Component 2: vars.yml (Ansible Vars) ---
if [[ ! -f "$vars_file" ]]; then
    echo "  -> Creating missing 'vars.yml' file from template..."
    cp "$vars_template_file" "$vars_file"
else
    echo "  -> 'vars.yml' file already exists."
fi

# --- Component 3: vault.yml (Secrets) ---
if [[ ! -f "$vault_file" ]]; then
    echo "  -> Creating missing 'vault.yml' file from template..."
    cp "$vault_template_file" "$vault_file"
    echo "  -> Encrypting new vault file..."
    
    # --- START FIX: Silence ansible-vault and print our own message ---
    ansible-vault encrypt "$vault_file" > /dev/null
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to encrypt vault. Please check your password and try again."
        # Don't cleanup, as we might be repairing a partial env
        exit 1
    fi
    echo "  -> Encryption successful."
    # --- END FIX ---
    
    new_vault_created=true # Set flag to open editor
else
    echo "  -> 'vault.yml' file already exists."
fi

# --- 4. Final Step: Edit vault if it's brand new ---
echo ""
echo "✅ Environment '$env' is ready."

if [[ "$new_vault_created" = true ]]; then
    echo "Opening new vault file for you to edit. If prompted, please enter the vault password you just created."
    ansible-vault edit "$vault_file"
    echo ""
    echo "🎉 Setup complete! You can now use '$env' with the export/import scripts."
else
    echo "To edit the vault, use: ./vault-edit.sh $env"
fi