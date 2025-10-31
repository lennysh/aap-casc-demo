#!/bin/bash

# This function contains all the common logic for argument parsing and validation.
# It sets the following variables for the calling script to use:
# - org
# - env
# - casc_aap_version
# - tags
# - execution_environment
#
# REQUIRES BASH 4.3+ for 'declare -n' (namerefs)

initialize_and_validate() {
    local script_type=$1
    shift # Remove script_type from the arguments list

    # --- Initial Argument Validation ---
    if [[ $# -lt 2 ]]; then
        echo "Error: Missing AAP Version and/or environment arguments."
        echo ""
        usage # Calls the usage() function defined in the parent script
    fi

    casc_aap_version=$1
    env=$2
    local base_dir="$parent_dir/aap_vars"

    # --- Validate Environment ---
    local env_dir="$base_dir"
    if [[ ! -d "$env_dir/$env" ]]; then
        echo "Error: Environment '$env' not found or is invalid."
        echo ""
        local available_envs
        available_envs=$(find "$env_dir" -mindepth 1 -maxdepth 1 -type d -not -name "common" -printf "%f|" | sed 's/|$//')
        echo "Available environments: {$available_envs}"
        exit 1
    fi

    # --- Argument Parsing ---
    shift 2 # Remove org and env from the argument list
    tags=""
    local all=false

    if [[ -z "$1" ]]; then
        echo "Error: Missing option [-a|--all] or [-t|--tags]."
        usage "$casc_aap_version"
    fi

    case $1 in
        -a|--all)
            all=true
            ;;
        -t|--tags)
            if [ -n "$2" ]; then
                tags="$2"
            else
                echo "Error: --tags requires an argument."
                usage "$casc_aap_version"
            fi
            ;;
        *)
            echo "Unknown option: $1"
            usage "$casc_aap_version"
            ;;
    esac

    # --- Define the single source of truth for the script vars file ---
    local script_vars_file="$script_vars_dir/$casc_aap_version/vars.env"
    if [[ ! -f "$script_vars_file" ]]; then
        echo "Error: Script variables file not found at $script_vars_file"
        exit 1
    fi

    # --- Source the variables file ---
    # shellcheck source=/dev/null
    source "$script_vars_file"

    # --- Tag Validation Section ---
    if [ -n "$tags" ]; then
        declare -A valid_tags_map

        # 1. Load category tags using nameref
        local category_tags_name="${script_type}_category_tags"
        declare -n category_tags_ref=$category_tags_name
        for tag in "${category_tags_ref[@]}"; do
            valid_tags_map["$tag"]=1
        done

        # 2. Load specific tags using namerefs for categories and the associative array
        local category_keys_name="${script_type}_specific_tags_categories"
        local assoc_array_name="${script_type}_specific_tags"
        declare -n category_keys_ref=$category_keys_name
        declare -n assoc_array_ref=$assoc_array_name

        for category in "${category_keys_ref[@]}"; do
            # Read the space-separated string into a temp array
            read -ra tags_array <<< "${assoc_array_ref[$category]}"
            for tag in "${tags_array[@]}"; do
                valid_tags_map["$tag"]=1
            done
        done

        # 3. Validate user-provided tags (this logic is unchanged)
        local invalid_tags=()
        local user_tags_arr=()
        IFS=',' read -ra user_tags_arr <<< "$tags"
        for user_tag in "${user_tags_arr[@]}"; do
            local user_tag_trimmed
            user_tag_trimmed=$(echo "$user_tag" | xargs) # Trim whitespace
            if [[ -z "${valid_tags_map[$user_tag_trimmed]}" ]]; then
                invalid_tags+=("$user_tag_trimmed")
            fi
        done

        if [ ${#invalid_tags[@]} -gt 0 ]; then
            echo "Error: Invalid tag(s) provided: ${invalid_tags[*]}"
            echo "Please use one of the supported tags for AAP version $casc_aap_version."
            echo ""
            usage "$casc_aap_version"
        fi
        echo "✅ Tags validated successfully."
    fi
}