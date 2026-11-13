#!/bin/bash
#
# Sourced (not run directly). Vault password handling shared by import.sh, export.sh,
# start_here.sh, vault-edit.sh and vault-view.sh.
#
# ensure_vault_password [--confirm] [--ignore-global] [file ...]
#
# Makes sure Ansible can get the vault password for a workspace, in this order:
#   1. CASC_VAULT_PASSWORD in the environment (e.g. CI)                -> used as-is
#   2. the workspace's own password file, .vault_pass/<workspace>.txt
#   3. the shared ("global") password file: ANSIBLE_VAULT_PASSWORD_FILE, or
#      vault_password_file in the active ansible.cfg
#   4. otherwise a prompt; the password is handed to Ansible through
#      scripts/vault_pass_from_env.sh and never written to disk.
#
# Password files (2, 3) are checked against an encrypted file from the arguments; one that
# doesn't open it is skipped (with a note), so each workspace can use its own password even
# when a shared password file is configured. A prompted password is checked the same way.
#
# The workspace is $VAULT_WORKSPACE if set, otherwise taken from the first argument path
# under orgs_vars/<workspace>/.
#
# --confirm        ask twice when no existing vault can verify the password (new vaults)
# --ignore-global  don't use the shared password file (a new workspace wants its own password)
# file ...         files the caller will decrypt or that share the password
#
# After a call:
#   VAULT_PASSWORD_SOURCE    env | workspace | global | prompt | "" (none needed)
#   VAULT_PASSWORD_FROM_ENV  true when the password is passed via the environment
#   VAULT_PASSWORD_PROMPTED  true when it was typed during this run
# vault_navigator_args prints the ansible-navigator options that pass it into an EE.
#
# Requires $parent_dir (the repository root) to be set by the caller.

# parent_dir is set by the sourcing script.
# shellcheck disable=SC2154

VAULT_PASSWORD_FROM_ENV=false
VAULT_PASSWORD_PROMPTED=false
VAULT_PASSWORD_SOURCE=""
VAULT_WORKSPACE=${VAULT_WORKSPACE:-}
_vault_resolved_for=""
# The user's own setting, before this script exports anything.
_vault_orig_password_file_env=${ANSIBLE_VAULT_PASSWORD_FILE:-}

