# Migration Guide: infra.controller_configuration, infra.eda_configuration, and galaxy.galaxy to infra.aap_configuration

> [!NOTE]
> **This is a collection-level reference** for people writing their own playbooks or configuration against the upstream collections. It maps roles and variables from `infra.controller_configuration`, `infra.eda_configuration` and `galaxy.galaxy` to `infra.aap_configuration`.
>
> **If you're moving a configuration with this project's `export.sh` / `import.sh`, you don't need this page.** The translation is handled for you. See [Migrating Between AAP Versions](MIGRATING_BETWEEN_AAP_VERSIONS.md) instead.

## Overview

This document provides a comprehensive guide for migrating from:
- `infra.controller_configuration` (designed for AAP 2.4 and lower)
- `infra.eda_configuration` (designed for AAP 2.4 and lower)
- `galaxy.galaxy` (designed for AAP 2.4 and lower)

to `infra.aap_configuration` (designed for AAP 2.5 and higher).

### Key Changes Summary

- **Collection Names**: 
  - `infra.controller_configuration` → `infra.aap_configuration`
  - `infra.eda_configuration` → `infra.aap_configuration` (consolidated)
  - `galaxy.galaxy` → `infra.aap_configuration` (consolidated)
- **Target Platform**: AAP 2.4 and lower → AAP 2.5 and higher
- **Role Naming**: Most roles renamed with `controller_`, `eda_`, or `hub_` prefix
- **Variable Naming**: Unified connection variables from `controller_*`, `eda_*`, and `ah_*` to `aap_*`
- **Global Variables**: Changed from `controller_configuration_*`, `eda_configuration_*`, and `ah_configuration_*` to `aap_configuration_*`
- **New Capabilities**: Added Gateway roles, enhanced Hub and EDA roles
- **Role Consolidation**: Some roles consolidated, others moved to extended collection
- **Multi-Collection Consolidation**: Controller, Hub, EDA, and Gateway roles now in single collection

---

## Table of Contents

