#!/bin/sh
# Vault password "file" used by the repo scripts when they prompt for the password.
# Ansible executes an executable vault_password_file and reads the password from stdout,
# so the password only lives in the CASC_VAULT_PASSWORD environment variable, never on disk.
if [ -z "${CASC_VAULT_PASSWORD:-}" ]; then
    echo "vault_pass_from_env.sh: CASC_VAULT_PASSWORD is not set" >&2
    exit 1
fi
printf '%s\n' "$CASC_VAULT_PASSWORD"
