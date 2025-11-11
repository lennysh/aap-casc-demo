flat_to_filetree
================

Converts a flat directory of Ansible variable files (e.g., from an AAP export) into a structured file tree.

This role is designed to take a large set of `*.yml` files containing lists of objects (like `controller_credentials`, `controller_projects`, etc.) and split each object into its own individual YAML file, sorted into directories based on rules you provide.

It is particularly useful for converting "flat" Configuration as Code exports into a "file tree" structure that is easier to manage in Git.

Requirements
------------

* Ansible 2.15.0 or later.
* The `lookup('pipe', 'cat ...')` feature must be available on the Ansible controller, as this role uses it to read files without triggering Jinja2 templating.
* Source YAML files must be parsable. The role automatically strips `!unsafe` tags to handle common export formats.

Role Variables
--------------

All variables are set in the playbook that calls this role or in `defaults/main.yml`.

### Key Variables

* `flat_to_filetree_source_path`
    * **Required:** The full or relative path to the directory containing the flat `*.yml` / `*.yaml` files you want to process.
    * Example: `"aap_vars/AAP26/exports/my_export"`

* `flat_to_filetree_output_path`
    * **Required:** The path to the new directory where the file tree will be created.
    * Example: `"aap_vars/AAP26/imports"`

* `flat_to_filetree_var_to_folder_map`
    * **Required:** A dictionary mapping the top-level YAML variable (e.g., `controller_credentials`) to the name of the root folder you want to create for it.
    * Example:
```yaml
flat_to_filetree_var_to_folder_map:
  controller_credentials: controller_credentials.d
  controller_projects: controller_projects.d
```

* `flat_to_filetree_filename_logic`
    * **Required:** This is the core logic map that controls *how* each variable is processed. It defines the variable's `type` and, for lists, the `key` to use for grouping and filenames.

### Logic Types

The `flat_to_filetree_filename_logic` map supports four types:

1.  **`type: list` (Default)**
    * This is the most common type. It assumes the variable is a list of dictionaries.
    * It requires a `key` to be specified (e.g., `name`, `team`, `username`).
    * It will group the list based on this key and create a separate file for each group.
    * `subfolder:` can be used to sort groups into subdirectories (e.g., `team_roles.d`).
    * `filename:` can be used to give a static filename for a single-item group (like `controller_settings`).

2.  **`type: dict`**
    * Used for variables that are a single, flat dictionary (not a list).
    * It requires a static `filename:` to be specified.
    * Example: `gateway_settings`

3.  **`type: single_list_item`**
    * Used for variables that are a list containing a *single* dictionary (like `controller_settings`).
    * It requires a static `filename:` to be specified.

4.  **`__default__`**
    * A fallback rule for any variable *not* explicitly defined in the map.
    * By default, it uses `type: list` and `key: "name"`.

### Example `flat_to_filetree_filename_logic` (from defaults/main.yml)

```yaml
flat_to_filetree_filename_logic:

  # --- Type 1: Dictionary ---
  gateway_settings:
    - type: dict
      filename: "gateway_settings.yml"
      subfolder: ""

  # --- Type 2: List of 1 item ---
  controller_settings:
    - type: single_list_item # Special type for this var
      filename: "controller_settings.yml"
      subfolder: ""

  # --- Type 3: Grouped List ---
  controller_roles:
    - type: list
      key: "team"
      subfolder: "team_roles.d"
    - type: list
      key: "user"
      subfolder: "user_roles.d"

  # Also a list, but grouped by 'username' instead of 'name'
  aap_user_accounts:
    - type: list
      key: "username"
      subfolder: ""

  # --- Type 4: Default (List grouped by 'name') ---
  __default__:
    - type: list
      key: "name"
      subfolder: ""
```

Dependencies
------------

This role has no external dependencies.

Example Playbook
----------------

This is an example of how this role is called.

```yaml
---
- name: Split Ansible Variable Files
  hosts: localhost
  connection: local
  gather_facts: false

  vars:
    # 1. Path to search for your source files
    flat_to_filetree_source_path: "aap_vars/AAP26/exports/aap26_export_20251031_161923"

    # 2. Path to create the new split files
    flat_to_filetree_output_path: "aap_vars/AAP26/imports"

    # 3. Mappings are assumed to be in roles/flat_to_filetree/defaults/main.yml

  roles:
    - role: flat_to_filetree
```

License
-------

GPL-3.0-or-later

Author Information
------------------

Lenny Shirley II