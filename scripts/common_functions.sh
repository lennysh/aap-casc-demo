#!/bin/bash
# Sourced (not run directly) by import.sh and export.sh.

# This function contains all the common logic for argument parsing and validation.
# It sets the following variables for the calling script to use:
# - env
# - casc_aap_version
# - tags
# - execution_environment
#
# REQUIRES BASH 4.3+ for 'declare -n' (namerefs)

set -euo pipefail

initialize_and_validate() {
    local script_type=$1
    shift # Remove script_type from the arguments list

    # --- Initial Argument Validation ---
    if [[ $# -lt 2 ]]; then
        echo "Error: Missing workspace or environment argument."
        echo ""
        usage # Calls the usage() function defined in the parent script (no args)
    fi

    org=$1
    env=$2
    local orgs_vars_dir="$parent_dir/orgs_vars"
    local org_base_dir="$orgs_vars_dir/$org"
    local env_dir="$org_base_dir/$env"

    # --- Validate Workspace ---
    if [[ ! -d "$org_base_dir" ]]; then
        echo "Error: Workspace '$org' not found under orgs_vars/."
        echo ""
        if [[ -d "$orgs_vars_dir" ]]; then
            local available_orgs
            available_orgs=$(find "$orgs_vars_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f|" | sed 's/|$//')
            echo "Available workspaces: {$available_orgs}"
        fi
        exit 1
    fi

    # --- Validate Environment ---
    if [[ ! -d "$env_dir" ]]; then
        echo "Error: Environment '$env' not found in workspace '$org'."
        echo ""
        local available_envs
        available_envs=$(find "$org_base_dir" -mindepth 1 -maxdepth 1 -type d -not -name "common" -printf "%f|" | sed 's/|$//')
        echo "Available environments in '$org': {$available_envs}"
        exit 1
    fi

    # --- Source Environment Vars ---
    local env_vars_file="$env_dir/vars.env"
    if [[ ! -f "$env_vars_file" ]]; then
        echo "Error: Environment config file '$env_vars_file' not found."
        echo "This file should contain the CASC_AAP_VERSION for this environment."
        echo "Try running './start_here.sh $org $env' again to fix it."
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$env_vars_file" # This loads $CASC_AAP_VERSION

    # --- Argument Parsing ---
    shift 2 # Remove workspace and env from the argument list
    tags=""

    if [[ -z "${1:-}" ]]; then
        echo "Error: Missing option [-a|--all] or [-t|--tags]."
        usage "$org" "$env" # Call usage with the workspace and env to show tags
    fi

    case $1 in
        -a|--all)
            # When --all is used, tags remains empty, which signals "process all tags"
            ;;
        -t|--tags)
            if [ -n "$2" ]; then
                tags="$2"
            else
                echo "Error: --tags requires an argument."
                usage "$org" "$env" # Call usage with the workspace and env to show tags
            fi
            ;;
        *)
            echo "Unknown option: $1"
            usage "$org" "$env" # Call usage with the workspace and env to show tags
            ;;
    esac

    # --- Define the single source of truth for the script vars file ---
    local script_vars_file="$script_vars_dir/$CASC_AAP_VERSION/vars.env"
    if [[ ! -f "$script_vars_file" ]]; then
        echo "Error: Script variables file not found for version '$CASC_AAP_VERSION' at $script_vars_file"
        exit 1
    fi

    # --- Source the variables file ---
    # shellcheck source=/dev/null
    source "$script_vars_file"

    # --- Validate execution_environment is set (only when using ansible-navigator / EE) ---
    if [[ "${USE_ANSIBLE_PLAYBOOK:-false}" != "true" ]] && [[ -z "${execution_environment:-}" ]]; then
        echo "Error: 'execution_environment' variable not found in script vars file '$script_vars_file'"
        exit 1
    fi

    # --- Tag Validation Section ---
    if [ -n "$tags" ]; then
        declare -A valid_tags_map

        # 1. Load category tags using nameref
        local category_tags_name="${script_type}_category_tags"
        declare -n category_tags_ref=$category_tags_name
        for tag in "${category_tags_ref[@]}"; do
            valid_tags_map["$tag"]=1
        done

        # 2. Load specific tags using namerefs
        local category_keys_name="${script_type}_specific_tags_categories"
        local assoc_array_name="${script_type}_specific_tags"
        declare -n category_keys_ref=$category_keys_name
        declare -n assoc_array_ref=$assoc_array_name

        for category in "${category_keys_ref[@]}"; do
            read -ra tags_array <<< "${assoc_array_ref[$category]}"
            for tag in "${tags_array[@]}"; do
                valid_tags_map["$tag"]=1
            done
        done

        # 3. Validate user-provided tags
        local invalid_tags=()
        local user_tags_arr=()
        IFS=',' read -ra user_tags_arr <<< "$tags"
        for user_tag in "${user_tags_arr[@]}"; do
            local user_tag_trimmed
            user_tag_trimmed=$(echo "$user_tag" | xargs) # Trim whitespace
            if [[ -z "${valid_tags_map[$user_tag_trimmed]+exists}" ]]; then
                invalid_tags+=("$user_tag_trimmed")
            fi
        done

        if [ ${#invalid_tags[@]} -gt 0 ]; then
            echo "Error: Invalid tag(s) provided: ${invalid_tags[*]}"
            echo "Please use one of the supported tags for AAP version $CASC_AAP_VERSION."
            echo ""
            usage "$org" "$env" # Call usage with the workspace and env to show tags
        fi
        echo "✅ Tags validated successfully."
    fi
}