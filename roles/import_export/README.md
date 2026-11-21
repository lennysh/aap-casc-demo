import_export
=============

The main role behind `export.sh` and `import.sh`. It exports an AAP instance's configuration to YAML, or imports YAML into an AAP instance, using the collections for that instance's AAP version.

Most users run it through the scripts (see the [README](../../README.md)). This page is for running the role directly, for example from CI or an AAP job template.

What it does
------------

1. **Authentication:** with `vault_aap_username` / `vault_aap_password`, creates a temporary token (controller API on 2.4, gateway API on 2.5+) and deletes it at the end of the run. With `vault_aap_token`, it uses that token.
2. **Export** (`import_export_mode: export`): runs `filetree_create` into `<export_path>/flat_version/`, then `flat_to_filetree` into `<export_path>/filetree_version/`, normalizing organizations, teams, users and applications to the standard `aap_*` names.
3. **Import** (`import_export_mode: import`), before authenticating:
   * finds every `*.yml` / `*.yaml` file (except `ignore_*` files and anything inside `ignore_*` folders) under `common_dir` (when `import_common` is true) and `env_dir/imports`, in any folder structure, including vault-encrypted files such as `common/vault.yml`;
   * when Ansible tags are given (`--tags`), keeps only the object variables whose dispatch role matches the selected tags (mapping read from the collection's `dispatch` role; legacy alias names included) and drops the rest before the duplicate check and merge. Helper variables (keys that aren't object types) are always kept. An unparseable file is skipped with a warning only when tags are given and all its top-level keys are unselected object types. Loaded and skipped object variables are printed;
   * when `import_export_only_files` is set (`import.sh -f`), keeps object variables only from those files (folders expanded to the files import reads; helper variables and vault files still load from every file), and fails if a path isn't one import reads (missing, outside `common_dir` / `env_dir/imports`, `ignore_*`, not YAML, `common_dir` with `import_common` false, or a folder with no such files). Combines with tags. An unparseable file that isn't selected is skipped with a warning when all its top-level keys are object variables. The selected files are printed. The duplicate check and preflight then cover only the loaded objects, and dispatch skips types with nothing defined;
   * fails if the same loaded object is defined more than once with different values (`import_export_identity_keys`, `import_export_allow_duplicates`);
   * merges variables defined in several files without templating them (lists appended, `common_dir` first; dicts combined, later files win per key; others last-wins), translates organizations, teams, users and applications written with the other AAP version's variable names, and merges entries that share identity fields (`import_export_var_aliases`, `import_export_merge_keys`). All of this happens in `action_plugins/casc_import_prepare.py`, which writes the result (keeping `!unsafe` and `!vault` values) to a temporary folder that a single `include_vars` loads. Values stay lazily templated, so an undefined variable only affects the object that uses it;
   * preflight (`action_plugins/casc_import_preflight.py`, when `import_export_preflight` is true): templates every loaded object and fails with the list of objects that can't be resolved (undefined variables, unknown filters), so nothing is sent to AAP. Only the variable, object identity and error are reported, never values;
   * applies everything with the collection's `dispatch` role.

| AAP version | Collections used |
|---|---|
| 2.4 (`casc_aap_version <= 2.4`) | `infra.controller_configuration`, `ansible.controller` |
| 2.5+ | `infra.aap_configuration`, `infra.aap_configuration_extended`, `ansible.platform`, `ansible.controller`, `ansible.eda`, `ansible.hub` |

Requirements
------------

* ansible-core 2.16 or newer (2.16–2.18 for imports into AAP 2.4).
* The collections for the target AAP version (see `collections/<version>/requirements.yml`).
* Run from a playbook in the repository root (such as `import_export.yml`), so the repo's `library/` and `filter_plugins/` are found.

Variables
---------

**Required**

| Variable | Description |
|---|---|
| `import_export_mode` | `export` or `import`. |
| `casc_aap_version` | AAP version, for example `"2.6"`. |
| `vault_aap_hostname` | AAP URL (gateway URL on 2.5+). Falls back to the `AAP_HOST` environment variable. |
| `vault_aap_username` + `vault_aap_password`, or `vault_aap_token` | Credentials (fallback: `AAP_USERNAME` / `AAP_PASSWORD`). |
| `export_path` | Export only: output directory. |
| `orgs`, `env`, `dir_orgs_vars`, `env_dir`, `common_dir` | Import only: workspace and environment names (`orgs` holds the workspace name), the `orgs_vars` path, the environment folder, and the workspace's `common` folder. |

**Optional**

| Variable | Default | Description |
|---|---|---|
| `vault_aap_validate_certs` | `AAP_VERIFY_SSL` env | Validate TLS certificates. |
| `import_common` | `true` | Also import `common_dir`. |
| `organization_filter` | unset | Export a single AAP organization. |
| `secrets_as_variables` / `secrets_as_variables_prefix` | `true` / `"vault"` | Export secrets as placeholder variables. |
| `input_tag` | all | Export only these object types (list of tags). |
| `aap_configuration_async_retries` / `aap_configuration_async_delay` | `60` / `5` | Polling for asynchronous object updates. |
| `aap_configuration_secure_logging` | `false` | Hide object data in Ansible output (`no_log`). |
| `import_export_var_aliases` | see `defaults/main.yml` | Cross-version variable translations applied on import. |
| `import_export_merge_keys` | see `defaults/main.yml` | Identity fields used to merge duplicate objects on import. |
| `import_export_allow_unsupported_core` | `false` | Skip the ansible-core < 2.19 check for AAP 2.4 imports. |
| `import_export_allow_duplicates` | `false` | Import even if an object is defined more than once with different values. |
| `import_export_preflight` | `true` | Before authenticating, fail if any loaded object can't be resolved (`import.sh --skip-preflight` sets it to false). |
| `import_export_identity_keys` | see `defaults/main.yml` | Fields that identify an object for the duplicate check, per variable (`__default__`: name + organization). |
| `import_export_skip_duplicate_check` | role assignments, settings | Variables never duplicate-checked. |
| `import_export_only_files` | `[]` | Import only: absolute paths of files or folders whose object variables are loaded (`import.sh -f` sets it). Empty loads all files. |

On import, limit object types with Ansible tags (`--tags controller_projects`). Only the matching object variables are loaded; helper variables are always loaded.

Example
-------

```bash
ANSIBLE_COLLECTIONS_PATH=$PWD/collections/2.6 ansible-playbook import_export.yml \
  -e import_export_mode=import -e casc_aap_version=2.6 \
  -e "{orgs: MyCompany, dir_orgs_vars: orgs_vars, env: prod}" \
  -e "{env_dir: $PWD/orgs_vars/MyCompany/prod}" \
  -e "{common_dir: $PWD/orgs_vars/MyCompany/common}" \
  -e @orgs_vars/MyCompany/prod/vault.yml \
  -e @orgs_vars/MyCompany/prod/vars.yml \
  --ask-vault-pass --tags controller_projects
```

License
-------

MIT

Author Information
------------------

Lenny Shirley II
