"""Unit tests for the pure helpers in casc_import_prepare.py."""

import importlib.util
import os
import types

import pytest

from conftest import ACTION_PLUGINS, REPO, requires_version


@pytest.fixture(scope="module")
def prep():
    spec = importlib.util.spec_from_file_location(
        "casc_import_prepare_under_test", ACTION_PLUGINS / "casc_import_prepare.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# --- _merge_values -------------------------------------------------------------------------

def test_merge_lists_appended_in_order(prep):
    assert prep._merge_values([[1, 2], [3], []]) == [1, 2, 3]


def test_merge_dicts_later_wins(prep):
    assert prep._merge_values([{"a": 1, "b": 1}, {"b": 2, "c": 2}]) == {"a": 1, "b": 2, "c": 2}


def test_merge_dicts_is_shallow(prep):
    assert prep._merge_values([{"a": {"x": 1}}, {"a": {"y": 2}}]) == {"a": {"y": 2}}


@pytest.mark.parametrize("values, expected", [
    (["a", "b"], "b"),
    ([1, None], None),
    ([[1], {"a": 1}], {"a": 1}),  # mixed types: last wins
    ([{"a": 1}, [1]], [1]),
])
def test_merge_scalars_and_mixed_last_wins(prep, values, expected):
    assert prep._merge_values(values) == expected


def test_merge_does_not_mutate_inputs(prep):
    a, b = {"a": 1}, {"b": 2}
    prep._merge_values([a, b])
    assert a == {"a": 1} and b == {"b": 2}


# --- _conflicts ----------------------------------------------------------------------------

def test_conflicts_none_when_identical(prep):
    assert prep._conflicts([{"name": "a", "x": 1}, {"name": "a", "x": 1}]) == []


def test_conflicts_only_shared_differing_fields(prep):
    items = [{"name": "a", "x": 1, "only1": 1}, {"name": "a", "x": 2, "only2": 2}]
    assert prep._conflicts(items) == ["x"]


def test_conflicts_across_three_items_sorted(prep):
    items = [{"b": 1, "a": 1}, {"b": 1, "a": 1}, {"b": 2, "a": 3}]
    assert prep._conflicts(items) == ["a", "b"]


# --- _rename_keys --------------------------------------------------------------------------

def test_rename_keys(prep):
    item = {"username": "u", "is_system_auditor": True}
    out = prep._rename_keys(item, {"is_system_auditor": "is_platform_auditor"})
    assert out == {"username": "u", "is_platform_auditor": True}
    assert item == {"username": "u", "is_system_auditor": True}  # input untouched


def test_rename_keys_existing_target_wins(prep):
    out = prep._rename_keys({"auditor": False, "is_platform_auditor": True}, {"auditor": "is_platform_auditor"})
    assert out == {"is_platform_auditor": True}


@pytest.mark.parametrize("item", ["text", ["a"], None])
def test_rename_keys_non_dict_untouched(prep, item):
    assert prep._rename_keys(item, {"a": "b"}) == item


def test_rename_keys_no_mapping(prep):
    item = {"a": 1}
    assert prep._rename_keys(item, None) is item


# --- _yaml_files ---------------------------------------------------------------------------

def test_yaml_files(prep, tmp_path):
    for rel in ("b.yml", "A.yaml", "sub/c.YML", "sub/ignore_x.yml", "sub/d.yml", "e.txt", "ignore_dir/f.yml",
                "sub/ignore_old.d/deep/g.yml", "sub/not_ignore_dir/h.yml"):
        p = tmp_path / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("")
    found = [os.path.relpath(p, str(tmp_path)) for p in prep._yaml_files(str(tmp_path))]
    # Case-insensitive order; ignore_* files and ignore_* folders (at any depth, with everything
    # in them) are skipped; only a name *starting* with ignore_ counts; extension is case-sensitive.
    assert found == ["A.yaml", "b.yml", "sub/d.yml", "sub/not_ignore_dir/h.yml"]


# --- _dispatcher_roles ---------------------------------------------------------------------

def _with_paths(monkeypatch, prep, paths):
    monkeypatch.setattr(prep, "AnsibleCollectionConfig", types.SimpleNamespace(collection_paths=paths))


@pytest.mark.parametrize("fqcn", [None, "", "infra.dispatch", "a.b.c.d"])
def test_dispatcher_roles_bad_fqcn(prep, fqcn):
    assert prep._dispatcher_roles(fqcn) == (None, None)


def test_dispatcher_roles_not_found(prep, monkeypatch, tmp_path):
    _with_paths(monkeypatch, prep, [str(tmp_path)])
    assert prep._dispatcher_roles("infra.aap_configuration.dispatch") == (None, None)


def test_dispatcher_roles_reads_every_list(prep, monkeypatch, tmp_path):
    defaults = tmp_path / "ansible_collections" / "ns" / "col" / "roles" / "dispatch" / "defaults" / "main.yml"
    defaults.parent.mkdir(parents=True)
    defaults.write_text(
        "a_roles:\n  - {role: x, var: x_var, tags: x_tag}\n  - {role: y, var: y_var, tags: [y1, y2]}\n"
        "  - {role: z, var: z_no_tags}\n"
        "b_roles:\n  - {role: w, var: w_var, tags: [w]}\n"
        "joined: '{{ a_roles + b_roles }}'\n"
    )
    # Path without the ansible_collections suffix gets it appended; a missing path is skipped.
    _with_paths(monkeypatch, prep, [str(tmp_path / "missing"), str(tmp_path)])
    roles, path = prep._dispatcher_roles("ns.col.dispatch")
    assert path == str(defaults)
    assert {r["var"]: r["tags"] for r in roles} == {"x_var": {"x_tag"}, "y_var": {"y1", "y2"}, "w_var": {"w"}}


@requires_version("2.6")
def test_dispatcher_roles_real_26(prep, monkeypatch):
    _with_paths(monkeypatch, prep, [str(REPO / "collections" / "2.6")])
    roles, _ = prep._dispatcher_roles("infra.aap_configuration.dispatch")
    tags = {}
    for r in roles:
        tags.setdefault(r["var"], set()).update(r["tags"])
    assert "controller_job_templates" in tags["controller_templates"]
    assert "gateway_organizations" in tags["aap_organizations"]
    assert "controller_projects" in tags["controller_projects"]


@requires_version("2.4")
def test_dispatcher_roles_real_24(prep, monkeypatch):
    _with_paths(monkeypatch, prep, [str(REPO / "collections" / "2.4" / "ansible_collections")])
    roles, _ = prep._dispatcher_roles("infra.controller_configuration.dispatch")
    tags = {r["var"]: r["tags"] for r in roles}
    assert tags["controller_templates"] == {"job_templates"}
    assert tags["controller_organizations"] == {"organizations"}


# --- !unsafe / !vault round trip -----------------------------------------------------------

def test_unsafe_and_vault_round_trip(prep):
    import yaml
    text = "a: !unsafe '{{ x }}'\nb: !vault |\n  $ANSIBLE_VAULT;1.1;AES256\n  3132\nc: plain\n"
    data = yaml.load(text, Loader=prep._RawLoader)
    assert isinstance(data["a"], prep._Unsafe) and isinstance(data["b"], prep._Vault)
    dumped = yaml.dump(data, Dumper=prep._RawDumper)
    assert "!unsafe" in dumped and "!vault" in dumped
    again = yaml.load(dumped, Loader=prep._RawLoader)
    assert again == data
    assert isinstance(again["a"], prep._Unsafe) and isinstance(again["b"], prep._Vault)
