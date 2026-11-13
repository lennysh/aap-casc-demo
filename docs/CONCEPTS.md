# Concepts and Glossary

This page explains the ideas behind configuration as code and defines every term this project uses. If you're new to managing AAP this way, read it once; the rest of the docs assume these terms.

* [Configuration as code in one minute](#configuration-as-code-in-one-minute)
* [The AAP components](#the-aap-components)
* [Workspace and environment](#workspace-and-environment)
* [Common vs. imports](#common-vs-imports)
* [Export and import](#export-and-import)
* [Filetree and flat layouts](#filetree-and-flat-layouts)
* [Glossary](#glossary)

---

## Configuration as code in one minute

Normally you configure AAP by clicking through the web UI. With **configuration as code (CaC, sometimes "CaSC")** you describe the configuration in text files instead, and a tool makes AAP match the files.

```yaml
# orgs_vars/MyCompany/common/controller_projects.d/network-playbooks.yml
---
controller_projects:
  - name: Network Playbooks
    organization: Network Team
    scm_type: git
    scm_url: https://github.com/example/network-playbooks.git
    scm_branch: main
```

Importing this file creates the project if it doesn't exist and updates it if it does. Importing it again changes nothing, because AAP already matches. This "run it as often as you like, it only changes what's different" behavior is called **idempotency**.

Because the files are plain text you can:

* keep them in **Git**, so every change has an author, a date and a reason;
* **review** changes in a pull request before they reach AAP;
* **apply the same files** to several AAP instances to keep them consistent;
* **rebuild** an instance from scratch by importing everything.

You rarely have to write these files from nothing. **Export** reads an existing AAP instance and writes the files for you, which is the usual starting point.

## The AAP components

AAP is made of several components. Each manages different object types, and the object-type names in this project start with the component they belong to.

| Component | Prefix | What it manages | AAP versions |
|---|---|---|---|
| **Automation Controller** | `controller_` | Projects, inventories, hosts, credentials, job templates, workflows, schedules, execution environments, instance groups, notifications, settings, roles. | 2.4+ |
| **Platform Gateway** | `gateway_` | The single entry point for 2.5+: authentication (LDAP, SAML, ...), users, teams, organizations, role-based access, gateway settings and service routing. | 2.5+ |
| **Event-Driven Ansible (EDA)** | `eda_` | Projects, decision environments, credentials, event streams, rulebook activations. | 2.5+ (in this project) |
| **Automation Hub** | `hub_` | Collection namespaces, collections, remotes and repositories, and execution environment registries, repositories and images. | 2.5+ (in this project) |

Some objects are shared across the whole platform, so they use the `aap_` prefix: **organizations, teams, users and OAuth applications** (`aap_organizations`, `aap_teams`, `aap_user_accounts`, `aap_applications`).

In **AAP 2.4** there's no gateway; each component is a separate server with its own login. This project manages the **Automation Controller** on 2.4.

## Workspace and environment

These two words are how this project groups your configuration on disk. **They're folder names you choose, not AAP objects.**

* An **environment** is **one AAP instance**, for example `dev`, `qa`, `prod` or `AAP26`. Each environment has its own AAP version, connection details (vault), options and configuration files.
* A **workspace** (`orgs_vars/<workspace>/`) is a **group of related environments** that can share configuration through the workspace's `common/` folder. Most people use a company, team or lab name, for example `MyCompany` with environments `dev`, `qa` and `prod`. A workspace with a single environment is fine too.

> [!NOTE]
> **A workspace isn't an AAP organization.** Name it whatever suits you. One workspace can manage any number of AAP organizations (`aap_organizations`, such as `Default`). If you want a workspace to cover just one AAP organization, give it that organization's name and set `organization_filter` in its environments' `vars.yml`. That's a convention, not a requirement.

```text
orgs_vars/
└── MyCompany/          <- workspace (a folder; any name)
    ├── common/         <- shared by dev, qa and prod
    ├── dev/            <- environment = one AAP instance
    ├── qa/
    └── prod/
```

(The top-level folder is still called `orgs_vars/` for compatibility with existing setups.)

## Common vs. imports

Import reads configuration from two folders and applies both:

| Folder | Use it for |
|---|---|
| `orgs_vars/<workspace>/common/` | Things that should be **identical in every environment**: credential types, projects, job templates, notification templates, and so on. |
| `orgs_vars/<workspace>/<env>/imports/` | Things that are **specific to one environment**: its hosts and inventories, instance groups, settings, environment-only credentials. |

Both are read together. If both define objects of the same type, all of them are imported. Values that differ between environments (URLs, hostnames, secrets) can stay in `common/` as variables, such as `{{ vault_smtp_host }}`, with the real value in each environment's vault. See [How-To: promote configuration from dev to prod](HOW_TO.md#promote-configuration-from-dev-to-prod).

Set `import_common: false` in an environment's `vars.yml` to ignore `common/` for that environment.

## Export and import

| | Export | Import |
|---|---|---|
| Direction | AAP → files | Files → AAP |
| Script | `./export.sh <workspace> <env> ...` | `./import.sh <workspace> <env> ...` |
| Writes to | `orgs_vars/<workspace>/<env>/exports/<timestamp>/` | your AAP instance |
| Reads from | your AAP instance | `common/` and `<env>/imports/` |

Export never touches your `imports/` or `common/` folders. You decide what to copy from an export into them and commit it. This keeps your curated configuration separate from raw exports.

Import **creates and updates**. It doesn't delete objects just because they're missing from your files. To delete something, mark it `state: absent` (see [How-To: delete an object](HOW_TO.md#delete-an-object)).

## Filetree and flat layouts

Your configuration files can be organized in one of two ways. Each environment uses one of them for **import**, set by `flatten_output` in its `vars.yml` (the setup wizard asks). **Export always writes both**, so you can switch at any time.

### Filetree (default, recommended)

One folder per object type, usually one file per object. The folder names and the key inside each file must match the [Object Reference](FOLDER_LAYOUT.md#object-type-reference).

```text
imports/
├── controller_projects.d/
│   ├── Network Playbooks.yml        # controller_projects: [ {name: Network Playbooks, ...} ]
│   └── Linux Playbooks.yml
├── controller_job_templates.d/
│   └── Patch Servers.yml            # controller_templates: [ ... ]
└── aap_teams.d/
    └── netops.yml                   # aap_teams: [ ... ]
```

* Copy from an export's **`filetree_version/`**.
* Files may sit in subfolders inside a `<type>.d/` folder (for example `controller_roles.d/team_roles.d/`), and a file may hold several objects of its type.
* A file outside the matching folder, or with the wrong top-level key, is ignored.

### Flat (`flatten_output: true`)

Folder and file names don't matter. Every `*.yml` / `*.yaml` file under `imports/` (and `common/`) is loaded, at any depth, and a single file can define several object types.

```text
imports/
├── projects.yml                     # controller_projects: [ ... ]
└── team-a/
    └── everything.yml               # controller_templates: [ ... ] and aap_teams: [ ... ]
```

* Copy from an export's **`flat_version/`** (one file per object type), or write your own files.
* If several files define the same variable, the lists are combined. `common/` is read first, then `imports/`.
* Files whose names start with `ignore_` are skipped.

### Which should I use?

| | Filetree | Flat |
|---|---|---|
| Best for | Most teams; anything kept in Git and reviewed | Small or hand-written configurations, quick experiments |
| Code review | One object per file, so diffs are small and clear | Many objects per file, so diffs are larger |
| Merge conflicts | Rare (people edit different files) | More likely (people edit the same file) |
| Rules to follow | Folder name and top-level key must match | Only the top-level key matters |
| Typos in folder names | The file is silently skipped | Not possible |
| Matches export | `filetree_version/` | `flat_version/` |

**If in doubt, choose filetree.** It scales better and is how exports are organized.

### Switching layouts later

1. Convert your files (or copy the other layout from a fresh export):

    ```bash
    # filetree -> flat
    ansible-playbook filetree_to_flat.yml -e filetree_to_flat_base_path=orgs_vars/MyCompany/prod/imports \
      -e filetree_to_flat_output_path=orgs_vars/MyCompany/prod/imports_flat
    # flat -> filetree
    ansible-playbook flat_to_filetree.yml -e flat_to_filetree_source_path=orgs_vars/MyCompany/prod/imports \
      -e flat_to_filetree_output_path=orgs_vars/MyCompany/prod/imports_filetree
    ```

2. Replace `imports/` (and `common/`, if you use it) with the converted files.
3. Change `flatten_output` in the environment's `vars.yml`.
4. Confirm that `./import.sh <workspace> <env> -a --check` reports no unexpected changes.

Environments in the same workspace share `common/`, so they should all use the same layout.

---

## Glossary

**AAP (Ansible Automation Platform):** Red Hat's enterprise automation platform, made up of the [components above](#the-aap-components).

**Ansible Vault:** Ansible's built-in encryption for files. This project keeps connection details and secrets in vault-encrypted `vault.yml` files. See the [README](../README.md#vault-files).

**ansible-navigator:** a command-line tool that runs playbooks inside an Execution Environment container. Use it with `--navigator`.

**ansible-playbook:** the standard Ansible command, and this project's default runner. It uses the collections installed under `collections/<version>/`.

**Category tag:** a tag that selects every object type of one component on export (`controller`, `gateway`, `eda`, `hub`; AAP 2.5+ only).

**Check mode (`--check`):** a dry run. Ansible reports what it would change without changing anything.

**Collection:** a packaged set of Ansible roles and modules. This project relies on `infra.aap_configuration`, `infra.aap_configuration_extended` (AAP 2.5+) and `infra.controller_configuration` (AAP 2.4), plus the `ansible.controller`, `ansible.platform`, `ansible.eda` and `ansible.hub` modules. See [Versions and Collections](VERSIONS_AND_COLLECTIONS.md).

**Common:** `orgs_vars/<workspace>/common/`, configuration shared by every environment in a workspace.

**Dispatch:** the collection role that applies every object type in the correct order (organizations before teams, projects before job templates, and so on). Import calls it for you.

**Environment:** one AAP instance, stored as `orgs_vars/<workspace>/<env>/`.

**Execution Environment (EE):** a container image with Ansible and the needed collections inside. It's used by `ansible-navigator` and by AAP itself.

**Export:** reading configuration from AAP into YAML files.

**Filetree layout:** one folder per object type (`<type>.d/`), with files inside it. See [Folder Layout](FOLDER_LAYOUT.md).

**Flat layout:** YAML files anywhere under `imports/` and `common/`, each holding one or more object-type lists.

**Idempotent:** safe to run repeatedly; only differences are changed.

**Import:** applying YAML files to AAP.

**Imports folder:** `orgs_vars/<workspace>/<env>/imports/`, configuration for one environment.

**Object type:** a kind of AAP resource, such as projects or teams. Each has its own folder and YAML key, for example `controller_projects.d/` and `controller_projects:`.

**Organization (AAP):** an AAP object that owns resources such as projects and credentials. It's defined in `aap_organizations`. Not the same as a workspace.

**Placeholder / secrets as variables:** exported secrets are written as Jinja variables (for example `{{ vault_controller_credentials_my_cred_password }}`) instead of real values. You supply the values in a vault. See [How-To: handle secrets](HOW_TO.md#handle-secrets).

**`state: absent`:** set on an object in your files to delete it from AAP on the next import.

**Tag:** a name that selects one object type (for example `controller_projects`) so you can export or import just that type with `-t`.

**Workspace:** `orgs_vars/<workspace>/`, a folder grouping related environments that share `common/` configuration (for example a company name). Not the same as an AAP organization.

**Vault password:** the password that decrypts your vault files. See [Vault password](../README.md#vault-password-prompt-or-password-file).
