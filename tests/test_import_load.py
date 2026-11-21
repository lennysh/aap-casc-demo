"""End-to-end tests: run the real roles/import_export/tasks/import_load.yml against fixture
workspaces (no AAP needed). See conftest.py for the harness."""

import pytest

from conftest import PREFLIGHT_PLUGIN, UNDEFINED, _versions_available, requires_version

ALL_VERSIONS = _versions_available() or ["2.6"]

# Tag names per version: 2.5+ use component-prefixed tags, 2.4 short ones.
TAGS = {
    "2.4": {"jt": "job_templates", "projects": "projects", "orgs": "organizations", "settings": "settings"},
    "2.6": {"jt": "controller_job_templates", "projects": "controller_projects",
            "orgs": "gateway_organizations", "settings": "controller_settings"},
}
TAGS["2.5"] = TAGS["2.7"] = TAGS["2.6"]
TAG_VERSIONS = [pytest.param(v, marks=requires_version(v)) for v in ("2.6", "2.4")]
ALL_TAG_VERSIONS = [pytest.param(v, marks=requires_version(v)) for v in ("2.4", "2.5", "2.6", "2.7")]

PROJECT = """\
controller_projects:
  - name: {name}
    organization: Default
    scm_url: {url}
"""
TEMPLATE = """\
controller_templates:
  - name: {name}
    organization: Default
    project: P1
    playbook: site.yml
    description: {description}
"""


def project(name="P1", url="https://example.com/p1.git"):
    return PROJECT.format(name=name, url=url)


def template(name="JT1", description="plain"):
    return TEMPLATE.format(name=name, description=description)


def ok(result):
    assert result.rc == 0, result.output
    return result


def failed(result):
    assert result.rc != 0, result.output
    return result


# --------------------------------------------------------------------------------------------
# Loading
# --------------------------------------------------------------------------------------------

@pytest.mark.parametrize("ver", ALL_VERSIONS)
def test_loads_any_folder_structure_and_file_names(make_ws, run_import_load, ver):
    ws = make_ws({
        "common/deep/er/whatever.yaml": "helper_a: from-yaml-ext\n",
        "common/controller_projects.d/my projects.yml": project("P1"),
        "env/imports/flat.yml": template("JT1"),
        "env/imports/x/y/z/Some-Name.YAML.yml": "helper_b: nested\n",
    })
    r = ok(run_import_load(ws, ver))
    assert r.vars["helper_a"] == "from-yaml-ext"
    assert r.vars["helper_b"] == "nested"
    assert [p["name"] for p in r.vars["controller_projects"]] == ["P1"]
    assert [t["name"] for t in r.vars["controller_templates"]] == ["JT1"]
    assert r.prepare["files"] == 4


def test_ignored_and_non_yaml_files_are_skipped(make_ws, run_import_load):
    ws = make_ws({
        "common/ignore_broken.yml": "this: is: not: [valid yaml\n",
        "env/imports/sub/ignore_projects.yml": project("IGNORED"),
        "env/imports/notes.txt": "controller_projects: nope\n",
        "env/imports/projects.yml.bak": project("BAK"),
        "env/imports/projects.yml": project("P1"),
    })
    r = ok(run_import_load(ws, "2.6"))
    assert [p["name"] for p in r.vars["controller_projects"]] == ["P1"]
    assert r.prepare["files"] == 1


def test_ignored_folders_are_skipped(make_ws, run_import_load):
    ws = make_ws({
        "common/ignore_controller_projects.d/old.yml": project("OLD"),
        "common/ignore_wip/broken.yml": "this: is: not: [valid yaml\n",
        "env/imports/controller_projects.d/ignore_drafts/nested/draft.yml": project("DRAFT"),
        "env/imports/controller_projects.d/projects.yml": project("P1"),
    })
    r = ok(run_import_load(ws, "2.6"))
    assert [p["name"] for p in r.vars["controller_projects"]] == ["P1"]
    assert r.prepare["files"] == 1


