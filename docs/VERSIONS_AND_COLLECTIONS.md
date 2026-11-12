# Versions and Collections

What each AAP version needs, how the collections are installed, and which tags each version accepts.

* [Supported versions](#supported-versions)
* [Collections per AAP version](#collections-per-aap-version)
* [Installing collections](#installing-collections)
* [ansible-core requirements](#ansible-core-requirements)
* [Execution Environments](#execution-environments)
* [Per-version settings (`script_vars`)](#per-version-settings-script_vars)
* [Tags](#tags)

---

## Supported versions

| AAP | What's managed | Configuration collections |
|---|---|---|
| 2.4 | Automation Controller (plus organizations, teams, users, applications) | `infra.controller_configuration` |
| 2.5 | Controller, Platform Gateway, Event-Driven Ansible, Automation Hub | `infra.aap_configuration`, `infra.aap_configuration_extended` |
| 2.6 | Same as 2.5 | Same as 2.5 |
| 2.7 | Same as 2.5 (work in progress) | Same as 2.5 |

The AAP version of each environment is stored in `orgs_vars/<org>/<env>/vars.env` (`CASC_AAP_VERSION`). You choose it when you run `start_here.sh`.

## Collections per AAP version

The pinned versions are in `collections/<version>/requirements.yml`:

| Collection | 2.4 | 2.5 | 2.6 | 2.7 |
|---|---|---|---|---|
| `infra.controller_configuration` | latest | – | – | – |
| `infra.aap_configuration` | – | latest | latest | `>=4.10.0` |
| `infra.aap_configuration_extended` | – | latest | latest | `>=4.12.0` |
| `ansible.controller` | `>=4.5.0,<4.6.0` | `>=4.6,<4.7` | `>=4.7,<4.8` | `>=4.8,<4.9` |
| `ansible.platform` | – | `>=2.6,<2.7` | `>=2.6,<2.7` | `>=2.7,<2.8` |
| `ansible.eda` | latest | `>=2.9.0` | `>=2.9.0` | `>=2.12.1` |
| `ansible.hub` | latest | latest | latest | `>=1.0.6` |

* **Export** uses the `filetree_create` role (`infra.controller_configuration` on 2.4, `infra.aap_configuration_extended` on 2.5+).
* **Import** uses `filetree_read` to load your files and `dispatch` to apply them in dependency order (`infra.controller_configuration` on 2.4; `infra.aap_configuration_extended` and `infra.aap_configuration` on 2.5+).
* AAP 2.5 uses `ansible.platform` 2.6 on purpose: `infra.aap_configuration` needs modules that first appeared there.

To compare collection variables between the 2.4 and 2.5+ collections when writing configuration by hand, see the [Collection Variable Reference](MIGRATION_GUIDE_CONTROLLER_TO_AAP.md).

## Installing collections

With the default `ansible-playbook` runner, each AAP version uses its own self-contained collection directory, `collections/<version>/ansible_collections/`. Nothing is installed into `~/.ansible`, and versions never affect each other.

`ansible.controller` and `ansible.platform` are certified collections from **Red Hat Automation Hub**. Before installing, copy `ansible.cfg.example` to `ansible.cfg` and add your [Automation Hub token](https://console.redhat.com/ansible/automation-hub/token) to the `token=` lines.

```bash
./install_collections.sh               # every version in script_vars/
./install_collections.sh 2.6           # one version
./install_collections.sh 2.5 2.6       # several
./install_collections.sh --git 2.6     # use requirements-git.yml (upstream Git sources)
./list_collections.sh 2.6              # what's installed for 2.6
```

Re-running `install_collections.sh` reinstalls (and upgrades within the pinned ranges). Edit `requirements.yml` or `requirements-git.yml` to change versions.

## ansible-core requirements

| Running | ansible-core |
|---|---|
| Export, any version | 2.16 or newer |
| Import into AAP 2.5+ | 2.16 or newer |
| Import into **AAP 2.4** | **2.16 – 2.18** |

`infra.controller_configuration` (AAP 2.4) isn't compatible with ansible-core 2.19 or newer. Objects that omit some optional fields (notification `messages`; inventory, host or group `variables`; credential type `injectors`; inventory source `source_vars`) fail to import. To protect you, a 2.4 import stops right away with an explanation when it detects ansible-core 2.19+. To import into 2.4:

* use `--navigator` with an AAP 2.4 Execution Environment, or
* run from a Python virtualenv with ansible-core 2.18 (`pip install 'ansible-core>=2.16,<2.19'`).

If every object in your files defines all of those fields, you can skip the check with `-e import_export_allow_unsupported_core=true`.

## Execution Environments

With `--navigator` (or `CASC_USE_PLAYBOOK=false`), the scripts run inside an Execution Environment (EE) container instead of using local collections. You need:

* `ansible-navigator`, plus Podman or Docker;
* an EE image per AAP version that contains that version's [collections](#collections-per-aap-version). For a 2.4 import, the image needs ansible-core 2.18 or older;
* the image name in `script_vars/<version>/vars.env`:

    ```bash
    execution_environment="registry.example.com/ee-casc-aap26:latest"
    ```

The repository is mounted into the container at the same path, so your `orgs_vars/` files and a prompted vault password are available inside. The image is pulled only if it isn't already present locally. To build an image, see [ansible-builder](https://ansible.readthedocs.io/projects/builder/), and use the matching `collections/<version>/requirements.yml` as the collection list.

## Per-version settings (`script_vars`)

`script_vars/<version>/vars.env` holds settings for each AAP version:

| Setting | Purpose |
|---|---|
| `execution_environment` | EE image for `--navigator`. |
| `export_category_tags`, `export_specific_tags` | Tags accepted by `export.sh -t`. |
| `import_category_tags`, `import_specific_tags` | Tags accepted by `import.sh -t`. |
| `aap_folders_needed` | Folders `start_here.sh` creates in `common/` and `<env>/imports/`. |

## Tags

Run a script with only the org and env to print the tags valid for that environment:

```bash
./export.sh MyCompany prod
./import.sh MyCompany prod
```

### AAP 2.5, 2.6 and 2.7

**Export category tags:** `controller`, `gateway`, `eda`, `hub`

| Component | Export tags | Import tags |
|---|---|---|
| Controller | `controller_applications`, `controller_credential_types`, `controller_credentials`, `controller_execution_environments`, `controller_groups`, `controller_hosts`, `controller_instance_groups`, `controller_instances`, `controller_inventories`, `controller_inventory_sources`, `controller_job_templates`, `controller_labels`, `controller_notification_templates`, `controller_organizations`, `controller_projects`, `controller_roles`, `controller_schedules`, `controller_settings`, `controller_teams`, `controller_users`, `controller_workflow_job_templates` | `controller_credential_input_sources`, `controller_credential_types`, `controller_credentials`, `controller_execution_environments`, `controller_host_groups`, `controller_hosts`, `controller_instance_groups`, `controller_instances`, `controller_inventories`, `controller_inventory_sources`, `controller_job_templates`, `controller_labels`, `controller_notification_templates`, `controller_projects`, `controller_roles`, `controller_schedules`, `controller_settings`, `controller_workflow_job_templates` |
| Gateway | `gateway_applications`, `gateway_authenticator_maps`, `gateway_authenticators`, `gateway_http_ports`, `gateway_organizations`, `gateway_role_definitions`, `gateway_role_team_assignments`, `gateway_role_user_assignments`, `gateway_routes`, `gateway_service_clusters`, `gateway_service_keys`, `gateway_service_nodes`, `gateway_services`, `gateway_settings`, `gateway_teams`, `gateway_users` | same as export |
| EDA | `eda_credential_types`, `eda_credentials`, `eda_decision_environments`, `eda_event_streams`, `eda_projects`, `eda_rulebook_activations` | same as export |
| Hub | `hub_collection_remotes`, `hub_collection_repositories`, `hub_collections`, `hub_ee_images`, `hub_ee_registries`, `hub_ee_repositories`, `hub_namespaces` | same as export |

On 2.5+, organizations, teams, users and applications are imported with the **gateway** tags (`gateway_organizations`, `gateway_teams`, `gateway_users`, `gateway_applications`).

### AAP 2.4

| | Tags |
|---|---|
| Export | `applications`, `credential_types`, `credentials`, `execution_environments`, `instance_groups`, `inventory`, `job_templates`, `labels`, `notification_templates`, `organizations`, `projects`, `roles`, `schedules`, `settings`, `teams`, `users`, `workflow_job_templates` |
| Import | `applications`, `credential_input_sources`, `credential_types`, `credentials`, `execution_environments`, `hosts`, `instance_groups`, `inventories`, `inventory_sources`, `job_templates`, `labels`, `notification_templates`, `organizations`, `projects`, `roles`, `schedules`, `settings`, `teams`, `users`, `workflow_job_templates` |

On 2.4, the `inventory` export tag also exports hosts, groups and inventory sources. The `inventories` import tag also imports groups.
