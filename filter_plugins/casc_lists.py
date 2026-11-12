"""List helpers shared by the import_export and flat_to_filetree roles.

Used to normalize object lists between AAP versions (e.g. AAP 2.4 ``controller_*``
names to the standard AAP 2.5+ ``aap_*`` names).
"""

from ansible.errors import AnsibleFilterError


def rename_keys(items, mapping):
    """Return copies of the dicts in ``items`` with keys renamed per ``mapping``.

    An old key is only renamed when the new key is not already set; otherwise the
    old key is dropped so the explicit new-style value wins.
    """
    if not mapping:
        return list(items or [])
    if not isinstance(mapping, dict):
        raise AnsibleFilterError("rename_keys: mapping must be a dict")
    result = []
    for item in items or []:
        if not isinstance(item, dict):
            result.append(item)
            continue
        new_item = dict(item)
        for old, new in mapping.items():
            if old in new_item:
                value = new_item.pop(old)
                new_item.setdefault(new, value)
        result.append(new_item)
    return result


def merge_by_key(items, keys):
    """Collapse dicts in ``items`` that share the same values for ``keys``.

    Order is preserved. The first occurrence keeps its values; later duplicates only
    contribute fields the first one doesn't have. Items missing every key field, and
    non-dict items, are passed through unchanged.
    """
    if not keys:
        return list(items or [])
    if isinstance(keys, str):
        keys = [keys]
    result = []
    index = {}
    for item in items or []:
        if not isinstance(item, dict):
            result.append(item)
            continue
        identity = tuple(item.get(k) for k in keys)
        if all(part is None for part in identity):
            result.append(dict(item))
            continue
        if identity in index:
            existing = result[index[identity]]
            for field, value in item.items():
                existing.setdefault(field, value)
        else:
            index[identity] = len(result)
            result.append(dict(item))
    return result


class FilterModule(object):
    def filters(self):
        return {
            "rename_keys": rename_keys,
            "merge_by_key": merge_by_key,
        }