def test_import_common_false_skips_common(make_ws, run_import_load):
    ws = make_ws({
        "common/projects.yml": project("COMMON"),
        "env/imports/projects.yml": project("ENV"),
    })
    r = ok(run_import_load(ws, "2.6", extra_vars={"import_common": False}))
    assert [p["name"] for p in r.vars["controller_projects"]] == ["ENV"]


def test_merge_order_common_first_then_imports(make_ws, run_import_load):
    ws = make_ws({
        "common/b.yml": project("C2"),
        "common/A.yml": project("C1") + "scalar: common\n",
        "env/imports/a.yml": project("E1"),
        "env/imports/z/z.yml": project("E2") + "scalar: env\n",
        "common/settings.yml": """\
            controller_settings:
              SETTING_A: common-a
              SETTING_B: common-b
            """,
        "env/imports/settings.yml": """\
            controller_settings:
              SETTING_B: env-b
              SETTING_C: env-c
            """,
    })
    r = ok(run_import_load(ws, "2.6"))
    # Lists appended: common/ first, files in case-insensitive path order.
    assert [p["name"] for p in r.vars["controller_projects"]] == ["C1", "C2", "E1", "E2"]
    # Dicts merged, later (env) wins per key.
    assert r.vars["controller_settings"] == {"SETTING_A": "common-a", "SETTING_B": "env-b", "SETTING_C": "env-c"}
    # Scalars: last wins.
    assert r.vars["scalar"] == "env"


def test_unsafe_values_stay_literal(make_ws, run_import_load):
    ws = make_ws({
        "common/projects.yml": """\
            controller_projects:
              - name: P1
                organization: Default
                description: !unsafe '{{ not_a_var }}'
            """,
        "env/imports/projects.yml": """\
            controller_projects:
              - name: P2
                organization: Default
                description: !unsafe '{% raw %}{{ x }}{{ y }}'
            unsafe_scalar: !unsafe '{{ also_not_a_var }}'
            """,
    })
    r = ok(run_import_load(ws, "2.6"))
    assert [p["description"] for p in r.vars["controller_projects"]] == ["{{ not_a_var }}", "{% raw %}{{ x }}{{ y }}"]
    assert r.vars["unsafe_scalar"] == "{{ also_not_a_var }}"


def test_lazy_templating_of_helpers(make_ws, run_import_load):
    ws = make_ws({
        "common/helpers.yml": "org_name: Default\nscm_base: 'https://git.example.com/{{ org_name | lower }}'\n",
        "env/imports/projects.yml": """\
            controller_projects:
              - name: P1
                organization: '{{ org_name }}'
                scm_url: '{{ scm_base }}/p1.git'
            """,
    })
    r = ok(run_import_load(ws, "2.6"))
    assert r.vars["controller_projects"] == [
        {"name": "P1", "organization": "Default", "scm_url": "https://git.example.com/default/p1.git"}]


def test_vault_encrypted_file_loads(make_ws, run_import_load, vault_encrypt):
    ws = make_ws({
        "env/imports/vault.yml": "vault_scm_password: s3cret\n",
        "env/imports/creds.yml": """\
            controller_credentials:
              - name: C1
                organization: Default
                credential_type: Source Control
                inputs:
                  password: '{{ vault_scm_password }}'
            """,
    })
    vault_encrypt(ws / "env" / "imports" / "vault.yml")
    assert (ws / "env" / "imports" / "vault.yml").read_text().startswith("$ANSIBLE_VAULT")
    r = ok(run_import_load(ws, "2.6", vault=True))
    assert r.vars["vault_scm_password"] == "s3cret"
    assert r.vars["controller_credentials"][0]["inputs"]["password"] == "s3cret"


