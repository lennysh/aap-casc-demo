# AAP Configuration as Code Demo

[![GitHub last commit](https://img.shields.io/github/last-commit/lennysh/aap-casc-demo.svg)](https://github.com/lennysh/aap-casc-demo/commits/main) [![GitHub license](https://img.shields.io/github/license/lennysh/aap-casc-demo.svg)](https://github.com/lennysh/aap-casc-demo/blob/main/LICENSE) [![Contributions welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](https://github.com/lennysh/aap-casc-demo/pulls) ![GitHub contributors](https://img.shields.io/github/contributors/lennysh/aap-casc-demo) ![GitHub Issues or Pull Requests](https://img.shields.io/github/issues/lennysh/aap-casc-demo)

> [!WARNING]
> **🚧 Work in Progress 🚧**
>
> This repository is under active development. Features may be incomplete, subject to breaking changes, or not fully tested. Please use with caution.

---

## 📖 Table of Contents

* 🧐 [What is This Tool?](#-what-is-this-tool)
* ✨ [Why Use "Configuration as Code" (CaSC)?](#-why-use-configuration-as-code-casc)
* 🚀 [Core Features](#-core-features)
* ⚙️ [How It Works](#-how-it-works)
* 🛠️ [Prerequisites](#-prerequisites)
* 🏁 [Step 1: Setup & Configuration](#-step-1-setup--configuration)
* 👟 [Step 2: Usage / Examples](#-step-2-usage--examples)
    * [Exporting Configuration](#exporting-configuration)
    * [Importing Configuration](#importing-configuration)
* 💡 [Tips and Advanced Usage](#-tips-and-advanced-usage)
    * [ansible-playbook vs ansible-navigator](#ansible-playbook-vs-ansible-navigator)
    * [Versioned collections](#versioned-collections)
    * [Environment vars.yml](#environment-varsyml)
* 📚 [Documentation](#-documentation)
* 🤝 [Contributing](#-contributing)
* 🙏 [Thank You](#-thank-you)
* 📦 [Supported AAP Versions](#-supported-aap-versions)
* 📜 [License](#-license)

---

## 🧐 What is This Tool?

This project is a set of Ansible playbooks and helper scripts designed to help you manage your **Ansible Automation Platform (AAP)** setup like code.

It has two primary functions:

1.  **EXPORT:** Read the *current configuration* from your AAP instance (like Job Templates, Credentials, Inventories, Projects, etc.) and save them as human-readable YAML files.
2.  **IMPORT:** Take those YAML configuration files and *apply them* to an AAP instance, automatically creating or updating resources to match what's in the files.

This process is often called **Configuration as Code (CaSC)**.

## ✨ Why Use "Configuration as Code" (CaSC)?

If you're new to CaSC, here's why it's so powerful:

* **Version Control:** You can store your *entire* AAP configuration in Git. This lets you see a full history of who changed what and when.
* **Migration:** Easily move your setup from one environment to another (e.g., from a 'test' server to a 'production' server).
* **Consistency:** Ensure your 'dev' and 'prod' environments are configured identically, reducing "it worked in test" problems.
* **Disaster Recovery:** If a server fails, you can rebuild it and re-apply your configuration from code in minutes.
* **Auditing & Review:** You can use "Pull Requests" to review and approve changes to your AAP configuration *before* they are applied.

## 🚀 Core Features

* **Export from AAP:** Dumps your live AAP configuration into structured YAML files.
* **Import to AAP:** Configures an AAP instance based on your YAML files.
* **Version-Aware:** Includes different logic for different versions of AAP (e.g., 2.4, 2.5, 2.6).
* **Granular Control:** Uses Ansible **tags** to let you export or import only specific pieces of your configuration (e.g., just `controller_projects` or `eda_credentials`).

## ⚙️ How It Works

This tool provides two main wrapper scripts, `export.sh` and `import.sh`, which are the easiest way to get started.

These scripts are user-friendly wrappers for the underlying Ansible playbooks (`import_export.yml` in export or import mode). They automatically:
1.  Read your environment's **AAP version** from `orgs_vars/<org_name>/<env_name>/vars.env`.
2.  Read your environment's credentials from an encrypted Ansible Vault.
3.  Validate your command-line tags against the version-specific list in `script_vars/<version>/`.
4.  Run the playbook using **`ansible-playbook`** by default (with versioned collections from `collections/<version>/`), or **`ansible-navigator`** with an Execution Environment if you pass `--navigator`.

You don't need to be an Ansible expert to use them, but you *do* need the prerequisite tools installed.

## 🛠️ Prerequisites

Before you begin, you **must** have the following installed on your local machine:

1.  **Ansible** (for **`ansible-playbook`**, the default): Used with versioned collections in `collections/<version>/`. Install collections per AAP version with `./install_collections.sh`; use `./list_collections.sh` to verify what is installed (see [Versioned collections](#versioned-collections)).
2.  **`Bash 4.3+`**: Required for script features (associative arrays and namerefs).
3.  **Git**: To clone this repository.

**Optional (for Execution Environment runs):** If you prefer to run with **`ansible-navigator`** and an EE, you need **`ansible-navigator`** and **Podman** or **Docker**. You must **create the Execution Environments yourself** (e.g. build or pull images that include the required collections and dependencies). You must also **update the config** so the scripts use your EE: set the `execution_environment` variable in the version-specific script vars file (see [Using ansible-navigator (EE)](#using-ansible-navigator-ee) below). Then pass `--navigator` to `export.sh` or `import.sh`.

---

## 🏁 Step 1: Setup & Configuration

1.  **Clone this repository:**
    ```bash
    git clone https://github.com/lennysh/aap-casc-demo.git
    cd aap-casc-demo
    ```

2.  **Run the Initialization Script:**
    This tool now includes an interactive script to get you started. Run the `start_here.sh` script and provide an organization name and environment name (e.g., `OCP0Lab` and `my_prod`).

    ```bash
    chmod +x start_here.sh
    ./start_here.sh OCP0Lab my_prod
    ```

3.  **What This Script Does:**
    The `start_here.sh` script will automatically:
    * **Create the organization directory** if it doesn't exist (e.g., `orgs_vars/OCP0Lab/`).
    * **Ask you to select an AAP version** (e.g., 2.6, 2.5) for this environment.
    * Create the full directory structure: `orgs_vars/OCP0Lab/my_prod/imports` and `orgs_vars/OCP0Lab/my_prod/exports`.
    * Create the common directory: `orgs_vars/OCP0Lab/common/` for shared configurations.
    * Save your version choice to `orgs_vars/OCP0Lab/my_prod/vars.env`.
    * Copy `templates/vars.yml` to `orgs_vars/OCP0Lab/my_prod/vars.yml` (export/import behavior options; see [Environment vars.yml](#environment-varsyml) below).
    * Copy the `templates/vault.yml` to `orgs_vars/OCP0Lab/my_prod/vault.yml`.
    * Encrypt the new `vault.yml` using `ansible-vault`. (It will ask you to create a new vault password.)
    * Open the new `vault.yml` in your editor so you can add your AAP hostname and credentials.

4.  **(Optional) Edit Your Vault Later:**
    If you need to edit your encrypted vault file again later, you can use the `vault-edit.sh` script:

    ```bash
    chmod +x vault-edit.sh
    ./vault-edit.sh OCP0Lab my_prod
    ```

## 👟 Step 2: Usage / Examples

The two main scripts are `./export.sh` and `./import.sh`. You must make them executable first:

```bash
chmod +x export.sh import.sh
```

### Exporting Configuration

This command reads from your AAP instance and saves the files locally. **Note that you no longer need to provide the version number.**

* **Command:** `./export.sh <org_name> <environment_name> [--playbook|--navigator] [options]`
* **Arguments:**
    * `<org_name>`: The name of your organization (e.g., `OCP0Lab`, `TAMLab`, `HomeLab`).
    * `<environment_name>`: The name of your config directory (e.g., `my_prod`, `AAP25`).
    * `--playbook`: Use `ansible-playbook` with versioned collections (default if `CASC_USE_PLAYBOOK` is set).
    * `--navigator`: Use `ansible-navigator` with the Execution Environment.
    * `[options]`:
        * `-a` or `--all`: Export *all* supported configurations.
        * `-t "tag1,tag2"`: Export *only* the specific items you list.
        * `-o <dir>` or `--export-path <dir>`: Write the export under this directory instead of the default timestamped folder under `orgs_vars/<org_name>/<environment_name>/exports/`.

**Example: Export only Projects and Credentials**
```bash
./export.sh OCP0Lab my_prod -t "controller_projects,controller_credentials"
```
* **What this does:**
    1.  Reads `orgs_vars/OCP0Lab/my_prod/vars.env` to find this env is for AAP 2.6 (or whichever version you selected).
    2.  Reads connection details from your encrypted `orgs_vars/OCP0Lab/my_prod/vault.yml`.
    3.  Connects to your AAP instance.
    4.  Saves the result into a new directory. By default this is timestamped under `orgs_vars/OCP0Lab/my_prod/exports/ocp0lab_my_prod_export_YYYYMMDD_HHMMSS/`; use `-o` / `--export-path` to choose a different destination. **Export always produces both** **`flat_version/`** (single-file-per-resource YAML) and **`filetree_version/`** (hierarchical layout). Which one you copy into `imports` for a later import is determined by the **`flatten_output`** setting in `vars.yml` (see [Importing](#importing-configuration) and [Environment vars.yml](#environment-varsyml)).

---

### Importing Configuration

This command reads from your local files and configures your AAP instance.

* **Command:** `./import.sh <org_name> <environment_name> [--playbook|--navigator] [options]`
* **Arguments:**
    * `<org_name>` and `<environment_name>`: Same as export.
    * `--playbook` / `--navigator`: Same as export (default is playbook with versioned collections).
    * `[options]`:
        * `-a` or `--all`: Import *all* configurations from the environment's `imports` directory and the organization's `common` directory.
        * `-t "tag1,tag2"`: Import *only* the specific items you list.

**Example: Import only Projects**

1.  **First, copy your config files:** Before you can import, place your configuration files into the `imports` directory for your environment. Export always produces both `flat_version/` and `filetree_version/`. **Which of those two folders you copy from** depends on the **`flatten_output`** setting in your environment's **`vars.yml`** (e.g. `orgs_vars/OCP0Lab/my_prod/vars.yml`):
    * **`flatten_output: true`** → Copy from the export's **`flat_version/`** folder. When importing with flat layout, the import process reads **every YAML file it finds recursively** under `imports` (and under `common` when `import_common` is true). You can put YAML files in the root of `imports/` or in any subfolders—both work.
    * **`flatten_output: false`** → Copy from the export's **`filetree_version/`** folder. The import expects the filetree layout (e.g. `controller_projects.d/`, `gateway_teams.d/`, etc.); keep that structure when copying.
    ```bash
    # Example (flatten_output: true): copy from flat_version
    # cp orgs_vars/OCP0Lab/my_prod/exports/ocp0lab_my_prod_export_*/flat_version/controller_projects.yml orgs_vars/OCP0Lab/my_prod/imports/

    # Example (flatten_output: false): copy the filetree_version layout
    # cp -r orgs_vars/OCP0Lab/my_prod/exports/ocp0lab_my_prod_export_*/filetree_version/* orgs_vars/OCP0Lab/my_prod/imports/
    ```

2.  **Run the import script:**
    ```bash
    ./import.sh OCP0Lab my_prod -t "controller_projects"
    ```
* **What this does:**
    1.  Reads `orgs_vars/OCP0Lab/my_prod/vars.env` to get the version.
    2.  Reads connection details from your encrypted `orgs_vars/OCP0Lab/my_prod/vault.yml`.
    3.  Connects to your AAP instance.
    4.  Applies *only* the configurations found that match the `controller_projects` tag from both the environment's `imports` directory and the organization's `common` directory.

> **💡 How to find all available tags?**
>
> The available tags are different for each AAP version and are now defined in the `script_vars/` directory.
>
> To see a full list of supported tags, run the script with just an organization name and environment name and no options (like `-a` or `-t`).
>
> ```bash
> ./export.sh OCP0Lab my_prod
> ```
>
> This will show the `Usage:` help text, which dynamically lists all valid tags for the version associated with `my_prod`.

## 💡 Tips and Advanced Usage

### ansible-playbook vs ansible-navigator

By default, the scripts use **`ansible-playbook`** with versioned collections from `collections/<version>/` (e.g. `collections/2.5/`). You must install those collections first (see [Versioned collections](#versioned-collections)).

To use **`ansible-navigator`** with an Execution Environment instead (no local collections), pass `--navigator`:

```bash
./export.sh OCP0Lab my_prod --navigator -t "controller_projects"
```

#### Using ansible-navigator (EE)

If you use **`--navigator`**, you are responsible for:

1. **Creating the Execution Environments ahead of time.** The scripts do not build or pull an EE for you. You must build (or otherwise obtain) container images that include the required Ansible collections and dependencies for each AAP version you use (e.g. `infra.aap_configuration`, `infra.aap_configuration_extended`, platform collections).

2. **Pointing the scripts at your EE image.** Set the **`execution_environment`** variable in the **script vars** file for each AAP version:
   - **File:** `script_vars/<version>/vars.env` (e.g. `script_vars/2.5/vars.env`, `script_vars/2.6/vars.env`).
   - **Variable:** `execution_environment="<your-ee-image>"` (e.g. a Quay or registry URL, or a local image name).
   - The scripts pass this value to `ansible-navigator` as `--execution-environment-image`. If `execution_environment` is missing when you run with `--navigator`, the scripts will error.

You can set the environment variable **`CASC_USE_PLAYBOOK`** to `1`, `true`, or `yes` to prefer playbook; leave it unset or set to something else to prefer navigator. The `--playbook` and `--navigator` flags override the environment variable.

### Versioned collections

When using **`ansible-playbook`** (the default), each AAP version uses its own self-contained collection directory under `collections/<version>/`. Two helper scripts manage that layout:

| Script | Purpose |
|--------|---------|
| **`install_collections.sh`** | Install collections from `collections/<version>/requirements.yml` into `collections/<version>/`. |
| **`list_collections.sh`** | List collections installed in `collections/<version>/` for a single AAP version. |

**Install collections**

```bash
chmod +x install_collections.sh list_collections.sh

# Install for all versions found under script_vars/
./install_collections.sh

# Install for one or more versions only
./install_collections.sh 2.6
./install_collections.sh 2.5 2.6

# Use requirements-git.yml instead of requirements.yml (git sources)
./install_collections.sh --git 2.6
```

Each version needs a requirements file at `collections/<version>/requirements.yml` (or `requirements-git.yml` with `--git`).

**List installed collections**

```bash
# Show what is installed for AAP 2.6 (only collections in collections/2.6/)
./list_collections.sh 2.6
```

This runs `ansible-galaxy collection list` scoped to that version directory, so it does not include collections from `~/.ansible/collections` or system paths.

### Bash tab completion

The repository includes `autocomplete.sh`, which offers Tab completion for `<org_name>` and `<environment_name>` on scripts such as `./export.sh` and `./import.sh`. Completion is based on directories under `orgs_vars/`.

Register it in your **interactive Bash shell** (sourcing from inside a running script does not affect your terminal):

**One-time (current shell session):**

```bash
source /path/to/your-clone/autocomplete.sh
```

Use the absolute path to this repository (or `source "$(pwd)/autocomplete.sh"` when your shell is already in the repo root).

**Every new terminal (add to `~/.bashrc`):**

```bash
source /path/to/your-clone/autocomplete.sh
```

After sourcing, Tab completion applies until you close that shell (or until reboot if you added it to `.bashrc`). This is Bash-only; zsh users need a separate completion setup.

### Avoid Typing Your Vault Password
By default, these scripts will securely prompt you for your vault password every time they run.

If you are in a trusted environment and want to avoid this, you can tell Ansible where to find your password in a file.
1.  Create a simple text file containing *only* your vault password (e.g., `.vault_pass.txt`).

2.  **Secure this file:** `chmod 600 .vault_pass.txt`

3.  **Tell Ansible to use it.** You have two common options:

      * **Option 1 (Environment Variable):** Set an environment variable in your `.bashrc` or `.zshrc`:

        ```bash
         export ANSIBLE_VAULT_PASSWORD_FILE=.vault_pass.txt
        ```

      * **Option 2 (`ansible.cfg`):** Create a file named `ansible.cfg` (or `cp ansible.cfg.example ansible.cfg`) in this repository's root directory with the following content:

        ```ini
        [defaults]
        vault_password_file = .vault_pass.txt
        ```

4.  **Important:** If you create this `ansible.cfg` file, make sure to add it to your `.gitignore` file so you don't accidentally commit it!

### Environment vars.yml

Each environment has a **`vars.yml`** (e.g. `orgs_vars/OCP0Lab/my_prod/vars.yml`) created from `templates/vars.yml`. It controls import behavior and optional export filters. **Export always produces both** `flat_version/` and `filetree_version/`; `flatten_output` only affects which layout **import** expects. All options in the template are:

| Option | Description |
|--------|--------------|
| **`organization_filter`** | (Optional.) Limit export to a single AAP organization (e.g. `'Default'`). If unset or empty, all organizations your credentials can access are exported. |
| **`flatten_output`** | **Import only.** `true`: import uses flat layout and reads every YAML file recursively under `imports` (and `common` when `import_common` is true). `false`: import expects the filetree layout (e.g. `controller_projects.d/`, `gateway_teams.d/`). Export always writes both layouts. |
| **`secrets_as_variables`** | When `true`, replaces `$encrypted$` in exported data with a variable name so you can define the secret (e.g. in Vault) before re-importing. |
| **`secrets_as_variables_prefix`** | Prefix for those variable names (default `"vault"`). |
| **`import_common`** | When `true`, import also reads config from `orgs_vars/<org_name>/common/`. Set to `false` to use only the environment's `imports` folder. |

## 📚 Documentation

Additional guides and references in the **`docs/`** directory:

* **[Migration guide: Controller to AAP](docs/MIGRATION_GUIDE_CONTROLLER_TO_AAP.md)** — Migrating from `infra.controller_configuration` (AAP 2.4 and earlier) to `infra.aap_configuration` / `infra.aap_configuration_extended` (AAP 2.5+).

## 🤝 Contributing

We welcome feedback and contributions.

* **Feature requests, bugs, documentation:** Open a [GitHub Issue](https://github.com/lennysh/aap-casc-demo/issues) and choose the appropriate template (Feature request, Bug report, or Documentation).
* **Questions, usage help, or chat:** Join the [Matrix channel](https://matrix.to/#/#lennysh-aap-casc-demo:matrix.org).
* **Code or doc changes:** Open a Pull Request. The repo uses a [pull request template](.github/PULL_REQUEST_TEMPLATE.md) to capture description, type of change, and a short checklist.

## 🙏 Thank You

Thanks to everyone who has offered ideas and suggestions that improved this project:

* **Joshua Laughlin @ Credit Acceptance** — for suggesting the `--export-path` / `-o` option on `export.sh`.

## 📦 Supported AAP Versions

This tool is explicitly designed to support multiple AAP versions by loading different tasks and tag lists for each. Supported versions include:

* **AAP 2.6**
* **AAP 2.5**
* **AAP 2.4**

---

## 📜 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

Copyright (c) 2025 Lenny Shirley.