#!/bin/bash
#
# Setup wizard: create (or repair) a workspace/environment under orgs_vars/.
# Run ./start_here.sh --help for options.

if [[ -z "${BASH_VERSINFO:-}" ]] || (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    echo "Error: Bash 4.3 or newer is required (found ${BASH_VERSION:-unknown})." >&2
    echo "On macOS, install a newer Bash (e.g. 'brew install bash') and run: bash ./start_here.sh" >&2
    exit 1
fi

set -euo pipefail

parent_dir=$(dirname "$(readlink -f "$0")")
script_vars_dir="$parent_dir/script_vars"
orgs_vars_dir="$parent_dir/orgs_vars"
vars_template_file="$parent_dir/templates/vars.yml"
vault_template_file="$parent_dir/templates/vault.yml"
vault_common_template_file="$parent_dir/templates/vault_common.yml"
# shellcheck source=scripts/vault_functions.sh
source "$parent_dir/scripts/vault_functions.sh"

usage() {
    cat <<EOF
Usage: $0 [<workspace> [<env>]] [options]

Creates an environment (one AAP instance) under orgs_vars/<workspace>/<env>/: folders, version
and options files, and encrypted vaults with your connection details. Run it again to repair an
environment; it only adds what's missing. Without <workspace>/<env>, it asks for them.

A workspace is just a folder name that groups environments sharing configuration, such as a
company, team or lab (MyCompany -> dev, qa, prod). It doesn't have to match an AAP organization.

Options (all optional; anything not given is asked for interactively):
  --version <ver>       AAP version (e.g. 2.6)
  --filetree | --flat   Import layout (default: filetree). See docs/CONCEPTS.md
  --hostname <url>      AAP URL or hostname (the platform gateway on 2.5+)
  --username <user>     AAP username; the password is read from \$AAP_PASSWORD or prompted
                        (set \$AAP_TOKEN instead to use an existing OAuth token)
  --no-verify-certs     Don't validate AAP's TLS certificate (self-signed certificates)
  --org-filter <name>   Export only this AAP organization (sets organization_filter in vars.yml)
  --skip-test           Don't test the connection to AAP
  -y, --yes             Don't ask questions; use defaults and fail if required input is missing
                        (the vault password is still prompted unless \$CASC_VAULT_PASSWORD,
                        .vault_pass/<workspace>.txt or a shared vault password file provides it)
  -h, --help            Show this help

When adding an environment to a workspace that already has one, the AAP version, layout,
certificate setting and username of the most recently set up environment are offered as
defaults (and used with --yes unless given).

Examples:
  $0                                        # fully interactive
  $0 MyCompany prod
  AAP_PASSWORD=... CASC_VAULT_PASSWORD=... $0 MyCompany prod --version 2.6 \\
      --hostname https://aap.example.com --username admin --yes
EOF
}

# --- Output helpers -------------------------------------------------------------------------
say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
info() { printf '  -> %s\n' "$*"; }
warn() { printf '  ⚠️  %s\n' "$*"; }
die()  { printf 'Error: %s\n' "$*" >&2; exit 1; }

# --- Arguments ------------------------------------------------------------------------------
org="" env="" opt_version="" opt_layout="" opt_hostname="" opt_username=""
opt_verify_certs="" opt_skip_test=false assume_yes=false opt_org_filter=""
choice=""
positional=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)          [[ -n "${2:-}" ]] || die "--version needs a value"; opt_version=$2; shift 2 ;;
        --flat)             opt_layout=flat; shift ;;
        --filetree)         opt_layout=filetree; shift ;;
        --hostname)         [[ -n "${2:-}" ]] || die "--hostname needs a value"; opt_hostname=$2; shift 2 ;;
        --username)         [[ -n "${2:-}" ]] || die "--username needs a value"; opt_username=$2; shift 2 ;;
        --no-verify-certs)  opt_verify_certs=false; shift ;;
        --org-filter)       [[ -n "${2:-}" ]] || die "--org-filter needs a value"; opt_org_filter=$2; shift 2 ;;
        --skip-test)        opt_skip_test=true; shift ;;
        -y|--yes)           assume_yes=true; shift ;;
        -h|--help)          usage; exit 0 ;;
        -*)                 usage >&2; die "Unknown option: $1" ;;
        *)                  positional+=("$1"); shift ;;
    esac
