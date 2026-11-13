# How-To Guide

Step-by-step recipes for common tasks. The examples use a workspace called `MyCompany` with environments `dev` and `prod`. Replace them with your own names.

**Getting started**

* [Export an existing AAP instance](#export-an-existing-aap-instance)
* [Put your configuration under Git](#put-your-configuration-under-git)
* [Add another environment](#add-another-environment)

**Day-to-day changes**

* [Add a new object](#add-a-new-object)
* [Change an existing object](#change-an-existing-object)
* [Rename an object](#rename-an-object)
* [Delete an object](#delete-an-object)
* [Check for drift](#check-for-drift)
* [Import only some object types](#import-only-some-object-types)

**Sharing and secrets**

* [Promote configuration from dev to prod](#promote-configuration-from-dev-to-prod)
* [Handle secrets](#handle-secrets)
* [Export a single AAP organization](#export-a-single-aap-organization)

**Automation and tooling**

* [Run without prompts (CI/CD)](#run-without-prompts-cicd)
* [Use an Execution Environment](#use-an-execution-environment)
* [Update or change collection versions](#update-or-change-collection-versions)
* [Convert between flat and filetree layouts](#convert-between-flat-and-filetree-layouts)
* [Convert controller roles to gateway role assignments](#convert-controller-roles-to-gateway-role-assignments)
* [Move to a different AAP version](#move-to-a-different-aap-version)

---

## Export an existing AAP instance

1. Create the environment (once):

    ```bash
    ./start_here.sh MyCompany prod
    ```

    Pick the AAP version and the *Filetree* layout, enter the AAP URL and credentials (answer **n** to certificate validation if AAP uses a self-signed certificate), and choose a vault password. The wizard tests the connection before saving anything.

2. Export:

    ```bash
    ./export.sh MyCompany prod -a
    ```

3. Look at the result in `orgs_vars/MyCompany/prod/exports/mycompany_prod_export_<timestamp>/filetree_version/`. Each object is its own YAML file.

4. Copy what you want to manage into `imports/` (or into `common/`, see [Promote configuration from dev to prod](#promote-configuration-from-dev-to-prod)):

    ```bash
    cp -r orgs_vars/MyCompany/prod/exports/mycompany_prod_export_*/filetree_version/* orgs_vars/MyCompany/prod/imports/
    ```

5. Fill in secrets ([Handle secrets](#handle-secrets)), then confirm that a dry run reports no changes:

    ```bash
    ./import.sh MyCompany prod -a --check
    ```

    Right after an export, a dry run should report few or no changes. Anything it does report is worth a look; usually it's a secret or default the export can't read back.

> [!TIP]
> You don't have to manage everything. Start with the object types that change most (for example job templates and projects), and copy only those folders into `imports/`.

## Put your configuration under Git

This repository's `.gitignore` excludes `orgs_vars/`, `vault.yml` and `ansible.cfg`, so your configuration and secrets are never committed to the tool's own repository by accident. Keep your configuration in **its own private repository** instead. The simplest way is to make `orgs_vars/` a Git repository:

```bash
cd orgs_vars
git init
git add .
git commit -m "Initial AAP configuration export"
git remote add origin git@github.com:my-org/aap-configuration.git   # a private repo
git push -u origin main
```

The tool repo ignores `orgs_vars/`, so the two repositories never interfere. You can update the tool with `git pull` in the repo root and manage your configuration in `orgs_vars/` independently.

What to commit in your configuration repo:

* ✅ `common/`, `<env>/imports/`, `<env>/vars.yml`, `<env>/vars.env`
* ✅ `vault.yml` files, **only while encrypted** (check that each starts with `$ANSIBLE_VAULT`)
* ❌ `<env>/exports/` (raw, regenerable output). Add `*/*/exports/` to that repo's `.gitignore`.
* ❌ Your vault password file

A typical change workflow: create a branch, edit files, run `./import.sh ... --check` against a test environment, open a pull request, merge, then import.

## Add another environment

```bash
./start_here.sh MyCompany test
```

The new environment shares `orgs_vars/MyCompany/common/` with the existing ones. When asked, use the **same vault password** as the workspace's existing common vault, so one password decrypts everything in that workspace.

The wizard suggests the AAP version, layout, certificate setting and username of the workspace's most recently set up environment, and checks that the vault password you enter opens the workspace's existing vaults.

To check an existing environment, run `./start_here.sh MyCompany test` again. It shows the AAP version, layout, export scope, vault status and last export, adds anything that's missing, and offers a menu to:

* **test the connection** with the saved details;
* **update the connection details** (URL, certificate check, login). Other secrets in the vault are kept;
* **save the vault password to a file**, if you're still typing it each time.

## Add a new object

1. Find the object type's folder and top-level key in the [Object Reference](FOLDER_LAYOUT.md#object-type-reference).
2. Create a file in `common/<type>.d/` (all environments) or `<env>/imports/<type>.d/` (one environment):

    ```yaml
    # orgs_vars/MyCompany/common/controller_projects.d/Linux Playbooks.yml
    ---
    controller_projects:
      - name: Linux Playbooks
        organization: Default
        scm_type: git
        scm_url: https://github.com/example/linux-playbooks.git
        scm_branch: main
        scm_update_on_launch: true
    ```

3. Dry run, then import just that type:

    ```bash
    ./import.sh MyCompany dev -t controller_projects --check
    ./import.sh MyCompany dev -t controller_projects
    ```

> [!TIP]
> Not sure which fields an object supports? Create one in the AAP UI, export it with `-t <tag>`, and copy the result.

## Change an existing object

Edit its file, then import (ideally with `--check` first). Only the fields you list are managed; fields you leave out keep whatever value AAP already has.

```bash
./import.sh MyCompany dev -t controller_job_templates --check
./import.sh MyCompany dev -t controller_job_templates
```

## Rename an object

Objects are matched by name, so changing `name:` would create a second object. Use `new_name:` instead:

```yaml
controller_projects:
  - name: Linux Playbooks          # current name in AAP
    new_name: Linux Automation     # name to change it to
    organization: Default
```

After the import, set `name:` to the new name and remove `new_name:`.

## Delete an object

Import never deletes objects just because they're missing from your files. Mark them for deletion explicitly:

```yaml
controller_projects:
  - name: Old Project
    organization: Default
    state: absent
```

Import, confirm the object is gone, then delete the entry (or the file) from your configuration.

> [!CAUTION]
> Deleting an object can fail or cascade if other objects depend on it. For example, a project still used by a job template can't be removed. Delete dependents first, and always use `--check` first in shared environments.

## Check for drift

"Drift" means someone changed AAP by hand and it no longer matches your files. To find it, run a dry-run import:

```bash
./import.sh MyCompany prod -a --check
```

Anything reported as `changed` differs from your files. Then either import to put AAP back in line, or export and update your files if the manual change should be kept.

## Import only some object types

Use `-t` with one or more tags:

```bash
./import.sh MyCompany dev -t "controller_credentials,controller_projects,controller_job_templates"
```

Run `./import.sh MyCompany dev` (no `-a` / `-t`) to list every valid tag for that environment's AAP version.

Import applies object types in dependency order (organizations, then credentials, projects, inventories, job templates, and so on), but only for the tags you ask for. If you import just `controller_job_templates`, its projects, inventories and credentials must already exist in AAP.

## Promote configuration from dev to prod

Put what should be identical everywhere in `common/` and only the differences in each environment's `imports/`:

```text
orgs_vars/MyCompany/
├── common/
│   ├── controller_projects.d/          # same projects everywhere
│   ├── controller_job_templates.d/     # same job templates everywhere
│   └── controller_credentials.d/       # same credentials, secrets as variables
├── dev/imports/
│   ├── controller_inventories.d/       # dev hosts
│   └── controller_settings.d/
└── prod/imports/
    ├── controller_inventories.d/       # prod hosts
    └── controller_settings.d/
```

For values that differ per environment, use a variable in `common/` and set it in each environment's vault (or in `vars.yml` for non-secrets):

```yaml
# common/controller_credentials.d/ServiceNow.yml
controller_credentials:
  - name: ServiceNow
    organization: Default
    credential_type: ServiceNow
    inputs:
      instance: "{{ vault_servicenow_instance }}"
      password: "{{ vault_servicenow_password }}"
```

The workflow is then: change `common/`, import into dev and test, then import the same commit into prod.

## Handle secrets

AAP never returns secrets through its API. With `secrets_as_variables: true` (the default in `vars.yml`), export writes a **placeholder variable** wherever a secret was:

```yaml
controller_credentials:
  - name: GitHub
    inputs:
      username: automation-bot
      password: '{{ vault_controller_credentials_github_password }}'
```

Before importing, define every placeholder in a vault:

1. List the placeholders. On AAP 2.5+, the export's `flat_version/env_variables.yml` already lists them. Otherwise, search the export:

    ```bash
    grep -rhoE '\{\{ *vault_[A-Za-z0-9_]+ *\}\}' orgs_vars/MyCompany/prod/imports | sort -u
    ```

2. Add them with their real values to the right vault:

    ```bash
    ./vault-edit.sh MyCompany prod       # environment-specific secrets
    ./vault-edit.sh MyCompany common     # secrets shared by every environment
    ```

    ```yaml
    vault_controller_credentials_github_password: "ghp_xxxxxxxxxxxx"
    ```

You can also rename placeholders to something friendlier (for example `{{ vault_github_token }}`), as long as the file and the vault agree.

**Users:** on AAP 2.5+, user passwords are exported as placeholders like any other secret. AAP 2.4 exports set every password to `INITIAL` with `update_secrets: false`, which means "set on create, never overwrite". Either way, give each user a real initial password, or rely on an external authenticator (LDAP, SAML) and leave passwords out.

**Never** commit a decrypted vault or put real secrets directly into files under `imports/` or `common/`.

## Export a single AAP organization

Set `organization_filter` in the environment's `vars.yml`:

```yaml
organization_filter: 'Network Team'
```

Then export as usual. Remove or empty the option to export everything again. (`start_here.sh` asks about this when you create an environment, listing the organizations it finds in AAP; unattended, use `--org-filter '<name>'`.)

If each AAP organization is managed separately (for example by a different team), a common pattern is one workspace per AAP organization, named after it, with `organization_filter` set in each of its environments:

```bash
./start_here.sh NetworkTeam prod     # then set organization_filter: 'Network Team' in its vars.yml
```

Workspaces and AAP organizations are otherwise unrelated. See [Workspace and environment](CONCEPTS.md#workspace-and-environment).

## Run without prompts (CI/CD)

The scripts can run unattended:

```bash
export CASC_VAULT_PASSWORD="$VAULT_PASSWORD_FROM_YOUR_CI_SECRET_STORE"
export CASC_USE_PLAYBOOK=true        # or false to use ansible-navigator
./import.sh MyCompany prod -a
```

Environments can be created unattended too (for example in a bootstrap pipeline):

```bash
export CASC_VAULT_PASSWORD=...          # encrypts the new vaults
export AAP_PASSWORD=...                 # or AAP_TOKEN=... instead of --username
./start_here.sh MyCompany prod --version 2.6 --filetree \
  --hostname https://aap.example.com --username admin --org-filter 'Network Team' --yes
```

`--yes` never asks questions and fails if something required is missing. When the workspace already has an environment, its AAP version, layout, certificate setting and username are used for anything you don't pass. The connection test still runs (add `--skip-test` to skip it), and a failed test stops the script without saving the vault. `./start_here.sh --help` lists every option.

* `CASC_VAULT_PASSWORD` supplies the vault password without a prompt. Alternatively, provide a password file through `ANSIBLE_VAULT_PASSWORD_FILE`.
* Without a terminal and without a password source, the scripts stop with an explanation instead of hanging on a prompt.
* A common pipeline: on pull request, run `--check` against a test environment; on merge, import into test, then (after approval) into prod.

You can also run the playbook directly, which is useful when your pipeline already runs inside an Execution Environment or as an AAP job template:

```bash
# Collections: collections/<version>/ (or already present in your EE)
ANSIBLE_COLLECTIONS_PATH=$PWD/collections/2.6 ansible-playbook import_export.yml \
  -e import_export_mode=import -e casc_aap_version=2.6 \
  -e "{orgs: MyCompany, dir_orgs_vars: orgs_vars, env: prod}" \
  -e "{env_dir: $PWD/orgs_vars/MyCompany/prod}" -e "{common_dir: $PWD/orgs_vars/MyCompany/common}" \
  -e @orgs_vars/MyCompany/prod/vault.yml -e @orgs_vars/MyCompany/prod/vars.yml
```

## Use an Execution Environment

1. Build or obtain an EE image that contains the collections for your AAP version (see [Versions and Collections](VERSIONS_AND_COLLECTIONS.md#collections-per-aap-version)), and make it available to Podman or Docker.
2. Set it in `script_vars/<version>/vars.env`:

    ```bash
    execution_environment="registry.example.com/ee-casc-aap26:latest"
    ```

3. Run any script with `--navigator` (or set `CASC_USE_PLAYBOOK=false`):

    ```bash
    ./export.sh MyCompany prod -a --navigator
    ```

The repository is mounted into the container, and a prompted vault password is passed in automatically. The image is pulled only if it's missing locally.

## Update or change collection versions

Each AAP version's collections are pinned in `collections/<version>/requirements.yml`. To update:

```bash
./install_collections.sh 2.6          # re-install (upgrades within the pinned ranges)
./list_collections.sh 2.6             # see what's installed
```

To try the latest upstream code, install from Git sources instead (`collections/<version>/requirements-git.yml`):

```bash
./install_collections.sh --git 2.6
```

Edit the requirements file to pin specific versions. Installs for one version never affect another.

## Convert between flat and filetree layouts

Export already writes both layouts. To convert files you've edited yourself:

```bash
# Flat files -> one file per object
ansible-playbook flat_to_filetree.yml \
  -e flat_to_filetree_source_path=orgs_vars/MyCompany/prod/my_flat_files \
  -e flat_to_filetree_output_path=orgs_vars/MyCompany/prod/imports_filetree

# Filetree -> one file per object type
ansible-playbook filetree_to_flat.yml \
  -e filetree_to_flat_base_path=orgs_vars/MyCompany/prod/imports \
  -e filetree_to_flat_output_path=orgs_vars/MyCompany/prod/imports_flat
```

Write to a new folder, review the result, then swap it in, and set `flatten_output` in `vars.yml` to match. Both converters keep `{{ variables }}` as they are. `flat_to_filetree` also writes organizations, teams, users and applications under the standard `aap_*` names, whatever version they came from.

## Convert controller roles to gateway role assignments

AAP 2.5+ adds platform-wide role-based access (`gateway_role_user_assignments`, `gateway_role_team_assignments`). Classic controller permissions (`controller_roles`) keep working, but if you want to move to the new model, `convert_roles.yml` translates a `controller_roles` file:

```bash
ansible-playbook convert_roles.yml \
  -e convert_roles_import_path=orgs_vars/MyCompany/common/controller_roles.d/team_roles.d/netops.yml \
  -e convert_roles_export_user_path=/tmp/user_assignments.yml \
  -e convert_roles_export_team_path=/tmp/team_assignments.yml
```

Review the output, then place it in `gateway_role_user_assignments.d/` / `gateway_role_team_assignments.d/`.

## Move to a different AAP version

See [Migrating Between AAP Versions](MIGRATING_BETWEEN_AAP_VERSIONS.md).
