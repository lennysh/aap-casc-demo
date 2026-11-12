# Migrating Between AAP Versions

Every supported AAP version (2.4 through 2.7) exports **the same folder layout and variable names**. An export from one version can therefore be imported into another, most commonly from AAP 2.4 into a new 2.5, 2.6 or 2.7 instance.

* [How it works](#how-it-works)
* [Migrate AAP 2.4 to 2.5+ step by step](#migrate-aap-24-to-25-step-by-step)
* [What's translated automatically](#whats-translated-automatically)
* [What needs manual work](#what-needs-manual-work)
* [Moving between 2.5, 2.6 and 2.7](#moving-between-25-26-and-27)
* [Going from 2.5+ back to 2.4](#going-from-25-back-to-24)

---

## How it works

AAP 2.4 and 2.5+ are configured by different collections that use different variable names for a few shared objects:

| Object | AAP 2.4 name | AAP 2.5+ name (standard) |
|---|---|---|
| Organizations | `controller_organizations` | `aap_organizations` |
| Teams | `controller_teams` | `aap_teams` |
| Users | `controller_user_accounts` | `aap_user_accounts` |
| OAuth applications | `controller_applications` | `aap_applications` |

This project hides the difference:

* **Export** always writes the **standard (2.5+) names and folders** (`aap_organizations.d`, `aap_teams.d`, `aap_user_accounts.d`, `aap_applications.d`), whatever version you export from. User fields are normalized too: `superuser` becomes `is_superuser`, and `auditor` becomes `is_platform_auditor`.
* **Import** accepts **either** naming on **any** version and converts to what that version expects. Duplicates (the same team written both ways, for example) are merged into one.

Every other object type (credentials, projects, inventories, hosts, job templates, workflows, schedules, notifications, execution environments, instance groups, labels, settings, roles) already uses the same name in both versions.

## Migrate AAP 2.4 to 2.5+ step by step

1. **Create an environment for each instance** (same organization folder, so they share `common/`):

    ```bash
    ./start_here.sh MyCompany aap24     # choose 2.4
    ./start_here.sh MyCompany aap26     # choose 2.6 (same vault password)
    ```

2. **Export the 2.4 instance:**

    ```bash
    ./export.sh MyCompany aap24 -a
    ```

3. **Copy the export into the new environment** (or into `common/` if both instances will keep running and should stay identical):

    ```bash
    cp -r orgs_vars/MyCompany/aap24/exports/mycompany_aap24_export_*/filetree_version/* orgs_vars/MyCompany/aap26/imports/
    ```

4. **Review and adjust** using [What needs manual work](#what-needs-manual-work). In particular, define every secret placeholder in the `aap26` vault (see [Handle secrets](HOW_TO.md#handle-secrets)).

5. **Dry run, then import** into the new instance. Importing in stages makes problems easier to spot:

    ```bash
    ./import.sh MyCompany aap26 -a --check
    ./import.sh MyCompany aap26 -t "gateway_organizations,gateway_teams,gateway_users"
    ./import.sh MyCompany aap26 -t "controller_credential_types,controller_credentials,controller_projects,controller_inventories"
    ./import.sh MyCompany aap26 -a
    ```

6. **Verify** in the AAP UI, run a few jobs, then run `./import.sh MyCompany aap26 -a --check` again. It should report no changes.

## What's translated automatically

| Item | Handling |
|---|---|
| Organizations, teams, users, applications | Converted to the standard names on export; either name is accepted on import. |
| User superuser / auditor flags | `superuser` → `is_superuser`, `auditor` → `is_platform_auditor` (and back when importing into 2.4). |
| Duplicate entries | Merged by name (organization + name for teams and applications, username for users). |
| All other controller objects | Same names in both versions, so nothing to translate. |
| Classic controller permissions (`controller_roles`) | Still supported on 2.5+. Optionally convert them to gateway role assignments (see [How-To](HOW_TO.md#convert-controller-roles-to-gateway-role-assignments)). |

## What needs manual work

* **Authentication (LDAP, SAML, OIDC, GitHub, ...):** in 2.4 these live in `controller_settings` (`AUTH_LDAP_*`, `SOCIAL_AUTH_*`). In 2.5+, authentication moved to the platform gateway. Recreate them as `gateway_authenticators` (and `gateway_authenticator_maps` for team and organization mapping), and remove the old keys from `controller_settings`.
* **Other controller settings:** some 2.4 settings no longer exist or moved to `gateway_settings` in 2.5+. Review `controller_settings.d/` before importing, and drop anything 2.5+ rejects.
* **Secrets:** AAP never exports secret values. Every credential secret becomes a placeholder you must define in a vault.
* **User passwords:** 2.4 exports users with `password: INITIAL` and `update_secrets: false`. Set real initial passwords, or let users log in through an external authenticator.
* **Execution environments and instance groups:** image names, registries and instance group names often differ on the new platform. Check `controller_execution_environments.d/` and `controller_instance_groups.d/`.
* **EDA and Automation Hub on 2.4:** in 2.4 they're separate servers with their own logins, and this project doesn't export them. Recreate their configuration on 2.5+ using the `eda_*` and `hub_*` folders.
* **URLs and hostnames** in settings, notification templates and inventories that pointed at the old instance.

> [!TIP]
> Red Hat's [AAP 2.7 Upgrade: API and Configuration as Code Migration Guide](https://access.redhat.com/articles/7143981) covers platform-level changes worth reading before a migration.

## Moving between 2.5, 2.6 and 2.7

These versions use the same collections and the same layout. Create an environment for the target instance, copy the files, define secrets and import. Note that AAP 2.7 only accepts API access through the platform gateway, so point `vault_aap_hostname` at the gateway URL.

## Going from 2.5+ back to 2.4

Importing 2.5+ files into 2.4 works for **Automation Controller objects** and for organizations, teams, users and applications, which are converted back to the 2.4 names. Gateway, EDA and Hub files are ignored by a 2.4 import. Remember that importing into 2.4 needs ansible-core 2.18 or older (see [Versions and Collections](VERSIONS_AND_COLLECTIONS.md#ansible-core-requirements)).
