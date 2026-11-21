# -*- coding: utf-8 -*-
"""Resolve every loaded object before anything is sent to AAP.

Values are templated lazily, so without this check a missing variable (for example a vault
secret nobody defined yet) only fails when its role starts, after earlier roles have already
changed AAP. This templates each object of each given variable, collects every failure, and
reports them all at once. Nothing templated is returned (values may contain secrets); only the
variable, the object's identity and the error.
"""

from __future__ import absolute_import, division, print_function

__metaclass__ = type

from ansible.module_utils.common.text.converters import to_text
from ansible.plugins.action import ActionBase

DOCUMENTATION = r"""
---
action: casc_import_preflight
short_description: Check that every loaded configuration object can be templated
options:
  variables: {type: list, required: true, description: Object variable names to check.}
  identity_keys: {type: dict, default: {}, description: "Variable name -> identity fields (__default__ for others), used to label objects."}
"""

_LABEL_FALLBACK = ("name", "username", "hostname", "target_credential", "team", "user", "role_definition")


def _first_line(text, limit=300):
    line = to_text(text).strip().splitlines()[0] if to_text(text).strip() else "unknown error"
    return line if len(line) <= limit else line[: limit - 3] + "..."


class ActionModule(ActionBase):
    TRANSFERS_FILES = False
    _requires_connection = False
    _supports_check_mode = True

    def _label(self, item, fields):
        if not isinstance(item, dict):
            return None
        for field in list(fields) + [f for f in _LABEL_FALLBACK if f not in fields]:
            value = item.get(field)
            # Show the raw (untemplated) identity; a templated one could itself be the problem.
            if value not in (None, "") and not isinstance(value, (dict, list)):
                return "%s=%s" % (field, to_text(value))
        return None

    def run(self, tmp=None, task_vars=None):
        result = super(ActionModule, self).run(tmp, task_vars)
        task_vars = task_vars or {}
        variables = [to_text(v) for v in (self._task.args.get("variables") or [])]
        identity_keys = self._task.args.get("identity_keys") or {}
        try:
            templar = self._templar.copy_with_new_env(available_variables=task_vars)
        except TypeError:  # older ansible-core
            templar = self._templar
            templar.available_variables = task_vars

        problems = []
        checked = 0

        def check(variable, label, value):
            try:
                templar.template(value, fail_on_undefined=True)
            except Exception as exc:  # undefined variables, filter errors, bad syntax...
                problems.append({"variable": variable, "object": label, "error": _first_line(exc)})

        for variable in variables:
            if variable not in task_vars:
                continue
            value = task_vars[variable]
            fields = identity_keys.get(variable) or identity_keys.get("__default__") or ["name"]
            if isinstance(value, list):
                for index, item in enumerate(value):
                    checked += 1
                    check(variable, self._label(item, fields) or "item %d" % (index + 1), item)
            elif isinstance(value, dict):  # settings: check key by key
                for key in value:
                    checked += 1
                    check(variable, to_text(key), value[key])
            else:
                checked += 1
                check(variable, None, value)

        result.update(changed=False, checked=checked, problems=problems)
        if problems:
            lines = ["  %s%s: %s" % (p["variable"], " [%s]" % p["object"] if p["object"] else "", p["error"]) for p in problems]
            result.update(
                failed=True,
                msg=(
                    "Preflight: %d of %d object(s) can't be resolved, so nothing was sent to AAP:\n%s\n"
                    "Define the missing variables (for secrets, in your vault), wrap values AAP must receive "
                    "literally in {%%- raw -%%}...{%%- endraw -%%} or tag them !unsafe, or import only other "
                    "object types with -t. To skip this check, run import.sh with --skip-preflight."
                    % (len(problems), checked, "\n".join(lines))
                ),
            )
        return result
