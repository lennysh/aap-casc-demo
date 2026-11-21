# -*- coding: utf-8 -*-
"""Split flat AAP variable files into the filetree (<type>.d/) layout in one task.

Runs entirely on the controller. Doing the read / alias / merge / split / write /
format steps in Python, instead of hundreds of looped tasks plus one module call per
output file, turns a multi-minute conversion into a second or two.
"""

from __future__ import absolute_import, division, print_function

__metaclass__ = type

import importlib.util
import io
import os
import re
import shutil

from ansible.errors import AnsibleActionFail
from ansible.module_utils.common.text.converters import to_text
from ansible.plugins.action import ActionBase

import yaml

try:
    from ruamel.yaml import YAML
    from ruamel.yaml.scalarstring import PreservedScalarString

    HAS_RUAMEL = True
except ImportError:
    HAS_RUAMEL = False

DOCUMENTATION = r"""
---
action: flat_to_filetree_split
short_description: Split flat AAP variable files into the filetree layout
description:
  - Reads every C(*.yml)/C(*.yaml) file under I(source_path) (skipping C(ignore_*)) without
    templating (keeping C(!unsafe) and C(!vault) tags), applies variable aliases and identity merges, writes one file per object
    under I(output_path)/<type>.d/, then pretty-prints every YAML file in I(output_path)
    (same formatting as library/format_yaml.py with auto_block_scalars).
options:
  source_path: {type: str, required: true}
  output_path: {type: str, required: true}
  copy_only_map: {type: dict, default: {}}
  var_aliases: {type: dict, default: {}}
  merge_keys: {type: dict, default: {}}
  var_to_folder_map: {type: dict, required: true}
  filename_logic: {type: dict, required: true}
"""

_UNSAFE_SEGMENT_RE = re.compile(r'[/\\:\0*?"<>|]|[\x00-\x1f]')
_CONSECUTIVE_UNDERSCORES_RE = re.compile(r"_+")