def test_inline_vault_value_loads(make_ws, run_import_load, vault_encrypt_string):
    ws = make_ws({
        "env/imports/secrets.yml": vault_encrypt_string("vault_token", "tok-123"),
        "common/helpers.yml": "token_ref: '{{ vault_token }}'\n",
    })
    r = ok(run_import_load(ws, "2.6", vault=True))
    assert r.vars["vault_token"] == "tok-123"
    assert r.vars["token_ref"] == "tok-123"


def test_key_in_vault_file_and_elsewhere_fails(make_ws, run_import_load, vault_encrypt):
    ws = make_ws({
        "env/imports/vault.yml": "shared_secret: one\n",
        "common/plain.yml": "shared_secret: two\n",
    })
    vault_encrypt(ws / "env" / "imports" / "vault.yml")
    r = failed(run_import_load(ws, "2.6", vault=True))
    assert "'shared_secret' is defined in a vault-encrypted file and elsewhere" in r.failure
    assert "env/imports/vault.yml" in r.failure and "common/plain.yml" in r.failure


@pytest.mark.parametrize("text, kind", [("- a\n- b\n", "list"), ("just a string\n", "string")])
def test_non_mapping_file_fails(make_ws, run_import_load, text, kind):
    ws = make_ws({"env/imports/bad.yml": text})
    r = failed(run_import_load(ws, "2.6"))
    assert "env/imports/bad.yml must contain variables" in r.failure
    assert "not a %s" % kind in r.failure


def test_empty_files_are_ok(make_ws, run_import_load):
    ws = make_ws({
        "common/empty.yml": "",
        "common/comments.yml": "# nothing here yet\n---\n",
        "env/imports/projects.yml": project("P1"),
    })
    r = ok(run_import_load(ws, "2.6"))
    assert [p["name"] for p in r.vars["controller_projects"]] == ["P1"]


def test_invalid_yaml_fails_without_tags(make_ws, run_import_load):
    ws = make_ws({"env/imports/broken.yml": "controller_projects:\n  - name: [unclosed\n"})
    r = failed(run_import_load(ws, "2.6"))
    assert "Could not read env/imports/broken.yml" in r.failure


def test_missing_imports_folder_warns(make_ws, run_import_load):
    ws = make_ws({"common/projects.yml": project("P1")})
    (ws / "env" / "imports").rmdir()
    r = ok(run_import_load(ws, "2.6"))
    assert "Folder(s) not found, skipped: env/imports" in r.warnings


def test_staging_folder_is_removed(make_ws, run_import_load):
    import os
    ws = make_ws({"env/imports/projects.yml": project("P1")})
    r = ok(run_import_load(ws, "2.6"))
    assert r.prepare["stage_dir"]
    assert not os.path.exists(r.prepare["stage_dir"])


# --------------------------------------------------------------------------------------------
# Duplicates
# --------------------------------------------------------------------------------------------

def test_conflicting_duplicate_fails_and_lists_both_files(make_ws, run_import_load):
    ws = make_ws({
        "common/projects.yml": project("P1", "https://example.com/a.git"),
        "env/imports/controller_projects.d/p1.yml": project("P1", "https://example.com/b.git"),
    })
    r = failed(run_import_load(ws, "2.6"))
    assert "1 object(s) are defined more than once with different values" in r.failure
    assert "controller_projects [name=P1, organization=Default] - differs in: scm_url" in r.failure
    assert "common/projects.yml (controller_projects)" in r.failure
    assert "env/imports/controller_projects.d/p1.yml (controller_projects)" in r.failure
    assert r.prepare["duplicates"][0]["differs"] == ["scm_url"]


def test_identical_duplicate_only_warns(make_ws, run_import_load):
    ws = make_ws({
        "common/projects.yml": project("P1"),
        "env/imports/projects.yml": project("P1"),
    })
    r = ok(run_import_load(ws, "2.6"))
    assert "defined more than once without conflicting values" in r.warnings
    assert r.prepare["duplicates_merged"] == 1
    assert r.prepare["duplicates_conflicting"] == 0