# Print the ansible.cfg Ansible will use when run from the repository root.
_vault_find_ansible_cfg() {
    local candidate
    for candidate in "${ANSIBLE_CONFIG:-}" "$parent_dir/ansible.cfg" "$HOME/.ansible.cfg" "/etc/ansible/ansible.cfg"; do
        if [[ -n "$candidate" && -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# Print the (resolved) vault_password_file from the [defaults] section of an ansible.cfg,
# or nothing if it's unset or commented out. Relative paths are relative to the cfg file.
_vault_cfg_password_file() {
    local cfg=$1 value
    value=$(awk '
        /^[[:space:]]*\[/ { in_defaults = ($0 ~ /^[[:space:]]*\[defaults\][[:space:]]*$/); next }
        in_defaults && /^[[:space:]]*vault_password_file[[:space:]]*[=:]/ {
            sub(/^[^=:]*[=:][[:space:]]*/, ""); sub(/[[:space:]]+[;#].*$/, ""); sub(/[[:space:]]+$/, "")
            print; exit
        }' "$cfg")
    [[ -z "$value" ]] && return 0
    value="${value/#\~/$HOME}"
    if [[ "$value" != /* ]]; then
        value="$(cd "$(dirname "$cfg")" && pwd)/$value"
    fi
    echo "$value"
}

_vault_is_encrypted() {
    [[ -f "$1" ]] && head -c 14 "$1" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT'
}

_vault_rel() { printf '%s' "${1#"$parent_dir"/}"; }

# Path of the shared password file (ANSIBLE_VAULT_PASSWORD_FILE or ansible.cfg), even if missing.
vault_global_password_file() {
    local cfg
    if [[ -n "$_vault_orig_password_file_env" ]]; then
        echo "$_vault_orig_password_file_env"
    elif cfg=$(_vault_find_ansible_cfg); then
        _vault_cfg_password_file "$cfg"
    fi
}

# Path of a workspace's own password file.
vault_workspace_password_file() {
    printf '%s/.vault_pass/%s.txt' "$parent_dir" "$1"
}

_vault_workspace_from_paths() {
    local p rest
    for p in "$@"; do
        case "$p" in
            */orgs_vars/*|orgs_vars/*)
                rest=${p#*orgs_vars/}
                rest=${rest%%/*}
                if [[ -n "$rest" ]]; then
                    printf '%s' "$rest"
                    return 0
                fi ;;
        esac
    done
}

_vault_first_encrypted() {
    local f
    for f in "$@"; do
        if _vault_is_encrypted "$f"; then
            printf '%s' "$f"
            return 0
        fi
    done
}

# Does <password-file> open <vault-file>? Runs with an empty config so no other configured
# password can make the check pass.
_vault_try_password_file() {
    local pwfile=$1 vfile=$2 cfg rc=0
    cfg=$(mktemp --suffix=.cfg) || return 1
    printf '[defaults]\n' > "$cfg"
    env -u ANSIBLE_VAULT_PASSWORD_FILE -u ANSIBLE_VAULT_IDENTITY_LIST ANSIBLE_CONFIG="$cfg" \
        ansible-vault view --vault-password-file "$pwfile" "$vfile" >/dev/null 2>&1 || rc=$?
    rm -f "$cfg"
    return "$rc"
}

_vault_try_password() {
    (export CASC_VAULT_PASSWORD="$1"; _vault_try_password_file "$parent_dir/scripts/vault_pass_from_env.sh" "$2")
}

ensure_vault_password() {
    local confirm=false ignore_global=false
    while [[ "${1:-}" == --* ]]; do
        case "$1" in
            --confirm)       confirm=true ;;
            --ignore-global) ignore_global=true ;;
            *)               break ;;
        esac
        shift
    done

    local ws enc
    ws=${VAULT_WORKSPACE:-$(_vault_workspace_from_paths "$@")}
    enc=$(_vault_first_encrypted "$@")

    # Already resolved for this workspace during this run.
    if [[ -n "$VAULT_PASSWORD_SOURCE" && "$_vault_resolved_for" == "$ws" ]]; then
        return 0
    fi

    if [[ -n "${CASC_VAULT_PASSWORD:-}" ]]; then
        export ANSIBLE_VAULT_PASSWORD_FILE="$parent_dir/scripts/vault_pass_from_env.sh"
        VAULT_PASSWORD_FROM_ENV=true
        [[ "$VAULT_PASSWORD_PROMPTED" == "true" ]] || VAULT_PASSWORD_SOURCE="env"
        _vault_resolved_for=$ws
        return 0
    fi

    local need_prompt=false wsfile global
    if [[ -n "$ws" ]]; then
        wsfile=$(vault_workspace_password_file "$ws")
        if [[ -f "$wsfile" ]]; then
            if [[ -z "$enc" ]] || _vault_try_password_file "$wsfile" "$enc"; then
                export ANSIBLE_VAULT_PASSWORD_FILE="$wsfile"
                VAULT_PASSWORD_SOURCE=workspace
                _vault_resolved_for=$ws
                return 0
            fi
            echo "Note: $(_vault_rel "$wsfile") doesn't open $(_vault_rel "$enc"); asking for the password instead."
            need_prompt=true
        fi
    fi

    global=$(vault_global_password_file)
    if [[ -n "$global" ]]; then
        if [[ ! -f "$global" ]]; then
            echo "Note: the vault password file '$global' (ansible.cfg or ANSIBLE_VAULT_PASSWORD_FILE) doesn't exist."
            need_prompt=true
        elif [[ "$ignore_global" == "true" ]]; then
            need_prompt=true
        elif [[ -z "$enc" ]] || _vault_try_password_file "$global" "$enc"; then
            VAULT_PASSWORD_SOURCE=global
            _vault_resolved_for=$ws
            return 0
        else
            echo "Note: the shared vault password file '$global' doesn't open $(_vault_rel "$enc");"
            echo "      this workspace uses a different password."
            need_prompt=true
        fi
    fi

    # With nothing configured, only ask if something needs decrypting or encrypting.
    if [[ "$need_prompt" != "true" && "$confirm" != "true" && -z "$enc" ]]; then
        return 0
    fi

    if [[ ! -t 0 ]]; then
        echo "Error: A vault password is required${ws:+ for workspace '$ws'}, but no usable vault password"
        echo "file was found and this shell isn't interactive, so it can't prompt for one. Either:"
        echo "  - set CASC_VAULT_PASSWORD in the environment, or"
        echo "  - save the password in .vault_pass/${ws:-<workspace>}.txt (chmod 600; ./start_here.sh can do this)."
        exit 1
    fi

    local password password2 tries=0 label="Vault password${ws:+ for workspace '$ws'}"
    while true; do
        read -rsp "$label: " password
        echo ""
        if [[ -z "$password" ]]; then
            echo "The vault password can't be empty."
            continue
        fi
        if [[ -n "$enc" ]]; then
            if _vault_try_password "$password" "$enc"; then
                break
            fi
            tries=$((tries + 1))
            if (( tries >= 3 )); then
                echo "Error: Wrong vault password for $(_vault_rel "$enc")."
                exit 1
            fi
            echo "That password doesn't open $(_vault_rel "$enc"). Try again."
            continue
        fi
        if [[ "$confirm" == "true" ]]; then
            read -rsp "Confirm vault password: " password2
            echo ""
            if [[ "$password" != "$password2" ]]; then
                echo "Passwords don't match. Try again."
                continue
            fi
        fi
        break
    done

    export CASC_VAULT_PASSWORD="$password"
    export ANSIBLE_VAULT_PASSWORD_FILE="$parent_dir/scripts/vault_pass_from_env.sh"
    VAULT_PASSWORD_FROM_ENV=true
    VAULT_PASSWORD_PROMPTED=true
    VAULT_PASSWORD_SOURCE=prompt
    _vault_resolved_for=$ws
}

_vault_restore_password_file_env() {
    if [[ -n "$_vault_orig_password_file_env" ]]; then
        export ANSIBLE_VAULT_PASSWORD_FILE="$_vault_orig_password_file_env"
    else
        unset ANSIBLE_VAULT_PASSWORD_FILE
    fi
}

# Forget a password that was prompted for, so the next ensure_vault_password asks again.
reset_prompted_vault_password() {
    if [[ "$VAULT_PASSWORD_PROMPTED" == "true" ]]; then
        unset CASC_VAULT_PASSWORD
        _vault_restore_password_file_env
        VAULT_PASSWORD_FROM_ENV=false
        VAULT_PASSWORD_PROMPTED=false
        VAULT_PASSWORD_SOURCE=""
        _vault_resolved_for=""
    fi
}

# Forget how the password was resolved (any source except $CASC_VAULT_PASSWORD), so the next
# ensure_vault_password looks it up and verifies it again.
forget_vault_password() {
    if [[ "$VAULT_PASSWORD_PROMPTED" == "true" ]]; then
        reset_prompted_vault_password
        return 0
    fi
    [[ "$VAULT_PASSWORD_SOURCE" == "workspace" ]] && _vault_restore_password_file_env
    VAULT_PASSWORD_SOURCE=""
    _vault_resolved_for=""
}

# Human-readable description of where the current vault password came from.
vault_password_source_label() {
    case "$VAULT_PASSWORD_SOURCE" in
        env)       printf 'from $CASC_VAULT_PASSWORD' ;;
        workspace) printf 'from %s' "$(_vault_rel "$ANSIBLE_VAULT_PASSWORD_FILE")" ;;
        global)    printf 'from the shared password file %s' "$(vault_global_password_file)" ;;
        prompt)    printf 'entered at the prompt' ;;
        *)         printf 'not needed' ;;
    esac
}

# Save a prompted password as the workspace's password file. Prints the file's path.
# Returns 1 if a different password is already saved there.
save_workspace_password_file() {
    local ws=$1 password=$2 file
    file=$(vault_workspace_password_file "$ws")
    if [[ -f "$file" ]]; then
        [[ "$(cat "$file")" == "$password" ]] || return 1
    else
        (umask 077; mkdir -p "$(dirname "$file")"; printf '%s\n' "$password" > "$file")
    fi
    chmod 700 "$(dirname "$file")" 2>/dev/null || true
    printf '%s' "$file"
}

# Extra ansible-navigator args to pass the vault password into the EE. The repo is mounted at
# the same path inside the EE, so scripts/vault_pass_from_env.sh and .vault_pass/ resolve there.
vault_navigator_args() {
    if [[ "$VAULT_PASSWORD_FROM_ENV" == "true" ]]; then
        printf '%s\n' "--penv" "ANSIBLE_VAULT_PASSWORD_FILE" "--penv" "CASC_VAULT_PASSWORD"
    elif [[ "$VAULT_PASSWORD_SOURCE" == "workspace" ]]; then
        printf '%s\n' "--penv" "ANSIBLE_VAULT_PASSWORD_FILE"
    fi
}
