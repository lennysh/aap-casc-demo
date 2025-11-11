filetree_to_flat
================

Converts a structured file tree directory of Ansible variable files back into a single "flat" variable in memory. It can also optionally save these merged variables back to individual flat files.

This role is the inverse of the `flat_to_filetree` role. It is designed to:
1.  Find all individual `.yml` files in a given directory (e.g., `controller_projects.d/`).
2.  Read the raw content of each file *without* templating any variables inside them (allowing `{{ vault_vars }}` to be preserved as strings).
3.  Parse and merge all found files into a single in-memory Ansible variable (e.g., `controller_projects: [ ... ]`).
4.  Optionally save these new, merged variables into a flat directory (e.g., `exports_merged/controller_projects.yml`).

This allows you to manage your Configuration as Code in a granular file tree structure but "flatten" them at runtime for an Ansible role that expects all variables to be defined in one place.

Requirements
------------

* Ansible 2.15.0 or later.
* The `lookup('pipe', 'cat ...')` feature must be available on the Ansible controller, as this role uses it to read files without triggering Jinja2 templating.
* The `type_debug` filter must be available (standard in modern Ansible).

Role Variables
--------------

All variables are set in the playbook that calls this role or in `defaults/main.yml`.

### Key Variables

* `filetree_to_flat_base_path`
    * **Required:** The full or relative path to the *parent* directory containing all the file tree folders (e.g., `controller_projects.d`, `aap_organizations.d`).
    * Example: `"aap_vars/AAP26/imports"`

* `filetree_to_flat_map`
    * **Required:** A dictionary mapping the final **variable name** to create (e.g., `controller_projects`) to the **directory** to scan for its files (e.g., `controller_projects.d`). This map is defined in `defaults/main.yml`.
    * Example:
```yaml
filetree_to_flat_map:
  controller_projects: controller_projects.d
  aap_organizations: aap_organizations.d
  gateway_settings: gateway_settings.d
```

### Optional Save-to-File Variables

* `filetree_to_flat_save_files`
    * **Optional:** A boolean that controls whether the role saves the merged variables to disk.
    * Default: `false`
    * Set to `true` to enable saving.

* `filetree_to_flat_output_path`
    * **Required if `save_files` is true:** The path to the new directory where the flat files will be created.
    * Example: `"aap_vars/AAP26/exports_merged"`

Dependencies
------------

This role has no external dependencies.

Example Playbook
----------------

### Example 1: Merge variables in-memory (for another role)

This playbook merges all files from `aap_vars/AAP26/imports2/` into in-memory variables and then (presumably) passes them to a subsequent role.

```yaml
---
- name: Merge FileTree and Configure AAP
  hosts: localhost
  connection: local
  gather_facts: false

  vars:
    # 1. Path to your 'imports' directory that contains
    #    all the .d folders
    filetree_to_flat_base_path: "aap_vars/AAP26/imports2"

    # 2. 'filetree_to_flat_save_files' is false by default

  roles:
    # This role merges the files into memory
    - role: filetree_to_flat

    # This role can now use {{ controller_projects }}
    # as if it were loaded from a single flat file.
    - role: infra.controller_configuration.dispatch

  post_tasks:
    - name:  DEBUG - Show merged variables
      ansible.builtin.debug:
        msg:
          - "controller_projects has {{ controller_projects | length }} items."
          - "aap_organizations has {{ aap_organizations | length }} items."
      when: controller_projects is defined or aap_organizations is defined
```

### Example 2: Merge variables and save to flat files

This playbook merges all files and saves them to a new `exports_merged` directory.

```yaml
---
- name: Merge FileTree to Flattened Files
  hosts: localhost
  connection: local
  gather_facts: false

  vars:
    # 1. Path to your 'imports' directory
    filetree_to_flat_base_path: "aap_vars/AAP26/imports2"

    # 2. Set the boolean to true
    filetree_to_flat_save_files: true

    # 3. Provide the new output directory
    filetree_to_flat_output_path: "aap_vars/AAP26/exports_merged"

  roles:
    - role: filetree_to_flat
```

License
-------

GPL-3.0-or-later

Author Information
------------------

Lenny Shirley II