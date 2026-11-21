# -*- coding: utf-8 -*-
"""Prepare the configuration files for import in one controller-side task.

1. Finds every *.yml / *.yaml file (except ignore_* files and anything in ignore_* folders) under the given folders, in order
   (common/ first, then <env>/imports/), in any folder structure: filetree (<type>.d/),
   flat, or a mix.
2. Checks for duplicate objects (same type and identity, e.g. a project with the same name
   and organization) defined more than once, and fails early unless allowed.
3. Merges the plain files without templating (lists appended, mappings combined with later
   files winning per key, anything else last-wins), keeping !unsafe and !vault values, and
   applies the cross-version aliases and identity merges (import_export_var_aliases /
   import_export_merge_keys), and writes the result to a staging folder together with any vault-encrypted files. The
   playbook loads that folder with a single include_vars, so values stay lazily templated:
   a missing variable only matters where it's used, not for the whole import.

With tags (import.sh -t), only the object variables whose dispatcher role matches a selected
tag are loaded (plus their cross-version aliases); the tag -> variable mapping is read from the
collection's dispatch role defaults, so it matches what the dispatcher runs. Object variables for
other types are dropped before the duplicate check and merge, so unfinished definitions of other
types don't get in the way. Other top-level variables (helpers used through Jinja) always load.
Without tags (import.sh -a) everything is loaded.

With only_paths (import.sh -f), object variables are taken only from the named files/folders;
helper variables and vault files still come from every file. Combined with tags, both apply.
"""

from __future__ import absolute_import, division, print_function

__metaclass__ = type

import io
import os
import re
import shutil
import importlib.util
import tempfile

import yaml

from ansible.errors import AnsibleActionFail
from ansible.module_utils.common.text.converters import to_text
from ansible.plugins.action import ActionBase
from ansible.utils.collection_loader import AnsibleCollectionConfig

DOCUMENTATION = r"""
---
action: casc_import_prepare
short_description: Find, duplicate-check and stage configuration files for import
options:
  paths: {type: list, required: true, description: Folders to read, in merge order.}
  display_root: {type: str, description: Paths in messages are shown relative to this folder.}
  var_aliases: {type: list, default: [], description: "[{target, source, rename_keys}] for this AAP version."}
  identity_keys: {type: dict, default: {}, description: "Variable name -> identity fields (__default__ for others)."}
  skip_duplicate_check: {type: list, default: [], description: Variables that are never duplicate-checked.}
  allow_duplicates: {type: bool, default: false}
  merge_keys: {type: dict, default: {}, description: "Variable name -> identity fields; entries sharing them are merged."}
  run_tags: {type: list, default: [all], description: "ansible_run_tags; anything but [all] limits the object types loaded."}
  skip_tags: {type: list, default: [], description: ansible_skip_tags; object types whose role matches are not loaded.}
  only_paths: {type: list, default: [], description: "Files/folders (absolute) to take object variables from; others only contribute helper variables and vaults."}
  dispatch_role: {type: str, description: "FQCN of the dispatch role whose defaults map tags to variables (e.g. infra.aap_configuration.dispatch)."}
"""

