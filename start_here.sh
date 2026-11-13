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
  --skip-test           Don't test the connection to AAP
  -y, --yes             Don't ask questions; use defaults and fail if required input is missing
                        (the vault password is still prompted unless \$CASC_VAULT_PASSWORD or a
                        vault password file is set)
  -h, --help            Show this help

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
opt_verify_certs="" opt_skip_test=false assume_yes=false
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
    say "Guides: README.md and docs/HOW_TO.md. Tab completion: source \"$parent_dir/autocomplete.sh\""
}

# --- Already complete? Show status and exit ---------------------------------------------------
if [[ -f "$env_vars_file" && -f "$vars_file" && -f "$vault_file" && -d "$imports_dir" && -d "$exports_dir" ]]; then
    # shellcheck source=/dev/null
    source "$env_vars_file"
    layout=$(current_layout)
    create_type_folders "$layout"
    say "Environment '$env' in workspace '$org' is already set up:"
    say "  AAP version:   ${CASC_AAP_VERSION:-unknown}"
    say "  Import layout: $layout (flatten_output in $rel_env/vars.yml)"
    if _vault_is_encrypted "$vault_file"; then
        say "  Vault:         $rel_env/vault.yml (encrypted)"
    else
        say "  Vault:         $rel_env/vault.yml (⚠️  NOT encrypted; run: ansible-vault encrypt $rel_env/vault.yml)"
    fi
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
    say "Edit the vault with: ./vault-edit.sh $org $env   (view it with ./vault-view.sh $org $env)"
    if [[ "$import_files" -eq 0 ]]; then
        print_next_steps "$layout"
    fi
    exit 0
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
    if [[ -n "$opt_version" ]]; then
        CASC_AAP_VERSION=$opt_version
    else
        interactive || die "No AAP version given. Use --version <ver> (available: ${available_versions[*]})."
        version_labels=()
        for v in "${available_versions[@]}"; do
            label=$(bash -c 'source "$1" >/dev/null 2>&1; printf "%s" "${aap_version_label:-}"' _ "$script_vars_dir/$v/vars.env")
            version_labels+=("AAP $v${label:+  ($label)}")
        done
        menu choice "Which AAP version is this environment?" "" "${version_labels[@]}"
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
    ask choice "Choose [1-2]" "1"
    case "$choice" in
        2|f|flat) layout=flat ;;
        *)        layout=filetree ;;
    esac
    info "${layout^} layout"
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
        warn "Installing needs a Red Hat Automation Hub token in ansible.cfg:"
        warn "  cp ansible.cfg.example ansible.cfg, then fill in the token= lines"
        warn "  (get a token at https://console.redhat.com/ansible/automation-hub/token)"
    fi
    if interactive && confirm "Install them now with ./install_collections.sh $CASC_AAP_VERSION?" y; then
        if ! "$parent_dir/install_collections.sh" "$CASC_AAP_VERSION"; then
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

# --- Step: connection details and vaults ------------------------------------------------------
aap_hostname="" aap_verify_certs="" aap_auth="" aap_username="" aap_password="" aap_token=""

collect_connection_details() {
    aap_hostname=${opt_hostname:-$aap_hostname}
    if [[ -z "$aap_hostname" ]]; then
        interactive || die "No AAP hostname given. Use --hostname <url>."
        local hint="the platform gateway URL"
        [[ "$CASC_AAP_VERSION" == "2.4" ]] && hint="the Automation Controller URL"
        while [[ -z "$aap_hostname" ]]; do
            ask aap_hostname "AAP URL ($hint, e.g. https://aap.example.com)"
        done
    fi
    aap_hostname=${aap_hostname%/}

    if [[ -n "$opt_verify_certs" ]]; then
        aap_verify_certs=$opt_verify_certs
    elif [[ -z "$aap_verify_certs" ]]; then
        if confirm "Validate AAP's TLS certificate? (answer n for self-signed certificates)" y; then
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
        menu choice "How should the scripts log in to AAP?" 1 \
            "Username and password (recommended; a temporary token is created for each run)" \
            "An existing OAuth token"
        if [[ "$choice" == "2" ]]; then
            aap_auth=token
        else
            aap_auth=password
            ask aap_username "AAP username" "${aap_username:-admin}"
        fi
    else
        die "No AAP credentials given. Use --username <user> with \$AAP_PASSWORD, or set \$AAP_TOKEN."
    fi

    if [[ "$aap_auth" == "password" && -z "$aap_password" ]]; then
        interactive || die "No password for '$aap_username'. Set \$AAP_PASSWORD."
        while [[ -z "$aap_password" ]]; do
            read -rsp "AAP password for $aap_username: " aap_password
            echo ""
        done
    elif [[ "$aap_auth" == "token" && -z "$aap_token" ]]; then
        while [[ -z "$aap_token" ]]; do
            read -rsp "AAP OAuth token: " aap_token
            echo ""
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

render_vault() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            vault_aap_hostname:*)
                printf 'vault_aap_hostname: %s\n' "$(yaml_quote "$aap_hostname")" ;;
            vault_aap_validate_certs:*)
                printf 'vault_aap_validate_certs: %s\n' "$aap_verify_certs" ;;
            vault_aap_username:*)
                if [[ "$aap_auth" == "token" ]]; then printf '# %s\n' "$line"
                else printf 'vault_aap_username: %s\n' "$(yaml_quote "$aap_username")"; fi ;;
            vault_aap_password:*)
                if [[ "$aap_auth" == "token" ]]; then printf '# %s\n' "$line"
                else printf 'vault_aap_password: %s #sensitive\n' "$(yaml_quote "$aap_password")"; fi ;;
            "# vault_aap_token:"*)
                if [[ "$aap_auth" == "token" ]]; then printf 'vault_aap_token: %s #sensitive\n' "$(yaml_quote "$aap_token")"
                else printf '%s\n' "$line"; fi ;;
            *)
                printf '%s\n' "$line" ;;
        esac
    done < "$vault_template_file"
}

need_env_vault=false need_common_vault=false
[[ -f "$vault_file" ]] || need_env_vault=true
[[ ! -f "$common_vault_file" && -f "$vault_common_template_file" ]] && need_common_vault=true

if [[ "$need_env_vault" == "true" ]]; then
    step "Connection to AAP"
    say "These details are stored encrypted in $rel_env/vault.yml."
    while true; do
        collect_connection_details
        if [[ "$opt_skip_test" == "true" ]]; then
            break
        fi
        test_connection
        case "$test_result" in
            ok|skipped) break ;;
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
            1) aap_hostname="" aap_verify_certs="" aap_password="" aap_token=""
               opt_hostname="" opt_verify_certs="" opt_username="" ;;
            2) break ;;
            3) say "Nothing was saved to the vault. Re-run ./start_here.sh $org $env when ready."; exit 1 ;;
        esac
    done
fi

if [[ "$need_env_vault" == "true" || "$need_common_vault" == "true" ]]; then
    step "Vault password"
    if [[ "$need_env_vault" == "true" && "$need_common_vault" == "false" && -f "$common_vault_file" ]]; then
        say "If asked, use the same vault password as $rel_common/vault.yml, so one password unlocks the whole workspace."
    else
        say "Choose a password to encrypt the vault(s). You'll need it for every export and import"
        say "(or store it in a file; see 'Vault password' in README.md)."
    fi
    ensure_vault_password --confirm
fi

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
print_next_steps "$layout"
