"""Shared fixtures: build fixture workspaces and run the real import_load.yml against them.

No AAP is needed: the harness playbook only runs roles/import_export/tasks/import_load.yml
(prepare -> include_vars -> preflight) and then dumps the resulting variables to a JSON file.
"""

import json
import os
import shutil
import subprocess
import textwrap
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
ROLE = REPO / "roles" / "import_export"
ACTION_PLUGINS = ROLE / "action_plugins"
IMPORT_LOAD = ROLE / "tasks" / "import_load.yml"
PREFLIGHT_PLUGIN = ACTION_PLUGINS / "casc_import_preflight.py"
VAULT_PASSWORD = "casc-test-password"

UNDEFINED = "__UNDEFINED__"

HARNESS = """\
- hosts: localhost
  gather_facts: false
  connection: local
  vars_files:
    - {defaults}
    - {role_vars}
  vars:
    common_dir: "{{{{ ws }}}}/common"
    env_dir: "{{{{ ws }}}}/env"
    casc_aap_version: "{{{{ ver }}}}"
    __auth_mode: "{{{{ 'controller' if ver == '2.4' else 'gateway' }}}}"
  tasks:
    - ansible.builtin.include_tasks: {import_load}
      args:
        apply:
          tags: [always]
      tags: [always]

    - name: Dump loaded variables
      ansible.builtin.copy:
        dest: "{{{{ dump_file }}}}"
        content: >-
          {{% set out = {{}} %}}{{% for n in probe | default(__import_prepare.variables) %}}{{%
          set _ = out.update({{n: lookup('ansible.builtin.vars', n, default='{undefined}')}}) %}}{{% endfor %}}{{{{
          {{'vars': out}} | to_json }}}}
      tags: [always]
"""


# Records every task result (by task name) to $CASC_TEST_RECORD, so tests can read the
# prepare / preflight results whether they passed or failed.
RECORD_CALLBACK = '''
import json, os
from ansible.plugins.callback import CallbackBase
from ansible.module_utils.common.json import AnsibleJSONEncoder

class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "aggregate"
    CALLBACK_NAME = "casc_test_record"
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self, *args, **kwargs):
        super(CallbackModule, self).__init__(*args, **kwargs)
        self.results = {}

    def _record(self, result, status):
        data = dict(result._result)
        data["__status"] = status
        self.results[result._task.get_name()] = data
        path = os.environ.get("CASC_TEST_RECORD")
        if path:
            with open(path, "w") as handle:
                json.dump(self.results, handle, cls=AnsibleJSONEncoder, default=str)

    def v2_runner_on_ok(self, result):
        self._record(result, "ok")

    def v2_runner_on_failed(self, result, ignore_errors=False):
        self._record(result, "failed")

    def v2_runner_on_skipped(self, result):
        self._record(result, "skipped")
'''


def _versions_available():
    return [v for v in ("2.4", "2.5", "2.6", "2.7") if (REPO / "collections" / v).is_dir()]


def requires_version(ver):
    return pytest.mark.skipif(
        not (REPO / "collections" / ver).is_dir(),
        reason="collections/%s not installed (run ./install_collections.sh)" % ver,
    )


@pytest.fixture(scope="session")
def harness_dir(tmp_path_factory):
    """A directory outside the repo with its own ansible.cfg, harness playbook and vault password."""
    if shutil.which("ansible-playbook") is None:
        pytest.skip("ansible-playbook not installed")
    d = tmp_path_factory.mktemp("harness")
    (d / "ansible.cfg").write_text(
        "[defaults]\nretry_files_enabled = False\nlocalhost_warning = False\n"
        "interpreter_python = auto_silent\n"
        "callback_plugins = %s\ncallbacks_enabled = casc_test_record\n" % (d / "callback_plugins")
    )
    (d / "callback_plugins").mkdir()
    (d / "callback_plugins" / "casc_test_record.py").write_text(RECORD_CALLBACK)
    (d / "playbook.yml").write_text(HARNESS.format(
        defaults=ROLE / "defaults" / "main.yml",
        role_vars=ROLE / "vars" / "main.yml",
        import_load=IMPORT_LOAD,
        undefined=UNDEFINED,
    ))
    (d / "vault_pass.txt").write_text(VAULT_PASSWORD + "\n")
    return d


def write_files(root, files):
    root = Path(root)
    for rel, text in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(textwrap.dedent(text) if isinstance(text, str) else text)
    return root


@pytest.fixture
def make_ws(tmp_path):
    """make_ws({relative_path: yaml_text}) -> workspace path. Paths are relative to the
    workspace: 'common/...' and 'env/imports/...'."""
    def _make(files):
        ws = tmp_path / "ws"
        (ws / "common").mkdir(parents=True, exist_ok=True)
        (ws / "env" / "imports").mkdir(parents=True, exist_ok=True)
        return write_files(ws, files)
    return _make