done
[[ ${#positional[@]} -le 2 ]] || { usage >&2; die "Too many arguments."; }
org=${positional[0]:-}
env=${positional[1]:-}

interactive() { [[ "$assume_yes" != "true" && -t 0 ]]; }

# Ask a question with an optional default. Usage: ask <var> "<prompt>" [default]
ask() {
    local __var=$1 __prompt=$2 __default=${3:-} __reply
    if [[ -n "$__default" ]]; then
        read -rp "$__prompt [$__default]: " __reply
        __reply=${__reply:-$__default}
    else
        read -rp "$__prompt: " __reply
    fi
    printf -v "$__var" '%s' "$__reply"
}

# Yes/no question. Usage: confirm "<prompt>" <y|n default>
confirm() {
    local __prompt=$1 __default=$2 __reply __hint="y/N"
    [[ "$__default" == "y" ]] && __hint="Y/n"
    if ! interactive; then
        [[ "$__default" == "y" ]]
        return
    fi
    read -rp "$__prompt ($__hint): " __reply
    __reply=${__reply:-$__default}
    [[ "$__reply" =~ ^[yY] ]]
}

# Numbered menu. Usage: menu <var> "<title>" <default-index-or-empty> "<option>" ...
# Sets <var> to the chosen index (1-based).
menu() {
    local __var=$1 __title=$2 __default=$3 __reply i
    shift 3
    say "$__title"
    for ((i = 1; i <= $#; i++)); do
        say "  $i) ${!i}"
    done
    while true; do
        if [[ -n "$__default" ]]; then
            read -rp "Choose [1-$#, default $__default]: " __reply
            __reply=${__reply:-$__default}
        else
            read -rp "Choose [1-$#]: " __reply
        fi
        if [[ "$__reply" =~ ^[0-9]+$ ]] && (( __reply >= 1 && __reply <= $# )); then
            printf -v "$__var" '%s' "$__reply"
            return
        fi
        say "Please enter a number from 1 to $#."
    done
}

valid_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }

check_org_name() {
    valid_name "$1" || die "Invalid workspace name '$1'. Use letters, digits, '.', '_' or '-' (no spaces or slashes), starting with a letter or digit."
}

check_env_name() {
    valid_name "$1" || die "Invalid environment name '$1'. Use letters, digits, '.', '_' or '-' (no spaces or slashes), starting with a letter or digit."
    [[ "$1" != "common" ]] || die "'common' is reserved for configuration shared by all environments; choose another environment name."
}

# YAML double-quoted scalar.
yaml_quote() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    printf '"%s"' "$s"
}

# Value for a curl config file (-K): double-quoted with backslash escapes.
curl_quote() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    printf '"%s"' "$s"
}

# Python that can import yaml (the one ansible runs on), used to read vault and API data.
vault_python=()
find_vault_python() {
    local shebang
    [[ ${#vault_python[@]} -gt 0 ]] && return 0
    shebang=$(head -1 "$(command -v ansible-vault)" 2>/dev/null || true)
    if [[ "$shebang" == '#!'* ]]; then
        read -ra vault_python <<< "${shebang#\#!}"
        if "${vault_python[@]}" -c 'import yaml' 2>/dev/null; then
            return 0
        fi
    fi
    vault_python=(python3)
    "${vault_python[@]}" -c 'import yaml' 2>/dev/null
}

# Decrypt a vault (password must already be available) and set vv_hostname, vv_verify,
# vv_username, vv_password, vv_token. Returns non-zero if it can't be read.
read_vault_values() {
    local file=$1
    vv_hostname="" vv_verify="" vv_username="" vv_password="" vv_token=""
    find_vault_python || return 1
    ansible-vault view "$file" >/dev/null 2>&1 || return 1
    { IFS= read -r -d '' vv_hostname; IFS= read -r -d '' vv_verify; IFS= read -r -d '' vv_username
      IFS= read -r -d '' vv_password; IFS= read -r -d '' vv_token; } < <(ansible-vault view "$file" 2>/dev/null | "${vault_python[@]}" -c '
import sys, yaml
d = yaml.safe_load(sys.stdin) or {}
def v(k):
    x = d.get(k)
    if x is None: return ""
    if isinstance(x, bool): return "true" if x else "false"
    return str(x)
for k in ("vault_aap_hostname", "vault_aap_validate_certs", "vault_aap_username", "vault_aap_password", "vault_aap_token"):
    sys.stdout.write(v(k) + "\0")
') || true
    return 0
}

# Make sure the vault password opens <file>. Password files that don't fit and wrong typed
# passwords are handled by ensure_vault_password (it falls back to / repeats the prompt).
unlock_vault() {
    local file=$1 rel=${1#"$parent_dir"/}
    ensure_vault_password "$file"
    ansible-vault view "$file" >/dev/null 2>&1 && return 0
    [[ "$VAULT_PASSWORD_SOURCE" != "env" ]] || die "The vault password in \$CASC_VAULT_PASSWORD doesn't open $rel."
    # Resolved earlier without a vault to check against; look it up again, verified.
    forget_vault_password
    ensure_vault_password "$file"
    ansible-vault view "$file" >/dev/null 2>&1 || die "Couldn't decrypt $rel."
}

# Where this workspace's vault password comes from, without prompting.
describe_vault_password_source() {
    local wsfile global
    wsfile=$(vault_workspace_password_file "$org")
    global=$(vault_global_password_file)
    if [[ -n "${CASC_VAULT_PASSWORD:-}" ]]; then
        say "\$CASC_VAULT_PASSWORD"
    elif [[ -f "$wsfile" ]]; then
        say "${wsfile#"$parent_dir"/} (this workspace's password file)"
    elif [[ -n "$global" && -f "$global" ]] && { ! _vault_is_encrypted "$vault_file" || _vault_try_password_file "$global" "$vault_file"; }; then
        say "shared password file $global"
    elif [[ -n "$global" && -f "$global" ]]; then
        say "asked on each run (the shared password file $global holds a different password)"
    else
        say "asked on each run"
    fi
}

# True if the user is typing this workspace's vault password (no file or variable provides it).
password_is_prompted() {
    [[ "$(describe_vault_password_source)" == "asked on each run"* ]]
}

# True if the repo's ansible.cfg is (or, once created, would be) the active config without
# hiding the user's own settings: only $ANSIBLE_CONFIG and ~/.ansible.cfg are respected;
# the system-wide /etc/ansible/ansible.cfg is just defaults and is overridden by the repo's.
repo_cfg_is_active() {
    local active
    active=$(_vault_find_ansible_cfg || true)
    [[ -z "$active" || "$active" == "$parent_dir/ansible.cfg" || "$active" == "/etc/ansible/ansible.cfg" ]]
}

ensure_repo_cfg() {
    if [[ ! -f "$parent_dir/ansible.cfg" ]]; then
        cp "$parent_dir/ansible.cfg.example" "$parent_dir/ansible.cfg"
        info "Created ansible.cfg from ansible.cfg.example"
    fi
}

# Offer to store a typed vault password as this workspace's password file.
offer_save_vault_password() {
    local ask_first=${1:-true} file rel
    [[ "$VAULT_PASSWORD_PROMPTED" == "true" && -n "${CASC_VAULT_PASSWORD:-}" ]] || return 0
    interactive || return 0
    rel=$(vault_workspace_password_file "$org")
    rel=${rel#"$parent_dir"/}
    if [[ "$ask_first" == "true" ]]; then
        say ""
        say "You'll be asked for this password on every export and import in workspace '$org'."
        say "It can be saved to $rel instead: readable only by you and used only for this"
        say "workspace (other workspaces keep their own passwords). Anyone who can read that file can"
        say "decrypt this workspace's vaults."
        confirm "Save the vault password for workspace '$org' to $rel?" n || return 0
    fi
    if file=$(save_workspace_password_file "$org" "$CASC_VAULT_PASSWORD"); then
        info "Saved to ${file#"$parent_dir"/} (mode 600; .vault_pass/ is in .gitignore, never commit it)"
    else
        warn "$rel already exists with a different password; left unchanged."
    fi
    return 0
}

# Ask for an Automation Hub token and put it into the repo's ansible.cfg.
offer_hub_token() {
    local token
    interactive || return 1
    if ! repo_cfg_is_active; then
        warn "Your active Ansible config is $(_vault_find_ansible_cfg); add the Automation Hub token there."
        return 1
    fi
    if [[ -f "$parent_dir/ansible.cfg" ]] && ! grep -q '^\[galaxy_server\.certified\]' "$parent_dir/ansible.cfg"; then
        warn "ansible.cfg has no [galaxy_server.certified] section; compare it with ansible.cfg.example."
        return 1
    fi
    confirm "Paste your Automation Hub token now? (get one at https://console.redhat.com/ansible/automation-hub/token)" y || return 1
    read -rsp "Automation Hub token (input hidden): " token
    echo ""
    [[ -n "$token" ]] || { warn "No token entered."; return 1; }
    ensure_repo_cfg
    local tmp
    tmp=$(mktemp)
    TOKEN=$token awk '
        /^[[:space:]]*\[/ { hub = ($0 ~ /^\[galaxy_server\.(certified|validated)\]/) }
        hub && /^[[:space:]]*token[[:space:]]*=[[:space:]]*$/ { print "token=" ENVIRON["TOKEN"]; next }
        { print }' "$parent_dir/ansible.cfg" > "$tmp"
    cat "$tmp" > "$parent_dir/ansible.cfg"
    rm -f "$tmp"
    chmod 600 "$parent_dir/ansible.cfg"
    info "Saved the token to ansible.cfg (ignored by Git)"
}

# Set organization_filter in vars.yml (replacing an existing or commented-out line).
set_org_filter() {
    local name=$1 quoted tmp sq="'"
    quoted="'${name//$sq/$sq$sq}'"
    tmp=$(mktemp)
    LINE="organization_filter: $quoted" awk '
        !done && /^#?[[:space:]]*organization_filter:/ { print ENVIRON["LINE"]; done = 1; next }
        !done && /^\.\.\.[[:space:]]*$/ { print ENVIRON["LINE"]; done = 1 }
        { print }
        END { if (!done) print ENVIRON["LINE"] }' "$vars_file" > "$tmp"
    cat "$tmp" > "$vars_file"
    rm -f "$tmp"
}

current_org_filter() {
    [[ -f "$vars_file" ]] || return 0
    sed -n "s/^organization_filter:[[:space:]]*['\"]\{0,1\}\([^'\"]*\)['\"]\{0,1\}[[:space:]]*\$/\1/p" "$vars_file" | head -1
}

completion_in_bashrc() { grep -Fqs "$parent_dir/autocomplete.sh" "$HOME/.bashrc"; }

offer_bash_completion() {
    local line="source \"$parent_dir/autocomplete.sh\""
    interactive || return 0
    [[ "${SHELL##*/}" == "bash" ]] || return 0
    completion_in_bashrc && return 0
    say ""
    if confirm "Enable Tab completion of workspace and environment names in new terminals (adds one line to ~/.bashrc)?" n; then
        printf '\n# aap-casc-demo: Tab completion for workspace and environment names\n%s\n' "$line" >> "$HOME/.bashrc"
        info "Added to ~/.bashrc. It applies to new terminals (or run now: $line)"
    fi
}

# --- Preflight ------------------------------------------------------------------------------
command -v ansible-vault >/dev/null 2>&1 || die "ansible-vault not found. Install ansible-core first (e.g. 'pip install ansible-core')."
[[ -f "$vars_template_file" && -f "$vault_template_file" ]] || die "Templates are missing from $parent_dir/templates."
mapfile -t available_versions < <(find "$script_vars_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V)
[[ ${#available_versions[@]} -gt 0 ]] || die "No AAP versions found in $script_vars_dir."

# --- Workspace and environment --------------------------------------------------------------
env_status() {
    local d="$orgs_vars_dir/$1/$2" ver=""
    if [[ -f "$d/vars.env" ]]; then
        ver=$(sed -n 's/^CASC_AAP_VERSION="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$d/vars.env")
    fi
    if [[ -f "$d/vars.env" && -f "$d/vars.yml" && -f "$d/vault.yml" && -d "$d/imports" ]]; then
        say "AAP ${ver:-?}"
    else
        say "AAP ${ver:-?}, incomplete"
    fi
}

if [[ -z "$org" ]]; then
    interactive || { usage >&2; die "Missing <workspace> and <env>."; }
    mapfile -t existing_orgs < <(find "$orgs_vars_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
    if [[ ${#existing_orgs[@]} -gt 0 ]]; then
        say "A workspace groups related environments that can share configuration, e.g. a company,"
        say "team or lab (MyCompany -> dev, qa, prod). It's just a folder name; it doesn't have to be"
        say "an AAP organization."
        menu choice "Choose a workspace:" "" "${existing_orgs[@]}" "Create a new workspace"
        if (( choice <= ${#existing_orgs[@]} )); then
            org=${existing_orgs[choice-1]}
        fi
    fi
    if [[ -z "$org" ]]; then
        if [[ ${#existing_orgs[@]} -eq 0 ]]; then
            say "A workspace groups related environments that can share configuration, e.g. a company,"
            say "team or lab (MyCompany -> dev, qa, prod). It's just a folder name; it doesn't have to be"
            say "an AAP organization."
        fi
        ask org "New workspace name (e.g. MyCompany)"
    fi
fi
check_org_name "$org"
VAULT_WORKSPACE=$org

if [[ -z "$env" ]]; then
    interactive || { usage >&2; die "Missing <env>."; }
    mapfile -t existing_envs < <(find "$orgs_vars_dir/$org" -mindepth 1 -maxdepth 1 -type d -not -name common -printf '%f\n' 2>/dev/null | sort)
    if [[ ${#existing_envs[@]} -gt 0 ]]; then
        env_labels=()
        for e in "${existing_envs[@]}"; do
            env_labels+=("$e ($(env_status "$org" "$e"))")
        done
        say ""
        say "An environment is one AAP instance (e.g. dev, qa, prod)."
        menu choice "Choose an environment in '$org':" "" "${env_labels[@]}" "Create a new environment"
        if (( choice <= ${#existing_envs[@]} )); then
            env=${existing_envs[choice-1]}
        fi
    fi
    if [[ -z "$env" ]]; then
        if [[ ${#existing_envs[@]} -eq 0 ]]; then
            say ""
            say "An environment is one AAP instance (e.g. dev, qa, prod)."
        fi
        ask env "New environment name (e.g. prod)"
    fi
fi
check_env_name "$env"

org_base_dir="$orgs_vars_dir/$org"
common_dir="$org_base_dir/common"
env_dir="$org_base_dir/$env"
imports_dir="$env_dir/imports"
exports_dir="$env_dir/exports"
vault_file="$env_dir/vault.yml"
vars_file="$env_dir/vars.yml"
env_vars_file="$env_dir/vars.env"
common_vault_file="$common_dir/vault.yml"
rel_env="orgs_vars/$org/$env"
rel_common="orgs_vars/$org/common"

# Most recently set up other environment in this workspace, used for defaults.
sibling_env="" sib_version="" sib_layout=""
if [[ ! -f "$env_vars_file" && -d "$org_base_dir" ]]; then
    # Complete environments (with a vault) first, newest first.
    while IFS= read -r d; do
        [[ "$d" == "$env_dir" || "$d" == "$common_dir" ]] && continue
        sibling_env=$(basename "$d")
        sib_version=$(sed -n 's/^CASC_AAP_VERSION="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$d/vars.env")
        [[ -d "$script_vars_dir/$sib_version" ]] || sib_version=""
        if [[ -f "$d/vars.yml" ]] && grep -Eq '^flatten_output:[[:space:]]*(true|True|yes)' "$d/vars.yml"; then
            sib_layout=flat
        elif [[ -f "$d/vars.yml" ]]; then
            sib_layout=filetree
        fi
        break
    done < <(find "$org_base_dir" -mindepth 2 -maxdepth 2 -name vars.env -printf '%T@ %h\n' 2>/dev/null | sort -rn | cut -d' ' -f2- \
             | while IFS= read -r d; do if [[ -f "$d/vault.yml" ]]; then echo "0 $d"; else echo "1 $d"; fi; done \
             | sort -s -k1,1 | cut -d' ' -f2-)
fi

# --- Helpers that depend on the environment --------------------------------------------------
created_folders=0
ensure_folders() {
    local f
    for f in "$@"; do
        if [[ ! -d "$f" ]]; then
            mkdir -p "$f"
            created_folders=$((created_folders + 1))
        fi
    done
}

# Read the import layout from vars.yml (source of truth), falling back to vars.env.
current_layout() {
    if [[ -f "$vars_file" ]] && grep -Eq '^flatten_output:[[:space:]]*(true|True|yes)' "$vars_file"; then
        say flat
    elif [[ -f "$vars_file" ]]; then
        say filetree
    elif [[ "${FLATTEN_OUTPUT:-false}" == "true" ]]; then
        say flat
    else
        say filetree
    fi
}

create_type_folders() {
    local layout=$1 script_vars_file="$script_vars_dir/$CASC_AAP_VERSION/vars.env" f
    created_folders=0
    ensure_folders "$imports_dir" "$exports_dir" "$common_dir"
    if [[ "$layout" != "flat" ]]; then
        [[ -f "$script_vars_file" ]] || die "Unknown AAP version '$CASC_AAP_VERSION' (no $script_vars_file)."
        aap_folders_needed=()
        # shellcheck source=/dev/null
        source "$script_vars_file"
        for f in "${aap_folders_needed[@]}"; do
            ensure_folders "$imports_dir/$f" "$common_dir/$f"
        done
    fi
    if (( created_folders > 0 )); then
        if [[ "$layout" == "flat" ]]; then
            info "Created $created_folders folder(s) ($rel_env/imports, exports and $rel_common)"
        else
            info "Created $created_folders folder(s) for the filetree layout in $rel_env/imports and $rel_common"
        fi
    fi
}

latest_export() {
    find "$exports_dir" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %f\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
}

print_next_steps() {
    local layout=$1 copy_from=filetree_version
    [[ "$layout" == "flat" ]] && copy_from=flat_version
    say ""
    say "Next steps:"
    say "  1. Export the current configuration:"
    say "       ./export.sh $org $env -a"
    say "  2. Copy what you want to manage into imports/ (or $rel_common/ to share it):"
    say "       cp -r $rel_env/exports/<export-folder>/$copy_from/* $rel_env/imports/"
    say "  3. Add the secret placeholders ({{ vault_... }}) to your vault:"
    say "       ./vault-edit.sh $org $env"
    say "  4. Dry run, then import:"
    say "       ./import.sh $org $env -a --check"
    say "       ./import.sh $org $env -a"
    say ""
    say "Guides: README.md and docs/HOW_TO.md."
    completion_in_bashrc || say "Tab completion for workspace/env names: source \"$parent_dir/autocomplete.sh\""
}

# --- Step: connection details and vaults ------------------------------------------------------
aap_hostname="" aap_verify_certs="" aap_auth="" aap_username="" aap_password="" aap_token=""
# Defaults offered by collect_connection_details (from a sibling environment or the current vault).
def_hostname="" def_verify="" def_auth="" def_username="" def_password="" def_token=""
api_base="" api_server="" test_result=""

collect_connection_details() {
    aap_hostname=${opt_hostname:-$aap_hostname}
    if [[ -z "$aap_hostname" ]]; then
        interactive || die "No AAP hostname given. Use --hostname <url>."
        local hint="the platform gateway URL"
        [[ "$CASC_AAP_VERSION" == "2.4" ]] && hint="the Automation Controller URL"
        while [[ -z "$aap_hostname" ]]; do
            ask aap_hostname "AAP URL ($hint, e.g. https://aap.example.com)" "$def_hostname"
        done
    fi
    aap_hostname=${aap_hostname%/}

    if [[ -n "$opt_verify_certs" ]]; then
        aap_verify_certs=$opt_verify_certs
    elif [[ -z "$aap_verify_certs" ]]; then
        if confirm "Validate AAP's TLS certificate? (answer n for self-signed certificates)" \
                "$([[ "$def_verify" == "false" ]] && echo n || echo y)"; then
            aap_verify_certs=true
        else
            aap_verify_certs=false
        fi
    fi

    if [[ -n "${AAP_TOKEN:-}" ]]; then
        aap_auth=token aap_token=$AAP_TOKEN
    elif [[ -n "$opt_username" ]]; then
        aap_auth=password aap_username=$opt_username aap_password=${AAP_PASSWORD:-}
    elif interactive; then
        menu choice "How should the scripts log in to AAP?" "$([[ "$def_auth" == "token" ]] && echo 2 || echo 1)" \
            "Username and password (recommended; a temporary token is created for each run)" \
            "An existing OAuth token"
        if [[ "$choice" == "2" ]]; then
            aap_auth=token
        else
            aap_auth=password
            ask aap_username "AAP username" "${def_username:-admin}"
        fi
    elif [[ -n "$def_username" && -n "${AAP_PASSWORD:-}" ]]; then
        aap_auth=password aap_username=$def_username aap_password=$AAP_PASSWORD
    else
        die "No AAP credentials given. Use --username <user> with \$AAP_PASSWORD, or set \$AAP_TOKEN."
    fi

    if [[ "$aap_auth" == "password" && -z "$aap_password" ]]; then
        interactive || die "No password for '$aap_username'. Set \$AAP_PASSWORD."
        local keep=""
        [[ -n "$def_password" && "$aap_username" == "$def_username" ]] && keep=" (Enter keeps the current one)"
        while [[ -z "$aap_password" ]]; do
            read -rsp "AAP password for $aap_username$keep: " aap_password
            echo ""
            if [[ -z "$aap_password" && -n "$keep" ]]; then aap_password=$def_password; fi
        done
    elif [[ "$aap_auth" == "token" && -z "$aap_token" ]]; then
        local keep=""
        [[ -n "$def_token" ]] && keep=" (Enter keeps the current one)"
        while [[ -z "$aap_token" ]]; do
            read -rsp "AAP OAuth token$keep: " aap_token
            echo ""
            if [[ -z "$aap_token" && -n "$keep" ]]; then aap_token=$def_token; fi
        done
    fi
}

# Sets test_result to ok | failed | cert | skipped
test_connection() {
    test_result=skipped
    if ! command -v curl >/dev/null 2>&1; then
        warn "curl not found; skipping the connection test."
        return
    fi
    local base=$aap_hostname body code rc err server="" me_path detected="" server_version=""
    local -a insecure=()
    [[ "$base" =~ ^https?:// ]] || base="https://$base"
    [[ "$aap_verify_certs" == "false" ]] && insecure=(--insecure)
    body=$(mktemp) err=$(mktemp)

    _probe() {
        rc=0
        code=$(curl -sS --max-time 15 ${insecure[@]+"${insecure[@]}"} -o "$body" -w '%{http_code}' "$1" 2>"$err") || rc=$?
    }

    _probe "$base/api/gateway/v1/ping/"
    if (( rc == 60 || rc == 35 || rc == 51 || rc == 58 || rc == 77 || rc == 83 )); then
        warn "TLS problem talking to $base: $(head -1 "$err")"
        test_result=cert
        rm -f "$body" "$err"
        return
    elif (( rc != 0 )); then
        warn "Can't reach $base: $(head -1 "$err")"
        test_result=failed
        rm -f "$body" "$err"
        return
    fi
    if [[ "$code" == "200" || "$code" == "401" || "$code" == "403" ]]; then
        server_version=$(grep -o '"version" *: *"[^"]*"' "$body" | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true)
        server=gateway me_path="/api/gateway/v1/me/"
        detected="${server_version:-2.5 or newer} (platform gateway)"
    else
        _probe "$base/api/v2/ping/"
        if [[ "$rc" == "0" && "$code" == "200" ]]; then
            local cv
            cv=$(grep -o '"version" *: *"[^"]*"' "$body" | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true)
            server=controller me_path="/api/v2/me/" detected="2.4 (Automation Controller${cv:+ $cv})"
        fi
    fi
    if [[ -z "$server" ]]; then
        warn "$base answered, but doesn't look like AAP (no gateway or controller API found)."
        test_result=failed
        rm -f "$body" "$err"
        return
    fi
    info "Reached AAP $detected"
    api_base=$base api_server=$server

    local cfg
    cfg="url = $(curl_quote "$base$me_path")"$'\n'
    if [[ "$aap_auth" == "token" ]]; then
        cfg+="header = $(curl_quote "Authorization: Bearer $aap_token")"$'\n'
    else
        cfg+="user = $(curl_quote "$aap_username:$aap_password")"$'\n'
    fi
    rc=0
    code=$(printf '%s' "$cfg" | curl -sS --max-time 15 ${insecure[@]+"${insecure[@]}"} -o "$body" -w '%{http_code}' -K - 2>"$err") || rc=$?
    rm -f "$body" "$err"
    if [[ "$rc" != "0" ]]; then
        warn "The login check failed to run (curl exit $rc)."
        test_result=failed
        return
    fi
    case "$code" in
        200) info "Credentials accepted" ;;
        401) warn "AAP rejected the credentials (HTTP 401)."; test_result=failed; return ;;
        403) warn "AAP refused the request (HTTP 403); the account may be locked or lack API access."; test_result=failed; return ;;
        *)   warn "Unexpected answer from AAP when checking credentials (HTTP $code)."; test_result=failed; return ;;
    esac

    if [[ "$server" == "gateway" && -n "$server_version" && "$server_version" != "$CASC_AAP_VERSION" ]]; then
        warn "This environment is set to AAP $CASC_AAP_VERSION, but the server reports AAP $server_version."
        warn "Fix CASC_AAP_VERSION in $rel_env/vars.env (or delete it and re-run) if that's wrong."
    elif [[ "$server" == "gateway" && "$CASC_AAP_VERSION" == "2.4" ]]; then
        warn "This environment is set to AAP 2.4, but the server is AAP 2.5 or newer."
        warn "Fix CASC_AAP_VERSION in $rel_env/vars.env (or delete it and re-run) if that's wrong."
    elif [[ "$server" == "controller" && "$CASC_AAP_VERSION" != "2.4" ]]; then
        warn "This environment is set to AAP $CASC_AAP_VERSION, but that URL answers like AAP $detected."
        warn "On AAP 2.5+, use the platform gateway URL, not the controller's. If the server really is 2.4,"
        warn "fix CASC_AAP_VERSION in $rel_env/vars.env (or delete it and re-run) if that's wrong."
    fi
    test_result=ok
}

# Rewrite the connection keys of a vault's plaintext (stdin -> stdout), keeping everything else.
# Keys that don't exist yet are added before the YAML end marker (or at the end).
apply_connection_to_vault() {
    local line wrote_host=false wrote_verify=false wrote_user=false wrote_pass=false wrote_token=false
    _missing_keys() {
        [[ "$wrote_host" == "true" ]] || printf 'vault_aap_hostname: %s\n' "$(yaml_quote "$aap_hostname")"
        [[ "$wrote_verify" == "true" ]] || printf 'vault_aap_validate_certs: %s\n' "$aap_verify_certs"
        if [[ "$aap_auth" == "token" ]]; then
            [[ "$wrote_token" == "true" ]] || printf 'vault_aap_token: %s #sensitive\n' "$(yaml_quote "$aap_token")"
        else
            [[ "$wrote_user" == "true" ]] || printf 'vault_aap_username: %s\n' "$(yaml_quote "$aap_username")"
            [[ "$wrote_pass" == "true" ]] || printf 'vault_aap_password: %s #sensitive\n' "$(yaml_quote "$aap_password")"
        fi
        wrote_host=true wrote_verify=true wrote_user=true wrote_pass=true wrote_token=true
    }
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            vault_aap_hostname:*)
                printf 'vault_aap_hostname: %s\n' "$(yaml_quote "$aap_hostname")"; wrote_host=true ;;
            vault_aap_validate_certs:*)
                printf 'vault_aap_validate_certs: %s\n' "$aap_verify_certs"; wrote_verify=true ;;
            vault_aap_username:*|"# vault_aap_username:"*)
                if [[ "$aap_auth" == "token" ]]; then printf '# %s\n' "${line#\# }"
                else printf 'vault_aap_username: %s\n' "$(yaml_quote "$aap_username")"; wrote_user=true; fi ;;
            vault_aap_password:*|"# vault_aap_password:"*)
                if [[ "$aap_auth" == "token" ]]; then printf '# vault_aap_password: "" #sensitive\n'
                else printf 'vault_aap_password: %s #sensitive\n' "$(yaml_quote "$aap_password")"; wrote_pass=true; fi ;;
            vault_aap_token:*|"# vault_aap_token:"*)
                if [[ "$aap_auth" == "token" ]]; then printf 'vault_aap_token: %s #sensitive\n' "$(yaml_quote "$aap_token")"; wrote_token=true
                elif [[ "$line" == "#"* ]]; then printf '%s\n' "$line"
                else printf '# vault_aap_token: "" #sensitive\n'; fi ;;
            ...)
                _missing_keys; printf '%s\n' "$line" ;;
            *)
                printf '%s\n' "$line" ;;
        esac
    done
    _missing_keys
}

render_vault() {
    apply_connection_to_vault < "$vault_template_file"
}

# Ask for connection details and test them until they work (or the user saves/quits).
connection_loop() {
    while true; do
        collect_connection_details
        if [[ "$opt_skip_test" == "true" ]]; then
            test_result=skipped
            return 0
        fi
        test_connection
        case "$test_result" in
            ok|skipped) return 0 ;;
        esac
        interactive || die "Connection test failed. Fix the details, or re-run with --skip-test to save them anyway."
        if [[ "$test_result" == "cert" && "$aap_verify_certs" == "true" ]]; then
            if confirm "AAP's certificate isn't trusted. Turn off certificate validation and retry?" n; then
                aap_verify_certs=false
                continue
            fi
        fi
        menu choice "What now?" 1 "Re-enter the connection details" "Save them anyway" "Quit"
        case "$choice" in
            1) def_hostname=$aap_hostname def_verify=$aap_verify_certs def_auth=$aap_auth def_username=$aap_username
               aap_hostname="" aap_verify_certs="" aap_password="" aap_token=""
               opt_hostname="" opt_verify_certs="" opt_username="" ;;
            2) return 0 ;;
            3) say "Nothing was saved to the vault. Re-run ./start_here.sh $org $env when ready."; exit 1 ;;
        esac
    done
}

# Load connection details from an existing (unlocked) vault into the def_* defaults.
load_defaults_from_vault() {
    read_vault_values "$1" || return 1
    def_hostname=$vv_hostname def_verify=$vv_verify def_username=$vv_username
    def_password=$vv_password def_token=$vv_token def_auth=password
    [[ -n "$vv_token" && -z "$vv_password" ]] && def_auth=token
    return 0
}

# List AAP organization names (after a successful connection test).
fetch_org_names() {
    local path cfg
    [[ -n "$api_base" ]] || return 1
    find_vault_python || return 1
    path="/api/gateway/v1/organizations/?page_size=200&order_by=name"
    [[ "$api_server" == "controller" ]] && path="/api/v2/organizations/?page_size=200&order_by=name"
    cfg="url = $(curl_quote "$api_base$path")"$'\n'
    if [[ "$aap_auth" == "token" ]]; then
        cfg+="header = $(curl_quote "Authorization: Bearer $aap_token")"$'\n'
    else
        cfg+="user = $(curl_quote "$aap_username:$aap_password")"$'\n'
    fi
    [[ "$aap_verify_certs" == "false" ]] && cfg+="insecure"$'\n'
    printf '%s' "$cfg" | curl -sSf --max-time 15 -K - 2>/dev/null | "${vault_python[@]}" -c '
import json, sys
for o in json.load(sys.stdin).get("results", []):
    if o.get("name"): print(o["name"])
' 2>/dev/null
}

choose_org_filter() {
    local current names=() opts i
    [[ -f "$vars_file" ]] || return 0
    current=$(current_org_filter)
    if [[ -n "$opt_org_filter" ]]; then
        set_org_filter "$opt_org_filter"
        info "Exports limited to AAP organization '$opt_org_filter' (organization_filter in vars.yml)"
        return 0
    fi
    [[ -z "$current" ]] || return 0
    interactive || return 0
    step "Organizations to export"
    say "Exports can include every AAP organization your user can see, or just one (organization_filter"
    say "in vars.yml). This only affects exports; imports apply whatever is in your files."
    if [[ "$test_result" == "ok" ]]; then
        mapfile -t names < <(fetch_org_names || true)
    fi
    if [[ ${#names[@]} -gt 0 ]]; then
        opts=("All organizations (no filter)" "${names[@]}" "Type a name")
        menu choice "Which organizations should be exported?" 1 "${opts[@]}"
        if (( choice == 1 )); then
            info "All organizations"
            return 0
        elif (( choice == ${#opts[@]} )); then
            ask current "AAP organization name"
        else
            current=${names[choice-2]}
        fi
    else
        confirm "Limit exports to one AAP organization?" n || { info "All organizations"; return 0; }
        ask current "AAP organization name"
    fi
    [[ -n "$current" ]] || return 0
    set_org_filter "$current"
    info "Exports limited to '$current' (organization_filter in $rel_env/vars.yml)"
}

# Re-encrypt the environment vault with new connection details, keeping other secrets.
update_env_vault() {
    local tmp="$vault_file.tmp.$$"
    if ! ansible-vault view "$vault_file" | apply_connection_to_vault | ansible-vault encrypt --output "$tmp" >/dev/null; then
        rm -f "$tmp"
        die "Failed to update $rel_env/vault.yml; it was left unchanged."
    fi
    mv "$tmp" "$vault_file"
    info "Updated the connection details in $rel_env/vault.yml (other secrets kept)"
}



# --- Already complete? Show status (and a menu) ---------------------------------------------
if [[ -f "$env_vars_file" && -f "$vars_file" && -f "$vault_file" && -d "$imports_dir" && -d "$exports_dir" ]]; then
    # shellcheck source=/dev/null
    source "$env_vars_file"
    layout=$(current_layout)
    create_type_folders "$layout"
    show_status() {
        local import_files last filter
        say ""
        say "Environment '$env' in workspace '$org' is set up:"
        say "  AAP version:   ${CASC_AAP_VERSION:-unknown}"
        say "  Import layout: $layout (flatten_output in $rel_env/vars.yml)"
        filter=$(current_org_filter)
        if [[ -n "$filter" ]]; then
            say "  Export scope:  AAP organization '$filter' (organization_filter)"
        else
            say "  Export scope:  all AAP organizations"
        fi
        if _vault_is_encrypted "$vault_file"; then
            say "  Vault:         $rel_env/vault.yml (encrypted)"
        else
            say "  Vault:         $rel_env/vault.yml (⚠️  NOT encrypted; run: ansible-vault encrypt $rel_env/vault.yml)"
        fi
        say "  Password:      $(describe_vault_password_source)"
        if [[ -f "$common_vault_file" ]]; then
            say "  Common vault:  $rel_common/vault.yml"
        else
            say "  Common vault:  missing (create with: ./vault-edit.sh $org common)"
        fi
        import_files=$(find "$imports_dir" -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | wc -l)
        say "  Imports:       $import_files YAML file(s) in $rel_env/imports"
        last=$(latest_export)
        say "  Last export:   ${last:-none yet}"
        say ""
    }
    show_status
    if ! interactive; then
        say "Edit the vault with: ./vault-edit.sh $org $env   (view it with ./vault-view.sh $org $env)"
        exit 0
    fi
    while true; do
        opts=("Test the connection to AAP" "Update the connection details (URL, certificate check, login)")
        if password_is_prompted; then
            opts+=("Save this workspace's vault password to a file (stop being asked for it)")
        fi
        opts+=("Show next steps" "Exit")
        menu choice "What would you like to do?" "${#opts[@]}" "${opts[@]}"
        case "${opts[choice-1]}" in
            "Test the connection"*)
                unlock_vault "$vault_file"
                load_defaults_from_vault "$vault_file" || die "Couldn't read $rel_env/vault.yml."
                if [[ "$def_hostname" == "aap.mycompany.com" ]]; then
                    warn "The vault still has the template hostname; choose 'Update the connection details'."
                    continue
                fi
                aap_hostname=$def_hostname aap_verify_certs=${def_verify:-true} aap_auth=$def_auth
                aap_username=$def_username aap_password=$def_password aap_token=$def_token
                step "Connection test"
                test_connection
                [[ "$test_result" == "ok" ]] && info "The saved connection details work."
                say "" ;;
            "Update the connection details"*)
                unlock_vault "$vault_file"
                load_defaults_from_vault "$vault_file" || true
                step "Connection to AAP"
                aap_hostname="" aap_verify_certs="" aap_password="" aap_token=""
                connection_loop
                update_env_vault
                say "" ;;
            "Save this workspace's vault password"*)
                unlock_vault "$vault_file"
                if [[ "$VAULT_PASSWORD_PROMPTED" == "true" ]]; then
                    offer_save_vault_password false
                else
                    info "The vault password already comes $(vault_password_source_label)."
                fi
                say "" ;;
            "Show next steps")
                print_next_steps "$layout" ;;
            *)
                offer_bash_completion
                exit 0 ;;
        esac
    done
fi

if [[ -d "$env_dir" ]]; then
    say "🔧 Repairing environment '$env' in workspace '$org' (only missing pieces are added)."
else
    say "🚀 Setting up environment '$env' in workspace '$org'."
fi

# --- Step: AAP version ------------------------------------------------------------------------
if [[ -f "$env_vars_file" ]]; then
    # shellcheck source=/dev/null
    source "$env_vars_file"
    step "AAP version"
    info "Using AAP ${CASC_AAP_VERSION} from $rel_env/vars.env"
else
    step "AAP version"
    if [[ -n "$sibling_env" ]]; then
        say "Defaults are taken from environment '$sibling_env' in this workspace."
    fi
    if [[ -n "$opt_version" ]]; then
        CASC_AAP_VERSION=$opt_version
    elif ! interactive && [[ -n "$sib_version" ]]; then
        CASC_AAP_VERSION=$sib_version
    else
        interactive || die "No AAP version given. Use --version <ver> (available: ${available_versions[*]})."
        version_labels=() default_idx=""
        for i in "${!available_versions[@]}"; do
            v=${available_versions[i]}
            label=$(bash -c 'source "$1" >/dev/null 2>&1; printf "%s" "${aap_version_label:-}"' _ "$script_vars_dir/$v/vars.env")
            version_labels+=("AAP $v${label:+  ($label)}")
            [[ "$v" == "$sib_version" ]] && default_idx=$((i + 1))
        done
        menu choice "Which AAP version is this environment?" "$default_idx" "${version_labels[@]}"
        CASC_AAP_VERSION=${available_versions[choice-1]}
    fi
    [[ -d "$script_vars_dir/$CASC_AAP_VERSION" ]] || die "Unsupported AAP version '$CASC_AAP_VERSION' (available: ${available_versions[*]})."
    info "AAP $CASC_AAP_VERSION"
fi

# --- Step: import layout ----------------------------------------------------------------------
step "Import layout"
if [[ -f "$vars_file" ]]; then
    layout=$(current_layout)
    info "Using the $layout layout from $rel_env/vars.yml"
elif [[ -n "$opt_layout" ]]; then
    layout=$opt_layout
    info "${layout^} layout"
elif interactive; then
    say "How should configuration files be organized for import? (Exports always contain both.)"
    say ""
    say "  1) Filetree (recommended)"
    say "       One folder per object type, usually one file per object:"
    say "         imports/controller_projects.d/Network Playbooks.yml"
    say "         imports/controller_job_templates.d/Backup Configs.yml"
    say "       Easy to review and merge in Git; matches how exports are organized."
    say ""
    say "  2) Flat"
    say "       Any YAML files, anywhere under imports/ and common/; folder names don't matter:"
    say "         imports/projects.yml       (contains controller_projects: [...])"
    say "         imports/team-a/stuff.yml   (can contain several object types)"
    say "       Handy for small or hand-written configurations."
    say ""
    say "  You can switch later with flatten_output in vars.yml. Details: docs/CONCEPTS.md#filetree-and-flat-layouts"
    ask choice "Choose [1-2]" "$([[ "$sib_layout" == "flat" ]] && echo 2 || echo 1)"
    case "$choice" in
        2|f|flat) layout=flat ;;
        *)        layout=filetree ;;
    esac
    info "${layout^} layout"
elif [[ -n "$sib_layout" ]]; then
    layout=$sib_layout
    info "${layout^} layout (same as '$sibling_env')"
else
    layout=filetree
    info "Filetree layout (default)"
fi

# --- Step: tools and collections --------------------------------------------------------------
step "Checking tools"
core_version=$(ansible --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
if command -v ansible-playbook >/dev/null 2>&1; then
    info "ansible-core ${core_version:-?}"
    if [[ "$CASC_AAP_VERSION" == "2.4" && -n "$core_version" ]] && \
       [[ "$(printf '%s\n%s\n' "$core_version" "2.19" | sort -V | head -1)" == "2.19" ]]; then
        warn "Importing into AAP 2.4 needs ansible-core 2.16-2.18 (you have $core_version)."
        warn "Use a virtualenv with ansible-core 2.18, or --navigator with an AAP 2.4 Execution Environment."
        warn "Exports work fine. See docs/VERSIONS_AND_COLLECTIONS.md#ansible-core-requirements"
    fi
else
    warn "ansible-playbook not found. Install ansible-core, or use --navigator with an Execution Environment."
fi
collections_dir="$parent_dir/collections/$CASC_AAP_VERSION/ansible_collections"
if [[ -d "$collections_dir" ]] && [[ -n "$(ls -A "$collections_dir" 2>/dev/null)" ]]; then
    info "Collections for AAP $CASC_AAP_VERSION are installed"
else
    warn "Collections for AAP $CASC_AAP_VERSION aren't installed (needed unless you use --navigator)."
    if ! grep -Eqs '^[[:space:]]*token[[:space:]]*=[[:space:]]*[^[:space:]]' "$parent_dir/ansible.cfg"; then
        warn "Installing needs a Red Hat Automation Hub token in ansible.cfg (for ansible.controller"
        warn "and ansible.platform)."
        if ! offer_hub_token; then
            warn "To add it later: cp ansible.cfg.example ansible.cfg, then fill in the token= lines"
            warn "(get a token at https://console.redhat.com/ansible/automation-hub/token)"
        fi
    fi
    if interactive && confirm "Install them now with ./install_collections.sh $CASC_AAP_VERSION?" y; then
        if ! (cd "$parent_dir" && ./install_collections.sh "$CASC_AAP_VERSION"); then
            warn "Installation failed (see above). Fix it and run ./install_collections.sh $CASC_AAP_VERSION later."
        fi
    else
        info "Install later with: ./install_collections.sh $CASC_AAP_VERSION"
    fi
fi

# --- Step: folders and settings files ---------------------------------------------------------
step "Folders and settings"
if [[ ! -f "$env_vars_file" ]]; then
    mkdir -p "$env_dir"
    {
        echo "CASC_AAP_VERSION=\"$CASC_AAP_VERSION\""
        echo "FLATTEN_OUTPUT=$([[ "$layout" == "flat" ]] && echo true || echo false)"
    } > "$env_vars_file"
    info "Wrote $rel_env/vars.env"
fi
create_type_folders "$layout"
if [[ ! -f "$vars_file" ]]; then
    cp "$vars_template_file" "$vars_file"
    if [[ "$layout" == "flat" ]]; then
        sed -i 's/^flatten_output: .*/flatten_output: true/' "$vars_file"
    fi
    info "Wrote $rel_env/vars.yml (import options; see the comments inside)"
fi

need_env_vault=false need_common_vault=false
[[ -f "$vault_file" ]] || need_env_vault=true
[[ ! -f "$common_vault_file" && -f "$vault_common_template_file" ]] && need_common_vault=true

# An existing vault in this workspace whose password new vaults must share.
reference_vault=""
for f in "$common_vault_file" "$vault_file"; do
    if _vault_is_encrypted "$f"; then reference_vault=$f; break; fi
done
if [[ -z "$reference_vault" ]]; then
    while IFS= read -r f; do
        if _vault_is_encrypted "$f"; then reference_vault=$f; break; fi
    done < <(find "$org_base_dir" -mindepth 2 -maxdepth 2 -name vault.yml -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
fi

if [[ "$need_env_vault" == "true" || "$need_common_vault" == "true" ]]; then
    step "Vault password"
    new_ws_password_file=$(vault_workspace_password_file "$org")
    shared_password_file=$(vault_global_password_file)
    if [[ -n "$reference_vault" ]]; then
        say "All vaults in a workspace share one password; it's checked against ${reference_vault#"$parent_dir"/}."
        unlock_vault "$reference_vault"
        info "Vault password OK ($(vault_password_source_label))"
    elif [[ -n "${CASC_VAULT_PASSWORD:-}" ]]; then
        info "Encrypting the new vault(s) with the password from \$CASC_VAULT_PASSWORD"
        ensure_vault_password --confirm
    elif [[ -f "$new_ws_password_file" ]]; then
        info "Encrypting the new vault(s) with ${new_ws_password_file#"$parent_dir"/}"
        ensure_vault_password --confirm
    elif [[ -n "$shared_password_file" && -f "$shared_password_file" ]]; then
        use_shared=true
        if interactive; then
            say "A shared vault password file is configured ($shared_password_file). This new workspace"
            say "can use that password, or one of its own (you'll be asked for it, or can save it to"
            say "${new_ws_password_file#"$parent_dir"/})."
            menu choice "Which vault password should workspace '$org' use?" 1 \
                "The password in $shared_password_file (same as other workspaces using it)" \
                "A new password for this workspace only"
            if [[ "$choice" == "2" ]]; then
                use_shared=false
            fi
        fi
        if [[ "$use_shared" == "true" ]]; then
            info "Encrypting the new vault(s) with the password in $shared_password_file"
            ensure_vault_password --confirm
        else
            ensure_vault_password --confirm --ignore-global
        fi
    else
        say "Choose a password to encrypt this workspace's vaults (connection details and secrets)."
        say "Every environment in the workspace uses this password; other workspaces can use different ones."
        ensure_vault_password --confirm
    fi
    offer_save_vault_password
fi

if [[ "$need_env_vault" == "true" ]]; then
    # Defaults from the sibling environment's vault (same password).
    if [[ -n "$sibling_env" && -f "$org_base_dir/$sibling_env/vault.yml" ]] && \
       load_defaults_from_vault "$org_base_dir/$sibling_env/vault.yml"; then
        def_hostname="" def_password="" def_token=""
    fi
    step "Connection to AAP"
    say "These details are stored encrypted in $rel_env/vault.yml."
    connection_loop
fi

choose_org_filter

if [[ "$need_env_vault" == "true" ]]; then
    if ! render_vault | ansible-vault encrypt --output "$vault_file" >/dev/null; then
        rm -f "$vault_file"
        die "Failed to encrypt $rel_env/vault.yml (see the message above). Nothing was saved; re-run to try again."
    fi
    info "Saved connection details to $rel_env/vault.yml (encrypted)"
fi

if [[ "$need_common_vault" == "true" ]]; then
    if ansible-vault encrypt --output "$common_vault_file" < "$vault_common_template_file" >/dev/null; then
        info "Created $rel_common/vault.yml (encrypted) for secrets shared by every environment"
    else
        rm -f "$common_vault_file"
        warn "Couldn't create $rel_common/vault.yml. Create it later with: ./vault-edit.sh $org common"
    fi
fi

# --- Done --------------------------------------------------------------------------------------
say ""
say "✅ Environment '$env' in workspace '$org' is ready (AAP $CASC_AAP_VERSION, $layout layout)."
say "   Edit connection details or secrets any time with: ./vault-edit.sh $org $env"
say "   Check or update this environment later with:      ./start_here.sh $org $env"
offer_bash_completion
print_next_steps "$layout"