def test_allow_duplicates_passes_with_warning(make_ws, run_import_load):
    ws = make_ws({
        "common/projects.yml": project("P1", "https://example.com/a.git"),
        "env/imports/projects.yml": project("P1", "https://example.com/b.git"),
    })
    r = ok(run_import_load(ws, "2.6", extra_vars={"import_export_allow_duplicates": True}))
    assert "defined more than once with different values" in r.warnings
    assert [p["scm_url"] for p in r.vars["controller_projects"]] == [
        "https://example.com/a.git", "https://example.com/b.git"]


def test_same_name_other_identity_is_not_a_duplicate(make_ws, run_import_load):
    ws = make_ws({
        "common/projects.yml": project("P1", "https://example.com/a.git"),
        "env/imports/projects.yml": PROJECT.format(name="P1", url="https://example.com/b.git").replace(
            "Default", "Other"),
    })
    r = ok(run_import_load(ws, "2.6"))
    assert r.prepare["duplicates_merged"] == 0 and r.prepare["duplicates_conflicting"] == 0


def test_skip_duplicate_check_vars_are_not_checked(make_ws, run_import_load):
    role = "controller_roles:\n  - name: x\n    role: {role}\n    team: T\n"
    ws = make_ws({
        "common/roles.yml": role.format(role="admin"),
        "env/imports/roles.yml": role.format(role="read"),
    })
    ok(run_import_load(ws, "2.6"))


# --------------------------------------------------------------------------------------------
# Cross-version aliases
# --------------------------------------------------------------------------------------------

@requires_version("2.6")
def test_26_controller_organizations_merged_into_aap_organizations(make_ws, run_import_load):
    ws = make_ws({
        "common/aap_organizations.yml": "aap_organizations:\n  - name: OrgA\n    description: from aap\n",
        "env/imports/orgs.yml": """\
            controller_organizations:
              - name: OrgA
                max_hosts: 5
              - name: OrgB
            """,
    })
    r = ok(run_import_load(ws, "2.6", probe=["aap_organizations", "controller_organizations"]))
    # Same name merged (first wins, later adds missing fields).
    assert r.vars["aap_organizations"] == [
        {"name": "OrgA", "description": "from aap", "max_hosts": 5},
        {"name": "OrgB"},
    ]


@requires_version("2.6")
def test_26_alias_conflict_is_a_duplicate(make_ws, run_import_load):
    ws = make_ws({
        "common/a.yml": "aap_organizations:\n  - name: OrgA\n    description: one\n",
        "env/imports/b.yml": "controller_organizations:\n  - name: OrgA\n    description: two\n",
    })
    r = failed(run_import_load(ws, "2.6"))
    assert "aap_organizations [name=OrgA] - differs in: description" in r.failure


@requires_version("2.4")
def test_24_aap_organizations_merged_into_controller_organizations(make_ws, run_import_load):
    ws = make_ws({
        "common/orgs.yml": "controller_organizations:\n  - name: OrgA\n",
        "env/imports/orgs.yml": "aap_organizations:\n  - name: OrgB\n  - name: OrgA\n    description: added\n",
    })
    r = ok(run_import_load(ws, "2.4", probe=["controller_organizations"]))
    assert r.vars["controller_organizations"] == [{"name": "OrgA", "description": "added"}, {"name": "OrgB"}]


@requires_version("2.6")
def test_26_user_auditor_keys_renamed(make_ws, run_import_load):
    ws = make_ws({
        "env/imports/users.yml": """\
            controller_user_accounts:
              - username: alice
                is_system_auditor: true
              - username: bob
                superuser: true
            """,
    })
    r = ok(run_import_load(ws, "2.6", probe=["aap_user_accounts"]))
    assert r.vars["aap_user_accounts"] == [
        {"username": "alice", "is_platform_auditor": True},
        {"username": "bob", "is_superuser": True},
    ]


