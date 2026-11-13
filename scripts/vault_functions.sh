#!/bin/bash
#
# Sourced (not run directly). Vault password handling shared by import.sh, export.sh, start_here.sh, vault-edit.sh
# and vault-view.sh.
#
# ensure_vault_password [--confirm] [file ...]
#
# Makes sure Ansible can get the vault password, in this order:
#   1. CASC_VAULT_PASSWORD already set in the environment (e.g. CI) -> used as-is
#   2. ANSIBLE_VAULT_PASSWORD_FILE set and the file exists          -> used as-is
#   3. vault_password_file set (uncommented) in the active ansible.cfg
#      and the file exists                                          -> used as-is
#   4. otherwise prompt once for the password and hand it to Ansible via
#      scripts/vault_pass_from_env.sh. If no password file is configured at all, the prompt is
#      skipped unless one of the given files is vault-encrypted (or --confirm is passed).
#      A configured-but-missing password file always prompts: Ansible refuses to start
#      when vault_password_file points at a file that doesn't exist.
#
# --confirm  ask twice (use when a new vault is about to be encrypted)
# file ...   files the caller will decrypt (used to decide whether a prompt is needed)
#
# Sets VAULT_PASSWORD_FROM_ENV=true when Ansible should read the password from the
# environment, so callers can pass it into an ansible-navigator EE (see
# vault_navigator_args).
#
# Requires $parent_dir (the repository root) to be set by the caller.

VAULT_PASSWORD_FROM_ENV=false
# true when ensure_vault_password prompted for the password during this run
VAULT_PASSWORD_PROMPTED=false

# parent_dir is set by the sourcing script.
# shellcheck disable=SC2154

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

ensure_vault_password() {
    local confirm=false
    if [[ "${1:-}" == "--confirm" ]]; then
        confirm=true
        shift
    fi

    if [[ -n "${CASC_VAULT_PASSWORD:-}" ]]; then
        export ANSIBLE_VAULT_PASSWORD_FILE="$parent_dir/scripts/vault_pass_from_env.sh"
        VAULT_PASSWORD_FROM_ENV=true
        return 0
    fi

    local configured_but_missing=false
    if [[ -n "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ]]; then
        if [[ -f "$ANSIBLE_VAULT_PASSWORD_FILE" ]]; then
            return 0
        fi
        configured_but_missing=true
        echo "Note: ANSIBLE_VAULT_PASSWORD_FILE points to '$ANSIBLE_VAULT_PASSWORD_FILE', which doesn't exist."
    else
        local cfg cfg_file
        if cfg=$(_vault_find_ansible_cfg); then
            cfg_file=$(_vault_cfg_password_file "$cfg")
            if [[ -n "$cfg_file" ]]; then
                if [[ -f "$cfg_file" ]]; then
                    return 0
                fi
                configured_but_missing=true
                echo "Note: $cfg sets vault_password_file = $cfg_file, but that file doesn't exist."
            fi
        fi
    fi

    # No usable password source. With nothing configured, only ask if something actually
    # needs decrypting.
    if [[ "$confirm" != "true" && "$configured_but_missing" != "true" ]]; then
        local f needs_password=false
        for f in "$@"; do
            if _vault_is_encrypted "$f"; then
                needs_password=true
                break
            fi
        done
        [[ "$needs_password" == "true" ]] || return 0
    fi

    if [[ ! -t 0 ]]; then
        echo "Error: A vault password is required, but no usable vault password file was found and"
        echo "this shell isn't interactive, so it can't prompt for one. Either:"
        echo "  - set CASC_VAULT_PASSWORD in the environment, or"
        echo "  - create a password file (e.g. .vault_pass.txt, chmod 600) and set"
        echo "    vault_password_file in ansible.cfg or ANSIBLE_VAULT_PASSWORD_FILE."
        exit 1
    fi

    local password password2
    while true; do
        read -rsp "Vault password: " password
        echo ""
        if [[ -z "$password" ]]; then
            echo "The vault password can't be empty."
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
}

# Forget a password that was prompted for, so the next ensure_vault_password asks again.
reset_prompted_vault_password() {
    if [[ "$VAULT_PASSWORD_PROMPTED" == "true" ]]; then
        unset CASC_VAULT_PASSWORD ANSIBLE_VAULT_PASSWORD_FILE
        VAULT_PASSWORD_FROM_ENV=false
        VAULT_PASSWORD_PROMPTED=false
    fi
}

# Extra ansible-navigator args to pass the prompted password into the EE. The repo is
# mounted at the same path inside the EE, so scripts/vault_pass_from_env.sh resolves there too.
vault_navigator_args() {
    if [[ "$VAULT_PASSWORD_FROM_ENV" == "true" ]]; then
        printf '%s\n' "--penv" "ANSIBLE_VAULT_PASSWORD_FILE" "--penv" "CASC_VAULT_PASSWORD"
    fi
}
