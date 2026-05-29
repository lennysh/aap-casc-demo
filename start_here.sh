#!/bin/bash

set -euo pipefail

# Get the directory of the script
parent_dir=$(dirname "$(readlink -f "$0")")
script_vars_dir="$parent_dir/script_vars"
full_aap_folders=()

# --- Function to display usage ---
usage() {
    echo "Usage: $0 <org_name> <environment_name>"
    echo ""
    echo "This script initializes a new environment by:"
    echo "  1. Prompting you to select an AAP version."
    echo "  2. Creating the directory structure (orgs_vars/<org_name>/<env_name>/...)"
    echo "  3. Saving your version choice to 'orgs_vars/<org_name>/<env_name>/vars.env'"
    echo "  4. Copying vault templates to org/env (vault.yml) and org/common (vault.yml from vault_common.yml if missing)"
    echo "  5. Encrypting new vault files with ansible-vault"
    echo "  6. Opening the new env vault file for editing"
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
    local org_name=$2
    local env_name=$3
    local relative_target_file="orgs_vars/$org_name/$env_name/$(basename "$target_env_vars_file")"
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

    # Ask if user wants flattened mode (no AAP subfolders; flatten_output: true in vars.yml)
    echo ""
    read -p "Do you want to use flattened mode? (y/n) [n]: " flatten_choice
    flatten_choice=${flatten_choice:-n}
    if [[ "$flatten_choice" =~ ^[yY] ]]; then
        flatten_output_value="true"
        echo "  -> Flattened mode: YES (no AAP subfolders will be created)"
    else
        flatten_output_value="false"
        echo "  -> Flattened mode: NO (AAP subfolders will be created)"
    fi

    # Create env vars file
    echo "  -> Saving version to $relative_target_file..."
    {
        echo "CASC_AAP_VERSION=\"$casc_aap_version\""
        echo "FLATTEN_OUTPUT=$flatten_output_value"
    } > "$target_env_vars_file"
    # --- START FIX: Align ...done. ---
    echo "  ...done."
    # --- END FIX ---
}

# --- Function ---
# This function loops through the array and creates folders if they don't exist.
ensure_folders_exist() {
    # Loop through ALL arguments passed to the function ("$@")
    for folder in "$@"; do        
        # Check if the directory does NOT exist
        if [ ! -d "$folder" ]; then
            # If it doesn't exist, create it
            echo "  -> Creating missing directory: $folder"
            # Use 'mkdir -p' to create the folder and any missing parent directories
            mkdir -p "$folder"
        fi
    done
}

build_full_aap_folders() {
    local script_vars_file="$script_vars_dir/$CASC_AAP_VERSION/vars.env"
    source "$script_vars_file"
    for folder in "${aap_folders_needed[@]}"; do
        full_aap_folders+=("$relative_env_dir/imports/$folder")
    done
    for folder in "${aap_folders_needed[@]}"; do
        full_aap_folders+=("$org_base_dir/common/$folder")
    done
}