@requires_version("2.4")
def test_24_user_auditor_keys_renamed(make_ws, run_import_load):
    ws = make_ws({
        "env/imports/users.yml": "aap_user_accounts:\n  - username: alice\n    is_platform_auditor: true\n",
    })
    r = ok(run_import_load(ws, "2.4", probe=["controller_user_accounts"]))
    assert r.vars["controller_user_accounts"] == [{"username": "alice", "is_system_auditor": True}]


# --------------------------------------------------------------------------------------------
# Tags
# --------------------------------------------------------------------------------------------

@pytest.mark.parametrize("ver", ALL_TAG_VERSIONS)
def test_tags_load_only_selected_types_plus_helpers(make_ws, run_import_load, ver):
    ws = make_ws({
        "common/helpers.yml": "jt_description: 'from helper {{ jt_suffix }}'\njt_suffix: ok\n",
        "env/imports/templates.yml": template("JT1", "'{{ jt_description }}'"),
        "env/imports/projects.yml": project("P1"),
        "env/imports/mixed.yml": project("P2") + "controller_settings:\n  A: 1\n",
    })
    r = ok(run_import_load(ws, ver, tags=[TAGS[ver]["jt"]],
                           probe=["controller_templates", "controller_projects", "controller_settings",
                                  "jt_description"]))
    assert r.vars["controller_templates"][0]["description"] == "from helper ok"
    assert not r.defined("controller_projects")
    assert not r.defined("controller_settings")
    assert r.vars["jt_description"] == "from helper ok"
    assert r.prepare["tag_filtered"] is True
    assert r.prepare["loaded_object_variables"] == ["controller_templates"]
    assert set(r.prepare["skipped_object_variables"]) == {"controller_projects", "controller_settings"}
    assert "env/imports/projects.yml" in r.prepare["skipped_files"]
    assert "env/imports/mixed.yml" in r.prepare["skipped_files"]
    assert "Loaded: controller_templates" in r.output


@pytest.mark.parametrize("ver", TAG_VERSIONS)
def test_tags_unfinished_unselected_object_does_not_fail(make_ws, run_import_load, ver):
    ws = make_ws({
        "env/imports/templates.yml": template("JT1"),
        "env/imports/projects.yml": """\
            controller_projects:
              - name: WIP
                organization: '{{ org_not_defined_yet }}'
                credential: '{{ vault_missing | mandatory }}'
            """,
    })
    r = ok(run_import_load(ws, ver, tags=[TAGS[ver]["jt"]], probe=["controller_templates"]))
    assert r.vars["controller_templates"][0]["name"] == "JT1"


@pytest.mark.parametrize("ver", TAG_VERSIONS)
def test_tags_conflicting_duplicate_in_unselected_type_does_not_fail(make_ws, run_import_load, ver):
    ws = make_ws({
        "common/projects.yml": project("P1", "https://example.com/a.git"),
        "env/imports/projects.yml": project("P1", "https://example.com/b.git"),
        "env/imports/templates.yml": template("JT1"),
    })
    r = ok(run_import_load(ws, ver, tags=[TAGS[ver]["jt"]]))
    assert r.prepare["duplicates_conflicting"] == 0
    # ...but it still fails when that type is selected.
    r = failed(run_import_load(ws, ver, tags=[TAGS[ver]["projects"]]))
    assert "differs in: scm_url" in r.failure


@pytest.mark.parametrize("ver", TAG_VERSIONS)
def test_tags_broken_yaml_of_unselected_type_is_skipped(make_ws, run_import_load, ver):
    ws = make_ws({
        "env/imports/projects.yml": "controller_projects:\n  - name: [unclosed\n",
        "env/imports/templates.yml": template("JT1"),
    })
    r = ok(run_import_load(ws, ver, tags=[TAGS[ver]["jt"]], probe=["controller_templates"]))
    assert "Skipped env/imports/projects.yml (not selected by tags) because it can't be read" in r.warnings
    assert "env/imports/projects.yml" in r.prepare["skipped_files"]
    assert "controller_projects" in r.prepare["skipped_object_variables"]
    assert r.vars["controller_templates"][0]["name"] == "JT1"


