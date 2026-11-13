# Troubleshooting

Find your error message or symptom below. For more detail from any run, add `ANSIBLE_VERBOSITY=3` in front of the command:

```bash
ANSIBLE_VERBOSITY=3 ./import.sh MyCompany prod -t controller_projects
```

* [Setup and scripts](#setup-and-scripts)
* [Setup wizard connection test](#setup-wizard-connection-test)
* [Vault and passwords](#vault-and-passwords)
* [Collections and ansible-core](#collections-and-ansible-core)
* [Connecting to AAP](#connecting-to-aap)
* [Import problems](#import-problems)
* [Export problems](#export-problems)
* [Getting help](#getting-help)

---

## Setup and scripts

**`Permission denied` when running a script**
Make the scripts executable: `chmod +x *.sh scripts/*.sh`.

**`declare: -n: invalid option` or `declare: -A: invalid option`**
Your Bash is older than 4.3. macOS ships Bash 3.2, so install a newer one (for example `brew install bash`) and run the scripts with it.

**`Error: Workspace '<workspace>' not found` / `Environment '<env>' not found`**
The folder doesn't exist under `orgs_vars/`. The message lists the ones that do. Create a new environment with `./start_here.sh <workspace> <env>`.

**`Error: Environment config file '.../vars.env' not found`**
The environment is incomplete. Run `./start_here.sh <workspace> <env>` again; it repairs missing pieces without overwriting existing ones.

**`Error: Invalid tag(s) provided`**
Tags differ between AAP versions (for example `projects` on 2.4 vs. `controller_projects` on 2.5+). Run `./export.sh <workspace> <env>` or `./import.sh <workspace> <env>` without options to list the valid tags. See [Tags](VERSIONS_AND_COLLECTIONS.md#tags).

**`Error: Missing option [-a|--all] or [-t|--tags]`**
Tell the script what to process: `-a` for everything, or `-t "<tags>"`.

**`Invalid workspace name` / `Invalid environment name` / `'common' is reserved`**
Names may contain letters, digits, `.`, `_` and `-`, and must start with a letter or digit. `common` can't be an environment name because it's the workspace's shared folder.

**`That password doesn't open orgs_vars/<workspace>/.../vault.yml`**
Every vault in a workspace uses the same password, and the one you type is checked against an existing vault (three tries). Enter that workspace's password. If you've forgotten it, the existing vaults can't be decrypted; you'll need to recreate them (delete them and re-run the wizard).

**`Note: the shared vault password file ... doesn't open ...; this workspace uses a different password`**
Not an error. Your shared password file (`ansible.cfg` or `ANSIBLE_VAULT_PASSWORD_FILE`) holds another workspace's password, so you're asked for this workspace's password instead. To stop being asked, save it to `.vault_pass/<workspace>.txt` (`./start_here.sh <workspace> <env>` offers this).

**`Note: .vault_pass/<workspace>.txt doesn't open ...`**
The workspace's password file holds the wrong password (for example, the vaults were re-keyed). Fix or delete the file; until then you're asked for the password.

**`The vault password in $CASC_VAULT_PASSWORD doesn't open ...`**
`$CASC_VAULT_PASSWORD` holds a different workspace's password. Set the right one, or unset it to use a password file or the prompt.

**I picked the wrong AAP version or layout in the wizard**
Change `CASC_AAP_VERSION` in `orgs_vars/<workspace>/<env>/vars.env`, or `flatten_output` in `vars.yml`. Or delete the file and run `./start_here.sh <workspace> <env>` again to be asked again. If you change the version, re-run the wizard so it creates that version's folders.

## Setup wizard connection test

The wizard tests the connection before saving your credentials. If the test fails, you can re-enter the details, save them anyway, or quit (nothing is saved). With `--yes`, a failed test stops the wizard; add `--skip-test` to save without testing.

**`Can't reach https://...: Could not resolve host`** / **`Connection refused`** / **`timed out`**
Check the URL, DNS, VPN and proxy settings. The test uses `curl`, so `https_proxy` / `no_proxy` apply.

**I need to change the saved URL, password or token**
Run `./start_here.sh <workspace> <env>` and choose **Update the connection details**. It re-tests the connection and keeps the other secrets in the vault. Or edit the vault directly with `./vault-edit.sh <workspace> <env>`.

**`TLS problem talking to ...`**
The certificate isn't trusted (often self-signed). The wizard offers to turn off certificate validation; or install the CA certificate on your machine and keep validation on.

**`... answered, but doesn't look like AAP`**
The URL reached a web server without an AAP API. Use the base URL of AAP (for example `https://aap.example.com`), not a page or sub-path.

**`AAP rejected the credentials (HTTP 401)`**
Wrong username or password (or token). Accounts that only exist in an external authenticator may need a local account or a token instead.

**`the server reports AAP X` / `that URL answers like AAP 2.4`**
The version you chose doesn't match the server. Either choose the right version, or, on AAP 2.5+, use the **platform gateway** URL instead of the controller's.

## Vault and passwords

**The script asks for a vault password every time**
That's the default when no password file is configured. To avoid it, see [Vault password](../README.md#vault-password-prompt-or-password-file).

**`Note: the vault password file '...' (ansible.cfg or ANSIBLE_VAULT_PASSWORD_FILE) doesn't exist.`**
`ansible.cfg` (or `ANSIBLE_VAULT_PASSWORD_FILE`) points to a missing file, so the script prompts instead. Create the file, or comment out the setting.

**`Error: A vault password is required, but no usable vault password file was found and this shell isn't interactive`**
You're running without a terminal (CI, cron, a pipe). Set `CASC_VAULT_PASSWORD`, or save the workspace's password to `.vault_pass/<workspace>.txt`. See [Run without prompts](HOW_TO.md#run-without-prompts-cicd).

**`Decryption failed (no vault secrets were found that could decrypt)`**
The password is wrong for that vault file. All vaults in a workspace (environments and `common`) must share one password. If they don't, re-key one with `ansible-vault rekey <file>`. Different workspaces may use different passwords.

**`Attempting to decrypt but no vault secrets found`** or **`The vault password file ... was not found`**
These appear when running `ansible-playbook` or `ansible-vault` directly, outside the scripts. Pass `--ask-vault-pass` or `--vault-password-file <file>`, or use the scripts, which handle it for you.

**`'vault_...' is undefined`**
A file references a secret placeholder that no vault defines. Add it to the environment vault (`./vault-edit.sh <workspace> <env>`) or the common vault (`./vault-edit.sh <workspace> common`). See [Handle secrets](HOW_TO.md#handle-secrets).

## Collections and ansible-core

**`Error: Collections not found for AAP <version>`**
Install them: `./install_collections.sh <version>`. Or run with `--navigator` and an Execution Environment.

**`install_collections.sh` fails with `401`, `403` or `Failed to get data from the API server` (console.redhat.com)**
The certified collections need a valid Automation Hub token in `ansible.cfg` (`token=` under `[galaxy_server.certified]` and `[galaxy_server.validated]`). Get a new token at <https://console.redhat.com/ansible/automation-hub/token>; offline tokens expire after 30 days without use.

**`AAP 2.4 import requires ansible-core < 2.19`**
The AAP 2.4 collection doesn't work with ansible-core 2.19+. Use a virtualenv with ansible-core 2.18 or the 2.4 Execution Environment. See [ansible-core requirements](VERSIONS_AND_COLLECTIONS.md#ansible-core-requirements).

**`argument 'messages' is of type str and we were unable to convert to dict` (or the same for `variables`, `injectors`, `source_vars`), or `<<Omit>>` in an error**
Same cause as above: importing into AAP 2.4 with ansible-core 2.19+.

**`Error: 'execution_environment' variable not found`**
You used `--navigator`, but `script_vars/<version>/vars.env` has no `execution_environment`. Set it to your EE image, or drop `--navigator`.

**`couldn't resolve module/action` or `the role '...' was not found`**
The collections for that AAP version are missing or incomplete. Re-run `./install_collections.sh <version>`, then check with `./list_collections.sh <version>`.

## Connecting to AAP

**`CERTIFICATE_VERIFY_FAILED` / `certificate verify failed`**
AAP uses a certificate your machine doesn't trust (for example, self-signed). Set `vault_aap_validate_certs: false` in the environment vault, or install the CA certificate on your machine.

**`Name or service not known` / `Connection refused` / timeouts while creating the token**
Check `vault_aap_hostname` (`./vault-view.sh <workspace> <env>` shows it). On AAP 2.5+, it must be the **platform gateway** URL, not the controller's.

**`401 Unauthorized` / `Invalid username/password`**
Check `vault_aap_username` / `vault_aap_password`, or `vault_aap_token`. Users from an external authenticator (LDAP, SAML) may not be able to create tokens. Try a local admin account or a pre-created token.

**`403 Forbidden` / `You do not have permission`**
The account can't read (export) or change (import) some objects. Use an account with more rights, or limit the run with `-t` or `organization_filter`.

## Import problems

**Import succeeds, but my objects weren't created**
Check, in order:

1. **Top-level key:** it must match the [Object Reference](FOLDER_LAYOUT.md#object-type-reference) exactly. Common mistakes are `controller_job_templates:` (should be `controller_templates:`), `controller_workflow_job_templates:` (should be `controller_workflows:`) and `controller_notification_templates:` (should be `controller_notifications:`).
2. **Folder** (filetree layout): the file must be inside that type's `<type>.d/` folder (subfolders are fine).
3. **Layout:** `flatten_output` in `vars.yml` must match how your files are laid out.
4. **Location:** controller settings are read from `<env>/imports/controller_settings.d/` only, not `common/`. Files in `common/` are skipped when `import_common: false`.
5. **Tags:** with `-t`, only those object types are imported. On AAP 2.5+, organizations, teams, users and applications use the `gateway_*` import tags.

**`... does not exist` / `could not find <project/inventory/credential>`**
An object refers to something that isn't in AAP yet. Import its dependencies first, or include their tags in the same run. Check spelling, and the `organization:` field for objects whose names are only unique per organization.

**A second copy of an object was created**
Its `name:` changed. Objects are matched by name. To rename, use `new_name:` (see [Rename an object](HOW_TO.md#rename-an-object)), then delete the extra copy with `state: absent`.

**The same organization, team or user appears twice in my files**
That's fine. Entries with the same name (organization + name for teams and applications, username for users) are merged on import.

**Dry run (`--check`) reports changes right after an export**
Secrets always show as changed because AAP can't compare them. Some defaults differ between what AAP returns and what it accepts. Review the reported fields; if a field keeps changing, set it explicitly in your file.

## Export problems

**Export times out on a large instance**
Raise the API timeout: `CONTROLLER_REQUEST_TIMEOUT=300 ./export.sh <workspace> <env> -a`. Or export in parts with `-t`, or use `organization_filter`.

**Secrets show as `{{ vault_... }}` instead of values**
That's expected: AAP never returns secrets. See [Handle secrets](HOW_TO.md#handle-secrets).

**Some objects are missing from the export**
The account only sees what it has permission to see. Check `organization_filter` in `vars.yml`, and the tags you used.

## Getting help

* Ask in the [Matrix channel](https://matrix.to/#/#lennysh-aap-casc-demo:matrix.org).
* Open a [GitHub issue](https://github.com/lennysh/aap-casc-demo/issues). Include the AAP version, the command you ran, and the error (re-run with `ANSIBLE_VERBOSITY=3`). **Remove hostnames, passwords and tokens first.**