def _load_casc_lists():
    # Reuse the repo-level filters (filter_plugins/casc_lists.py) so behaviour matches import.
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.normpath(os.path.join(here, "..", "..", "..", "filter_plugins", "casc_lists.py"))
    spec = importlib.util.spec_from_file_location("casc_lists_for_flat_to_filetree", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class _Unsafe(str):
    """A string tagged !unsafe in the source; written back with the tag."""


class _Vault(str):
    """A !vault value (ciphertext); written back unchanged."""


class _Loader(getattr(yaml, "CSafeLoader", yaml.SafeLoader)):
    pass


_Loader.add_constructor("!unsafe", lambda loader, node: _Unsafe(loader.construct_scalar(node)))
_Loader.add_constructor("!vault", lambda loader, node: _Vault(loader.construct_scalar(node)))


class _Dumper(yaml.SafeDumper):
    pass


# Values that came from task args are Ansible's str/dict/list subclasses; dump them as plain types.
_Dumper.add_multi_representer(str, yaml.representer.SafeRepresenter.represent_str)
_Dumper.add_multi_representer(dict, yaml.representer.SafeRepresenter.represent_dict)
_Dumper.add_multi_representer(list, yaml.representer.SafeRepresenter.represent_list)
_Dumper.add_representer(_Unsafe, lambda dumper, data: dumper.represent_scalar("!unsafe", str(data)))
_Dumper.add_representer(_Vault, lambda dumper, data: dumper.represent_scalar("!vault", str(data), style="|"))


_casc_lists = _load_casc_lists()
rename_keys = _casc_lists.rename_keys
merge_by_key = _casc_lists.merge_by_key


def safe_path_segment(value):
    """Same as the role's safe_path_segment filter."""
    if value is None:
        return "unnamed"
    result = str(value).strip()
    result = _UNSAFE_SEGMENT_RE.sub("_", result)
    result = _CONSECUTIVE_UNDERSCORES_RE.sub("_", result)
    result = result.strip(" _.")
    return result or "unnamed"


def _yaml_files(root):
    found = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for filename in filenames:
            if filename.startswith("ignore_"):
                continue
            if filename.endswith((".yml", ".yaml")):
                found.append(os.path.join(dirpath, filename))
    return sorted(found)


def _combine_append_rp(base, new):
    """Equivalent of base | combine(new, list_merge='append_rp') (non-recursive)."""
    result = dict(base)
    for key, value in new.items():
        old = result.get(key)
        if isinstance(old, list) and isinstance(value, list):
            result[key] = [item for item in old if item not in value] + value
        else:
            result[key] = value
    return result


def _unique_sorted(values):
    unique = []
    for value in values:
        if value not in unique:
            unique.append(value)
    try:
        # Jinja's sort filter is case-insensitive by default.
        return sorted(unique, key=lambda v: v.lower() if isinstance(v, str) else v)
    except TypeError:
        return sorted(unique, key=lambda v: str(v).lower())


def _repair_flattened_crypto_keys(text):
    if "-----BEGIN" in text and "-----END" in text and "\n" not in text:
        match = re.search(r"(-----BEGIN.*?-----)\s+(.*?)\s+(-----END.*?-----)", text)
        if match:
            return "%s\n%s\n%s" % (match.group(1), match.group(2).replace(" ", "\n"), match.group(3))
    return text


def _clean_yaml_tree(node):
    if hasattr(node, "fa"):
        node.fa.set_block_style()
    if isinstance(node, dict):
        children = list(node.items())
    elif isinstance(node, list):
        children = list(enumerate(node))
    else:
        return
    for key, value in children:
        if isinstance(value, str):
            value = _repair_flattened_crypto_keys(value)
            node[key] = PreservedScalarString(value) if "\n" in value else value
        else:
            _clean_yaml_tree(value)


def _new_formatter():
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.explicit_start = True
    yaml.explicit_end = True
    yaml.default_flow_style = False
    yaml.width = 4096
    yaml.indent(mapping=2, sequence=4, offset=2)
    return yaml


def _format_text(text):
    yaml = _new_formatter()
    data = yaml.load(text)
    _clean_yaml_tree(data)
    out = io.StringIO()
    yaml.dump(data, out)
    return out.getvalue()


def _relpath(folder, subfolder, filename):
    parts = [safe_path_segment(folder)]
    if (subfolder or "").strip():
        parts.append(safe_path_segment(subfolder))
    parts.append(safe_path_segment(filename))
    return os.path.join(*parts)


def _dump(var_name, value):
    # Same options as Ansible's to_nice_yaml filter.
    return to_text(
        yaml.dump(
            {var_name: value}, Dumper=_Dumper, indent=2, allow_unicode=True,
            default_flow_style=False, sort_keys=False, explicit_start=True,
        )
    )


def build_outputs(combined, folder_map, filename_logic, copy_only_vars):
    """Return {relative_path: yaml_text} for every object file to write."""
    outputs = {}
    for var_name, folder in folder_map.items():
        if var_name not in combined or var_name in copy_only_vars:
            continue
        value = combined[var_name]
        if value is None:
            continue
        rules = filename_logic.get(var_name) or filename_logic["__default__"]
        primary = rules[0]
        kind = primary.get("type")

        if kind == "dict":
            if value:
                outputs[_relpath(folder, primary.get("subfolder"), primary["filename"])] = _dump(var_name, value)
            continue
        if kind == "single_list_item":
            if isinstance(value, (list, dict)):
                outputs[_relpath(folder, primary.get("subfolder"), primary["filename"])] = _dump(var_name, value)
            continue
        if kind != "list" or not isinstance(value, list):
            continue

        for rule in rules:
            if rule.get("type") != "list":
                continue
            key = rule["key"]
            matching = [item for item in value if isinstance(item, dict) and key in item]
            for group_key in _unique_sorted([item[key] for item in matching]):
                group = [item for item in matching if item[key] == group_key]
                filename = rule.get("filename") or ("%s.yml" % group_key)
                outputs[_relpath(folder, rule.get("subfolder"), filename)] = _dump(var_name, group)
    return outputs


class ActionModule(ActionBase):
    TRANSFERS_FILES = False
    _requires_connection = False

    def run(self, tmp=None, task_vars=None):
        result = super(ActionModule, self).run(tmp, task_vars)
        args = self._task.args

        source = (args.get("source_path") or "").strip()
        output = (args.get("output_path") or "").strip()
        if not source or not output:
            raise AnsibleActionFail("Please define 'flat_to_filetree_source_path' and 'flat_to_filetree_output_path'")
        source = os.path.abspath(os.path.expanduser(source))
        output = os.path.abspath(os.path.expanduser(output))
        if not os.path.isdir(source):
            raise AnsibleActionFail("Source path not found: %s" % source)

        copy_only_map = args.get("copy_only_map") or {}
        var_aliases = args.get("var_aliases") or {}
        merge_keys = args.get("merge_keys") or {}
        folder_map = args.get("var_to_folder_map") or {}
        filename_logic = args.get("filename_logic") or {}
        check_mode = bool(self._task.check_mode)

        source_files = _yaml_files(source)
        copy_only = [f for f in source_files if os.path.basename(f) in copy_only_map]
        to_process = [f for f in source_files if os.path.basename(f) not in copy_only_map]
        copy_only_vars = [v["var_name"] for v in copy_only_map.values() if isinstance(v, dict) and "var_name" in v]

        # Parse without templating, keeping !unsafe (AAP-side Jinja such as credential type
        # injectors must not be rendered on import) and !vault values.
        combined = {}
        for path in to_process:
            with io.open(path, "r", encoding="utf-8") as handle:
                text = handle.read()
            try:
                parsed = yaml.load(text, Loader=_Loader)
            except Exception as exc:
                raise AnsibleActionFail("Failed to parse %s: %s" % (path, to_text(exc)))
            if isinstance(parsed, dict):
                combined = _combine_append_rp(combined, parsed)

        # Normalize to the standard (AAP 2.5+) variable names, in order.
        for source_var, alias in var_aliases.items():
            if source_var not in combined:
                continue
            items = combined.pop(source_var) or []
            target = alias["target"]
            combined[target] = (combined.get(target) or []) + rename_keys(items, alias.get("rename_keys") or {})

        for var_name, keys in merge_keys.items():
            if isinstance(combined.get(var_name), list):
                combined[var_name] = merge_by_key(combined[var_name], keys)

        outputs = build_outputs(combined, folder_map, filename_logic, copy_only_vars)

        if not check_mode:
            for path in copy_only:
                spec = copy_only_map[os.path.basename(path)]
                dest = os.path.join(output, _relpath(spec["folder"], "", spec.get("filename") or os.path.basename(path)))
                os.makedirs(os.path.dirname(dest), mode=0o755, exist_ok=True)
                shutil.copyfile(path, dest)
                os.chmod(dest, 0o644)
            for relpath, text in outputs.items():
                dest = os.path.join(output, relpath)
                os.makedirs(os.path.dirname(dest), mode=0o755, exist_ok=True)
                with io.open(dest, "w", encoding="utf-8") as handle:
                    handle.write(text)
                os.chmod(dest, 0o644)
            if HAS_RUAMEL and os.path.isdir(output):
                for path in _yaml_files(output):
                    with io.open(path, "r", encoding="utf-8") as handle:
                        original = handle.read()
                    try:
                        formatted = _format_text(original)
                    except Exception as exc:
                        raise AnsibleActionFail("Failed to format %s: %s" % (path, to_text(exc)))
                    if formatted != original:
                        with io.open(path, "w", encoding="utf-8") as handle:
                            handle.write(formatted)

        result.update(
            changed=bool(outputs or copy_only),
            source_files=len(source_files),
            object_files=len(outputs),
            copied_as_is=len(copy_only),
            output_path=output,
        )
        if not HAS_RUAMEL:
            result["warnings"] = [
                "Python 'ruamel.yaml' is not installed on the controller; filetree files were written without pretty-printing."
            ]
        return result