@pytest.mark.parametrize("ver", TAG_VERSIONS)
def test_tags_broken_yaml_of_selected_type_fails(make_ws, run_import_load, ver):
    ws = make_ws({"env/imports/templates.yml": "controller_templates:\n  - name: [unclosed\n"})
    r = failed(run_import_load(ws, ver, tags=[TAGS[ver]["jt"]]))
    assert "Could not read env/imports/templates.yml" in r.failure


@pytest.mark.parametrize("ver", TAG_VERSIONS)
def test_tags_broken_file_with_helper_key_fails(make_ws, run_import_load, ver):
    ws = make_ws({
        "env/imports/mixed.yml": "my_helper: 1\ncontroller_projects:\n  - name: [unclosed\n",
        "env/imports/templates.yml": template("JT1"),
    })
    r = failed(run_import_load(ws, ver, tags=[TAGS[ver]["jt"]]))
    assert "Could not read env/imports/mixed.yml" in r.failure


@pytest.mark.parametrize("ver", TAG_VERSIONS)
def test_tags_non_mapping_file_fails(make_ws, run_import_load, ver):
    # No top-level keys, so it can't be attributed to an unselected type.
    ws = make_ws({"env/imports/list.yml": "- a\n", "env/imports/templates.yml": template("JT1")})
    r = failed(run_import_load(ws, ver, tags=[TAGS[ver]["jt"]]))
    assert "must contain variables" in r.failure


@requires_version("2.6")
def test_26_alias_source_follows_target_tag(make_ws, run_import_load):
    ws = make_ws({
        "env/imports/orgs.yml": "controller_organizations:\n  - name: OrgA\n",
        "env/imports/templates.yml": template("JT1"),
    })
    probe = ["aap_organizations", "controller_organizations", "controller_templates"]
    r = ok(run_import_load(ws, "2.6", tags=["gateway_organizations"], probe=probe))
    assert r.vars["aap_organizations"] == [{"name": "OrgA"}]
    assert not r.defined("controller_templates")
    assert "aap_organizations" in r.prepare["loaded_object_variables"]

    r = ok(run_import_load(ws, "2.6", tags=["controller_job_templates"], probe=probe))
    assert not r.defined("aap_organizations")
    assert not r.defined("controller_organizations")
    assert "controller_organizations" in r.prepare["skipped_object_variables"]


@requires_version("2.4")
def test_24_alias_source_follows_target_tag(make_ws, run_import_load):
    ws = make_ws({
        "env/imports/orgs.yml": "aap_organizations:\n  - name: OrgA\n",
        "env/imports/templates.yml": template("JT1"),
    })
    probe = ["aap_organizations", "controller_organizations", "controller_templates"]
    r = ok(run_import_load(ws, "2.4", tags=["organizations"], probe=probe))
    assert r.vars["controller_organizations"] == [{"name": "OrgA"}]
    assert not r.defined("controller_templates")

    r = ok(run_import_load(ws, "2.4", tags=["job_templates"], probe=probe))
    assert not r.defined("controller_organizations")
    assert not r.defined("aap_organizations")


@pytest.mark.parametrize("ver", TAG_VERSIONS)
def test_no_tags_loads_everything_and_broken_file_fails(make_ws, run_import_load, ver):
    files = {
        "env/imports/projects.yml": project("P1"),
        "env/imports/templates.yml": template("JT1"),
        "common/settings.yml": "controller_settings:\n  A: 1\n",
    }
    ws = make_ws(files)
    r = ok(run_import_load(ws, ver))
    assert r.prepare["tag_filtered"] is False
    assert r.defined("controller_projects") and r.defined("controller_templates") and r.defined("controller_settings")
    assert r.prepare["skipped_object_variables"] == [] and r.prepare["skipped_files"] == []
    assert "Loaded:" not in r.output

    (ws / "env" / "imports" / "broken.yml").write_text("controller_hosts:\n  - name: [unclosed\n")
    r = failed(run_import_load(ws, ver))
    assert "Could not read env/imports/broken.yml" in r.failure


