# AAP Configuration as Code Migration Tool

> [!WARNING]
> **🚧 Work in Progress 🚧**
>
> This repository is under active development. Features may be incomplete, subject to breaking changes, or not fully tested. Please use with caution.

---

## 📖 Table of Contents

* [🧐 What is This Tool?](#-what-is-this-tool)
* [✨ Why Use "Configuration as Code" (CaSC)?](#-why-use-configuration-as-code-casc)
* [🚀 Core Features](#-core-features)
* [⚙️How It Works](#-how-it-works)
* [🛠️ Prerequisites](#-prerequisites)
* [🏁 Step 1: Setup & Configuration](#-step-1-setup--configuration)
* [👟 Step 2: Usage / Examples](#-step-2-usage--examples)
    * [Exporting Configuration](#exporting-configuration)
    * [Importing Configuration](#importing-configuration)
* [📦Supported AAP Versions](#-supported-aap-versions)
* [📜 License](#-license)

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

This tool provides two main wrapper scripts, `aapexport.sh` and `aapimport.sh`, which are the easiest way to get started.

These scripts are user-friendly wrappers for the underlying Ansible playbooks (`aapexport.yml` and `aapimport.yml`). They automatically:
1.  Read your environment's credentials.
2.  Validate your command-line tags.
3.  Run the correct Ansible playbook using **`ansible-navigator`**.
4.  Use a pre-built **Execution Environment (EE)** to ensure all the right Ansible collections and dependencies are present.

You don't need to be an Ansible expert to use them, but you *do* need the prerequisite tools installed.

## 🛠️ Prerequisites

Before you begin, you **must** have the following tools installed on your local machine:

1.  **`ansible-navigator`**: The tool used to run the Ansible playbooks inside their execution environment.
2.  **`yq`**: A command-line YAML processor. The wrapper scripts use this to read configuration and validate tags.
3.  **Podman** or **Docker**: `ansible-navigator` needs a container runtime to pull and run the Execution Environment.
4.  **Git**: To clone this repository.

---

## 🏁 Step 1: Setup & Configuration

1.  **Clone this repository:**
    ```bash
    git clone https://github.com/lennysh/aap-casc-migration.git
    cd aap-casc-migration
    ```

2.  **Create your Environment Configuration:**
    This tool is designed to manage multiple environments (e.g., `dev`, `test`, `prod`). You must create a directory for your environment inside `aap_vars/`.

    For this example, let's create an environment called `my_prod`:
    ```bash
    mkdir -p aap_vars/my_prod
    ```

3.  **Create your `vault.yml` file:**
    This is the most important step. You need to create a file at `aap_vars/my_prod/vault.yml` that tells the tool how to connect to your AAP instance.

    > **Note:** Despite the name `vault.yml`, the scripts currently read this as a plain YAML file. For production use, you should secure this file (e.g., using `ansible-vault` or file permissions).

    Create the file `aap_vars/my_prod/vault.yml` with the following content:

    ```aml
    # This file stores the connection details for your 'my_prod' environment
    
    # The full URL of your AAP instance
    vault_aap_hostname: "https://aap.mycompany.com"
    
    # Set to 'false' if you are using self-signed certificates
    vault_aap_validate_certs: true
    
    # --- Authentication (Choose ONE) ---
    
    # Option 1: Username / Password (Recommended for first run)
    # The tool will create a temporary token and delete it afterward
    vault_aap_username: "my_admin_user"
    vault_aap_password: "my_secret_password"
    
    # Option 2: Pre-generated OAuth2 Token
    # If you use this, comment out the username/password above
    # vault_aap_token: "aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890"
    
    ```

## 👟 Step 2: Usage / Examples

The two main scripts are `./aapexport.sh` and `./aapimport.sh`. You must make them executable first:

```bash
chmod +x aapexport.sh aapimport.sh
```

### Exporting Configuration

This command reads from your AAP instance and saves the files locally.

* **Command:** `./aapexport.sh <aap_version> <environment_name> [options]`
* **Arguments:**
    * `<aap_version>`: The version of your AAP instance (e.g., `2.6`).
    * `<environment_name>`: The name of your config directory (e.g., `my_prod`).
    * `[options]`:
        * `-a` or `--all`: Export *all* supported configurations.
        * `-t "tag1,tag2"`: Export *only* the specific items you list.

**Example: Export only Projects and Credentials from a 2.6 instance**
```bash
./aapexport.sh 2.6 my_prod -t "controller_projects,controller_credentials"
```
* **What this does:**
    1.  Reads connection details from `aap_vars/my_prod/vault.yml`.
    2.  Connects to your AAP 2.6 instance.
    3.  Runs the export playbook with the tags `controller_projects` and `controller_credentials`.
    4.  Saves the resulting YAML files into a new, timestamped directory like `aap_vars/my_prod/exports/aapexport_20251028_193000/`.

---

### Importing Configuration

This command reads from your local files and configures your AAP instance.

* **Command:** `./aapimport.sh <aap_version> <environment_name> [options]`
* **Arguments:**
    * `<aap_version>`: The version of your AAP instance (e.g., `2.6`).
    * `<environment_name>`: The name of your config directory (e.g., `my_prod`).
    * `[options]`:
        * `-a` or `--all`: Import *all* configurations from the `imports` directory.
        * `-t "tag1,tag2"`: Import *only* the specific items you list.

**Example: Import only Projects into a 2.6 instance**

1.  **First, copy your config files:** Before you can import, you must place your configuration files into the `imports` directory for your environment.
    ```bash
    # (Assuming you already exported)
    # mkdir -p aap_vars/my_prod/imports
    # cp aap_vars/my_prod/exports/aapexport.../controller_projects.yml aap_vars/my_prod/imports/
    ```

2.  **Run the import script:**
    ```bash
    ./aapimport.sh 2.6 my_prod -t "controller_projects"
    ```
* **What this does:**
    1.  Reads connection details from `aap_vars/my_prod/vault.yml`.
    2.  Connects to your AAP 2.6 instance.
    3.  Runs the import playbook, which reads configuration files from `aap_vars/my_prod/imports/`.
    4.  Applies *only* the configurations found that match the `controller_projects` tag.

> **💡 How to find all available tags?**
>
> The available tags are different for each AAP version. To see a full list of supported tags, run the script with just the version number:
> ```bash
> ./aapexport.sh 2.6
> ```
> This will show the `Usage:` help text, which lists all valid tags for both exporting and importing.

## 📦 Supported AAP Versions

This tool is explicitly designed to support multiple AAP versions by loading different tasks and tag lists for each. Supported versions include:

* **AAP 2.6**
* **AAP 2.5**
* **AAP 2.4**

---

## 📜 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

Copyright (c) 2025 Lenny Shirley.