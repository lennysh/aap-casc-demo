# Tests

Automated tests for the import loader (`roles/import_export/tasks/import_load.yml` and its
action plugins `casc_import_prepare.py` / `casc_import_preflight.py`). No AAP is needed.

```bash
python3 -m pytest tests -q            # ~80 s
python3 -m pytest tests -q -n auto    # ~15 s with pytest-xdist
```

Requirements: `pytest`, `ansible-core`, and the collections installed with
`./install_collections.sh` (`collections/<version>/`). Tests for a version whose collections
folder is missing are skipped.

## What's covered

* `test_import_load.py` runs the real `import_load.yml` with `ansible-playbook` against fixture
  workspaces built in a temp folder (see `conftest.py`), then dumps the loaded variables and
  every task result:
  * loading: any folder structure and file name, `.yml`/`.yaml`, `ignore_*` files and folders, `import_common`,
    merge order (lists appended common/ first, dicts merged later-wins, scalars last-wins),
    `!unsafe`, vault-encrypted files and inline `!vault` values, invalid / non-mapping / empty files,
    staging folder cleanup;
  * duplicate objects: conflicting (fails, lists files), identical (warning),
    `import_export_allow_duplicates`;
  * cross-version aliases (2.4 <-> 2.5+ organizations, user auditor key renames);
  * tags (`--tags` / `--skip-tags`, 2.4 short tags and 2.5+ prefixed tags): only selected object
    types load, helper variables always load, unselected types can be unfinished, duplicated or
    unparseable;
  * preflight: unresolvable values fail with every problem listed before anything connects to AAP;
    `!unsafe`, `{% raw %}`, `default(omit)` and helper references pass; `import_export_preflight=false`.
* `test_import_only_files.py` covers `import.sh -f` (`import_export_only_files`): only objects from
  the named files/folders load while helper variables and vaults come from everywhere, combining
  with tags, duplicates elsewhere ignored, broken unnamed files, preflight scope, and the error
  for each kind of path import doesn't read.
* `test_prepare_units.py` unit-tests the pure helpers of `casc_import_prepare.py`.

The harness uses its own `ansible.cfg` in a temp folder, so the repo's `ansible.cfg` (vault
password file) isn't used; vault tests use a throwaway password.
