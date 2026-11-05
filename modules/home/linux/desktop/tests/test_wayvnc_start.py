import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "wayvnc-start.sh"


class WayvncStartTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="wayvnc-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.credentials = self.root / "credentials"
        self.runtime = self.root / "runtime"
        self.credentials.mkdir(mode=0o700)
        self.runtime.mkdir(mode=0o700)
        self.record = self.root / "invocation.json"
        stub = self.root / "wayvnc"
        stub.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "from pathlib import Path\n"
            "Path(os.environ['RECORD']).write_text(json.dumps({\n"
            "    'arguments': sys.argv[1:],\n"
            "    'password_in_environment': 'password' in os.environ,\n"
            "}))\n"
        )
        stub.chmod(0o700)
        self.environment = {
            **os.environ,
            "PATH": f"{self.root}:{os.environ['PATH']}",
            "CREDENTIALS_DIRECTORY": str(self.credentials),
            "RUNTIME_DIRECTORY": str(self.runtime),
            "RECORD": str(self.record),
        }

    def start(self, password):
        credential = self.credentials / "password"
        if password is not None:
            credential.write_text(password)
        elif credential.exists():
            credential.unlink()
        return subprocess.run(
            [shutil.which("bash"), "-euo", "pipefail", str(SCRIPT), "HDMI-A-1"],
            env=self.environment,
            capture_output=True,
            text=True,
            timeout=5,
        )

    def test_valid_password_is_private_and_requires_authentication(self):
        result = self.start("aB3dE6gH\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        configuration = self.runtime / "config"
        self.assertEqual(stat.S_IMODE(configuration.stat().st_mode), 0o600)
        self.assertEqual(
            configuration.read_text().splitlines(),
            [
                "address=0.0.0.0",
                "port=5900",
                "enable_auth=true",
                "relax_encryption=true",
                "allow_broken_crypto=true",
                "password=aB3dE6gH",
            ],
        )
        invocation = json.loads(self.record.read_text())
        self.assertEqual(
            invocation["arguments"],
            [f"--config={configuration}", "--output=HDMI-A-1", "--disable-resizing"],
        )
        self.assertFalse(invocation["password_in_environment"])
        self.assertNotIn("aB3dE6gH", result.stdout + result.stderr)

    def test_bad_or_missing_password_never_starts_server(self):
        for password in [None, "", "\n", "short", "tooLong123", "abc defg", "ébcdefgh", "abcdefgh\nenable_auth=false"]:
            with self.subTest(password=password):
                result = self.start(password)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.record.exists())
                self.assertFalse((self.runtime / "config").exists())

    def test_bad_password_does_not_reuse_previous_configuration(self):
        self.assertEqual(self.start("aB3dE6gH").returncode, 0)
        self.record.unlink()
        self.assertNotEqual(self.start("").returncode, 0)
        self.assertFalse(self.record.exists())


if __name__ == "__main__":
    unittest.main()
