#!/bin/bash

# This function contains all the common logic for argument parsing and validation.
# It sets the following variables for the calling script to use:
# - org
# - env
# - casc_aap_version
# - tags
# - execution_environment

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
    local script_vars_file="$script_vars_dir/$casc_aap_version/vars.yml"
    if [[ ! -f "$script_vars_file" ]]; then
        echo "Error: Script variables file not found at $script_vars_file"
        exit 1
    fi

    # --- Tag Validation Section ---
    if [ -n "$tags" ]; then
        # Build the yq query keys dynamically based on the script type
        local category_tags_key="aap${script_type}_category_tags"
        local specific_tags_key="aap${script_type}_specific_tags"

        declare -A valid_tags_map
        while IFS= read -r tag; do
            valid_tags_map["$tag"]=1
        done < <(yq ".${category_tags_key}[], .${specific_tags_key}[][]" "$script_vars_file" 2>/dev/null)

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

    # --- Get Execution Environment ---
    execution_environment="$(yq '.execution_environment' "$script_vars_file")"
}