def _load_casc_lists():
    # Repo-level filters (filter_plugins/casc_lists.py), shared with the flat_to_filetree role.
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.normpath(os.path.join(here, "..", "..", "..", "filter_plugins", "casc_lists.py"))
    spec = importlib.util.spec_from_file_location("casc_lists_for_import", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_casc_lists = _load_casc_lists()


class _Unsafe(str):
    """A value tagged !unsafe; written back with the tag."""


class _Vault(str):
    """A !vault value (ciphertext); written back unchanged."""


class _RawLoader(getattr(yaml, "CSafeLoader", yaml.SafeLoader)):
    pass


_RawLoader.add_constructor("!unsafe", lambda loader, node: _Unsafe(loader.construct_scalar(node)))
_RawLoader.add_constructor("!vault", lambda loader, node: _Vault(loader.construct_scalar(node)))


class _RawDumper(getattr(yaml, "CSafeDumper", yaml.SafeDumper)):
    pass


# Values from task args (e.g. alias rename_keys) are Ansible str/dict/list subclasses.
_RawDumper.add_multi_representer(str, lambda dumper, data: dumper.represent_str(str(data)))
_RawDumper.add_multi_representer(dict, lambda dumper, data: dumper.represent_dict(dict(data)))
_RawDumper.add_multi_representer(list, lambda dumper, data: dumper.represent_list(list(data)))
_RawDumper.add_representer(_Unsafe, lambda dumper, data: dumper.represent_scalar("!unsafe", str(data)))
_RawDumper.add_representer(_Vault, lambda dumper, data: dumper.represent_scalar("!vault", str(data), style="|"))


def _merge_values(values):
    if all(isinstance(v, list) for v in values):
        return [item for v in values for item in v]
    if all(isinstance(v, dict) for v in values):
        merged = {}
        for v in values:
            merged.update(v)
        return merged
    return values[-1]


_OBJECT_VAR_RE = re.compile(r"^(aap|controller|gateway|eda|hub)_")
_VAULT_HEADER = "$ANSIBLE_VAULT"


def _yaml_files(root):
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        # Folders named ignore_* are skipped with everything in them, like ignore_* files.
        dirnames[:] = [d for d in dirnames if not d.startswith("ignore_")]
        for filename in filenames:
            if filename.startswith("ignore_") or not filename.endswith((".yml", ".yaml")):
                continue
            found.append(os.path.join(dirpath, filename))
    # Case-insensitive, like the Jinja sort filter the previous loader used.
    return sorted(found, key=lambda p: p.lower())


def _kind(value):
    # ansible-core 2.19+ wraps loaded values in tagged subclasses (_AnsibleTaggedList, ...).
    for kind, name in ((list, "list"), (str, "string"), (bool, "boolean"), (int, "number"), (float, "number")):
        if isinstance(value, kind):
            return name
    return type(value).__name__


def _dispatcher_roles(fqcn):
    """Return ([{var, tags}], path) from the dispatch role's defaults, or (None, None) if not found."""
    try:
        namespace, collection, role = fqcn.split(".")
    except (AttributeError, ValueError):
        return None, None
    for base in AnsibleCollectionConfig.collection_paths or []:
        base = os.path.expanduser(base)
        if os.path.basename(base.rstrip(os.sep)) != "ansible_collections":
            base = os.path.join(base, "ansible_collections")
        path = os.path.join(base, namespace, collection, "roles", role, "defaults", "main.yml")
        if not os.path.isfile(path):
            continue
        with io.open(path, "r", encoding="utf-8") as handle:
            data = yaml.load(handle, Loader=_RawLoader) or {}
        roles = []
        # Every list of {role, var, tags} entries (2.5+ splits them per component and joins
        # them with Jinja; 2.4 has one list).
        for value in data.values() if isinstance(data, dict) else []:
            if not isinstance(value, list):
                continue
            for entry in value:
                if isinstance(entry, dict) and entry.get("var") and entry.get("tags"):
                    tags = entry["tags"]
                    roles.append({"var": str(entry["var"]), "tags": {str(t) for t in (tags if isinstance(tags, list) else [tags])}})
        return roles, path
    return None, None


_TOP_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:", re.M)


def _rename_keys(item, mapping):
    if not mapping or not isinstance(item, dict):
        return item
    item = dict(item)
    for old, new in mapping.items():
        if old in item:
            value = item.pop(old)
            item.setdefault(new, value)
    return item


def _conflicts(items):
    """Return the fields whose values differ between the given dicts."""
    fields = set()
    for index, first in enumerate(items):
        for second in items[index + 1:]:
            for key in set(first) & set(second):
                if first[key] != second[key]:
                    fields.add(key)
    return sorted(fields)


class ActionModule(ActionBase):
    TRANSFERS_FILES = False
    _requires_connection = False
    _supports_check_mode = True

    def _rel(self, path, root):
        return os.path.relpath(path, root) if root else path

    def _parse(self, path, root):
        with io.open(path, "r", encoding="utf-8") as handle:
            text = handle.read()
        encrypted = text.lstrip().startswith(_VAULT_HEADER)
        try:
            data = self._loader.load_from_file(path) if encrypted else self._loader.load(
                text, file_name=path, show_content=False
            )
        except Exception as exc:
            raise AnsibleActionFail("Could not read %s: %s" % (self._rel(path, root), to_text(exc)))
        if data is None:
            data = {}
        if not isinstance(data, dict):
            raise AnsibleActionFail(
                "%s must contain variables (a YAML mapping such as 'controller_projects: [...]'), not a %s"
                % (self._rel(path, root), _kind(data))
            )
        return text, data, encrypted

    def _why_not_read(self, path, roots, display_root):
        if not os.path.exists(path):
            return "it doesn't exist."
        inside = [r for r in roots if path == r or path.startswith(r.rstrip(os.sep) + os.sep)]
        if not inside:
            return (
                "it's outside the folders this import reads (%s). common/ is only read when "
                "import_common is true, and export folders are never read; copy the file into "
                "common/ or <env>/imports/ first." % ", ".join(self._rel(r, display_root) + "/" for r in roots)
            )
        rel = os.path.relpath(path, inside[0])
        if any(part.startswith("ignore_") for part in rel.split(os.sep)):
            return "it (or a folder above it) starts with ignore_."
        if os.path.isdir(path):
            return "the folder contains no .yml/.yaml files import reads."
        return "only .yml and .yaml files are read."

    def run(self, tmp=None, task_vars=None):
        result = super(ActionModule, self).run(tmp, task_vars)
        args = self._task.args
        roots = [os.path.abspath(os.path.expanduser(p)) for p in (args.get("paths") or []) if p]
        display_root = args.get("display_root") or ""
        aliases = args.get("var_aliases") or []
        identity_keys = args.get("identity_keys") or {}
        skip_check = set(args.get("skip_duplicate_check") or [])
        allow_duplicates = bool(args.get("allow_duplicates"))
        merge_keys = args.get("merge_keys") or {}
        run_tags = {str(t) for t in (args.get("run_tags") or ["all"])}
        skip_tags = {str(t) for t in (args.get("skip_tags") or [])}
        warnings = []

        # --- Tag selection: which object variables to load -------------------------------------
        roles, _path = _dispatcher_roles(args.get("dispatch_role")) if args.get("dispatch_role") else (None, None)
        all_object_vars = None  # every object variable name this version knows (None = unknown)
        if roles is not None:
            all_object_vars = {r["var"] for r in roles} | {
                a["source"] for a in aliases if isinstance(a, dict) and a.get("source") and a.get("target")
            }
        known_vars = selected_vars = None  # None = load everything
        if run_tags != {"all"} or skip_tags:
            if roles is None:
                warnings.append(
                    "Could not find the defaults of %s, so every object type is loaded regardless of tags."
                    % args.get("dispatch_role")
                )
            else:
                known_vars = {r["var"] for r in roles}
                selected_vars = {
                    r["var"] for r in roles
                    if ("all" in run_tags or r["tags"] & run_tags) and not r["tags"] & skip_tags
                }
                for alias in aliases:
                    if isinstance(alias, dict) and alias.get("source") and alias.get("target"):
                        known_vars.add(alias["source"])
                        if alias["target"] in selected_vars:
                            selected_vars.add(alias["source"])
        skipped_vars = {}  # variable -> number of files it was skipped in
        skipped_files = []

        alias_of = {a["source"]: a for a in aliases if isinstance(a, dict) and "source" in a and "target" in a}
        missing = [r for r in roots if not os.path.isdir(r)]
        files = [path for root in roots if os.path.isdir(root) for path in _yaml_files(root)]

        # --- File selection (import.sh -f) -------------------------------------------------------
        only_paths = [os.path.realpath(os.path.expanduser(to_text(p))) for p in (args.get("only_paths") or []) if p]
        selected_files = None  # None = object variables from every file
        if only_paths:
            real = {os.path.realpath(f): f for f in files}
            real_roots = [os.path.realpath(r) for r in roots]
            selected_files = set()
            for wanted in only_paths:
                matched = [r for r in real if r == wanted or r.startswith(wanted.rstrip(os.sep) + os.sep)]
                if not matched:
                    raise AnsibleActionFail("%s isn't one of the files import reads: %s" % (wanted, self._why_not_read(wanted, real_roots, display_root)))
                selected_files.update(matched)

        def is_object(key):
            return key in all_object_vars if all_object_vars is not None else bool(_OBJECT_VAR_RE.match(key))

        def unselected(key, path):
            if known_vars is not None and key in known_vars and key not in selected_vars:
                return True  # type not selected by tags
            return selected_files is not None and os.path.realpath(path) not in selected_files and is_object(key)

        filtering = known_vars is not None or selected_files is not None

        parsed = []  # (path, text, data, encrypted)
        occurrences = {}  # top-level key -> [index into parsed]
        for path in files:
            try:
                text, data, encrypted = self._parse(path, display_root)
            except AnsibleActionFail as exc:
                # With tags or -f, a broken file holding only objects that aren't being imported
                # is only a warning.
                keys = set()
                if filtering:
                    with io.open(path, "r", encoding="utf-8", errors="replace") as handle:
                        keys = set(_TOP_KEY_RE.findall(handle.read()))
                if keys and all(unselected(k, path) for k in keys):
                    why = ("not in the -f files" if selected_files is not None and os.path.realpath(path) not in selected_files
                           else "not selected by tags")
                    warnings.append("Skipped %s (%s) because it can't be read: %s" % (self._rel(path, display_root), why, to_text(exc)))
                    for key in keys:
                        skipped_vars[key] = skipped_vars.get(key, 0) + 1
                    skipped_files.append(self._rel(path, display_root))
                    continue
                raise
            if not data:
                continue
            if filtering:
                dropped = [k for k in data if unselected(k, path)]
                for key in dropped:
                    skipped_vars[key] = skipped_vars.get(key, 0) + 1
                if dropped and len(dropped) == len(data):
                    skipped_files.append(self._rel(path, display_root))
                    continue
                if dropped and not encrypted:  # vault files are staged whole
                    data = {k: v for k, v in data.items() if k not in dropped}
            for key in data:
                occurrences.setdefault(key, []).append(len(parsed))
            parsed.append((path, text, data, encrypted))

        # --- Duplicate objects ---------------------------------------------------------------
        objects = {}  # (type, identity) -> [(file, var, item)]
        for path, _text, data, _enc in parsed:
            for var, value in data.items():
                if var in skip_check or not _OBJECT_VAR_RE.match(var) or not isinstance(value, list):
                    continue
                alias = alias_of.get(var)
                obj_type = alias["target"] if alias else var
                fields = identity_keys.get(obj_type) or identity_keys.get(var) or identity_keys.get("__default__") or ["name"]
                for item in value:
                    if not isinstance(item, dict) or item.get(fields[0]) is None:
                        continue
                    item = _rename_keys(item, alias.get("rename_keys") if alias else None)
                    identity = tuple(to_text(item.get(f)) if item.get(f) is not None else None for f in fields)
                    objects.setdefault((obj_type, tuple(fields), identity), []).append((path, var, item))

        conflicting, consistent = [], []
        for (obj_type, fields, identity), found in sorted(objects.items(), key=lambda kv: (kv[0][0], [to_text(i) for i in kv[0][2]])):
            if len(found) < 2:
                continue
            label = ", ".join("%s=%s" % (f, v) for f, v in zip(fields, identity) if v is not None)
            where = ["%s (%s)" % (self._rel(p, display_root), var) for p, var, _item in found]
            fields_differ = _conflicts([item for _p, _v, item in found])
            entry = {"type": obj_type, "identity": label, "files": where, "differs": fields_differ}
            (conflicting if fields_differ else consistent).append(entry)

        def describe(entries, with_fields):
            lines = []
            for e in entries:
                extra = " - differs in: %s" % ", ".join(e["differs"]) if with_fields else ""
                lines.append("  %s [%s]%s" % (e["type"], e["identity"], extra))
                lines.extend("      %s" % w for w in e["files"])
            return "\n".join(lines)

        if missing:
            warnings.append("Folder(s) not found, skipped: %s" % ", ".join(self._rel(m, display_root) for m in missing))
        if conflicting:
            message = (
                "%d object(s) are defined more than once with different values:\n%s\n"
                "Keep one definition of each (or move the shared one to common/ and remove it from imports/). "
                "To import anyway, run import.sh with --allow-duplicates (import_export_allow_duplicates=true); "
                "every definition is then sent to AAP in order, so the last one (from <env>/imports/) wins, "
                "except for organizations, teams, users and applications, where the first one wins."
                % (len(conflicting), describe(conflicting, True))
            )
            if not allow_duplicates:
                result.update(failed=True, msg=message, duplicates=conflicting)
                return result
            warnings.append(message)
        if consistent:
            warnings.append(
                "%d object(s) are defined more than once without conflicting values (safe to import; "
                "consider keeping only one definition):\n%s"
                % (len(consistent), describe(consistent, False))
            )

        # --- Staging copy ------------------------------------------------------------------------
        values = {}  # key -> [value per plain file, in order]
        encrypted_keys = {}  # key -> encrypted file index
        for i, (path, text, data, encrypted) in enumerate(parsed):
            if encrypted:
                for key in data:
                    encrypted_keys[key] = i
                continue
            try:
                raw = yaml.load(text, Loader=_RawLoader) or {}
            except yaml.YAMLError as exc:
                raise AnsibleActionFail("Could not read %s: %s" % (self._rel(path, display_root), to_text(exc)))
            for key, value in raw.items():
                if key in data:  # data has the keys left after tag selection
                    values.setdefault(key, []).append(value)
        for key, indexes in occurrences.items():
            in_vault = [i for i in indexes if parsed[i][3]]
            if in_vault and len(indexes) > 1:
                raise AnsibleActionFail(
                    "'%s' is defined in a vault-encrypted file and elsewhere (%s); define it in one place."
                    % (key, ", ".join(self._rel(parsed[i][0], display_root) for i in indexes))
                )

        merged = {key: _merge_values(found) for key, found in values.items()}
        # Append items written under another AAP version's names onto the names this version uses.
        for alias in aliases:
            items = merged.get(alias.get("source"))
            if not isinstance(items, list) or not items:
                continue
            target = merged.get(alias["target"]) or []
            for item in _casc_lists.rename_keys(items, alias.get("rename_keys") or {}):
                if item not in target:
                    target.append(item)
            merged[alias["target"]] = target
        for key, fields in merge_keys.items():
            if isinstance(merged.get(key), list) and len(merged[key]) > 1:
                merged[key] = _casc_lists.merge_by_key(merged[key], fields)
        stage_dir = tempfile.mkdtemp(prefix="casc_import_")
        try:
            with io.open(os.path.join(stage_dir, "merged.yml"), "w", encoding="utf-8") as handle:
                yaml.dump(merged, handle, Dumper=_RawDumper, allow_unicode=True, default_flow_style=False, sort_keys=False)
            for n, i in enumerate(sorted(set(encrypted_keys.values()))):
                with io.open(os.path.join(stage_dir, "vault_%03d.yml" % n), "w", encoding="utf-8") as handle:
                    handle.write(parsed[i][1])
        except Exception:
            shutil.rmtree(stage_dir, ignore_errors=True)
            raise
        if filtering and not any(is_object(k) for k in merged):
            warnings.append("Nothing to import: no object definitions are left after applying the selected tags and files.")
        merges = [{"name": key, "files": len(found)} for key, found in values.items() if len(found) > 1]

        result.update(
            changed=False,
            stage_dir=stage_dir,
            files=len(files),
            loaded_files=len(parsed),
            merges=merges,
            variables=sorted(set(occurrences) | set(merged)),
            duplicates_merged=len(consistent),
            duplicates_conflicting=len(conflicting),
            tag_filtered=known_vars is not None,
            file_filtered=selected_files is not None,
            selected_files=sorted(self._rel(f, display_root) for f in (selected_files or [])),
            loaded_object_variables=sorted(k for k in merged if filtering and is_object(k)),
            skipped_object_variables=sorted(skipped_vars),
            skipped_files=skipped_files,
            # Loaded object variables (for the preflight check), tags or not. Alias sources are
            # left out: their items were copied into the target, which is what gets dispatched.
            object_variables=sorted(
                k for k in merged
                if k not in alias_of
                and (k in all_object_vars if all_object_vars is not None else _OBJECT_VAR_RE.match(k))
            ),
        )
        if warnings:
            result["warnings"] = warnings
        return result