# --- Initial Argument Validation ---
if [[ $# -lt 2 ]]; then
    echo "Error: Missing organization name or environment name."
    echo ""
    if [[ $# -eq 0 ]]; then
        # No arguments provided, show usage and list available orgs
        usage
    elif [[ $# -eq 1 ]]; then
        # Only org provided, prompt for it or show available orgs
        orgs_vars_dir="$parent_dir/orgs_vars"
        if [[ -d "$orgs_vars_dir" ]]; then
            available_orgs=$(find "$orgs_vars_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f|" | sed 's/|$//')
            echo "Available organizations: {$available_orgs}"
        fi
    fi
    usage
fi

org=$1
env=$2
orgs_vars_dir="$parent_dir/orgs_vars"
org_base_dir="$orgs_vars_dir/$org"
env_dir="$org_base_dir/$env"
imports_dir="$env_dir/imports"
exports_dir="$env_dir/exports"
vault_file="$env_dir/vault.yml"
vars_file="$env_dir/vars.yml"
env_vars_file="$env_dir/vars.env"

# --- START FIX: Use relative path for display ---
relative_env_dir="orgs_vars/$org/$env"
# --- END FIX ---

# Create organization directory if it doesn't exist
if [[ ! -d "$org_base_dir" ]]; then
    echo "📁 Creating new organization directory: $org"
    mkdir -p "$org_base_dir"
fi

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
    
    source "$env_vars_file"
    FLATTEN_OUTPUT=${FLATTEN_OUTPUT:-false}
    build_full_aap_folders
    if [[ "$FLATTEN_OUTPUT" != "true" ]]; then
        ensure_folders_exist "${full_aap_folders[@]}"
    fi

    echo "Error: Environment '$env' in organization '$org' already exists and appears complete."
    echo "If you want to edit the existing vault, use: ./vault-edit.sh $org $env"
    exit 1
fi

# --- 3. If not complete, run "create if not exists" logic ---
if [[ ! -d "$env_dir" ]]; then
    echo "🚀 Initializing new environment: $env (in organization: $org)"
else
    echo "🔧 Repairing environment: $env (in organization: $org)"
fi

# Set a flag to track if we create a *new* vault, so we know to open the editor
new_vault_created=false

# List of folders needed for each environment
folders_needed=(
    "$relative_env_dir/imports"
    "$relative_env_dir/exports"
    "$org_base_dir/common"
)

# --- Component 1: Common Directories ---
ensure_folders_exist "${folders_needed[@]}"

# --- Component 2: vars.env (Version File) ---
if [[ ! -f "$env_vars_file" ]]; then
    echo "  -> Creating missing 'vars.env' file..."
    prompt_and_save_version "$env_vars_file" "$org" "$env"
else
    echo "  -> 'vars.env' file already exists."
fi

# Load env vars so CASC_AAP_VERSION and FLATTEN_OUTPUT are available
source "$env_vars_file"
FLATTEN_OUTPUT=${FLATTEN_OUTPUT:-false}

# --- Component 3: AAP Directories ---
build_full_aap_folders
if [[ "$FLATTEN_OUTPUT" != "true" ]]; then
    ensure_folders_exist "${full_aap_folders[@]}"
fi

# --- Component 2: vars.yml (Ansible Vars) ---
if [[ ! -f "$vars_file" ]]; then
    echo "  -> Creating missing 'vars.yml' file from template..."
    cp "$vars_template_file" "$vars_file"
    if [[ "$FLATTEN_OUTPUT" = "true" ]]; then
        sed -i 's/^flatten_output: .*/flatten_output: true/' "$vars_file"
        echo "  -> Set flatten_output: true in vars.yml (flattened mode)."
    fi
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

# --- Component 4: common vault (org-level secrets) ---
common_vault_file="$org_base_dir/common/vault.yml"
vault_common_template_file="$parent_dir/templates/vault_common.yml"
if [[ ! -f "$common_vault_file" ]]; then
    if [[ -f "$vault_common_template_file" ]]; then
        echo "  -> Creating missing common vault from template..."
        cp "$vault_common_template_file" "$common_vault_file"
        echo "  -> Encrypting common vault..."
        if ! ansible-vault encrypt "$common_vault_file" > /dev/null 2>&1; then
            echo "Error: Failed to encrypt common vault. You can create it later with: ./vault-edit.sh $org common"
            rm -f "$common_vault_file"
        else
            echo "  -> Common vault created and encrypted."
        fi
    fi
else
    echo "  -> Common vault already exists."
fi

# --- 4. Final Step: Edit vault if it's brand new ---
echo ""
echo "✅ Environment '$env' (in organization: $org) is ready."

if [[ "$new_vault_created" = true ]]; then
    echo "Opening new vault file for you to edit. If prompted, please enter the vault password you just created."
    ansible-vault edit "$vault_file"
    echo ""
    echo "🎉 Setup complete! You can now use '$env' with the export/import scripts."
else
    echo "To edit the vault, use: ./vault-edit.sh $org $env"
fi

echo ""
echo "💡 Bash tab completion: source this file in your interactive shell (once per session,"
echo "   or add the same line to ~/.bashrc for every new terminal):"
echo "   source \"$parent_dir/autocomplete.sh\""