import contextlib
import io
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
from security_check import findings, forbidden_name, check_repo, report
from verify_bundle import verify
from stage_source import stage


class SecurityGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], stderr=subprocess.DEVNULL)

    def repo(self):
        self.git("init")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Security fixture")

    def secret(self):
        return b"ghp_" + b"A" * 36

    def test_patterns(self):
        fixtures = [self.secret(), b"github_pat_" + b"B" * 60,
                    b"AKIA" + b"A" * 16, b"xoxb-" + b"1" * 30,
                    b"AIza" + b"x" * 35, b"sk_live_" + b"z" * 24,
                    b"BQ" + b"v" * 90, b"-----BEGIN " + b"PRIVATE KEY-----",
                    b'client_secret = "' + b"c" * 32 + b'"',
                    b'client_id: "' + b"d" * 32 + b'"',
                    b'let refreshToken: String = "' + b"r" * 32 + b'"',
                    b'Bearer ' + b"t" * 32]
        for fixture in fixtures:
            self.assertTrue(findings(fixture))
        self.assertFalse(findings(b'client_id: "YOUR_CLIENT_ID"'))
        self.assertFalse(findings(b'request.setValue("Bearer \\(access)", forHTTPHeaderField: "Authorization")'))

    def test_names(self):
        for name in [".env", "config/.env.local", "signing.p12", "credentials.json", "id_ed25519"]:
            self.assertTrue(forbidden_name(name))
        self.assertFalse(forbidden_name("Sources/SpotifyLibrary.swift"))

    def test_redaction(self):
        output = io.StringIO()
        with contextlib.redirect_stderr(output):
            self.assertEqual(report([("fixture.txt", "github-token")]), 1)
        self.assertNotIn(self.secret().decode(), output.getvalue())

    def test_staged_and_history(self):
        self.repo()
        path = self.root / "fixture.txt"
        path.write_bytes(self.secret())
        self.git("add", ".")
        path.write_text("clean working copy")
        self.assertTrue(check_repo(self.root))
        self.git("commit", "-m", "Synthetic security fixture")
        self.git("add", ".")
        self.git("commit", "-m", "Remove fixture")
        self.assertFalse(check_repo(self.root))
        self.assertTrue(check_repo(self.root, history=True))

    def test_untracked_and_symlink(self):
        self.repo()
        (self.root / "new.txt").write_bytes(self.secret())
        self.assertTrue(check_repo(self.root))
        (self.root / "new.txt").write_text("safe")
        self.assertFalse(check_repo(self.root))
        (self.root / "link").symlink_to("new.txt")
        self.assertTrue(check_repo(self.root))

    def test_force_added_credential_file(self):
        self.repo()
        (self.root / ".gitignore").write_text(".env\n")
        path = self.root / ".env"
        path.write_text("innocent-looking content")
        self.git("add", "--force", ".env")
        path.unlink()
        self.assertTrue(check_repo(self.root))

    def test_action_pin(self):
        self.repo()
        workflow = self.root / ".github/workflows/test.yml"
        workflow.parent.mkdir(parents=True)
        workflow.write_text("- uses: actions/checkout@v5\n")
        self.assertTrue(check_repo(self.root))
        workflow.write_text("- uses: actions/checkout@" + "a" * 40 + "\n")
        self.assertFalse(check_repo(self.root))

    def bundle(self):
        (self.root / "scripts").mkdir()
        (self.root / "scripts/bundle-files.txt").write_text("Contents/Info.plist\nContents/MacOS/NotchHarbor\n")
        (self.root / "Info.plist").write_text("fixture")
        app = self.root / "Test.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/Info.plist").write_text("fixture")
        (app / "Contents/MacOS/NotchHarbor").write_bytes(b"executable fixture")
        return app

    def test_clean_bundle(self):
        self.assertFalse(verify(self.bundle(), self.root, signed=False))

    def test_unexpected_and_missing(self):
        app = self.bundle()
        extra = app / "Contents/personal.txt"
        extra.write_text("must not ship")
        self.assertTrue(verify(app, self.root, signed=False))
        extra.unlink()
        (app / "Contents/MacOS/NotchHarbor").unlink()
        self.assertTrue(verify(app, self.root, signed=False))

    def test_resource_mismatch_and_link(self):
        app = self.bundle()
        info = app / "Contents/Info.plist"
        info.write_text("modified")
        self.assertTrue(verify(app, self.root, signed=False))
        info.unlink()
        info.symlink_to(self.root / "Info.plist")
        self.assertTrue(verify(app, self.root, signed=False))

    def test_secret_in_executable(self):
        app = self.bundle()
        (app / "Contents/MacOS/NotchHarbor").write_bytes(self.secret())
        self.assertTrue(verify(app, self.root, signed=False))

    def test_export_omits_ignored_files(self):
        self.repo()
        (self.root / ".gitignore").write_text(".env\nResources/Licenses/\nexport/\n")
        (self.root / "source.swift").write_text("safe")
        self.git("add", ".")
        self.git("commit", "-m", "Source fixture")
        (self.root / ".env").write_bytes(self.secret())
        private = self.root / "Resources/Licenses/personal.md"
        private.parent.mkdir(parents=True)
        private.write_text("private")
        exported = self.root / "export"
        stage(self.root, exported)
        self.assertTrue((exported / "source.swift").is_file())
        self.assertFalse((exported / ".env").exists())
        self.assertFalse((exported / "Resources/Licenses").exists())


if __name__ == "__main__":
    unittest.main()