@pytest.mark.parametrize("ver", TAG_VERSIONS)
def test_skip_tags_drops_that_type(make_ws, run_import_load, ver):
    ws = make_ws({
        "env/imports/projects.yml": project("P1"),
        "env/imports/templates.yml": template("JT1"),
        "env/imports/helpers.yml": "my_helper: yes\n",
    })
    r = ok(run_import_load(ws, ver, skip_tags=[TAGS[ver]["projects"]],
                           probe=["controller_projects", "controller_templates", "my_helper"]))
    assert r.prepare["tag_filtered"] is True
    assert not r.defined("controller_projects")
    assert r.defined("controller_templates")
    assert r.vars["my_helper"] is True


@pytest.mark.parametrize("ver", TAG_VERSIONS)
def test_tags_multiple_selected(make_ws, run_import_load, ver):
    ws = make_ws({
        "env/imports/projects.yml": project("P1"),
        "env/imports/templates.yml": template("JT1"),
        "env/imports/settings.yml": "controller_settings:\n  A: 1\n",
    })
    r = ok(run_import_load(ws, ver, tags=[TAGS[ver]["jt"], TAGS[ver]["projects"]],
                           probe=["controller_projects", "controller_templates", "controller_settings"]))
    assert r.defined("controller_projects") and r.defined("controller_templates")
    assert not r.defined("controller_settings")


# --------------------------------------------------------------------------------------------
# Preflight
# --------------------------------------------------------------------------------------------

preflight = pytest.mark.skipif(not PREFLIGHT_PLUGIN.exists(), reason="casc_import_preflight.py not present yet")


@preflight
@pytest.mark.parametrize("ver", ALL_VERSIONS)
def test_preflight_undefined_variable_fails(make_ws, run_import_load, ver):
    ws = make_ws({
        "env/imports/projects.yml": """\
            controller_projects:
              - name: P1
                organization: Default
                scm_url: 'https://{{ git_host_not_defined }}/p1.git'
            """,
    })
    r = failed(run_import_load(ws, ver))
    assert r.failure.startswith("Preflight:")
    assert "controller_projects [name=P1]: " in r.failure
    assert "git_host_not_defined" in r.failure
    problems = r.preflight["problems"]
    assert len(problems) == 1
    assert problems[0]["variable"] == "controller_projects"
    assert problems[0]["object"] == "name=P1"
    # Nothing after the preflight ran (the dump task), but the staging folder was removed.
    assert r.data is None
    assert r.task("Remove staging folder")["__status"] == "ok"


@preflight
def test_preflight_lists_every_problem(make_ws, run_import_load):
    ws = make_ws({
        "common/projects.yml": """\
            controller_projects:
              - name: P1
                organization: '{{ missing_org }}'
              - name: P2
                organization: Default
              - name: P3
                organization: Default
                scm_url: '{{ "x" | no_such_filter }}'
            """,
        "env/imports/users.yml": "aap_user_accounts:\n  - username: alice\n    email: '{{ missing_email }}'\n",
        "env/imports/settings.yml": "controller_settings:\n  GOOD: 1\n  BAD: '{{ missing_setting }}'\n",
    })
    r = failed(run_import_load(ws, "2.6"))
    assert r.failure.startswith("Preflight: 4 of ")
    for line in ("controller_projects [name=P1]: ", "controller_projects [name=P3]: ",
                 "aap_user_accounts [username=alice]: ", "controller_settings [BAD]: "):
        assert line in r.failure, r.failure
    assert "missing_org" in r.failure and "missing_email" in r.failure and "missing_setting" in r.failure
    assert "P2" not in r.failure
    assert {(p["variable"], p["object"]) for p in r.preflight["problems"]} == {
        ("controller_projects", "name=P1"), ("controller_projects", "name=P3"),
        ("aap_user_accounts", "username=alice"), ("controller_settings", "BAD")}