1. [Collection Information](#collection-information)
2. [Role Name Changes](#role-name-changes)
3. [Variable Name Changes](#variable-name-changes)
4. [Role Consolidations](#role-consolidations)
5. [New Roles](#new-roles)
6. [Removed/Moved Roles](#removedmoved-roles)
7. [Extended Collection](#extended-collection-infraaap_configuration_extended)
8. [Dispatch Role Changes](#dispatch-role-changes)
9. [Step-by-Step Migration Guide](#step-by-step-migration-guide)
10. [Variable Mapping Reference](#variable-mapping-reference)

---

## Collection Information

### Old Collections (AAP 2.4 and lower)

#### infra.controller_configuration
- **Name**: `infra.controller_configuration`
- **Namespace**: `infra.controller_configuration`
- **Target**: AAP 2.4 and lower, AWX
- **Dependencies**: `ansible.controller` (version `>=4.5.0,<4.6.0`)

#### infra.eda_configuration
- **Name**: `infra.eda_configuration`
- **Namespace**: `infra.eda_configuration`
- **Target**: AAP 2.4 and lower
- **Dependencies**: None (uses custom modules)
- **Note**: This collection was separate and managed EDA-specific configuration

#### galaxy.galaxy
- **Name**: `galaxy.galaxy`
- **Namespace**: `galaxy.galaxy`
- **Target**: AAP 2.4 and lower
- **Dependencies**: None (uses custom modules)
- **Note**: This collection was separate and managed Automation Hub (Galaxy NG) configuration

## New Collection (AAP 2.5+)

#### infra.aap_configuration
- **Name**: `infra.aap_configuration`
- **Namespace**: `infra.aap_configuration`
- **Target**: AAP 2.5 and higher
- **Dependencies**:
  - `ansible.platform` (>=2.5.0)
  - `ansible.hub` (>=1.0.0)
  - `ansible.controller` (>=4.6.0)
  - `ansible.eda` (>=2.5.0)
- **Note**: Consolidates Controller, Hub, Gateway, and EDA configuration into a single collection, replacing the need for three separate collections

---

## Role Name Changes

Most roles in the new collection have been prefixed with `controller_` to make their purpose explicit. Below is a complete mapping:

| Old Role Name (controller_configuration) | New Role Name (aap_configuration) | Notes |
|:------------------------------------------|:-----------------------------------|:------|
| `ad_hoc_command` | `controller_ad_hoc_command` | |
| `ad_hoc_command_cancel` | `controller_ad_hoc_command_cancel` | |
| `applications` | `controller_applications` | Variable changed to `aap_applications` |
| `bulk_host_create` | `controller_bulk_host_create` | |
| `bulk_job_launch` | `controller_bulk_job_launch` | |
| `credential_input_sources` | `controller_credential_input_sources` | |
| `credentials` | `controller_credentials` | |
| `credential_types` | `controller_credential_types` | |
| `execution_environments` | `controller_execution_environments` | |
| `groups` | `controller_host_groups` | **Name change** - now explicitly "host_groups" |
| `hosts` | `controller_hosts` | |
| `instance_groups` | `controller_instance_groups` | |
| `instances` | `controller_instances` | |
| `inventories` | `controller_inventories` | |
| `inventory_sources` | `controller_inventory_sources` | |
| `inventory_source_update` | `controller_inventory_source_update` | |
| `job_launch` | `controller_job_launch` | |
| `jobs_cancel` | `controller_jobs_cancel` | |
| `job_templates` | `controller_job_templates` | |
| `labels` | `controller_labels` | |
| `license` | `controller_license` | |
| `notification_templates` | `controller_notification_templates` | |
| `organizations` | `controller_organizations` | Variable changed to `aap_organizations` |
| `projects` | `controller_projects` | |
| `project_update` | `controller_project_update` | |
| `roles` | `controller_roles` | Renamed with `controller_` prefix |
| `schedules` | `controller_schedules` | |
| `settings` | `controller_settings` | |
| `teams` | `controller_teams` | Variable changed to `aap_teams` |
| `users` | `controller_users` | Variable changed to `aap_user_accounts` |
| `workflow_job_templates` | `controller_workflow_job_templates` | |
| `workflow_launch` | `controller_workflow_launch` | |
| `collect_async_status` | `collect_async_status` | **No change** |
| `dispatch` | `dispatch` | **No change** |
| `global_vars` | `global_vars` | **No change** |
| `meta_dependency_check` | `meta_dependency_check` | **No change** |

---

## EDA Role Migration (infra.eda_configuration → infra.aap_configuration)

### EDA Role Name Mapping

| Old Role Name (eda_configuration) | New Role Name (aap_configuration) | Variable Name | Notes |
|:----------------------------------|:-----------------------------------|:---------------|:------|
| `credential` | `eda_credentials` | `eda_credentials` | Renamed with `eda_` prefix |
| N/A | `eda_credential_types` | `eda_credential_types` | **New role** - credential types management |
| `decision_environment` | `eda_decision_environments` | `eda_decision_environments` | Renamed with `eda_` prefix |
| N/A | `eda_event_streams` | `eda_event_streams` | **New role** - event streams management |
| `project` | `eda_projects` | `eda_projects` | Renamed with `eda_` prefix |
| `project_sync` | `eda_projects` | `eda_projects` | **Consolidated** - sync functionality integrated |
| `rulebook_activation` | `eda_rulebook_activations` | `eda_rulebook_activations` | Renamed with `eda_` prefix |
| `user` | `eda_users` | `aap_user_accounts` or `eda_users` | Variable changed to shared `aap_user_accounts` |
| `user_token` | `eda_controller_tokens` | `eda_controller_tokens` | **Renamed** - more descriptive name |

### EDA Variable Changes

#### Connection Variables

| Old Variable (eda_configuration) | New Variable (aap_configuration) |
|:----------------------------------|:--------------------------------|
| `eda_hostname` or `eda_host` | `aap_hostname` |
| `eda_username` | `aap_username` |
| `eda_password` | `aap_password` |
| `eda_token` | `aap_token` |
| `eda_validate_certs` | `aap_validate_certs` |
| `eda_request_timeout` | `aap_request_timeout` |

#### Global Configuration Variables

| Old Variable (eda_configuration) | New Variable (aap_configuration) |
|:--------------------------------|:---------------------------------|
| `eda_configuration_secure_logging` | `aap_configuration_secure_logging` |
| `eda_configuration_async_retries` | `aap_configuration_async_retries` |
| `eda_configuration_async_delay` | `aap_configuration_async_delay` |
| `eda_configuration_async_dir` | `aap_configuration_async_dir` |

#### Data Variables

| Old Variable (eda_configuration) | New Variable (aap_configuration) | Notes |
|:--------------------------------|:----------------------------------|:-----|
| `eda_users` | `aap_user_accounts` or `eda_users` | Can use shared variable or EDA-specific |
| `eda_user_tokens` | `eda_controller_tokens` | **Renamed** - more descriptive |
| `eda_credentials` | `eda_credentials` | No change |
| `eda_projects` | `eda_projects` | No change, but sync functionality integrated |
| `eda_decision_environments` | `eda_decision_environments` | No change |
| `eda_rulebook_activations` | `eda_rulebook_activations` | No change |

### EDA Role-Specific Configuration Variables

Role-specific configuration variables follow this pattern:

**Old Format:**
```yaml
eda_configuration_<role>_<setting>
```

**New Format:**
```yaml
eda_configuration_<role>_<setting>  # Still uses eda_configuration_ prefix
```

However, these variables now reference the new global variables:

| Old Reference | New Reference |
|:--------------|:--------------|
| `eda_configuration_secure_logging` | `aap_configuration_secure_logging` |
| `eda_configuration_async_retries` | `aap_configuration_async_retries` |
| `eda_configuration_async_delay` | `aap_configuration_async_delay` |
| `eda_configuration_async_dir` | `aap_configuration_async_dir` |

**Example:**
```yaml
# Old
eda_configuration_project_secure_logging: "{{ eda_configuration_secure_logging | default('false') }}"

# New
eda_configuration_projects_secure_logging: "{{ aap_configuration_secure_logging | default('false') }}"
```

### EDA Dispatch Role Changes

**Old (eda_configuration):**
```yaml
eda_configuration_dispatcher_roles:
  - role: user
    var: eda_users
  - role: credential
    var: eda_credentials
  - role: user_token
    var: eda_user_tokens
  - role: project
    var: eda_projects
  - role: project_sync
    var: eda_projects
  - role: decision_environment
    var: eda_decision_environments
  - role: rulebook_activation
    var: eda_rulebook_activations
```

**New (aap_configuration):**
```yaml
eda_configuration_dispatcher_roles:
  - role: eda_credential_types
    var: eda_credential_types
  - role: eda_credentials
    var: eda_credentials
  - role: eda_controller_tokens
    var: eda_controller_tokens
  - role: eda_projects
    var: eda_projects
  - role: eda_event_streams
    var: eda_event_streams
  - role: eda_decision_environments
    var: eda_decision_environments
  - role: eda_rulebook_activations
    var: eda_rulebook_activations
```

**Key Changes:**
- `user` role removed from dispatch (use `eda_users` role directly or `aap_user_accounts`)
- `project_sync` role removed (functionality integrated into `eda_projects`)
- `user_token` renamed to `eda_controller_tokens`
- New roles added: `eda_credential_types` and `eda_event_streams`
- All roles now have `eda_` prefix

---

## Hub Role Migration (galaxy.galaxy → infra.aap_configuration)

### Hub Role Name Mapping

| Old Role Name (hub_configuration) | New Role Name (aap_configuration) | Variable Name | Notes |
|:-----------------------------------|:-----------------------------------|:---------------|:------|
| `namespace` | `hub_namespace` | `hub_namespaces` | Renamed with `hub_` prefix |
| `collection` | `hub_collection` | `hub_collections` | Renamed with `hub_` prefix |
| `collection_remote` | `hub_collection_remote` | `hub_collection_remotes` | Renamed with `hub_` prefix |
| `collection_repository` | `hub_collection_repository` | `hub_collection_repositories` | Renamed with `hub_` prefix |
| `collection_repository_sync` | `hub_collection_repository_sync` | `hub_collection_repositories` | Renamed with `hub_` prefix |
| `ee_registry` | `hub_ee_registry` | `hub_ee_registries` | Renamed with `hub_` prefix |
| `ee_registry_index` | `hub_ee_registry_index` | `hub_ee_registries` | Renamed with `hub_` prefix |
| `ee_registry_sync` | `hub_ee_registry_sync` | `hub_ee_registries` | Renamed with `hub_` prefix |
| `ee_repository` | `hub_ee_repository` | `hub_ee_repositories` | Renamed with `hub_` prefix |
| `ee_repository_sync` | `hub_ee_repository_sync` | `hub_ee_repository_sync` | Renamed with `hub_` prefix |
| `ee_image` | `hub_ee_image` | `hub_ee_images` | Renamed with `hub_` prefix |
| `ee_namespace` | N/A | N/A | **Removed** - functionality consolidated |
| `group` | `hub_group` | `aap_teams` | Renamed; variable changed to shared `aap_teams` |
| `group_roles` | `hub_group_roles` | `hub_group_roles` | Renamed with `hub_` prefix |
| `role` | `hub_role` | `hub_roles` | Renamed with `hub_` prefix |
| `user` | `hub_user` | `aap_user_accounts` | Renamed; variable changed to shared `aap_user_accounts` |
| `publish` | `hub_publish` | `hub_publish` | Renamed with `hub_` prefix |
| `ansible_config` | `ansible_config` | N/A | **No change** - same role name |
| `repository` | N/A | N/A | **Removed** - not in new collection |
| `repository_sync` | N/A | N/A | **Removed** - not in new collection |
| `offline_sync` | `infra.aap_configuration_extended.offline_sync` | N/A | **Moved** - now in extended collection |

### Hub Variable Changes

#### Connection Variables

| Old Variable (hub_configuration) | New Variable (aap_configuration) |
|:--------------------------------|:--------------------------------|
| `ah_hostname` or `galaxy_server` | `aap_hostname` |
| `ah_username` | `aap_username` |
| `ah_password` | `aap_password` |
| `ah_token` or `ah_oauthtoken` or `galaxy_oauthtoken` | `aap_token` |
| `ah_validate_certs` | `aap_validate_certs` |
| `ah_path_prefix` | N/A | **Removed** - no longer needed |

#### Global Configuration Variables

| Old Variable (hub_configuration) | New Variable (aap_configuration) |
|:--------------------------------|:--------------------------------|
| `ah_configuration_secure_logging` | `aap_configuration_secure_logging` |
| `ah_configuration_async_retries` | `aap_configuration_async_retries` |
| `ah_configuration_async_delay` | `aap_configuration_async_delay` |
| `ah_configuration_async_timeout` | `aap_configuration_async_timeout` | **Note**: Still available, now uses `aap_configuration_*` prefix |
| `ah_configuration_async_dir` | `aap_configuration_async_dir` |
| N/A | `aap_configuration_loop_delay` | **New** - Hub roles now support loop_delay in addition to async_timeout |
| N/A | `aap_configuration_collect_logs` | **New** - Unified error collection (was controller_configuration_collect_logs) |

#### Data Variables

| Old Variable (hub_configuration) | New Variable (aap_configuration) | Notes |
|:--------------------------------|:----------------------------------|:-----|
| `ah_namespaces` | `hub_namespaces` | Renamed with `hub_` prefix |
| `ah_collections` | `hub_collections` | Renamed with `hub_` prefix |
| `ah_collection_remotes` | `hub_collection_remotes` | Renamed with `hub_` prefix |
| `ah_collection_repositories` | `hub_collection_repositories` | Renamed with `hub_` prefix |
| `ah_ee_registries` | `hub_ee_registries` | Renamed with `hub_` prefix |
| `ah_ee_repositories` | `hub_ee_repositories` | Renamed with `hub_` prefix |
| `ah_ee_images` | `hub_ee_images` | Renamed with `hub_` prefix |
| `ah_groups` | `aap_teams` | **Changed** - now shared with controller/gateway |
| `ah_group_roles` | `hub_group_roles` | Renamed with `hub_` prefix |
| `ah_roles` | `hub_roles` | Renamed with `hub_` prefix |
| `ah_users` | `aap_user_accounts` | **Changed** - now shared with controller/gateway |

### Hub Role-Specific Configuration Variables

Role-specific configuration variables follow this pattern:

**Old Format:**
```yaml
ah_configuration_<role>_<setting>
```

**New Format:**
```yaml
hub_configuration_<role>_<setting>  # Changed prefix from ah_ to hub_
```

However, these variables now reference the new global variables:

| Old Reference | New Reference |
|:--------------|:--------------|
| `ah_configuration_secure_logging` | `aap_configuration_secure_logging` |
| `ah_configuration_async_retries` | `aap_configuration_async_retries` |
| `ah_configuration_async_delay` | `aap_configuration_async_delay` |
| `ah_configuration_async_timeout` | `aap_configuration_async_timeout` |
| `ah_configuration_async_dir` | `aap_configuration_async_dir` |
| N/A | `aap_configuration_loop_delay` | **New** - Hub roles now support this in addition to async_timeout |

**Example:**
```yaml
# Old
ah_configuration_namespace_secure_logging: "{{ ah_configuration_secure_logging | default('false') }}"

# New
hub_configuration_namespace_secure_logging: "{{ aap_configuration_secure_logging | default('false') }}"
```

**Note**: Some Hub role-specific variables changed from `async_delay` to `loop_delay`. For example:
- Old: `ah_configuration_collection_repository_async_delay`
- New: `hub_configuration_collection_repository_loop_delay`

This change reflects that Hub roles now use `loop_delay` (in addition to `async_timeout`) for better control over task execution timing.

### Hub Dispatch Role Changes

**Old (hub_configuration):**
```yaml
ah_configuration_dispatcher_roles:
  - {role: group, var: ah_groups, tags: groups}
  - {role: user, var: ah_users, tags: users}
  - {role: namespace, var: ah_namespaces, tags: namespaces}
  - {role: collection, var: ah_collections, tags: collections}
  - {role: ee_registry, var: ah_ee_registries, tags: registries}
  - {role: ee_repository, var: ah_ee_repositories, tags: repos}
  - {role: ee_repository_sync, var: ah_ee_repository_sync, tags: reposync}
  - {role: ee_image, var: ah_ee_images, tags: images}
  - {role: ee_registry_index, var: ah_ee_registries, tags: indices}
  - {role: ee_registry_sync, var: ah_ee_registries, tags: regsync}
  - {role: collection_remote, var: ah_collection_remotes, tags: collectionremote}
  - {role: collection_repository, var: ah_collection_repositories, tags: collectionsrep}
  - {role: collection_repository_sync, var: ah_collection_repositories, tags: collectionsrepsync}
  - {role: group_roles, var: ah_group_roles, tags: group_roles}
```

**New (aap_configuration):**
```yaml
hub_configuration_dispatcher_roles:
  - role: hub_namespace
    var: hub_namespaces
  - role: hub_collection
    var: hub_collections
  - role: hub_ee_registry
    var: hub_ee_registries
  - role: hub_ee_repository
    var: hub_ee_repositories
  - role: hub_ee_repository_sync
    var: hub_ee_repository_sync
  - role: hub_ee_image
    var: hub_ee_images
  - role: hub_ee_registry
    var: hub_ee_registries
  - role: hub_ee_registry_index
    var: hub_ee_registries
  - role: hub_ee_registry_sync
    var: hub_ee_registries
  - role: hub_collection_remote
    var: hub_collection_remotes
  - role: hub_collection_repository
    var: hub_collection_repositories
  - role: hub_collection_repository_sync
    var: hub_collection_repositories
```

**Key Changes:**
- All roles now have `hub_` prefix
- `group` and `user` roles removed from dispatch (use shared `aap_teams` and `aap_user_accounts` variables)
- `ee_namespace`, `repository`, and `repository_sync` roles removed
- `offline_sync` role moved to `infra.aap_configuration_extended` collection
- Variable names changed from `ah_*` to `hub_*` or `aap_*` (for shared variables)

---

## Variable Name Changes

### Connection Variables

All connection variables have been unified to use the `aap_*` prefix:

#### Controller Connection Variables

| Old Variable Name (controller_configuration) | New Variable Name | Description |
|:----------------------------------------------|:------------------|:------------|
| `controller_hostname` | `aap_hostname` | URL to the Ansible Automation Platform Server |
| `controller_username` | `aap_username` | Admin User on the AAP Server |
| `controller_password` | `aap_password` | Platform Admin User's password |
| `controller_oauthtoken` | `aap_token` | Controller Admin User's token |
| `controller_validate_certs` | `aap_validate_certs` | Whether to validate SSL certificates (default: `true`) |
| `controller_request_timeout` | `aap_request_timeout` | Timeout in seconds for requests (default: `10`) |

#### EDA Connection Variables

| Old Variable Name (eda_configuration) | New Variable Name | Description |
|:--------------------------------------|:------------------|:------------|
| `eda_hostname` or `eda_host` | `aap_hostname` | URL to the Ansible Automation Platform Server |
| `eda_username` | `aap_username` | Admin User on the AAP Server |
| `eda_password` | `aap_password` | Platform Admin User's password |
| `eda_token` | `aap_token` | Platform Admin User's token |
| `eda_validate_certs` | `aap_validate_certs` | Whether to validate SSL certificates (default: `true`) |
| `eda_request_timeout` | `aap_request_timeout` | Timeout in seconds for requests (default: `10`) |

#### Hub Connection Variables

| Old Variable Name (hub_configuration) | New Variable Name | Description |
|:--------------------------------------|:------------------|:------------|
| `ah_hostname` or `galaxy_server` | `aap_hostname` | URL to the Ansible Automation Platform Server |
| `ah_username` | `aap_username` | Admin User on the AAP Server |
| `ah_password` | `aap_password` | Platform Admin User's password |
| `ah_token` or `ah_oauthtoken` or `galaxy_oauthtoken` | `aap_token` | Platform Admin User's token |
| `ah_validate_certs` | `aap_validate_certs` | Whether to validate SSL certificates (default: `true`) |
| `ah_path_prefix` | N/A | **Removed** - path prefix no longer needed |

**Note**: The new collection uses a single set of connection variables for all components (Controller, Hub, EDA, Gateway), eliminating the need for separate connection variables for each service. This simplifies configuration management significantly.

### Global Configuration Variables

Global configuration variables have been renamed from `controller_configuration_*` and `eda_configuration_*` to `aap_configuration_*`:

#### Controller Global Variables

| Old Variable Name (controller_configuration) | New Variable Name | Default Value | Description |
|:---------------------------------------------|:------------------|:--------------|:------------|
| `controller_configuration_enforce_defaults` | `aap_configuration_enforce_defaults` | `false` | Whether to enforce default option values |
| `controller_configuration_secure_logging` | `aap_configuration_secure_logging` | `false` | Whether to include sensitive values in logs |
| `controller_configuration_async_retries` | `aap_configuration_async_retries` | `50` (was `30`) | Number of retries for async tasks |
| `controller_configuration_async_delay` | `aap_configuration_async_delay` | `1` | Delay between retries (seconds) |
| `controller_configuration_loop_delay` | `aap_configuration_loop_delay` | `1000` | Loop delay for roles (milliseconds) |
| `controller_configuration_async_dir` | `aap_configuration_async_dir` | `null` | Directory for async task results |
| `controller_configuration_collect_logs` | `aap_configuration_collect_logs` | `false` | Whether to collect async task errors and continue |
| `controller_configuration_role_errors` | `aap_configuration_role_errors` | N/A | Variable containing collected errors (read-only) |

#### EDA Global Variables

| Old Variable Name (eda_configuration) | New Variable Name | Default Value | Description |
|:--------------------------------------|:------------------|:--------------|:------------|
| `eda_configuration_secure_logging` | `aap_configuration_secure_logging` | `false` | Whether to include sensitive values in logs |
| `eda_configuration_async_retries` | `aap_configuration_async_retries` | `50` | Number of retries for async tasks |
| `eda_configuration_async_delay` | `aap_configuration_async_delay` | `1` | Delay between retries (seconds) |
| `eda_configuration_async_dir` | `aap_configuration_async_dir` | `null` | Directory for async task results |

#### Hub Global Variables

| Old Variable Name (hub_configuration) | New Variable Name | Default Value | Description |
|:-------------------------------------|:------------------|:--------------|:------------|
| `ah_configuration_secure_logging` | `aap_configuration_secure_logging` | `false` | Whether to include sensitive values in logs |
| `ah_configuration_async_retries` | `aap_configuration_async_retries` | `50` | Number of retries for async tasks |
| `ah_configuration_async_delay` | `aap_configuration_async_delay` | `1` | Delay between retries (seconds) |
| `ah_configuration_async_timeout` | `aap_configuration_async_timeout` | `1000` | Async timeout (milliseconds) - **Note**: Still available but now uses `aap_configuration_*` prefix |
| `ah_configuration_async_dir` | `aap_configuration_async_dir` | `null` | Directory for async task results |

**Important**: 
- The default for `aap_configuration_async_retries` changed from `30` to `50` for controller roles
- EDA and Hub roles already used `50` as default, so no change for those roles
- All roles now reference the same global `aap_configuration_*` variables
- Hub roles now support `aap_configuration_loop_delay` (new) in addition to `async_timeout` (which they already had)
- `controller_configuration_collect_logs` renamed to `aap_configuration_collect_logs` (unified across all components)
- Error collection variable renamed from `controller_configuration_role_errors` to `aap_configuration_role_errors`

### Role-Specific Data Variables

Several role-specific data variables have been renamed to reflect their unified nature across AAP components. These variables were previously specific to individual roles or collections but are now shared across multiple components:

#### Controller Variables (Now Shared with Gateway)

| Old Variable Name | New Variable Name | Used By Roles |
|:------------------|:------------------|:--------------|
| `controller_organizations` | `aap_organizations` | `controller_organizations` / `gateway_organizations` |
| `controller_applications` | `aap_applications` | `controller_applications` / `gateway_applications` |
| `controller_user_accounts` | `aap_user_accounts` | `controller_users` / `gateway_users` / `hub_user` / `eda_users` |
| `controller_teams` | `aap_teams` | `controller_teams` / `gateway_teams` / `hub_group` |

#### Hub Variables (Now Shared)

| Old Variable Name | New Variable Name | Used By Roles |
|:------------------|:------------------|:--------------|
| `ah_users` | `aap_user_accounts` | `hub_user` / `controller_users` / `gateway_users` / `eda_users` |
| `ah_groups` | `aap_teams` | `hub_group` / `controller_teams` / `gateway_teams` |

#### EDA Variables (Now Shared)

| Old Variable Name | New Variable Name | Used By Roles |
|:------------------|:------------------|:--------------|
| `eda_users` | `aap_user_accounts` (or `eda_users` for EDA-specific) | `eda_users` / `controller_users` / `gateway_users` / `hub_user` |

**Important Notes**: 
- **Organizations, Applications, Users, and Teams** are now shared across Gateway, Controller, Hub, and EDA components
- This allows unified management of these entities across the entire AAP platform
- `aap_user_accounts` can be used by all user-related roles (controller, gateway, hub, eda)
- `aap_teams` can be used by all team/group-related roles (controller, gateway, hub)
- EDA users can optionally use `eda_users` for EDA-specific user management, but `aap_user_accounts` is preferred for unified management

### Role-Specific Configuration Variables

Role-specific configuration variables follow this pattern:

**Old Format:**
```yaml
controller_configuration_<role>_<setting>
```

**New Format:**
```yaml
controller_configuration_<role>_<setting>  # Still uses controller_configuration_ prefix
```

However, these variables now reference the new global variables:

| Old Reference | New Reference |
|:--------------|:--------------|
| `controller_configuration_secure_logging` | `aap_configuration_secure_logging` |
| `controller_configuration_async_retries` | `aap_configuration_async_retries` |
| `controller_configuration_async_delay` | `aap_configuration_async_delay` |
| `controller_configuration_loop_delay` | `aap_configuration_loop_delay` |
| `controller_configuration_enforce_defaults` | `aap_configuration_enforce_defaults` |
| `controller_configuration_async_dir` | `aap_configuration_async_dir` |
| `controller_configuration_collect_logs` | `aap_configuration_collect_logs` |
| `controller_configuration_role_errors` | `aap_configuration_role_errors` |

**Example:**
```yaml
# Old
controller_configuration_projects_secure_logging: "{{ controller_configuration_secure_logging | default('false') }}"

# New
controller_configuration_projects_secure_logging: "{{ aap_configuration_secure_logging | default('false') }}"
```

---

## Role Consolidations

### Organizations Role Consolidation

The `organizations` role functionality has been split and enhanced:

- **Old**: Single `organizations` role called twice in dispatch (once without assignments, once with)
- **New**: 
  - `gateway_organizations` - Creates organizations at the platform level
  - `controller_organizations` - Configures controller-specific organization settings
  - Both use the same `aap_organizations` variable

**Migration Note**: The dispatch role now calls `gateway_organizations` for organization creation, and `controller_organizations` is only called when assignments are needed.

### Groups Role Rename

- **Old**: `groups` role
- **New**: `controller_host_groups` role
- **Variable**: Still uses `controller_groups` (no change)

This rename makes it explicit that the role manages host groups within inventories.

### EDA Project Sync Consolidation

- **Old**: Separate `project_sync` role in `infra.eda_configuration`
- **New**: Project sync functionality integrated into `eda_projects` role
- **Variable**: Still uses `eda_projects` (no change)

**Migration Note**: The `project_sync` role functionality is now handled by the `eda_projects` role. You can still use the `sync` option within the `eda_projects` variable to trigger project synchronization.

---

## New Roles

The new collection includes roles for Gateway, Hub, and EDA components that were not present in the old collection.

### Gateway Roles

These roles manage the AAP Gateway (platform-level configuration):

| Role Name | Variable | Description |
|:----------|:---------|:------------|
| `gateway_authenticators` | `gateway_authenticators` | Manage authentication methods |
| `gateway_authenticator_maps` | `gateway_authenticator_maps` | Map authenticators to organizations |
| `gateway_settings` | `gateway_settings` | Platform-level settings |
| `gateway_applications` | `aap_applications` | Platform applications (shared with controller) |
| `gateway_http_ports` | `gateway_http_ports` | HTTP port configuration |
| `gateway_organizations` | `aap_organizations` | Platform organizations (shared with controller) |
| `gateway_service_nodes` | `gateway_service_nodes` | Service node configuration |
| `gateway_service_keys` | `gateway_service_keys` | Service key management |
| `gateway_service_clusters` | `gateway_service_clusters` | Service cluster configuration |
| `gateway_services` | `gateway_services` | Service definitions |
| `gateway_teams` | `aap_teams` | Platform teams (shared with controller) |
| `gateway_users` | `aap_user_accounts` | Platform users (shared with controller) |
| `gateway_role_definitions` | `gateway_role_definitions` | Role definitions |
| `gateway_role_team_assignments` | `gateway_role_team_assignments` | Team role assignments |
| `gateway_role_user_assignments` | `gateway_role_user_assignments` | User role assignments |
| `gateway_routes` | `gateway_routes` | Route configuration |

### Hub Roles

These roles manage Ansible Automation Hub. The Hub roles were previously in the separate `galaxy.galaxy` collection and have been integrated into `infra.aap_configuration`:

| Old Role Name (hub_configuration) | New Role Name (aap_configuration) | Variable | Notes |
|:-----------------------------------|:-----------------------------------|:---------|:------|
| `namespace` | `hub_namespace` | `hub_namespaces` | Renamed with `hub_` prefix |
| `collection` | `hub_collection` | `hub_collections` | Renamed with `hub_` prefix |
| `collection_remote` | `hub_collection_remote` | `hub_collection_remotes` | Renamed with `hub_` prefix |
| `collection_repository` | `hub_collection_repository` | `hub_collection_repositories` | Renamed with `hub_` prefix |
| `collection_repository_sync` | `hub_collection_repository_sync` | `hub_collection_repositories` | Renamed with `hub_` prefix |
| `ee_registry` | `hub_ee_registry` | `hub_ee_registries` | Renamed with `hub_` prefix |
| `ee_registry_index` | `hub_ee_registry_index` | `hub_ee_registries` | Renamed with `hub_` prefix |
| `ee_registry_sync` | `hub_ee_registry_sync` | `hub_ee_registries` | Renamed with `hub_` prefix |
| `ee_repository` | `hub_ee_repository` | `hub_ee_repositories` | Renamed with `hub_` prefix |
| `ee_repository_sync` | `hub_ee_repository_sync` | `hub_ee_repository_sync` | Renamed with `hub_` prefix |
| `ee_image` | `hub_ee_image` | `hub_ee_images` | Renamed with `hub_` prefix |
| `ee_namespace` | N/A | N/A | **Removed** - functionality consolidated |
| `group` | `hub_group` | `aap_teams` | Renamed; variable changed to shared `aap_teams` |
| `group_roles` | `hub_group_roles` | `hub_group_roles` | Renamed with `hub_` prefix |
| `role` | `hub_role` | `hub_roles` | Renamed with `hub_` prefix |
| `user` | `hub_user` | `aap_user_accounts` | Renamed; variable changed to shared `aap_user_accounts` |
| `publish` | `hub_publish` | `hub_publish` | Renamed with `hub_` prefix |
| `ansible_config` | `ansible_config` | N/A | **No change** - same role name |
| `repository` | N/A | N/A | **Removed** - not in new collection |
| `repository_sync` | N/A | N/A | **Removed** - not in new collection |
| `offline_sync` | `infra.aap_configuration_extended.offline_sync` | N/A | **Moved** - now in extended collection |

**Key Changes:**
- All Hub roles now have the `hub_` prefix for consistency
- `group` role variable changed to `aap_teams` (shared with controller/gateway)
- `user` role variable changed to `aap_user_accounts` (shared with controller/gateway)
- `ee_namespace` role removed (functionality likely consolidated)
- `repository` and `repository_sync` roles removed (may have been for collections)
- `offline_sync` role moved to `infra.aap_configuration_extended` collection

### EDA Roles

These roles manage Event-Driven Ansible. The EDA roles were previously in the separate `infra.eda_configuration` collection and have been integrated into `infra.aap_configuration`:

| Old Role Name (eda_configuration) | New Role Name (aap_configuration) | Variable | Notes |
|:----------------------------------|:-----------------------------------|:---------|:------|
| `credential` | `eda_credentials` | `eda_credentials` | Renamed with `eda_` prefix |
| N/A | `eda_credential_types` | `eda_credential_types` | **New role** - credential types management |
| `decision_environment` | `eda_decision_environments` | `eda_decision_environments` | Renamed with `eda_` prefix |
| N/A | `eda_event_streams` | `eda_event_streams` | **New role** - event streams management |
| `project` | `eda_projects` | `eda_projects` | Renamed with `eda_` prefix |
| `project_sync` | `eda_projects` | `eda_projects` | **Consolidated** - sync functionality integrated |
| `rulebook_activation` | `eda_rulebook_activations` | `eda_rulebook_activations` | Renamed with `eda_` prefix |
| `user` | `eda_users` | `aap_user_accounts` | Renamed; variable changed to shared `aap_user_accounts` |
| `user_token` | `eda_controller_tokens` | `eda_controller_tokens` | **Renamed** - now called `controller_tokens` |

**Key Changes:**
- All EDA roles now have the `eda_` prefix for consistency
- `user_token` role renamed to `eda_controller_tokens` (more descriptive)
- `user` role variable changed to `aap_user_accounts` (shared with controller/gateway)
- `project_sync` role functionality consolidated into `eda_projects`
- New roles added: `eda_credential_types` and `eda_event_streams`

### Other New Roles

| Role Name | Description |
|:----------|:------------|
| `ansible_config` | Ansible configuration management |

---

## Removed/Moved Roles

### Roles Moved to Extended Collection

The following roles were removed from the old collections and moved to the [extended collection](https://github.com/redhat-cop/aap_configuration_extended) (`infra.aap_configuration_extended`):

| Removed Role | Old Collection | Reason | Alternative |
|:-------------|:---------------|:-------|:------------|
| `filetree_create` | `infra.controller_configuration` | Not creating/managing AAP objects | Use `infra.aap_configuration_extended.filetree_create` |
| `filetree_read` | `infra.controller_configuration` | Not creating/managing AAP objects | Use `infra.aap_configuration_extended.filetree_read` |
| `object_diff` | `infra.controller_configuration` | Not creating/managing AAP objects | Use `infra.aap_configuration_extended.object_diff` |
| `offline_sync` | `galaxy.galaxy` | Not creating/managing AAP objects | Use `infra.aap_configuration_extended.offline_sync` |

**Note**: These roles are utility roles that don't directly create or manage objects on AAP, so they were moved to the extended collection to keep the main collection focused on configuration management.

### EDA Roles Consolidated

| Removed Role | Collection | Status | Notes |
|:-------------|:-----------|:-------|:------|
| `project_sync` | `eda_configuration` | **Consolidated** | Functionality integrated into `eda_projects` role |
| `dispatch` | `eda_configuration` | **Replaced** | Use main `dispatch` role which handles all components |

**Note**: The EDA `dispatch` role from `infra.eda_configuration` is no longer needed. The main `dispatch` role in `infra.aap_configuration` handles Gateway, Hub, Controller, and EDA roles in the correct order.

### Hub Roles Removed/Consolidated

| Removed Role | Collection | Status | Notes |
|:-------------|:-----------|:-------|:------|
| `ee_namespace` | `galaxy.galaxy` | **Removed** | Functionality likely consolidated into other roles |
| `repository` | `galaxy.galaxy` | **Removed** | Not present in new collection |
| `repository_sync` | `galaxy.galaxy` | **Removed** | Not present in new collection |
| `offline_sync` | `galaxy.galaxy` | **Moved** | Now in `infra.aap_configuration_extended` collection |
| `dispatch` | `galaxy.galaxy` | **Replaced** | Use main `dispatch` role which handles all components |

**Note**: The Hub `dispatch` role from `galaxy.galaxy` is no longer needed. The main `dispatch` role in `infra.aap_configuration` handles Gateway, Hub, Controller, and EDA roles in the correct order.

---

## Extended Collection (`infra.aap_configuration_extended`)

The `infra.aap_configuration_extended` collection extends the functionality of `infra.aap_configuration` by providing advanced operations and utility roles for Ansible Automation Platform Configuration as Code. This collection is designed to work alongside `infra.aap_configuration` and provides additional capabilities for file tree management, object comparison, validation, and configuration upgrades.

### Collection Information

- **Collection Name**: `infra.aap_configuration_extended`
- **Purpose**: Extended functionality for AAP Configuration as Code
- **Dependencies**: Requires `infra.aap_configuration` (and its dependencies: `ansible.platform`, `ansible.hub`, `ansible.controller`, `ansible.eda`)
- **Repository**: [https://github.com/redhat-cop/aap_configuration_extended](https://github.com/redhat-cop/aap_configuration_extended)

### Roles in Extended Collection

#### Roles Moved from Old Collections

| Role Name | Old Collection | Description |
|:----------|:---------------|:------------|
| `filetree_create` | `infra.controller_configuration` | Creates a hierarchical directory structure from AAP object definitions |
| `filetree_read` | `infra.controller_configuration` | Reads variables from a hierarchical directory structure |
| `object_diff` | `infra.controller_configuration` | Compares AAP objects between current state and desired state |
| `offline_sync` | `galaxy.galaxy` | Offline synchronization of collections to Automation Hub or Galaxy |

#### New Roles

| Role Name | Description |
|:----------|:------------|
| `aap_rules_validation` | Validates AAP configuration against custom rules (e.g., naming conventions, required fields) |
| `upgrade_config` | Upgrades configuration from older collection formats to newer formats |

### Installation

Add the extended collection to your `requirements.yml`:

```yaml
collections:
  - name: ansible.platform
  - name: ansible.hub
  - name: ansible.controller
    version: ">=4.6.0"
  - name: ansible.eda
  - name: infra.aap_configuration
  - name: infra.aap_configuration_extended  # Extended collection
```

Install with:
```bash
ansible-galaxy collection install -r requirements.yml
```

### Variable Compatibility

The extended collection uses the same connection variables as `infra.aap_configuration`:

- **Connection Variables**: Uses `aap_*` prefix (e.g., `aap_hostname`, `aap_username`, `aap_password`, `aap_token`, `aap_validate_certs`)
- **Data Variables**: Uses the same variable names as the main collection (e.g., `aap_organizations`, `controller_projects`, `hub_namespaces`, `eda_projects`)
- **Configuration Variables**: Some roles may use `controller_configuration_*` or `hub_configuration_*` prefixes for role-specific settings, but they reference the global `aap_configuration_*` variables

### Usage Examples

#### Using `filetree_create`

```yaml
- name: Create file tree structure
  hosts: localhost
  collections:
    - infra.aap_configuration_extended
  roles:
    - role: infra.aap_configuration_extended.filetree_create
      vars:
        aap_organizations:
          - name: Production
        controller_projects:
          - name: MyProject
            organization: Production
        output_path: "/tmp/filetree_output"
```

#### Using `filetree_read`

```yaml
- name: Read file tree structure
  hosts: localhost
  collections:
    - infra.aap_configuration_extended
  roles:
    - role: infra.aap_configuration_extended.filetree_read
      vars:
        orgs: Production
        dir_orgs_vars: "/path/to/config"
        env: prod
```

#### Using `object_diff`

```yaml
- name: Compare AAP objects
  hosts: localhost
  collections:
    - infra.aap_configuration_extended
  roles:
    - role: infra.aap_configuration_extended.object_diff
      vars:
        aap_organizations:
          - name: Production
        controller_projects:
          - name: MyProject
```

#### Using `offline_sync`

```yaml
- name: Sync collections offline
  hosts: localhost
  collections:
    - infra.aap_configuration_extended
  roles:
    - role: infra.aap_configuration_extended.offline_sync
      vars:
        aap_hostname: hub.example.com
        aap_username: admin
        aap_password: "{{ vault_password }}"
        hub_configuration_working_dir: /var/tmp/hub_offline_sync
```

#### Using `aap_rules_validation`

```yaml
- name: Validate AAP configuration
  hosts: localhost
  collections:
    - infra.aap_configuration_extended
  roles:
    - role: infra.aap_configuration_extended.aap_rules_validation
      vars:
        aap_rules:
          - name: "Project naming convention"
            type: projects
            rule: "name must match pattern '^[a-z0-9-]+$'"
        aap_organizations:
          - name: Production
        controller_projects:
          - name: my-project
```

### Migration from Old Collections

If you were using these roles from the old collections, update your playbooks:

**Old (Controller):**
```yaml
- role: infra.controller_configuration.filetree_create
- role: infra.controller_configuration.filetree_read
- role: infra.controller_configuration.object_diff
```

**Old (Hub):**
```yaml
- role: galaxy.galaxy.offline_sync
```

**New:**
```yaml
- role: infra.aap_configuration_extended.filetree_create
- role: infra.aap_configuration_extended.filetree_read
- role: infra.aap_configuration_extended.object_diff
- role: infra.aap_configuration_extended.offline_sync
```

**Note**: The variable names used by these roles remain largely the same, but you should update connection variables to use the `aap_*` prefix instead of `controller_*` or `ah_*` prefixes.

### Key Features

1. **File Tree Management**: `filetree_create` and `filetree_read` enable hierarchical organization of configuration files, supporting multi-environment and multi-organization setups
2. **Object Comparison**: `object_diff` helps identify differences between desired and current AAP state
3. **Offline Operations**: `offline_sync` enables collection synchronization without direct API access
4. **Configuration Validation**: `aap_rules_validation` provides custom rule validation for configuration compliance
5. **Configuration Upgrades**: `upgrade_config` assists in migrating from older collection formats

### Additional Resources

- [Extended Collection README](https://github.com/redhat-cop/aap_configuration_extended/blob/devel/README.md)
- [Extended Collection Conversion Guide](https://github.com/redhat-cop/aap_configuration_extended/blob/devel/docs/CONVERSION_GUIDE.md)
- [Automate the Automation Guide](https://github.com/redhat-cop/aap_configuration_extended/blob/devel/roles/filetree_create/automatetheautomation.md)

---

## Dispatch Role Changes

### Execution Order

The dispatch role now executes roles in a specific order across all AAP components:

1. **Gateway roles** - Platform-level configuration
2. **Hub roles** - Automation Hub configuration
3. **Controller roles** - Controller configuration
4. **EDA roles** - Event-Driven Ansible configuration

### Dispatch Configuration

**Old Dispatch Structure:**
```yaml
controller_configuration_dispatcher_roles:
  - role: organizations
    var: controller_organizations
    # ... called twice with different flags
```

**New Dispatch Structure:**
```yaml
gateway_configuration_dispatcher_roles:
  - role: gateway_organizations
    var: aap_organizations
    # ...

hub_configuration_dispatcher_roles:
  - role: hub_namespace
    var: hub_namespaces
    # ...

controller_configuration_dispatcher_roles:
  - role: controller_organizations
    var: aap_organizations
    # ...

eda_configuration_dispatcher_roles:
  - role: eda_credential_types
    var: eda_credential_types
    # ...

aap_configuration_dispatcher_roles: >
  {{ gateway_configuration_dispatcher_roles
   + hub_configuration_dispatcher_roles
   + controller_configuration_dispatcher_roles
   + eda_configuration_dispatcher_roles }}
```

### Key Changes in Dispatch

1. **Organizations**: Now handled by `gateway_organizations` for creation, `controller_organizations` only for assignments
2. **New Variable**: `dispatch_include_wildcard_vars` (default: `false`)
3. **Roles Order**: Gateway → Hub → Controller → EDA
4. **Unified Variables**: Organizations, applications, users, and teams are now shared between gateway, controller, Hub, and EDA roles
5. **New Global Variables**: `aap_configuration_collect_logs` and `aap_configuration_loop_delay` added

---

## Step-by-Step Migration Guide

### Step 1: Update Collection Dependencies

**Old `requirements.yml` (if using all three collections):**
```yaml
collections:
  - name: ansible.controller
    version: '>=4.5.0,<4.6.0'
  - name: infra.controller_configuration
  - name: infra.eda_configuration  # If using EDA
  - name: galaxy.galaxy  # If using Hub
```

**New `requirements.yml`:**
```yaml
collections:
  - name: ansible.platform
  - name: ansible.hub
  - name: ansible.controller
    version: ">=4.6.0"
  - name: ansible.eda
  - name: infra.aap_configuration  # Replaces controller_configuration, eda_configuration, and galaxy.galaxy
```

### Step 2: Update Connection Variables

**Old `controller_configs/controller_auth.yml`:**
```yaml
controller_hostname: ansible-controller.example.com
controller_username: admin
controller_password: "{{ vault_controller_password }}"
controller_oauthtoken: "{{ vault_controller_token }}"
controller_validate_certs: true
controller_request_timeout: 10
```

**Old `eda_configs/eda_auth.yml` (if using EDA):**
```yaml
eda_hostname: ansible-eda.example.com
eda_username: admin
eda_password: "{{ vault_eda_password }}"
eda_token: "{{ vault_eda_token }}"
eda_validate_certs: true
eda_request_timeout: 10
```

**Old `ah_configs/ah_auth.yml` (if using Hub):**
```yaml
ah_hostname: ansible-hub.example.com
ah_username: admin
ah_password: "{{ vault_ah_password }}"
ah_token: "{{ vault_ah_token }}"
ah_validate_certs: true
ah_path_prefix: 'galaxy'
```

**New `aap_configs/auth.yml` (unified for all components):**
```yaml
aap_hostname: aap.example.com
aap_username: admin
aap_password: "{{ vault_aap_password }}"
aap_token: "{{ vault_aap_token }}"
aap_validate_certs: true
aap_request_timeout: 10
```

**Note**: If you were using separate authentication files for Controller, EDA, and Hub, you can now consolidate them into a single file since all components use the same connection variables. The `ah_path_prefix` variable is no longer needed.

### Step 3: Update Global Configuration Variables

**Old (Controller):**
```yaml
controller_configuration_secure_logging: false
controller_configuration_async_retries: 30
controller_configuration_async_delay: 1
controller_configuration_loop_delay: 1000
controller_configuration_enforce_defaults: false
```

**Old (EDA):**
```yaml
eda_configuration_secure_logging: false
eda_configuration_async_retries: 50
eda_configuration_async_delay: 1
```

**Old (Hub):**
```yaml
ah_configuration_secure_logging: false
ah_configuration_async_retries: 50
ah_configuration_async_delay: 1
ah_configuration_async_timeout: 1000
```

**New (unified for all components):**
```yaml
aap_configuration_secure_logging: false
aap_configuration_async_retries: 50  # Note: default changed from 30 to 50 for controller
aap_configuration_async_delay: 1
aap_configuration_loop_delay: 1000
aap_configuration_async_timeout: 1000  # Still available for Hub roles
aap_configuration_enforce_defaults: false
aap_configuration_collect_logs: false  # Changed from controller_configuration_collect_logs
```

**Note**: If you were using separate configuration variables for Controller, EDA, and Hub, you can now consolidate them into a single set of global variables. The `aap_configuration_collect_logs` variable (previously `controller_configuration_collect_logs`) enables collecting async task errors across all roles.

### Step 4: Update Role Names in Playbooks

**Old Playbook (Controller):**
```yaml
- name: Configure Controller
  hosts: localhost
  roles:
    - role: infra.controller_configuration.organizations
    - role: infra.controller_configuration.projects
    - role: infra.controller_configuration.users
```

**Old Playbook (EDA):**
```yaml
- name: Configure EDA
  hosts: localhost
  roles:
    - role: infra.eda_configuration.user
    - role: infra.eda_configuration.credential
    - role: infra.eda_configuration.project
    - role: infra.eda_configuration.project_sync
```

**Old Playbook (Hub):**
```yaml
- name: Configure Hub
  hosts: localhost
  roles:
    - role: galaxy.galaxy.namespace
    - role: galaxy.galaxy.collection
    - role: galaxy.galaxy.user
    - role: galaxy.galaxy.group
```

**New Playbook (unified):**
```yaml
- name: Configure AAP
  hosts: localhost
  roles:
    # Controller roles
    - role: infra.aap_configuration.gateway_organizations
    - role: infra.aap_configuration.controller_projects
    - role: infra.aap_configuration.controller_users
    # Hub roles
    - role: infra.aap_configuration.hub_namespace
    - role: infra.aap_configuration.hub_collection
    - role: infra.aap_configuration.hub_user
    - role: infra.aap_configuration.hub_group
    # EDA roles
    - role: infra.aap_configuration.eda_users
    - role: infra.aap_configuration.eda_credentials
    - role: infra.aap_configuration.eda_projects
    # Note: project_sync is now part of eda_projects
```

### Step 5: Update Data Variables

**Old Variables (Controller):**
```yaml
controller_organizations:
  - name: Production
    description: Production organization

controller_applications:
  - name: MyApp
    organization: Production

controller_user_accounts:
  - username: jdoe
    email: jdoe@example.com

controller_teams:
  - name: DevOps
    organization: Production
```

**Old Variables (EDA):**
```yaml
eda_users:
  - username: eda_user
    email: eda_user@example.com

eda_credentials:
  - name: eda_credential
    credential_type: ansible_galaxy_token

eda_projects:
  - name: my_eda_project
    url: https://github.com/example/rulebook.git
    sync: true

eda_user_tokens:
  - name: my_token
    user: eda_user
```

**Old Variables (Hub):**
```yaml
ah_namespaces:
  - name: my_namespace
    company: MyCompany

ah_collections:
  - namespace: my_namespace
    name: my_collection
    version: 1.0.0

ah_users:
  - username: hub_user
    email: hub_user@example.com

ah_groups:
  - name: hub_group
    perms: []
```

**New Variables (unified):**
```yaml
# Controller/Gateway shared variables
aap_organizations:  # Changed from controller_organizations
  - name: Production
    description: Production organization

aap_applications:  # Changed from controller_applications
  - name: MyApp
    organization: Production

aap_user_accounts:  # Changed from controller_user_accounts and eda_users
  - username: jdoe
    email: jdoe@example.com

aap_teams:  # Changed from controller_teams
  - name: DevOps
    organization: Production

# EDA-specific variables (mostly unchanged)
eda_credentials:  # No change
  - name: eda_credential
    credential_type: ansible_galaxy_token

eda_projects:  # No change, but project_sync functionality integrated
  - name: my_eda_project
    url: https://github.com/example/rulebook.git
    sync: true  # Sync functionality now part of eda_projects

eda_controller_tokens:  # Changed from eda_user_tokens
  - name: my_token
    user: eda_user

# Hub variables (mostly renamed with hub_ prefix)
hub_namespaces:  # Changed from ah_namespaces
  - name: my_namespace
    company: MyCompany

hub_collections:  # Changed from ah_collections
  - namespace: my_namespace
    name: my_collection
    version: 1.0.0

# Note: ah_users and ah_groups now use shared variables
```

**Note**: 
- EDA users can now use `aap_user_accounts` (shared) or `eda_users` (EDA-specific)
- Hub users and groups now use `aap_user_accounts` and `aap_teams` (shared with controller/gateway)
- `eda_user_tokens` variable renamed to `eda_controller_tokens`
- `project_sync` role removed; use `sync: true` in `eda_projects` instead
- Hub variables renamed from `ah_*` to `hub_*` prefix
- `ah_path_prefix` variable removed (no longer needed)

### Step 6: Update Dispatch Usage

**Old:**
```yaml
- name: Configure Controller
  hosts: localhost
  roles:
    - role: infra.controller_configuration.dispatch
```

**New:**
```yaml
- name: Configure AAP
  hosts: localhost
  roles:
    - role: infra.aap_configuration.dispatch
```

The dispatch role will automatically handle Gateway, Hub, Controller, and EDA roles in the correct order.

### Step 7: Update Collection References

**Old:**
```yaml
collections:
  - infra.controller_configuration
```

**New:**
```yaml
collections:
  - infra.aap_configuration
```

### Step 8: Handle Removed/Consolidated Roles

#### Removed Roles (Moved to Extended Collection)

If you were using `filetree_create`, `filetree_read`, `object_diff`, or `offline_sync`:

1. Install the extended collection:
```yaml
collections:
  - name: infra.aap_configuration_extended
```

2. Update role references:
```yaml
# Old (Controller roles)
- role: infra.controller_configuration.filetree_create
- role: infra.controller_configuration.filetree_read
- role: infra.controller_configuration.object_diff

# Old (Hub role)
- role: galaxy.galaxy.offline_sync

# New
- role: infra.aap_configuration_extended.filetree_create
- role: infra.aap_configuration_extended.filetree_read
- role: infra.aap_configuration_extended.object_diff
- role: infra.aap_configuration_extended.offline_sync
```

**Note**: The extended collection uses the same connection variables (`aap_*`) and data variables as the main collection, so you only need to update the role references and collection name.

#### Consolidated EDA Roles

If you were using `project_sync` from `infra.eda_configuration`:

**Old:**
```yaml
- role: infra.eda_configuration.project
  vars:
    eda_projects:
      - name: my_project
        url: https://github.com/example/rulebook.git

- role: infra.eda_configuration.project_sync
  vars:
    eda_projects:
      - name: my_project
        sync: true
```

**New:**
```yaml
- role: infra.aap_configuration.eda_projects
  vars:
    eda_projects:
      - name: my_project
        url: https://github.com/example/rulebook.git
        sync: true  # Sync functionality now integrated
```

If you were using the EDA or Hub `dispatch` role:

**Old (EDA):**
```yaml
- role: infra.eda_configuration.dispatch
```

**Old (Hub):**
```yaml
- role: galaxy.galaxy.dispatch
```

**New:**
```yaml
- role: infra.aap_configuration.dispatch
# The main dispatch role now handles Gateway, Hub, Controller, and EDA in the correct order
```

### Step 9: Test Migration

1. **Backup your current configuration**
2. **Test with a small subset** of your configuration first
3. **Verify organization creation** works with `gateway_organizations`
4. **Check that shared variables** (`aap_organizations`, `aap_applications`, etc.) work correctly
5. **Validate async retries** - you may need to adjust if you were relying on the old default of 30

---

## Variable Mapping Reference

### Quick Reference Table

| Category | Old Variable | New Variable |
|:---------|:-------------|:-------------|
| **Connection (Controller)** | `controller_hostname` | `aap_hostname` |
| | `controller_username` | `aap_username` |
| | `controller_password` | `aap_password` |
| | `controller_oauthtoken` | `aap_token` |
| | `controller_validate_certs` | `aap_validate_certs` |
| | `controller_request_timeout` | `aap_request_timeout` |
| **Connection (EDA)** | `eda_hostname` / `eda_host` | `aap_hostname` |
| | `eda_username` | `aap_username` |
| | `eda_password` | `aap_password` |
| | `eda_token` | `aap_token` |
| | `eda_validate_certs` | `aap_validate_certs` |
| | `eda_request_timeout` | `aap_request_timeout` |
| **Global Config (Controller)** | `controller_configuration_secure_logging` | `aap_configuration_secure_logging` |
| | `controller_configuration_async_retries` | `aap_configuration_async_retries` (default: 50) |
| | `controller_configuration_async_delay` | `aap_configuration_async_delay` |
| | `controller_configuration_loop_delay` | `aap_configuration_loop_delay` |
| | `controller_configuration_enforce_defaults` | `aap_configuration_enforce_defaults` |
| | `controller_configuration_async_dir` | `aap_configuration_async_dir` |
| | `controller_configuration_collect_logs` | `aap_configuration_collect_logs` |
| | `controller_configuration_role_errors` | `aap_configuration_role_errors` |
| **Global Config (EDA)** | `eda_configuration_secure_logging` | `aap_configuration_secure_logging` |
| | `eda_configuration_async_retries` | `aap_configuration_async_retries` |
| | `eda_configuration_async_delay` | `aap_configuration_async_delay` |
| | `eda_configuration_async_dir` | `aap_configuration_async_dir` |
| **Global Config (Hub)** | `ah_configuration_secure_logging` | `aap_configuration_secure_logging` |
| | `ah_configuration_async_retries` | `aap_configuration_async_retries` |
| | `ah_configuration_async_delay` | `aap_configuration_async_delay` |
| | `ah_configuration_async_timeout` | `aap_configuration_async_timeout` |
| | `ah_configuration_async_dir` | `aap_configuration_async_dir` |
| | N/A | `aap_configuration_loop_delay` (new for Hub) |
| | N/A | `aap_configuration_collect_logs` (unified) |
| **Data Variables** | `controller_organizations` | `aap_organizations` |
| | `controller_applications` | `aap_applications` |
| | `controller_user_accounts` | `aap_user_accounts` |
| | `controller_teams` | `aap_teams` |
| | `controller_projects` | `controller_projects` (no change) |
| | `controller_inventories` | `controller_inventories` (no change) |
| | `controller_credentials` | `controller_credentials` (no change) |
| | `controller_templates` | `controller_templates` (no change) |
| | `controller_workflows` | `controller_workflows` (no change) |
| | `controller_notifications` | `controller_notifications` (no change) |
| | `controller_launch_jobs` | `controller_launch_jobs` (no change) |
| | `controller_workflow_launch_jobs` | `controller_workflow_launch_jobs` (no change) |
| | `controller_bulk_hosts` | `controller_bulk_hosts` (no change) |
| **EDA Variables** | `eda_users` | `aap_user_accounts` or `eda_users` |
| | `eda_user_tokens` | `eda_controller_tokens` |
| | `eda_credentials` | `eda_credentials` (no change) |
| | `eda_projects` | `eda_projects` (no change, sync integrated) |
| | `eda_decision_environments` | `eda_decision_environments` (no change) |
| | `eda_rulebook_activations` | `eda_rulebook_activations` (no change) |
| **Hub Variables** | `ah_namespaces` | `hub_namespaces` |
| | `ah_collections` | `hub_collections` |
| | `ah_collection_remotes` | `hub_collection_remotes` |
| | `ah_collection_repositories` | `hub_collection_repositories` |
| | `ah_ee_registries` | `hub_ee_registries` |
| | `ah_ee_repositories` | `hub_ee_repositories` |
| | `ah_ee_images` | `hub_ee_images` |
| | `ah_groups` | `aap_teams` |
| | `ah_group_roles` | `hub_group_roles` |
| | `ah_roles` | `hub_roles` |
| | `ah_users` | `aap_user_accounts` |

### Role-Specific Variable Pattern

For role-specific configuration variables, the pattern remains the same, but they reference the new global variables:

**Pattern:**
```yaml
controller_configuration_<role_name>_<setting>: "{{ aap_configuration_<setting> | default('...') }}"
```

**Examples:**
- `controller_configuration_projects_secure_logging` → references `aap_configuration_secure_logging`
- `controller_configuration_organizations_async_retries` → references `aap_configuration_async_retries`
- `controller_configuration_users_loop_delay` → references `aap_configuration_loop_delay`

---

## Common Migration Issues and Solutions

### Issue 1: Organizations Not Created

**Problem**: Organizations are not being created after migration.

**Solution**: Ensure you're using `gateway_organizations` role (or dispatch) and the `aap_organizations` variable. The old `controller_organizations` variable no longer exists.

### Issue 2: Async Task Failures

**Problem**: More async task failures after migration.

**Solution**: The default `aap_configuration_async_retries` changed from 30 to 50. If you were relying on the old default, you may need to explicitly set it:
```yaml
aap_configuration_async_retries: 30  # If you need the old behavior
```

### Issue 3: Missing Roles

**Problem**: Roles like `filetree_create`, `filetree_read`, `object_diff`, or `offline_sync` are not found.

**Solution**: These roles were moved to the extended collection. Install `infra.aap_configuration_extended` and update your role references. See the [Extended Collection](#extended-collection-infraaap_configuration_extended) section for details.

### Issue 4: Variable Not Found Errors

**Problem**: Errors about `controller_configuration_*` variables not being defined.

**Solution**: Update all references to use `aap_configuration_*` for global variables. Role-specific variables still use `controller_configuration_*` prefix but reference the new global variables.

### Issue 5: Dispatch Not Running All Roles

**Problem**: Some roles are not being executed by dispatch.

**Solution**: Check that you're defining the correct variable names. Dispatch skips roles if their associated variable is not defined. Also ensure you're using the new variable names (`aap_organizations` instead of `controller_organizations`, etc.).

---

## Additional Resources

- [Official Conversion Guide](https://github.com/redhat-cop/infra.aap_configuration/blob/devel/docs/CONVERSION_GUIDE.md) - Main conversion guide from the new collection
- [Tower Conversion Guide](https://github.com/redhat-cop/infra.aap_configuration/blob/devel/docs/TOWER_CONVERSION_GUIDE.md) - For migrating from Tower to Controller/AAP
- [Getting Started Guide](https://github.com/redhat-cop/infra.aap_configuration/blob/devel/docs/GETTING_STARTED.md)
- [Dispatch Role Documentation](https://github.com/redhat-cop/infra.aap_configuration/blob/devel/roles/dispatch/README.md)
- [Extended Collection](https://github.com/redhat-cop/aap_configuration_extended)
- [Old Controller Configuration Conversion Guide](https://github.com/redhat-cop/infra.controller_configuration/blob/devel/docs/CONVERSION_GUIDE.md) - For reference on Tower → Controller migration

---

## Summary

The migration from `infra.controller_configuration`, `infra.eda_configuration`, and `galaxy.galaxy` to `infra.aap_configuration` involves:

1. **Collection consolidation**: 
   - `infra.controller_configuration` → `infra.aap_configuration`
   - `infra.eda_configuration` → `infra.aap_configuration` (consolidated)
   - `galaxy.galaxy` → `infra.aap_configuration` (consolidated)
2. **Role name changes**: 
   - Controller roles prefixed with `controller_`
   - EDA roles prefixed with `eda_`
3. **Variable unification**: 
   - Connection variables unified to `aap_*` prefix (from `controller_*`, `eda_*`, and `ah_*`)
   - Global variables unified to `aap_configuration_*` (from `controller_configuration_*`, `eda_configuration_*`, and `ah_configuration_*`)
4. **Shared variables**: Organizations, applications, users, and teams now shared between gateway, controller, Hub, and EDA
5. **New capabilities**: Gateway roles added, Hub and EDA roles enhanced
6. **Role consolidation**: 
   - Some roles consolidated (e.g., `project_sync` into `eda_projects`)
   - Utility roles moved to `infra.aap_configuration_extended` collection
7. **New EDA roles**: `eda_credential_types` and `eda_event_streams` added
8. **EDA role renames**: `user_token` → `eda_controller_tokens`
9. **Dispatch changes**: New execution order (Gateway → Hub → Controller → EDA) and unified structure
10. **Extended collection**: Utility roles (`filetree_create`, `filetree_read`, `object_diff`, `offline_sync`) and new roles (`aap_rules_validation`, `upgrade_config`) available in `infra.aap_configuration_extended`

The new collection provides a unified approach to managing all components of AAP 2.5+ (Controller, Hub, Gateway, and EDA), with consistent variable naming and role organization. This eliminates the need to manage three separate collections (`infra.controller_configuration`, `infra.eda_configuration`, and `galaxy.galaxy`) and separate connection variables for different AAP components. All components now use the same connection variables (`aap_*`) and global configuration variables (`aap_configuration_*`), significantly simplifying configuration management.

**Extended Collection**: The `infra.aap_configuration_extended` collection provides additional utility roles for advanced operations like file tree management, object comparison, offline synchronization, configuration validation, and configuration upgrades. These roles use the same connection and data variables as the main collection, ensuring seamless integration.

---

*Last Updated: Based on collection versions as of the analysis date*
