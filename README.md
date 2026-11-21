# AAP Configuration as Code Demo

[![GitHub last commit](https://img.shields.io/github/last-commit/lennysh/aap-casc-demo.svg)](https://github.com/lennysh/aap-casc-demo/commits/main) [![GitHub license](https://img.shields.io/github/license/lennysh/aap-casc-demo.svg)](https://github.com/lennysh/aap-casc-demo/blob/main/LICENSE) [![Contributions welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](https://github.com/lennysh/aap-casc-demo/pulls) ![GitHub contributors](https://img.shields.io/github/contributors/lennysh/aap-casc-demo) ![GitHub Issues or Pull Requests](https://img.shields.io/github/issues/lennysh/aap-casc-demo)

> [!WARNING]
> **🚧 Work in Progress 🚧**
>
> This repository is under active development. Features may be incomplete, subject to breaking changes, or not fully tested. Please use with caution.

---


## 📖 Table of Contents

* 🧐 [What Is This?](#-what-is-this)
* ✨ [Why Configuration as Code?](#-why-configuration-as-code)
* 🛠 [Prerequisites](#-prerequisites)
* 🚀 [Quick Start](#-quick-start)
* 👟 [Everyday Usage](#-everyday-usage)
    * [Exporting](#exporting)
    * [Importing](#importing)
    * [Choosing what to export or import (tags)](#choosing-what-to-export-or-import-tags)
    * [Dry runs](#dry-runs)
* 🗂 [How Your Configuration Is Organized](#-how-your-configuration-is-organized)
* ⚙ [Configuration Reference](#-configuration-reference)
    * [Environment `vars.yml`](#environment-varsyml)
    * [Vault files](#vault-files)
    * [Vault password: prompt or password file](#vault-password-prompt-or-password-file)
    * [Environment variables](#environment-variables)
* 🏃 [Running with ansible-playbook or ansible-navigator](#-running-with-ansible-playbook-or-ansible-navigator)
* 🧰 [Other Scripts and Tab Completion](#-other-scripts-and-tab-completion)
* 📚 [Documentation](#-documentation)
* 📦 [Supported AAP Versions](#-supported-aap-versions)
* 🔗 [Useful Links](#-useful-links)
* 🤝 [Contributing](#-contributing)
* 🙏 [Thank You](#-thank-you)
* 📜 [License](#-license)

---

## 🧐 What Is This?

A set of Ansible playbooks and helper scripts for managing your **Ansible Automation Platform (AAP)** configuration as code. It does two things:

1. **Export:** reads the current configuration from an AAP instance (organizations, teams, users, credentials, projects, inventories, job templates, workflows, schedules, EDA, Automation Hub, gateway settings, and more) and saves it as human-readable YAML files.
2. **Import:** applies YAML files to an AAP instance, creating or updating everything so it matches the files.

It works with **AAP 2.4 through 2.7**, and every version exports the same folder layout. You can export from one AAP version and import into another, for example when moving from 2.4 to 2.6.

New to the terminology? See [Concepts and Glossary](docs/CONCEPTS.md).

## ✨ Why Configuration as Code?

* **Version control:** keep your entire AAP configuration in Git, with a full history of who changed what and when.
* **Review before apply:** use pull requests to review and approve changes before they reach AAP.
* **Consistency:** keep dev, test, and prod configured the same way, sharing what should be shared.
* **Migration:** move a configuration between instances or AAP versions.
* **Disaster recovery:** rebuild an instance and re-apply its configuration in minutes.

## 🛠 Prerequisites

* **Bash 4.3 or newer** (the scripts use associative arrays and namerefs).
* **Git**, to clone this repository and to version your configuration.
* **Ansible** (`ansible-core`) for the default `ansible-playbook` mode. The collections each AAP version needs are installed into this repo by `./install_collections.sh` (see [Versions and Collections](docs/VERSIONS_AND_COLLECTIONS.md)).
    * Importing into **AAP 2.4** needs **ansible-core 2.18 or older** (or the AAP 2.4 Execution Environment). See [Versions and Collections](docs/VERSIONS_AND_COLLECTIONS.md#ansible-core-requirements).
* An **AAP user** that can read (export) or change (import) the objects you manage. An administrator account is the simplest option.

**Optional:** `ansible-navigator` plus **Podman** or **Docker**, to run inside an Execution Environment instead of using local collections. See [Running with ansible-playbook or ansible-navigator](#-running-with-ansible-playbook-or-ansible-navigator).

## 🚀 Quick Start

This walk-through exports an existing AAP instance and imports it again. It's the quickest way to see how everything fits together.

1. **Clone the repository**

    ```bash
    git clone https://github.com/lennysh/aap-casc-demo.git
    cd aap-casc-demo
    ```

2. **Install the collections** for the AAP version(s) you use. Some of them (`ansible.controller`, `ansible.platform`) come from Red Hat Automation Hub, so first copy `ansible.cfg.example` to `ansible.cfg` and paste your [Automation Hub token](https://console.redhat.com/ansible/automation-hub/token) into the two `token=` lines:

    ```bash
    cp ansible.cfg.example ansible.cfg     # then add your Automation Hub token
    ./install_collections.sh 2.6           # or: ./install_collections.sh   (all versions)
    ```

    Skip this step if you'll use `--navigator` with an Execution Environment.

3. **Create a workspace and environment.** A *workspace* is just a folder name that groups environments sharing configuration, typically a company, team or lab (for example `MyCompany` with environments `dev`, `qa` and `prod`). It doesn't have to match an AAP organization. An *environment* is one AAP instance (for example `prod`). See [Concepts](docs/CONCEPTS.md#workspace-and-environment).

    ```bash
    ./start_here.sh MyCompany prod      # or just ./start_here.sh to pick or create them from a menu
    ```

    The setup wizard asks:
    * **the AAP version** of that instance;
    * **a vault password**, which encrypts the connection details and other secrets. All environments in a workspace share one password (the wizard checks it against the workspace's existing vaults); different workspaces can use different passwords. It can save the password to `.vault_pass/<workspace>.txt` so you aren't asked every time;
    * **how to reach AAP:** URL, certificate validation, and a username and password (or an existing token). It then **tests the connection** and warns you if the server's version doesn't match what you chose;
    * **which AAP organizations to export:** all of them, or one picked from a list fetched from AAP.

    It also checks your tools and offers to install missing collections (asking for your Automation Hub token if needed). When you add another environment to a workspace, it suggests the settings of an existing one. It finishes with the exact commands to run next.

    Run it again on an existing environment to see its status, test the saved connection, update the connection details, or store the vault password in a file.

4. **Export everything:**

    ```bash
    ./export.sh MyCompany prod -a
    ```

    The export lands in `orgs_vars/MyCompany/prod/exports/mycompany_prod_export_<timestamp>/`.

5. **Copy the export into your imports folder** and review it:

    ```bash
    cp -r orgs_vars/MyCompany/prod/exports/mycompany_prod_export_*/filetree_version/* orgs_vars/MyCompany/prod/imports/
    ```

    (If you've exported more than once, replace the `*` with the timestamp of the export you want.)

    Exported secrets (passwords, tokens, keys) come out as placeholders like `{{ vault_controller_credentials_my_cred_password }}`. Add the real values to your vault before importing. See [Handling secrets](docs/HOW_TO.md#handle-secrets).

6. **Do a dry run, then import:**

    ```bash
    ./import.sh MyCompany prod -a --check     # shows what would change
    ./import.sh MyCompany prod -a
    ```

7. **Commit `orgs_vars/` to your own Git repository.** This repo's `.gitignore` excludes `orgs_vars/` and vault files by default, so keep your configuration in a private repo (or adjust `.gitignore` deliberately). See [How-To: put your configuration under Git](docs/HOW_TO.md#put-your-configuration-under-git).

## 👟 Everyday Usage

### Exporting

```bash
./export.sh <workspace> <env> (-a | -t <tags>) [--playbook | --navigator] [--check] [-o <dir>]
```

| Option | Meaning |
|---|---|
| `-a`, `--all` | Export everything supported for the environment's AAP version. |
| `-t`, `--tags "<t1>,<t2>"` | Export only these object types (see [tags](#choosing-what-to-export-or-import-tags)). |
| `-o`, `--export-path <dir>` | Write the export here instead of `orgs_vars/<workspace>/<env>/exports/<workspace>_<env>_export_<timestamp>/`. |
| `--playbook` / `--navigator` | Run with `ansible-playbook` (default) or `ansible-navigator`. |
| `-C`, `--check` | Ansible check mode. |

Every export contains two copies of the same data:

* **`filetree_version/`**: one file per object, grouped into one folder per object type (for example `controller_projects.d/My Project.yml`). Best for Git and code review. **Use this by default.**
* **`flat_version/`**: one file per object type, with all objects of that type in it. On AAP 2.5+ it also includes `env_variables.yml`, which lists every secret placeholder found in the export.

To export only one AAP organization, set `organization_filter` in the environment's [`vars.yml`](#environment-varsyml).

### Importing

```bash
./import.sh <workspace> <env> (-a | -t <tags> | -f <path>...) [--playbook | --navigator] [--check] [--allow-duplicates] [--skip-preflight]
```

Import reads the YAML files, in any folder structure, from two places and applies them to the environment's AAP instance:

* `orgs_vars/<workspace>/common/`: configuration shared by every environment in the workspace (skip it with `import_common: false`).
* `orgs_vars/<workspace>/<env>/imports/`: configuration for this environment only.

With `-a`, every object type in those files is loaded. With `-t`, only the object types for the selected tags are loaded; other object types are skipped, so unfinished files for them don't get in the way. Helper variables (top-level keys that aren't object types, used through Jinja) are always loaded. The run lists which object variables were loaded and which were skipped.

With `-f <path>` (repeatable), only the objects defined in the named files are loaded, for example `./import.sh MyCompany dev -f dev/imports/controller_job_templates.d/deploy_web.yml`:

* A path can be a file or a folder (every YAML file import would read inside it), relative to `orgs_vars/<workspace>/`, to the current directory, or absolute. Tab completion completes paths inside the workspace.
* `-f` replaces `-a` / `-t`; add `-t` to narrow it further. Helper variables and vault files are still loaded from every file, so Jinja references and secrets resolve.
* The duplicate and preflight checks cover only what's loaded. See [Import a single file (or folder)](docs/HOW_TO.md#import-a-single-file-or-folder).

Before connecting to AAP, import checks that no loaded object is defined more than once with different values (for example the same project in both `common/` and `imports/`) and stops with a list of the locations if one is. `--allow-duplicates` imports anyway; the last copy wins. See [How files are combined](docs/CONCEPTS.md#how-files-are-combined).

It then runs a **preflight** check: every loaded object is resolved (Jinja variables, filters) and, if any can't be, import stops with the full list (for example every vault secret you haven't defined yet) before anything is sent to AAP, so an import never fails halfway through over a missing variable. `--skip-preflight` turns the check off.

Objects are matched by name (and organization, where relevant). Existing objects are updated and missing ones are created. Objects that exist in AAP but not in your files are left alone. To remove an object, set `state: absent` on it (see [How-To](docs/HOW_TO.md#delete-an-object)).

### Choosing what to export or import (tags)

Each object type has a tag (for example `controller_projects`, `gateway_teams`, `eda_projects`). Run a script with just the workspace and env to see every valid tag for that environment's AAP version:

```bash
./export.sh MyCompany prod
./import.sh MyCompany prod
```

Combine tags with commas: `-t "controller_projects,controller_job_templates"`. On AAP 2.5+, export also accepts the category tags `controller`, `gateway`, `eda` and `hub`. AAP 2.4 uses shorter tag names (for example `projects`). The full lists are in [Versions and Collections](docs/VERSIONS_AND_COLLECTIONS.md#tags).

> [!TIP]
> When importing with tags, remember dependencies. A job template needs its project, inventory and credentials to exist already, so import those first (or include their tags too).

With `-t`, import loads only the object types for those tags (for example `-t controller_job_templates` loads `controller_templates`), so work-in-progress files for other types don't break the run. See [Import only some object types](docs/HOW_TO.md#import-only-some-object-types).

### Dry runs

`--check` runs Ansible in check mode: the import reports what it *would* create or change without changing anything. It's a good habit before every import into a shared environment.

## 🗂 How Your Configuration Is Organized

```text
orgs_vars/
└── MyCompany/                         # workspace: a group of related environments (any name)
    ├── common/                        # shared by every environment below
    │   ├── vault.yml                  # encrypted secrets shared by all environments
    │   ├── controller_credential_types.d/
    │   └── controller_projects.d/
    ├── dev/                           # one environment = one AAP instance
    │   ├── vars.env                   # AAP version for this environment
    │   ├── vars.yml                   # import/export options
    │   ├── vault.yml                  # encrypted connection details and secrets
    │   ├── imports/                   # environment-specific configuration
    │   │   ├── controller_job_templates.d/
    │   │   └── aap_teams.d/
    │   └── exports/                   # export output (timestamped folders)
    └── prod/
        └── ...
```

Each `<type>.d/` folder holds YAML files for one object type. A file can contain one object or many, and file and folder names are up to you (import reads every YAML file it finds, so a few larger "flat" files work too). What matters is the top-level key inside the file (for example `controller_projects:`). The [Folder Layout and Object Reference](docs/FOLDER_LAYOUT.md) lists every folder, its key, and examples, and [Object Examples](docs/OBJECT_EXAMPLES.md) has an example of every object type.

## ⚙ Configuration Reference

### Environment `vars.yml`

Each environment has a `vars.yml` (created from `templates/vars.yml`):

| Option | Default | Meaning |
|---|---|---|
| `organization_filter` | unset | Export only this AAP organization (for example `'Default'`). Unset exports everything your user can see. |
| `secrets_as_variables` | `true` | Export secrets as `{{ <prefix>_... }}` placeholders instead of AAP's `$encrypted$` marker. |
| `secrets_as_variables_prefix` | `"vault"` | Prefix for those placeholder variable names. |
| `import_common` | `true` | Also import `orgs_vars/<workspace>/common/`. Set to `false` to import only the environment's `imports/` folder. |

The environment's `vars.env` holds `CASC_AAP_VERSION` (the AAP version), written by `start_here.sh`.

### Vault files

| File | Holds |
|---|---|
| `orgs_vars/<workspace>/<env>/vault.yml` | How to reach this AAP instance, plus environment-specific secrets. |
| `orgs_vars/<workspace>/common/vault.yml` | Secrets shared by every environment in the workspace (loaded on import). |

Connection variables in the environment vault:

| Variable | Meaning |
|---|---|
| `vault_aap_hostname` | AAP URL or hostname (on 2.5+, the platform gateway). |
| `vault_aap_validate_certs` | `false` to accept self-signed certificates. |
| `vault_aap_username` / `vault_aap_password` | Credentials. A temporary token is created for the run and deleted afterwards. |
| `vault_aap_token` | Alternatively, an existing OAuth token (comment out username/password). |

Use `./vault-edit.sh <workspace> <env>` to edit a vault (use `common` as the env for the shared vault) and `./vault-view.sh <workspace> <env>` to print it with password and token lines hidden.

### Vault password: prompt or password file

Each **workspace** has one vault password, shared by all of its environments and its `common/` vault. Different workspaces can use different passwords, or the same one; it's up to you.

Scripts that need the vault password get it from the first of these that works:

1. The **`CASC_VAULT_PASSWORD`** environment variable (handy for CI and other non-interactive runs).
2. **The workspace's password file**, `.vault_pass/<workspace>.txt` in the repository root.
3. **A shared password file**: the `ANSIBLE_VAULT_PASSWORD_FILE` environment variable, or `vault_password_file` in the `[defaults]` section of the active `ansible.cfg` (`$ANSIBLE_CONFIG`, then this repo's `ansible.cfg`, then `~/.ansible.cfg`, then `/etc/ansible/ansible.cfg`).
4. Otherwise, a **prompt**: once per run (twice when creating a new workspace's first vault, to confirm). The password stays in memory for that run and is never written to disk. It's passed to `ansible-navigator` too.

Password files are checked against the workspace's vaults before they're used. A file that holds a different password is skipped with a note, and you're asked instead. So a shared password file and per-workspace passwords can be mixed: workspaces whose vaults match the shared file use it, the rest use their own file or are prompted. A typed password is checked too, and you get three tries.

If there's no terminal to prompt on, the script stops and explains how to provide the password.

**To stop typing the password**, save it per workspace (only in a trusted environment). `start_here.sh` offers this when you create a workspace, and its menu offers it for existing environments. By hand:

```bash
mkdir -p -m 700 .vault_pass
(umask 077; echo 'my-vault-password' > .vault_pass/MyCompany.txt)
```

`.vault_pass/` is in `.gitignore`. It lives in the repository root rather than under `orgs_vars/`, so it can't end up in your configuration repository, and `ansible-navigator` can still read it (the repository is mounted into the Execution Environment).

**One password for everything:** if all your workspaces share one password, a single shared file is simpler. Create `.vault_pass.txt` (mode 600) and uncomment `vault_password_file=.vault_pass.txt` in `ansible.cfg` (copied from `ansible.cfg.example`), or set `ANSIBLE_VAULT_PASSWORD_FILE`. When you create a new workspace while a shared file is configured, `start_here.sh` asks whether to use that password or a new one for the workspace.

### Environment variables

| Variable | Effect |
|---|---|
| `CASC_USE_PLAYBOOK` | Unset, `1`, `true` or `yes`: use `ansible-playbook` (default). Any other value: use `ansible-navigator`. The `--playbook` / `--navigator` flags override it. |
| `CASC_VAULT_PASSWORD` | Vault password for non-interactive runs (see above). It applies to whichever workspace you run against, so set it per run when workspaces have different passwords. |
| `ANSIBLE_VAULT_PASSWORD_FILE` | Standard Ansible vault password file setting, used as the shared password file. |
| `CONTROLLER_REQUEST_TIMEOUT` | API timeout in seconds for exports (default `60`). Raise it for very large instances. |
| `ANSIBLE_VERBOSITY` | Ansible output detail, for example `3` (same as `-vvv`) when troubleshooting. |

## 🏃 Running with ansible-playbook or ansible-navigator

**`ansible-playbook` (default):** uses your local `ansible-core` and the collections in `collections/<version>/`, which `./install_collections.sh` installs. Each AAP version has its own self-contained collection set, so versions never interfere with each other.

**`ansible-navigator` (`--navigator`):** runs inside an Execution Environment (EE) container, so you don't need local collections. You provide the EE image (it must contain the collections for that AAP version) and set it in `script_vars/<version>/vars.env`:

```bash
execution_environment="registry.example.com/my-ee-casc-aap26:latest"
```

Details, the collections each version needs, and ansible-core requirements are in [Versions and Collections](docs/VERSIONS_AND_COLLECTIONS.md).

## 🧰 Other Scripts and Tab Completion

Everything you run lives in the repository root. Internal helpers live in `scripts/` and aren't meant to be run directly.

| Script | Purpose |
|---|---|
| `start_here.sh [<workspace> <env>]` | Setup wizard: create, repair or check an environment (version, layout, folders, connection test, vaults). `--help` lists options for unattended use. |
| `export.sh` / `import.sh` | Export from / import to AAP. |
| `vault-edit.sh <workspace> <env\|common>` | Create or edit a vault. |
| `vault-view.sh <workspace> <env>` | Show a vault with secret lines hidden. |
| `install_collections.sh [--git] [version ...]` | Install each AAP version's collections into `collections/<version>/`. |
| `list_collections.sh <version>` | List the collections installed for a version. |
| `autocomplete.sh` | Tab completion for workspace and env names (`source` it). |

Utility playbooks for advanced use (`flat_to_filetree.yml`, `filetree_to_flat.yml`, `convert_roles.yml`) are covered in the [How-To guide](docs/HOW_TO.md).

**Tab completion (Bash):** add this to `~/.bashrc`, or run it in your current shell:

```bash
source /path/to/aap-casc-demo/autocomplete.sh
```

## 📚 Documentation

| Guide | What's in it |
|---|---|
| [Concepts and Glossary](docs/CONCEPTS.md) | Configuration as code basics, the AAP components, and every term this project uses. |
| [How-To Guide](docs/HOW_TO.md) | Step-by-step recipes: first export, Git workflow, promoting dev to prod, adding, changing and deleting objects, secrets, CI, and more. |
| [Folder Layout and Object Reference](docs/FOLDER_LAYOUT.md) | Every folder and YAML key, file format rules, and examples. |
| [Object Examples](docs/OBJECT_EXAMPLES.md) | A copy-and-edit example of every object type, for controller, gateway, EDA and hub. |
| [Migrating Between AAP Versions](docs/MIGRATING_BETWEEN_AAP_VERSIONS.md) | Moving a configuration from 2.4 to 2.5+ (or between any versions), and what needs manual work. |
| [Versions and Collections](docs/VERSIONS_AND_COLLECTIONS.md) | Collections per AAP version, ansible-core requirements, Execution Environments, and tag lists. |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Common errors and how to fix them. |
| [Collection Variable Reference (controller_configuration → aap_configuration)](docs/MIGRATION_GUIDE_CONTROLLER_TO_AAP.md) | Detailed role and variable mapping between the upstream collections, for writing configuration by hand. |

## 📦 Supported AAP Versions

| AAP version | Status |
|---|---|
| 2.7 | Supported |
| 2.6 | Supported |
| 2.5 | Supported |
| 2.4 | Supported (Automation Controller only) |

## 🔗 Useful Links

* [AAP 2.7 Upgrade: API and Configuration as Code Migration Guide](https://access.redhat.com/articles/7143981): Red Hat's guide to upgrading to AAP 2.7, including gateway-only API access and configuration-as-code considerations.
* [infra.aap_configuration](https://github.com/redhat-cop/infra.aap_configuration) and [infra.aap_configuration_extended](https://github.com/redhat-cop/aap_configuration_extended): the collections that do the work for AAP 2.5+.
* [infra.controller_configuration](https://github.com/redhat-cop/infra.controller_configuration): the collection used for AAP 2.4.

## 🤝 Contributing

Feedback and contributions are welcome.

* **Feature requests, bugs, documentation:** open a [GitHub Issue](https://github.com/lennysh/aap-casc-demo/issues) and pick the matching template.
* **Questions and chat:** join the [Matrix channel](https://matrix.to/#/#lennysh-aap-casc-demo:matrix.org).
* **Code or doc changes:** open a pull request. The [pull request template](.github/PULL_REQUEST_TEMPLATE.md) walks you through the details.

## 🙏 Thank You

Thanks to everyone who has offered ideas and suggestions that improved this project:

* **[JLaughlin](https://github.com/jd1306)**, for suggesting the `--export-path` / `-o` option on `export.sh`.

---

## 📜 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

Copyright (c) 2025 Lenny Shirley.
