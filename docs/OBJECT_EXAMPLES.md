# Object Examples

One working example of every object type this project can import, grouped by AAP component. Copy an example into your workspace, change the names, and import.

The examples build on each other: a single fictional organization, `Network Team`, with its own project, inventory, credentials and job templates. Names that refer to another object (for example `project: Network Playbooks`) point at an object defined elsewhere on this page.

* [Before you start](#before-you-start)
* [Shared platform objects](#shared-platform-objects)
* [Automation Controller](#automation-controller)
* [Platform Gateway (AAP 2.5+)](#platform-gateway-aap-25)
* [Event-Driven Ansible (AAP 2.5+)](#event-driven-ansible-aap-25)
* [Automation Hub (AAP 2.5+)](#automation-hub-aap-25)

---

## Before you start

* **Paths.** Each example shows a suggested file path relative to the workspace (`orgs_vars/<workspace>/`). Use `common/` for configuration shared by every environment, or `<env>/imports/` for configuration that belongs to one environment. Import reads both (see [Common vs. imports](CONCEPTS.md#common-vs-imports)).
* **The top-level key matters, the file name doesn't.** Keys and folders for every type are listed in the [Object Reference](FOLDER_LAYOUT.md#object-type-reference). Watch for the keys that differ from their folder name: `controller_templates`, `controller_workflows` and `controller_notifications`.
* **Minimal, not complete.** The examples show the common fields only. For every field a type accepts, see the matching role in [infra.aap_configuration](https://github.com/redhat-cop/infra.aap_configuration/tree/devel/roles) (AAP 2.5+) or [infra.controller_configuration](https://github.com/redhat-cop/infra.controller_configuration/tree/devel/roles) (AAP 2.4). Exporting an object you've built in the UI is often the quickest way to learn its fields.
* **Secrets.** Values like `"{{ vault_github_token }}"` are variables you define in a vault (see [Handle secrets](HOW_TO.md#handle-secrets)). Never put real secrets in plain files.
* **Literal Jinja.** Some fields (credential type injectors, host variables) must reach AAP with `{{ ... }}` intact instead of being resolved at import time. Wrap them in `{%- raw -%}...{%- endraw -%}` or tag them `!unsafe`, as in the [credential type](#credential-types) example. Export does this for you.
* **Lists.** Every type except the settings types (`controller_settings`, `gateway_settings`) is a list, so one file can hold several objects.

---

## Shared platform objects

These use the `aap_` prefix and import into AAP 2.4 (controller) and 2.5+ (gateway). See [Migrating Between AAP Versions](MIGRATING_BETWEEN_AAP_VERSIONS.md) for the older 2.4 key names.

### Organizations

`common/aap_organizations.d/Network Team.yml`

```yaml
---
aap_organizations:
  - name: Network Team
    description: Network automation
    max_hosts: 0                       # 0 = unlimited
    galaxy_credentials:
      - Automation Hub                 # credential that pulls collections
```

### Teams

`common/aap_teams.d/netops.yml`

```yaml
---
aap_teams:
  - name: netops
    organization: Network Team
    description: Network operations engineers
```

### Users

`<env>/imports/aap_user_accounts.d/jdoe.yml`

```yaml
---
aap_user_accounts:
  - username: jdoe
    email: jdoe@example.com
    first_name: Jane
    last_name: Doe
    password: "{{ vault_user_jdoe_password }}"
    update_secrets: false              # set the password on create, never overwrite it
    is_superuser: false
```

### OAuth applications

`common/aap_applications.d/Self Service Portal.yml`

```yaml
---
aap_applications:
  - name: Self Service Portal
    organization: Network Team
    authorization_grant_type: authorization-code
    client_type: confidential
    redirect_uris: https://portal.example.com/api/auth/handler/frame
    skip_authorization: false
```

---

## Automation Controller

### Settings

A dictionary, not a list. Files are merged key by key, so `<env>/imports/` can override individual settings from `common/`.

`<env>/imports/controller_settings.d/controller_settings.yml`

```yaml
---
controller_settings:
  TOWER_URL_BASE: https://aap-prod.example.com
  AWX_TASK_ENV:
    HTTPS_PROXY: http://proxy.example.com:3128
    NO_PROXY: localhost,.example.com
  DEFAULT_JOB_TIMEOUT: 3600
```

### Credential types

Injector values are filled in by AAP, not Ansible, so wrap them in `{%- raw -%}...{%- endraw -%}` (as below) or tag them `!unsafe`.

`common/controller_credential_types.d/Network API Token.yml`

```yaml
---
controller_credential_types:
  - name: Network API Token
    description: Token for the network controller REST API
    kind: cloud
    inputs:
      fields:
        - id: api_url
          type: string
          label: API URL
        - id: api_token
          type: string
          label: API Token
          secret: true
      required:
        - api_url
        - api_token
    injectors:
      env:
        NET_API_URL: '{%- raw -%}{{ api_url }}{%- endraw -%}'
        NET_API_TOKEN: '{%- raw -%}{{ api_token }}{%- endraw -%}'
```

### Credentials

`<env>/imports/controller_credentials.d/GitHub.yml`

```yaml
---
controller_credentials:
  - name: GitHub
    organization: Network Team
    credential_type: Source Control
    inputs:
      username: automation-bot
      password: "{{ vault_github_token }}"

  - name: Network SSH
    organization: Network Team
    credential_type: Machine
    inputs:
      username: netadmin
      ssh_key_data: "{{ vault_network_ssh_private_key }}"

  - name: HashiCorp Vault
    organization: Network Team
    credential_type: HashiCorp Vault Secret Lookup
    inputs:
      url: https://vault.example.com:8200
      token: "{{ vault_hashicorp_token }}"
      api_version: v2
```

### Credential input sources

Fills a field of one credential from an external secret store (the source credential) instead of storing the value in AAP.

`common/controller_credential_input_sources.d/Network SSH.yml`

```yaml
---
controller_credential_input_sources:
  - target_credential: Network SSH
    input_field_name: ssh_key_data
    source_credential: HashiCorp Vault
    description: Pull the SSH key from HashiCorp Vault
    metadata:
      secret_backend: kv
      secret_path: network/ssh
      secret_key: private_key
```

### Execution environments

`common/controller_execution_environments.d/Network EE.yml`

```yaml
---
controller_execution_environments:
  - name: Network EE
    organization: Network Team
    image: hub.example.com/network/ee-network:1.4
    pull: missing                      # always | missing | never
    credential: Automation Hub Registry
```

### Instance groups

`<env>/imports/controller_instance_groups.d/network-dmz.yml`

```yaml
---
controller_instance_groups:
  - name: network-dmz
    policy_instance_minimum: 1
    policy_instance_percentage: 0
    instances:
      - exec-dmz-01.example.com
```

A **container group** (runs jobs as pods on OpenShift or Kubernetes):

```yaml
---
controller_instance_groups:
  - name: openshift-jobs
    is_container_group: true
    credential: OpenShift Cluster
```

### Instances

AAP 2.5+. Usually only needed to add execution or hop nodes.

`<env>/imports/controller_instances.d/exec-dmz-01.yml`

```yaml
---
controller_instances:
  - hostname: exec-dmz-01.example.com
    node_type: execution
    node_state: installed
    listener_port: 27199
    peers_from_control_nodes: true
    enabled: true
```

### Labels

`common/controller_labels.d/labels.yml`

```yaml
---
controller_labels:
  - name: backup
    organization: Network Team
  - name: compliance
    organization: Network Team
```

### Notification templates

Note the `controller_notifications` key.

`<env>/imports/controller_notification_templates.d/Email NetOps.yml`

```yaml
---
controller_notifications:
  - name: Email NetOps
    organization: Network Team
    notification_type: email
    notification_configuration:
      host: smtp.example.com
      port: 25
      sender: aap@example.com
      recipients:
        - netops@example.com
      use_tls: false
      use_ssl: false
      timeout: 30
```

### Projects

`common/controller_projects.d/Network Playbooks.yml`

```yaml
---
controller_projects:
  - name: Network Playbooks
    organization: Network Team
    scm_type: git
    scm_url: https://github.com/example/network-playbooks.git
    scm_branch: main
    credential: GitHub
    scm_update_on_launch: true
    default_environment: Network EE
```

### Inventories

`common/controller_inventories.d/Network Devices.yml`

```yaml
---
controller_inventories:
  - name: Network Devices
    organization: Network Team
    description: Routers and switches
    variables:
      ansible_network_os: cisco.ios.ios
```

A **smart inventory** (built from a host filter over other inventories):

```yaml
---
controller_inventories:
  - name: Core Routers
    organization: Network Team
    kind: smart
    host_filter: name__startswith=core-
```

### Inventory sources

`common/controller_inventory_sources.d/Network Devices from Git.yml`

```yaml
---
controller_inventory_sources:
  - name: Network Devices from Git
    organization: Network Team
    inventory: Network Devices
    source: scm
    source_project: Network Playbooks
    source_path: inventories/network.ini
    overwrite: true
    update_on_launch: true
```

### Hosts

`<env>/imports/controller_hosts.d/core-rtr-01.yml`

```yaml
---
controller_hosts:
  - name: core-rtr-01
    inventory: Network Devices
    description: Core router, site A
    variables:
      ansible_host: 10.0.0.1
```

### Groups (inventory)

`<env>/imports/controller_groups.d/core_routers.yml`

```yaml
---
controller_groups:
  - name: core_routers
    inventory: Network Devices
    hosts:
      - core-rtr-01
    variables:
      ansible_connection: ansible.netcommon.network_cli
```

### Job templates

Note the `controller_templates` key.

`common/controller_job_templates.d/Backup Configs.yml`

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
    execution_environment: Network EE
    labels:
      - backup
    ask_limit_on_launch: true
    extra_vars:
      backup_dir: /backups
    notification_templates_error:
      - Email NetOps
    survey_enabled: true
    survey_spec:
      name: Backup options
      description: ''
      spec:
        - question_name: Compress backups?
          variable: compress
          type: multiplechoice
          choices:
            - "yes"
            - "no"
          default: "yes"
          required: true
```

### Workflow job templates

Note the `controller_workflows` key. Each node has an `identifier`; `success_nodes`, `failure_nodes` and `always_nodes` link nodes by identifier.

`common/controller_workflow_job_templates.d/Backup and Report.yml`

```yaml
---
controller_workflows:
  - name: Backup and Report
    organization: Network Team
    inventory: Network Devices
    simplified_workflow_nodes:
      - identifier: sync-project
        unified_job_template: Network Playbooks     # a project node runs a project sync
        success_nodes:
          - backup
      - identifier: backup
        unified_job_template: Backup Configs
        success_nodes:
          - approve
        failure_nodes:
          - notify-failure
      - identifier: approve
        approval_node:
          name: Approve compliance report
          timeout: 3600
        success_nodes:
          - report
      - identifier: report
        unified_job_template: Compliance Report
      - identifier: notify-failure
        unified_job_template: Send Failure Notice
```

### Schedules

`common/controller_schedules.d/Nightly Backup.yml`

```yaml
---
controller_schedules:
  - name: Nightly Backup
    unified_job_template: Backup Configs
    enabled: true
    rrule: DTSTART;TZID=America/New_York:20260101T020000 RRULE:FREQ=DAILY;INTERVAL=1
    extra_data:
      compress: "yes"
```

### Roles (permissions)

Grants a team or user a role on one or more objects. Use `teams:` / `users:` instead of `team:` / `user:` to grant several at once.

`common/controller_roles.d/team_roles.d/netops.yml`

```yaml
---
controller_roles:
  - team: netops
    job_templates:
      - Backup Configs
    role: execute

  - team: netops
    inventories:
      - Network Devices
    role: use

  - team: netops
    organizations:
      - Network Team
    role: member
```

`common/controller_roles.d/user_roles.d/jdoe.yml`

```yaml
---
controller_roles:
  - user: jdoe
    workflows:
      - Backup and Report
    role: approval
```

> [!TIP]
> On AAP 2.5+, organization and team membership is usually managed with [gateway role assignments](#user-role-assignments) instead.

---

## Platform Gateway (AAP 2.5+)

### Settings

A dictionary, not a list, merged key by key like controller settings.

`<env>/imports/gateway_settings.d/gateway_settings.yml`

```yaml
---
gateway_settings:
  SESSION_COOKIE_AGE: 1800
  password_min_length: 12
  password_min_digits: 1
  password_min_upper: 1
  password_min_special: 1
  CSRF_TRUSTED_ORIGINS:
    - https://aap-prod.example.com
```

### Authenticators

`<env>/imports/gateway_authenticators.d/Corporate LDAP.yml`

```yaml
---
gateway_authenticators:
  - name: Corporate LDAP
    type: ansible_base.authentication.authenticator_plugins.ldap
    enabled: true
    create_objects: true
    remove_users: false
    order: 2
    configuration:
      SERVER_URI:
        - ldaps://ldap.example.com:636
      BIND_DN: cn=aap-bind,ou=service,dc=example,dc=com
      BIND_PASSWORD: "{{ vault_ldap_bind_password }}"
      USER_SEARCH:
        - ou=people,dc=example,dc=com
        - SCOPE_SUBTREE
        - (uid=%(user)s)
      USER_ATTR_MAP:
        email: mail
        first_name: givenName
        last_name: sn
      GROUP_TYPE: GroupOfNamesType
      GROUP_SEARCH:
        - ou=groups,dc=example,dc=com
        - SCOPE_SUBTREE
        - (objectClass=groupOfNames)
```

### Authenticator maps

Map users from an authenticator into organizations, teams, roles or superuser status.

`<env>/imports/gateway_authenticator_maps.d/LDAP maps.yml`

```yaml
---
gateway_authenticator_maps:
  - name: LDAP - NetOps team members
    authenticator: Corporate LDAP
    map_type: team
    organization: Network Team
    team: netops
    role: Team Member
    revoke: true
    order: 1
    triggers:
      groups:
        has_or:
          - cn=netops,ou=groups,dc=example,dc=com

  - name: LDAP - Superusers
    authenticator: Corporate LDAP
    map_type: is_superuser
    order: 2
    triggers:
      groups:
        has_or:
          - cn=aap-admins,ou=groups,dc=example,dc=com
```

### Role definitions

Custom roles built from individual permissions.

`common/gateway_role_definitions.d/Job Template Runner.yml`

```yaml
---
gateway_role_definitions:
  - name: Job Template Runner
    description: Can view and run job templates
    content_type: awx.jobtemplate
    permissions:
      - awx.view_jobtemplate
      - awx.execute_jobtemplate
```

### Team role assignments

`common/gateway_role_team_assignments.d/netops.yml`

```yaml
---
gateway_role_team_assignments:
  - team: netops
    role_definition: Organization Inventory Admin
    assignment_objects:
      - name: Network Team
        type: organizations
```

### User role assignments

`common/gateway_role_user_assignments.d/jdoe.yml`

```yaml
---
gateway_role_user_assignments:
  - user: jdoe
    role_definition: Organization Member
    object_ids:
      - Network Team

  - user: jdoe
    role_definition: Team Member
    object_ids:
      - netops
```

### HTTP ports

The service-routing types below (ports, clusters, nodes, keys, services, routes) are created by the AAP installer. Most people never edit them; export them only if you need to reproduce a custom gateway topology.

`<env>/imports/gateway_http_ports.d/port-8443.yml`

```yaml
---
gateway_http_ports:
  - name: port-8443
    number: 8443
    use_https: true
    is_api_port: false
```

### Service clusters

`<env>/imports/gateway_service_clusters.d/custom-app.yml`

```yaml
---
gateway_service_clusters:
  - name: custom-app
    service_type: controller
```

### Service nodes

`<env>/imports/gateway_service_nodes.d/custom-app-node-1.yml`

```yaml
---
gateway_service_nodes:
  - name: custom-app-node-1
    service_cluster: custom-app
    address: 10.0.10.21
```

### Service keys

`<env>/imports/gateway_service_keys.d/custom-app-key.yml`

```yaml
---
gateway_service_keys:
  - name: custom-app-key
    service_cluster: custom-app
    algorithm: HS256
    is_active: true
    secret: "{{ vault_gateway_custom_app_key }}"
```

### Services

`<env>/imports/gateway_services.d/custom-app-api.yml`

```yaml
---
gateway_services:
  - name: custom-app api
    api_slug: custom-app
    http_port: port-8443
    service_cluster: custom-app
    service_port: 8080
    service_path: /api/custom-app/
    is_service_https: false
    enable_gateway_auth: true
```

### Routes

`<env>/imports/gateway_routes.d/custom-app-ui.yml`

```yaml
---
gateway_routes:
  - name: custom-app ui
    http_port: port-8443
    service_cluster: custom-app
    service_port: 8080
    service_path: /ui/
    gateway_path: /custom-app/
    is_service_https: false
    enable_gateway_auth: true
```

---

## Event-Driven Ansible (AAP 2.5+)

### Credential types

`common/eda_credential_types.d/Webhook Token.yml`

```yaml
---
eda_credential_types:
  - name: Webhook Token
    description: Shared secret for incoming webhooks
    inputs:
      fields:
        - id: webhook_token
          type: string
          label: Token
          secret: true
      required:
        - webhook_token
    injectors:
      extra_vars:
        webhook_token: !unsafe "{{ webhook_token }}"
```

### Credentials

`<env>/imports/eda_credentials.d/credentials.yml`

```yaml
---
eda_credentials:
  - name: registry.redhat.io
    organization: Network Team
    credential_type: Container Registry
    inputs:
      host: registry.redhat.io
      username: "{{ vault_rh_registry_username }}"
      password: "{{ vault_rh_registry_password }}"
      verify_ssl: true

  - name: AAP Controller
    organization: Network Team
    credential_type: Red Hat Ansible Automation Platform
    inputs:
      host: https://aap-prod.example.com/api/controller/
      username: eda-service
      password: "{{ vault_eda_aap_password }}"

  - name: NetOps Webhook Token
    organization: Network Team
    credential_type: Token Event Stream
    inputs:
      auth_type: token
      token: "{{ vault_eda_webhook_token }}"
      http_header_key: Authorization
```

### Decision environments

`common/eda_decision_environments.d/DE Supported.yml`

```yaml
---
eda_decision_environments:
  - name: DE Supported
    organization: Network Team
    image_url: registry.redhat.io/ansible-automation-platform-26/de-supported-rhel9:latest
    credential: registry.redhat.io
```

### Event streams

`<env>/imports/eda_event_streams.d/NetOps Alerts.yml`

```yaml
---
eda_event_streams:
  - name: NetOps Alerts
    organization: Network Team
    credential_name: NetOps Webhook Token
    forward_events: true
```

### Projects

`common/eda_projects.d/Network Rulebooks.yml`

```yaml
---
eda_projects:
  - name: Network Rulebooks
    organization: Network Team
    scm_type: git
    url: https://github.com/example/network-rulebooks.git
    scm_branch: main
    credential: GitHub EDA
```

### Rulebook activations

`<env>/imports/eda_rulebook_activations.d/Interface Down.yml`

```yaml
---
eda_rulebook_activations:
  - name: Interface Down
    organization: Network Team
    project: Network Rulebooks
    rulebook: interface_down.yml
    decision_environment: DE Supported
    eda_credentials:
      - AAP Controller
    event_streams:
      - event_stream: NetOps Alerts
        source_name: webhook
    enabled: true
    restart_policy: on-failure
    extra_vars:
      remediation_template: Bounce Interface
```

---

## Automation Hub (AAP 2.5+)

### Namespaces

`common/hub_namespaces.d/netops.yml`

```yaml
---
hub_namespaces:
  - name: netops
    company: Example Corp
    email: netops@example.com
    description: Internal network collections
```

### Collections

Upload a collection tarball, or (with `version`) manage an existing collection version.

`common/hub_collections.d/netops.backup.yml`

```yaml
---
hub_collections:
  - namespace: netops
    name: backup
    path: /tmp/netops-backup-1.2.0.tar.gz
    version: 1.2.0
    wait: true
```

### Collection remotes

`common/hub_collection_remotes.d/community.yml`

```yaml
---
hub_collection_remotes:
  - name: community
    url: https://galaxy.ansible.com/api/
    requirements:
      - name: ansible.utils
      - name: ansible.netcommon
    sync_dependencies: true
    tls_validation: true
```

A remote using a token (Red Hat certified or validated content):

```yaml
---
hub_collection_remotes:
  - name: rh-certified
    url: https://console.redhat.com/api/automation-hub/content/published/
    auth_url: https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
    token: "{{ vault_rh_hub_token }}"
```

### Collection repositories

`common/hub_collection_repositories.d/community.yml`

```yaml
---
hub_collection_repositories:
  - name: community
    description: Community collections synced from Galaxy
    remote: community
```

### EE registries

`common/hub_ee_registries.d/quay.yml`

```yaml
---
hub_ee_registries:
  - name: quay
    url: https://quay.io
    username: "{{ vault_quay_username }}"
    password: "{{ vault_quay_password }}"
    tls_validation: true
```

### EE repositories

`common/hub_ee_repositories.d/ee-network.yml`

```yaml
---
hub_ee_repositories:
  - name: network/ee-network
    description: Network execution environment
    registry: quay
    upstream_name: example/ee-network
    include_tags:
      - latest
      - "1.4"
```

### EE images

Manages the tags on an image already in Automation Hub.

`common/hub_ee_images.d/ee-network.yml`

```yaml
---
hub_ee_images:
  - name: network/ee-network:1.4
    tags:
      - prod
    append: true                       # false replaces the existing tags
```
