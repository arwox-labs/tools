import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "acc1-scripts"
PM2_SCRIPTS = ROOT / "scripts" / "pm2"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AgentToolsTest(unittest.TestCase):
    def test_download_backends_are_siblings(self):
        text = (PM2_SCRIPTS / "agent-download.sh").read_text()
        self.assertIn('$SCRIPT_DIR/gdrive-download.sh', text)
        self.assertIn('$SCRIPT_DIR/b244-fetch.sh', text)
        self.assertTrue((SCRIPTS / "gdrive-download.sh").is_file())
        self.assertTrue((PM2_SCRIPTS / "b244-fetch.sh").is_file())

    def test_google_expiry_accepts_epoch_and_iso(self):
        module = load("gdrive_download", SCRIPTS / "gdrive-download.py")
        self.assertEqual(module.parse_expiry(123), 123)
        self.assertEqual(module.parse_expiry("1970-01-01T00:02:03Z"), 123)
        self.assertEqual(module.parse_expiry("invalid"), 0)

    def test_assembly_result_has_word_timestamps(self):
        module = load("assemblyai_transcribe", SCRIPTS / "assemblyai-transcribe.py")
        transcript = SimpleNamespace(
            text="hello",
            words=[SimpleNamespace(text="hello", start=10, end=20, confidence=0.9)],
        )
        self.assertEqual(module.result_payload(transcript)["words"][0]["start_ms"], 10)

    def test_missing_assembly_key_is_redacted(self):
        module = load("assemblyai_transcribe_no_key", SCRIPTS / "assemblyai-transcribe.py")
        old = os.environ.pop("ASSEMBLYAI_API_KEY", None)
        module.SECRET_FILE = Path("/definitely/missing")
        try:
            with self.assertRaisesRegex(RuntimeError, "ASSEMBLYAI_API_KEY is not set"):
                module.api_key()
        finally:
            if old is not None:
                os.environ["ASSEMBLYAI_API_KEY"] = old

    def test_shell_syntax(self):
        for script in ("gdrive-download.sh", "share-file.sh", "sched-validator.sh"):
            subprocess.run(["bash", "-n", SCRIPTS / script], check=True)
        for script in ("agent-download.sh", "b244-fetch.sh"):
            subprocess.run(["bash", "-n", PM2_SCRIPTS / script], check=True)

    def test_validator_preserves_failed_exit_code(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as check:
            check.write("#!/bin/bash\nexit 7\n")
        try:
            result = subprocess.run(
                ["timeout", "2",
                    "bash", "-c",
                    'SCHED_VALIDATOR_SOURCE_ONLY=1 source "$1"; run_check probe "$2"',
                    "bash", SCRIPTS / "sched-validator.sh", check.name,
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["status"], "FAIL")
        finally:
            os.unlink(check.name)

    def test_validator_never_publishes_check_output(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as check:
            check.write("#!/bin/bash\necho SECRET_TOKEN=must-not-leak\n")
        try:
            result = subprocess.run(
                [
                    "bash", "-c",
                    'SCHED_VALIDATOR_SOURCE_ONLY=1 source "$1"; run_check probe "$2"',
                    "bash", SCRIPTS / "sched-validator.sh", check.name,
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), {"status": "PASS", "reason": "ok"})
            self.assertNotIn("must-not-leak", result.stdout)
        finally:
            os.unlink(check.name)

    def test_credential_probe_reports_only_safe_status(self):
        with tempfile.TemporaryDirectory() as secrets_root:
            result = subprocess.run(
                [sys.executable, SCRIPTS / "auth-health.py", "--secrets-root", secrets_root],
                text=True,
                capture_output=True,
            )
        self.assertEqual(result.returncode, 1)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["google_credentials"]["reason"], "not_found")
        self.assertEqual(payload["assemblyai_credentials"]["reason"], "not_found")
        self.assertNotIn("value", result.stdout.lower())


class ToolHelpContractTest(unittest.TestCase):
    def test_executable_tools_show_help_without_external_actions(self):
        listing = subprocess.run(
            ["git", "ls-files", "-s", "bin/"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        scripts = []
        for entry in listing.stdout.splitlines():
            metadata, name = entry.split("\t", 1)
            mode = metadata.split(maxsplit=1)[0]
            if mode != "100755" or name.endswith("-test"):
                continue
            # dcfg-9uhb3 owns the --help fixes for these scripts.
            if name in {"bin/ship", "bin/ship-post"}:
                continue
            if name == "bin/code-channel":
                continue
            scripts.append((name, ROOT / name))

        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            stubs = temporary / "stubs"
            home = temporary / "home"
            stub_log = temporary / "stub.log"
            stubs.mkdir()
            home.mkdir()
            for command in (
                "git", "gh", "tmux", "curl", "wget", "pm2", "bd", "ssh", "scp",
                "rsync", "opencode", "codex", "gitleaks", "docker", "npx",
            ):
                stub = stubs / command
                stub.write_text(
                    "#!/usr/bin/python3\n"
                    "from pathlib import Path\n"
                    f"with Path({str(stub_log)!r}).open('a') as log:\n"
                    "    log.write(Path(__file__).name + '\\n')\n"
                    "raise SystemExit(99)\n"
                )
                stub.chmod(0o755)

            env = os.environ.copy()
            env.update({
                "PATH": f"{stubs}:{env['PATH']}",
                "HOME": str(home),
            })
            for name, path in scripts:
                command = [str(path), "--help"]
                shebang = path.read_text().splitlines()[0]
                if shebang.startswith("#!") and not shebang.startswith("#!/usr/bin/env"):
                    interpreter = Path(shebang[2:].split(maxsplit=1)[0])
                    if not os.path.exists(interpreter):
                        command = [sys.executable, str(path), "--help"]
                with self.subTest(script=name):
                    stub_log.unlink(missing_ok=True)
                    result = subprocess.run(
                        command,
                        env=env,
                        stdin=subprocess.DEVNULL,
                        timeout=10,
                        capture_output=True,
                        text=True,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("usage:", result.stdout)
                    self.assertFalse(stub_log.exists() and stub_log.stat().st_size)

            for arguments in (("--help",), ("audit", "/missing", "/missing/tz.md")):
                with self.subTest(script="bin/code-channel", arguments=arguments):
                    stub_log.unlink(missing_ok=True)
                    result = subprocess.run(
                        [str(ROOT / "bin/code-channel"), *arguments],
                        env=env,
                        stdin=subprocess.DEVNULL,
                        timeout=10,
                        capture_output=True,
                        text=True,
                    )
                    self.assertEqual(result.returncode, 64, result.stderr)
                    self.assertEqual(result.stdout, "")
                    self.assertIn("/root/workspaces/tools/bin/code-agent", result.stderr)
                    self.assertFalse(stub_log.exists() and stub_log.stat().st_size)


if __name__ == "__main__":
    unittest.main()
