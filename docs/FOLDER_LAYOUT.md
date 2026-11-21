# Folder Layout and Object Reference

This page is the reference for where configuration lives and what goes in each file.

* [Repository layout](#repository-layout)
* [Workspace and environment folders](#workspace-and-environment-folders)
* [How import finds your files](#how-import-finds-your-files)
* [File format rules](#file-format-rules)
* [Object type reference](#object-type-reference)
* [Examples](#examples)

---

## Repository layout

| Path | What it is |
|---|---|
| `start_here.sh`, `export.sh`, `import.sh`, `vault-*.sh`, `*_collections.sh`, `autocomplete.sh` | The scripts you run. |
| `orgs_vars/` | **Your configuration**: workspaces, environments, vaults, imports and exports. Not committed to this repo (see [Put your configuration under Git](HOW_TO.md#put-your-configuration-under-git)). |
| `templates/` | Templates `start_here.sh` copies into new environments (`vars.yml`, `vault.yml`, `vault_common.yml`). |
| `script_vars/<version>/vars.env` | Per-AAP-version settings: valid tags, folders to create, Execution Environment image. |
| `collections/<version>/` | Per-AAP-version collection requirements (`requirements.yml`, `requirements-git.yml`) and the installed collections. |
| `import_export.yml` | The playbook behind `export.sh` and `import.sh`. |
| `roles/` | `import_export` (the main role), `flat_to_filetree` and `filetree_to_flat` (converters between the flat and filetree file styles). |
| `flat_to_filetree.yml`, `filetree_to_flat.yml`, `convert_roles.yml` | Utility playbooks (see the [How-To guide](HOW_TO.md)). |
| `library/`, `filter_plugins/`, `roles/*/action_plugins/` | Helper module, filters and plugins used by the roles. |
| `scripts/` | Internal helpers used by the scripts. Not run directly. |
| `tests/` | Automated tests for import (`python3 -m pytest tests -q`); no AAP needed. See `tests/README.md`. |
| `docs/` | This documentation. |

## Workspace and environment folders

```text
orgs_vars/<workspace>/
├── common/
│   ├── vault.yml                       # shared secrets (encrypted)
│   └── <type>.d/ ...                   # shared configuration
└── <env>/
    ├── vars.env                        # CASC_AAP_VERSION (written by start_here.sh)
    ├── vars.yml                        # import/export options
    ├── vault.yml                       # connection details + secrets (encrypted)
    ├── imports/
    │   └── <type>.d/ ...               # environment-specific configuration
    └── exports/
        └── <workspace>_<env>_export_<timestamp>/
            ├── filetree_version/       # one file per object (recommended to copy from)
            └── flat_version/           # one file per object type
```

`start_here.sh` creates every `<type>.d/` folder the environment's AAP version can import, in both `common/` and `<env>/imports/`, as a guide. They're optional: import reads any folder structure. Empty folders are fine. Delete the ones you'll never use if you prefer. Running `start_here.sh` again on an existing environment only adds what's missing.

## How import finds your files

* Every `*.yml` / `*.yaml` file under `common/` (unless `import_common: false`) and `<env>/imports/` is loaded, at any depth, whatever the folder or file name: filetree folders, flat files, or a mix. Files whose names start with `ignore_` are skipped, and so are folders whose names start with `ignore_`, with everything in them (handy for parking old or unfinished configuration, for example `ignore_controller_job_templates.d/`).
* **Tags filter what's loaded.** With `-t`, only the object variables whose type matches a selected tag are kept (for example `-t controller_job_templates` keeps `controller_templates`; `-t gateway_organizations` keeps `aap_organizations` and its older names `controller_organizations` / `gateway_organizations`). The mapping comes from the collection's dispatch role, so it matches exactly what runs. Other object variables are dropped before the duplicate check and merge, so broken or unfinished definitions of other types (undefined variables, duplicates) don't stop the import. **Helper variables** (top-level keys that aren't object types, such as `authentik:` or `email_template_01:` used through Jinja) are always loaded. A file that can't be parsed is skipped with a warning only when tags are used and all its top-level keys are unselected object types; otherwise it's an error. With `-a`, everything is loaded and checked. The run prints which object variables were loaded and which were skipped.
* **`-f` limits import to files.** With `-f <path>` (repeatable; a file or a folder), object variables are loaded only from the named files; helper variables and vault files still load from every file. Only the roles for the loaded object types run, and `-t` can narrow further. A path import wouldn't read (outside `common/` and `<env>/imports/`, `ignore_`, not `.yml` / `.yaml`, under `common/` with `import_common: false`) is an error. A file that wasn't named and can't be parsed is skipped with a warning when all its top-level keys are object variables. See [Import a single file (or folder)](HOW_TO.md#import-a-single-file-or-folder).
* The **top-level key** decides what a file contains (see the [reference table](#object-type-reference)), so a file in the "wrong" folder still imports correctly.
* `common/` is read first, then `<env>/imports/`. If the same variable appears in several files, lists are combined, dictionaries (such as `gateway_settings` or `controller_settings`) are merged with later files winning per key, and for other values the last file wins. So a setting in `<env>/imports/` overrides the same setting in `common/`.
* **Duplicate check:** before connecting to AAP, import checks that no loaded object (all of them with `-a`; with `-t` or `-f`, only what's loaded) is defined twice with different values (same type and identity, such as name + organization for projects, `username` for users, name + inventory for hosts). If one is, it stops and lists every location. Fix it, or use `./import.sh ... --allow-duplicates` to import anyway (each copy is sent to AAP in order, so the last one wins; for organizations, teams, users and applications the first one wins). Copies with no conflicting values are imported with a warning. The identity fields are set by `import_export_identity_keys` in `roles/import_export/defaults/main.yml`.
* **Preflight check:** next, import resolves every loaded object (with `-t` or `-f`, only what's loaded) (Jinja variables and filters). If any can't be resolved, it stops before connecting to AAP and lists each one (`<variable> [<object>]: <error>`), so a missing vault secret can't stop an import halfway through. `--skip-preflight` turns it off.
* Organizations, teams, users and applications may also be written with the AAP 2.4 variable names (`controller_organizations`, `controller_teams`, `controller_user_accounts`, `controller_applications`) and still import into AAP 2.5+, and vice versa. Duplicates are merged. See [Migrating Between AAP Versions](MIGRATING_BETWEEN_AAP_VERSIONS.md).

## File format rules

* Files are YAML. Start with `---` (recommended).
* The **top-level key** decides the object type, not the file name. Name files however you like; export names them after the object (`My Project.yml`).
* A file can hold **one or many** objects (it's a list), and an object type can be spread over **many files**. They're all combined, but each object should be defined only once (see the duplicate check above).
* Values can use **Jinja variables**, such as `"{{ vault_github_token }}"` or `"demolab-{{ env }}"`. Variables are resolved from your vaults, from `vars.yml`, or from any other file being imported. `env` and `orgs` hold the current environment and organization names.
* Objects are matched by **name** (plus organization where names are only unique per organization). Renaming an object in a file creates a new object. Use `new_name:` to rename an existing one.
* `state: absent` on an object deletes it on import.
* The available fields for each object type are the fields of the matching role in the collection. See the role docs in [infra.aap_configuration](https://github.com/redhat-cop/infra.aap_configuration/tree/devel/roles) (AAP 2.5+) or [infra.controller_configuration](https://github.com/redhat-cop/infra.controller_configuration/tree/devel/roles) (AAP 2.4). The easiest way to learn the fields is to export an existing object.

## Object type reference

Folder and key names are the same for every AAP version. [Object Examples](OBJECT_EXAMPLES.md) has a sample file for each type. The folder is where export puts each type (a good place to keep it); the top-level key is what import goes by. The *Versions* column shows where each type can be imported.

### Shared platform objects

| Object | Folder | Top-level key | Files named after | Versions |
|---|---|---|---|---|
| Organizations | `aap_organizations.d` | `aap_organizations` | `name` | 2.4+ |
| Teams | `aap_teams.d` | `aap_teams` | `name` | 2.4+ |
| Users | `aap_user_accounts.d` | `aap_user_accounts` | `username` | 2.4+ |
| OAuth applications | `aap_applications.d` | `aap_applications` | `name` | 2.4+ |

### Automation Controller

| Object | Folder | Top-level key | Files named after | Versions |
|---|---|---|---|---|
| Settings | `controller_settings.d` | `controller_settings` | single file | 2.4+ |
| Credential types | `controller_credential_types.d` | `controller_credential_types` | `name` | 2.4+ |
| Credentials | `controller_credentials.d` | `controller_credentials` | `name` | 2.4+ |
| Credential input sources | `controller_credential_input_sources.d` | `controller_credential_input_sources` | `target_credential` | 2.4+ |
| Execution environments | `controller_execution_environments.d` | `controller_execution_environments` | `name` | 2.4+ |
| Instance groups | `controller_instance_groups.d` | `controller_instance_groups` | `name` | 2.4+ |
| Instances | `controller_instances.d` | `controller_instances` | `hostname` | 2.5+ |
| Labels | `controller_labels.d` | `controller_labels` | `name` | 2.4+ |
| Notification templates | `controller_notification_templates.d` | `controller_notifications` | `name` | 2.4+ |
| Projects | `controller_projects.d` | `controller_projects` | `name` | 2.4+ |
| Inventories | `controller_inventories.d` | `controller_inventories` | `name` | 2.4+ |
| Inventory sources | `controller_inventory_sources.d` | `controller_inventory_sources` | `name` | 2.4+ |
| Hosts | `controller_hosts.d` | `controller_hosts` | `name` | 2.4+ |
| Groups (inventory) | `controller_groups.d` | `controller_groups` | `name` | 2.4+ |
| Job templates | `controller_job_templates.d` | `controller_templates` | `name` | 2.4+ |
| Workflow job templates | `controller_workflow_job_templates.d` | `controller_workflows` | `name` | 2.4+ |
| Schedules | `controller_schedules.d` | `controller_schedules` | `name` | 2.4+ |
| Roles (permissions) | `controller_roles.d` (export uses `team_roles.d/` and `user_roles.d/` subfolders) | `controller_roles` | `team` / `user` | 2.4+ |

> [!IMPORTANT]
> Watch the four controller types whose key **differs from the folder name**: notification templates (`controller_notifications`), job templates (`controller_templates`), workflow job templates (`controller_workflows`) and groups (`controller_groups`). A file with the wrong key is silently ignored.

### Platform Gateway (AAP 2.5+)

| Object | Folder | Top-level key |
|---|---|---|
| Settings | `gateway_settings.d` | `gateway_settings` (a dictionary, not a list) |
| Authenticators (LDAP, SAML, OIDC, ...) | `gateway_authenticators.d` | `gateway_authenticators` |
| Authenticator maps | `gateway_authenticator_maps.d` | `gateway_authenticator_maps` |
| Role definitions | `gateway_role_definitions.d` | `gateway_role_definitions` |
| Team role assignments | `gateway_role_team_assignments.d` | `gateway_role_team_assignments` |
| User role assignments | `gateway_role_user_assignments.d` | `gateway_role_user_assignments` |
| HTTP ports | `gateway_http_ports.d` | `gateway_http_ports` |
| Routes | `gateway_routes.d` | `gateway_routes` |
| Services | `gateway_services.d` | `gateway_services` |
| Service clusters | `gateway_service_clusters.d` | `gateway_service_clusters` |
| Service keys | `gateway_service_keys.d` | `gateway_service_keys` |
| Service nodes | `gateway_service_nodes.d` | `gateway_service_nodes` |

### Event-Driven Ansible (AAP 2.5+)

| Object | Folder | Top-level key |
|---|---|---|
| Credential types | `eda_credential_types.d` | `eda_credential_types` |
| Credentials | `eda_credentials.d` | `eda_credentials` |
| Decision environments | `eda_decision_environments.d` | `eda_decision_environments` |
| Event streams | `eda_event_streams.d` | `eda_event_streams` |
| Projects | `eda_projects.d` | `eda_projects` |
| Rulebook activations | `eda_rulebook_activations.d` | `eda_rulebook_activations` |

### Automation Hub (AAP 2.5+)

| Object | Folder | Top-level key |
|---|---|---|
| Namespaces | `hub_namespaces.d` | `hub_namespaces` |
| Collections | `hub_collections.d` | `hub_collections` |
| Collection remotes | `hub_collection_remotes.d` | `hub_collection_remotes` |
| Collection repositories | `hub_collection_repositories.d` | `hub_collection_repositories` |
| EE registries | `hub_ee_registries.d` | `hub_ee_registries` |
| EE repositories | `hub_ee_repositories.d` | `hub_ee_repositories` |
| EE images | `hub_ee_images.d` | `hub_ee_images` |

## Examples

A few common examples follow. For an example of **every** object type, see [Object Examples](OBJECT_EXAMPLES.md).

**Organization and team** (`common/aap_organizations.d/Network Team.yml`, `common/aap_teams.d/netops.yml`)

```yaml
---
aap_organizations:
  - name: Network Team
    description: Network automation
    galaxy_credentials:
      - Automation Hub
```

```yaml
---
aap_teams:
  - name: netops
    organization: Network Team
    description: Network operations engineers
```

**User** (`<env>/imports/aap_user_accounts.d/jdoe.yml`)

```yaml
---
aap_user_accounts:
  - username: jdoe
    email: jdoe@example.com
    first_name: Jane
    last_name: Doe
    password: "{{ vault_user_jdoe_password }}"
    update_secrets: false        # set the password on create only
    is_superuser: false
```

**Credential using a vault variable** (`<env>/imports/controller_credentials.d/GitHub.yml`)

```yaml
---
controller_credentials:
  - name: GitHub
    organization: Network Team
    credential_type: Source Control
    inputs:
      username: automation-bot
      password: "{{ vault_github_token }}"
```

**Job template** (`common/controller_job_templates.d/Backup Configs.yml`). Note the `controller_templates` key:

```yaml
---
controller_templates:
  - name: Backup Configs
    organization: Network Team
    project: Network Playbooks
    playbook: backup.yml
    inventory: Network Devices
    credentials:
      - Network SSH
    execution_environment: Default execution environment
```

**Permissions** (`common/controller_roles.d/team_roles.d/netops.yml`)

```yaml
---
controller_roles:
  - team: netops
    job_templates:
      - Backup Configs
    role: execute
```

**Controller settings** (`<env>/imports/controller_settings.d/controller_settings.yml`)

```yaml
---
controller_settings:
  TOWER_URL_BASE: https://aap-prod.example.com
  AWX_TASK_ENV:
    HTTPS_PROXY: http://proxy.example.com:3128
```

**Removing an object:**

```yaml
---
controller_projects:
  - name: Old Project
    organization: Network Team
    state: absent
```
