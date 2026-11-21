"""import.sh -f / import_export_only_files: take object definitions only from the named files or
folders, while helper variables and vaults still come from every file."""

import pytest

from conftest import requires_version
from test_import_load import TAGS, failed, ok, project, template

HELPER_TEMPLATE = """\
controller_templates:
  - name: JT1
    organization: Default
    project: P1
    playbook: "{{ helper.playbook }}"
"""


def only(*paths):
    return {"import_export_only_files": [str(p) for p in paths]}


def names(result, var):
    return [o["name"] for o in result.vars[var]]


@pytest.mark.parametrize("ver", [pytest.param(v, marks=requires_version(v)) for v in ("2.6", "2.4")])
def test_only_named_file_objects_load_helpers_still_resolve(make_ws, run_import_load, ver):
    ws = make_ws({
        "common/helpers.yml": "helper:\n  playbook: site.yml\n",
        "common/controller_job_templates.d/jt1.yml": HELPER_TEMPLATE,
        "common/controller_job_templates.d/jt2.yml": template("JT2"),
        "common/controller_projects.d/p1.yml": project("P1"),
    })
    r = ok(run_import_load(ws, ver, extra_vars=only(ws / "common/controller_job_templates.d/jt1.yml"),
                           probe=["controller_templates", "controller_projects", "helper"]))
    assert r.vars["controller_templates"] == [
        {"name": "JT1", "organization": "Default", "project": "P1", "playbook": "site.yml"}]
    assert not r.defined("controller_projects")
    assert r.defined("helper")
    assert r.prepare["file_filtered"] is True
    assert r.prepare["selected_files"] == ["common/controller_job_templates.d/jt1.yml"]
    assert r.prepare["loaded_object_variables"] == ["controller_templates"]
    assert "controller_projects" in r.prepare["skipped_object_variables"]


@requires_version("2.6")
def test_folder_selects_every_file_in_it(make_ws, run_import_load):
    ws = make_ws({
        "common/controller_job_templates.d/a/jt1.yml": template("JT1"),
        "common/controller_job_templates.d/jt2.yml": template("JT2"),
        "common/controller_job_templates.d/ignore_old.yml": template("OLD"),
        "env/imports/jt3.yml": template("JT3"),
    })
    r = ok(run_import_load(ws, "2.6", extra_vars=only(ws / "common/controller_job_templates.d")))
    assert sorted(names(r, "controller_templates")) == ["JT1", "JT2"]


@requires_version("2.6")
def test_several_paths_combine(make_ws, run_import_load):
    ws = make_ws({
        "common/controller_job_templates.d/jt1.yml": template("JT1"),
        "common/controller_projects.d/p1.yml": project("P1"),
        "common/controller_projects.d/p2.yml": project("P2"),
    })
    r = ok(run_import_load(ws, "2.6", extra_vars=only(
        ws / "common/controller_job_templates.d/jt1.yml", ws / "common/controller_projects.d/p1.yml")))
    assert names(r, "controller_templates") == ["JT1"]
    assert names(r, "controller_projects") == ["P1"]


@requires_version("2.6")
def test_mixed_file_keeps_its_helpers_and_objects(make_ws, run_import_load):
    ws = make_ws({
        "env/imports/both.yml": "local_helper: x\n" + project("P1"),
        "env/imports/other.yml": "other_helper: y\n" + project("P2"),
    })
    r = ok(run_import_load(ws, "2.6", extra_vars=only(ws / "env/imports/both.yml"),
                           probe=["controller_projects", "local_helper", "other_helper"]))
    assert names(r, "controller_projects") == ["P1"]
    assert r.vars["local_helper"] == "x" and r.vars["other_helper"] == "y"


@requires_version("2.6")
def test_vault_files_still_load(make_ws, run_import_load, vault_encrypt):
    ws = make_ws({
        "common/vault.yml": "vault_scm_token: s3cret\n",
        "env/imports/p1.yml": "controller_projects:\n  - name: P1\n    scm_url: \"https://{{ vault_scm_token }}@example.com\"\n",
    })
    vault_encrypt(ws / "common" / "vault.yml")
    r = ok(run_import_load(ws, "2.6", vault=True, extra_vars=only(ws / "env/imports/p1.yml")))
    assert r.vars["controller_projects"][0]["scm_url"] == "https://s3cret@example.com"
    assert r.preflight["problems"] == []


@requires_version("2.6")
def test_duplicate_elsewhere_is_ignored_and_named_file_wins(make_ws, run_import_load):
    ws = make_ws({
        "common/p1.yml": project("P1", url="https://example.com/common.git"),
        "env/imports/p1.yml": project("P1", url="https://example.com/env.git"),
    })
    assert "defined more than once" in failed(run_import_load(ws, "2.6")).failure
    r = ok(run_import_load(ws, "2.6", extra_vars=only(ws / "common/p1.yml")))
    assert [p["scm_url"] for p in r.vars["controller_projects"]] == ["https://example.com/common.git"]