def _env(harness_dir, ver):
    env = dict(os.environ)
    for key in list(env):
        if key.startswith("ANSIBLE_"):
            del env[key]
    env.update(
        ANSIBLE_CONFIG=str(harness_dir / "ansible.cfg"),
        ANSIBLE_ACTION_PLUGINS=str(ACTION_PLUGINS),
        ANSIBLE_COLLECTIONS_PATH=str(REPO / "collections" / ver),
        ANSIBLE_NOCOLOR="1",
        ANSIBLE_FORCE_COLOR="0",
        ANSIBLE_DEPRECATION_WARNINGS="False",
    )
    return env


@pytest.fixture
def vault_encrypt(harness_dir):
    """vault_encrypt(path) encrypts a file in place; vault_encrypt_string(name, value) returns YAML."""
    def _encrypt(path):
        subprocess.run(
            ["ansible-vault", "encrypt", "--vault-password-file", str(harness_dir / "vault_pass.txt"), str(path)],
            check=True, capture_output=True, cwd=harness_dir, env=_env(harness_dir, "2.6"),
        )
    return _encrypt


@pytest.fixture
def vault_encrypt_string(harness_dir):
    def _encrypt(name, value):
        proc = subprocess.run(
            ["ansible-vault", "encrypt_string", "--vault-password-file", str(harness_dir / "vault_pass.txt"),
             "--name", name, value],
            check=True, capture_output=True, text=True, cwd=harness_dir, env=_env(harness_dir, "2.6"),
        )
        return proc.stdout
    return _encrypt


class Result:
    """rc, data (dump of the probed variables, or None if the play failed before the dump),
    output (stdout+stderr) and tasks ({task name: result} for every task that ran)."""

    def __init__(self, rc, data, output, tasks):
        self.rc = rc
        self.data = data
        self.output = output
        self.tasks = tasks

    # Allow `rc, data, out = run_import_load(...)`
    def __iter__(self):
        return iter((self.rc, self.data, self.output))

    def task(self, prefix):
        for name, result in self.tasks.items():
            if name.startswith(prefix):
                return result
        return None

    @property
    def vars(self):
        return (self.data or {}).get("vars", {})

    @property
    def prepare(self):
        return self.task("Check for duplicates") or {}

    @property
    def preflight(self):
        """The preflight task result, or None if it didn't run."""
        return self.task("Preflight")

    @property
    def warnings(self):
        return "\n".join(self.prepare.get("warnings") or [])

    @property
    def failure(self):
        """msg of the failed task ('' if none failed)."""
        for result in self.tasks.values():
            if result.get("__status") == "failed":
                return str(result.get("msg", ""))
        return ""

    def defined(self, name):
        return self.vars.get(name, UNDEFINED) != UNDEFINED


@pytest.fixture
def run_import_load(harness_dir):
    """run_import_load(ws, ver, tags=None, skip_tags=None, extra_vars=None, probe=None, vault=False)
    -> Result. Result.data is None when the play failed before the dump; otherwise
    {'vars': {name: value}} for `probe` (default: every variable the prepare step staged), with
    UNDEFINED for undefined variables."""
    def _run(ws, ver, tags=None, skip_tags=None, extra_vars=None, probe=None, vault=False):
        if not (REPO / "collections" / ver).is_dir():
            pytest.skip("collections/%s not installed" % ver)
        ws = Path(ws)
        dump, record = ws / "dump.json", ws / "tasks.json"
        for f in (dump, record):
            if f.exists():
                f.unlink()
        evars = {"ws": str(ws), "ver": ver, "dump_file": str(dump)}
        if probe is not None:
            evars["probe"] = list(probe)
        evars.update(extra_vars or {})
        cmd = ["ansible-playbook", "-i", "localhost,", str(harness_dir / "playbook.yml"),
               "-e", json.dumps(evars)]
        if tags:
            cmd += ["--tags", ",".join(tags) if isinstance(tags, (list, tuple)) else tags]
        if skip_tags:
            cmd += ["--skip-tags", ",".join(skip_tags) if isinstance(skip_tags, (list, tuple)) else skip_tags]
        if vault:
            cmd += ["--vault-password-file", str(harness_dir / "vault_pass.txt")]
        env = _env(harness_dir, ver)
        env["CASC_TEST_RECORD"] = str(record)
        proc = subprocess.run(cmd, cwd=harness_dir, env=env, capture_output=True, text=True, timeout=180)
        data = json.loads(dump.read_text()) if dump.exists() else None
        tasks = json.loads(record.read_text()) if record.exists() else {}
        return Result(proc.returncode, data, proc.stdout + proc.stderr, tasks)
    return _run