@preflight
def test_preflight_passes_unsafe_raw_omit_and_helpers(make_ws, run_import_load):
    ws = make_ws({
        "common/helpers.yml": "org: Default\nurl_base: 'https://git/{{ org }}'\n",
        "env/imports/templates.yml": """\
            controller_templates:
              - name: JT1
                organization: '{{ org }}'
                project: P1
                playbook: site.yml
                description: !unsafe '{{ runtime_only }}'
                extra_vars:
                  greeting: '{% raw %}{{ ansible_hostname }}{% endraw %}'
                webhook_url: '{{ url_base }}/hook'
            """,
        # default(omit) passes the preflight (not dumped: omit can't be serialized to JSON).
        "env/imports/projects.yml": """\
            controller_projects:
              - name: P1
                organization: Default
                scm_branch: '{{ branch_not_defined | default(omit) }}'
            """,
    })
    r = ok(run_import_load(ws, "2.6", probe=["controller_templates"]))
    assert r.preflight["__status"] == "ok"
    assert r.preflight["problems"] == []
    assert r.preflight["checked"] == 2
    jt = r.vars["controller_templates"][0]
    assert jt["description"] == "{{ runtime_only }}"
    assert jt["extra_vars"]["greeting"] == "{{ ansible_hostname }}"
    assert jt["webhook_url"] == "https://git/Default/hook"


@preflight
def test_preflight_checked_counts_objects(make_ws, run_import_load):
    ws = make_ws({
        "env/imports/projects.yml": project("P1") + "  - name: P2\n    organization: Default\n",
        "env/imports/settings.yml": "controller_settings:\n  A: 1\n  B: 2\n  C: 3\n",
        "env/imports/helpers.yml": "not_an_object: '{{ undefined_but_unused }}'\n",
    })
    r = ok(run_import_load(ws, "2.6", probe=["controller_projects"]))
    assert r.preflight["checked"] == 5


@preflight
@pytest.mark.parametrize("ver", TAG_VERSIONS)
def test_preflight_with_tags_ignores_unselected_types(make_ws, run_import_load, ver):
    ws = make_ws({
        "env/imports/projects.yml": "controller_projects:\n  - name: P1\n    organization: '{{ nope }}'\n",
        "env/imports/templates.yml": template("JT1", "'{{ also_nope }}'"),
    })
    # Selecting templates: the broken project is not loaded, but the template is checked.
    r = failed(run_import_load(ws, ver, tags=[TAGS[ver]["jt"]]))
    assert "controller_templates [name=JT1]" in r.failure
    assert "controller_projects" not in r.failure
    # Selecting something else entirely: nothing broken is loaded.
    r = ok(run_import_load(ws, ver, tags=[TAGS[ver]["settings"]], probe=[]))
    assert r.preflight["checked"] == 0


@preflight
def test_preflight_can_be_disabled(make_ws, run_import_load):
    ws = make_ws({
        "env/imports/projects.yml": "controller_projects:\n  - name: P1\n    organization: '{{ nope }}'\n",
    })
    r = ok(run_import_load(ws, "2.6", extra_vars={"import_export_preflight": False}, probe=[]))
    assert r.preflight["__status"] == "skipped"


@preflight
@requires_version("2.6")
def test_preflight_reports_aliased_object_once(make_ws, run_import_load):
    ws = make_ws({
        "env/imports/orgs.yml": "controller_organizations:\n  - name: OrgA\n    description: '{{ nope }}'\n",
    })
    r = failed(run_import_load(ws, "2.6"))
    assert [(p["variable"], p["object"]) for p in r.preflight["problems"]] == [("aap_organizations", "name=OrgA")]