@pytest.mark.parametrize("ver", [pytest.param(v, marks=requires_version(v)) for v in ("2.6", "2.4")])
def test_combined_with_tags_both_apply(make_ws, run_import_load, ver):
    ws = make_ws({
        "env/imports/both.yml": project("P1") + template("JT1"),
        "env/imports/p2.yml": project("P2"),
    })
    r = ok(run_import_load(ws, ver, tags=[TAGS[ver]["projects"]], extra_vars=only(ws / "env/imports/both.yml"),
                           probe=["controller_projects", "controller_templates"]))
    assert names(r, "controller_projects") == ["P1"]
    assert not r.defined("controller_templates")


@requires_version("2.6")
def test_nothing_left_warns(make_ws, run_import_load):
    ws = make_ws({"env/imports/jt.yml": template("JT1")})
    r = ok(run_import_load(ws, "2.6", tags=["controller_projects"], extra_vars=only(ws / "env/imports/jt.yml")))
    assert "Nothing to import" in r.warnings


@requires_version("2.6")
def test_alias_names_in_named_file(make_ws, run_import_load):
    ws = make_ws({
        "env/imports/orgs.yml": "controller_organizations:\n  - name: OrgA\n",
        "env/imports/other.yml": "aap_organizations:\n  - name: OrgB\n",
    })
    r = ok(run_import_load(ws, "2.6", extra_vars=only(ws / "env/imports/orgs.yml")))
    assert names(r, "aap_organizations") == ["OrgA"]


# --- Broken files that weren't named -----------------------------------------------------------

@requires_version("2.6")
def test_broken_unnamed_object_file_is_skipped_with_warning(make_ws, run_import_load):
    ws = make_ws({
        "env/imports/broken.yml": "controller_projects:\n  - name: [oops\n",
        "env/imports/jt.yml": template("JT1"),
    })
    r = ok(run_import_load(ws, "2.6", extra_vars=only(ws / "env/imports/jt.yml")))
    assert "Skipped env/imports/broken.yml (not in the -f files)" in r.warnings
    assert "env/imports/broken.yml" in r.prepare["skipped_files"]


@requires_version("2.6")
def test_broken_unnamed_helper_file_fails(make_ws, run_import_load):
    ws = make_ws({
        "env/imports/broken.yml": "helper:\n  x: [oops\n",
        "env/imports/jt.yml": template("JT1"),
    })
    r = failed(run_import_load(ws, "2.6", extra_vars=only(ws / "env/imports/jt.yml")))
    assert "Could not read env/imports/broken.yml" in r.failure


@requires_version("2.6")
def test_broken_named_file_fails(make_ws, run_import_load):
    ws = make_ws({"env/imports/broken.yml": "controller_projects:\n  - name: [oops\n"})
    r = failed(run_import_load(ws, "2.6", extra_vars=only(ws / "env/imports/broken.yml")))
    assert "Could not read env/imports/broken.yml" in r.failure


# --- Preflight only checks what's loaded ---------------------------------------------------------

@requires_version("2.6")
def test_preflight_ignores_objects_in_other_files(make_ws, run_import_load):
    ws = make_ws({
        "env/imports/wip.yml": "controller_projects:\n  - name: WIP\n    scm_url: '{{ vault_not_yet }}'\n",
        "env/imports/jt.yml": template("JT1"),
    })
    assert failed(run_import_load(ws, "2.6")).preflight["problems"]
    r = ok(run_import_load(ws, "2.6", extra_vars=only(ws / "env/imports/jt.yml")))
    assert r.preflight["checked"] == 1 and r.preflight["problems"] == []


# --- Paths import doesn't read -------------------------------------------------------------------

@pytest.mark.parametrize("rel, files, extra, reason", [
    ("env/exports/x/p.yml", {"env/exports/x/p.yml": project()}, {}, "outside the folders this import reads"),
    ("common/p.yml", {"common/p.yml": project()}, {"import_common": False}, "outside the folders this import reads"),
    ("env/imports/ignore_p.yml", {"env/imports/ignore_p.yml": project()}, {}, "starts with ignore_"),
    ("env/imports/ignore_old/p.yml", {"env/imports/ignore_old/p.yml": project()}, {}, "starts with ignore_"),
    ("env/imports/notes.txt", {"env/imports/notes.txt": "x"}, {}, "only .yml and .yaml files are read"),
    ("env/imports/empty", {"env/imports/empty/readme.txt": "x"}, {}, "contains no .yml/.yaml files"),
    ("env/imports/missing.yml", {}, {}, "doesn't exist"),
])
@requires_version("2.6")
def test_paths_import_does_not_read_fail_with_reason(make_ws, run_import_load, rel, files, extra, reason):
    ws = make_ws(dict(files, **{"env/imports/ok.yml": project("OK")}))
    r = failed(run_import_load(ws, "2.6", extra_vars=dict(only(ws / rel), **extra)))
    assert "isn't one of the files import reads" in r.failure
    assert reason in r.failure


@requires_version("2.6")
def test_no_file_filter_by_default(make_ws, run_import_load):
    ws = make_ws({"env/imports/p.yml": project("P1"), "common/jt.yml": template("JT1")})
    r = ok(run_import_load(ws, "2.6"))
    assert r.prepare["file_filtered"] is False
    assert names(r, "controller_projects") == ["P1"] and names(r, "controller_templates") == ["JT1"]
