"""Regression tests use constructed dummy strings, never service credentials."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "check_public_files.py"
SPEC = importlib.util.spec_from_file_location("public_check", SCRIPT)
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)


class PublicFileTests(unittest.TestCase):
    def test_quoted_credentials_across_formats(self):
        value = "not-a-real-credential"
        cases = [
            'let ' + 'apiKey: String' + ' = "' + value + '"',
            'const ' + 'clientSecret' + ' = "' + value + '";',
            '{"' + 'password' + '": "' + value + '"}',
            'refresh_token' + ": '" + value + "'",
            'export ' + 'AWS_SECRET_ACCESS_KEY' + "='" + value + "'",
        ]
        for contents in cases:
            with self.subTest(format=contents.split()[0]):
                self.assertIn("embedded credential", checker.findings(contents))

    def test_unquoted_environment_password_is_found(self):
        contents = "DB_PASSWORD" + "=" + "not-a-real-credential"
        self.assertIn("embedded credential", checker.findings(contents))

    def test_placeholder_and_runtime_references_are_allowed(self):
        for value in ["YOUR_STORMGLASS_API_KEY_HERE", "REPLACE_ME", "${LOCAL_KEY}"]:
            self.assertEqual(checker.findings("STORMGLASS_API_KEY=" + value), [])
        self.assertEqual(checker.findings('case .missingAPIKey: "Supply a key."'), [])
        self.assertEqual(checker.findings('apiKey: ProcessInfo.processInfo.environment["KEY"]'), [])

    def test_service_patterns_are_found(self):
        cases = [
            ("ghp_" + "A" * 36, "GitHub token"),
            ("github_pat_" + "A" * 60, "GitHub token"),
            ("AKIA" + "A" * 16, "AWS access identifier"),
            ("ASIA" + "A" * 16, "AWS access identifier"),
            ("AIza" + "A" * 35, "Google API key"),
            ("sk-proj-" + "A" * 40, "API secret"),
            ("sk_live_" + "A" * 24, "Stripe secret"),
            ("xoxb-" + "1" * 24, "Slack token"),
            ("eyJ" + "A" * 12 + "." + "B" * 12 + "." + "C" * 12, "JWT"),
            ("-".join(["a" * 8, "b" * 4, "c" * 4, "d" * 4, "e" * 12, "f" * 12]), "Stormglass key"),
        ]
        for contents, label in cases:
            with self.subTest(category=label):
                self.assertIn(label, checker.findings(contents))

    def test_private_key_and_authorization_are_found(self):
        header = "-----BEGIN " + "PRIVATE KEY-----"
        self.assertIn("private key", checker.findings(header))
        auth_header = "Bearer " + "syntheticvalue" * 2
        self.assertIn("embedded credential", checker.findings(auth_header))

    def test_embedded_url_credentials_are_found(self):
        for scheme in ["https", "postgresql", "mongodb+srv", "redis"]:
            contents = scheme + "://" + "example:dummy-password@localhost"
            self.assertIn("credential-bearing URL", checker.findings(contents))

    def test_machine_account_paths_are_found(self):
        contents = "/" + "Users" + "/example/project"
        self.assertIn("local account path", checker.findings(contents))

    def test_email_addresses_are_found_except_reserved_examples(self):
        at = "@"
        for address in ["first.last" + at + "mail-provider.com", "1234+user" + at + "users.noreply.host.io"]:
            with self.subTest(kind=address.split(at)[1]):
                self.assertIn("email address", checker.findings("Contact: " + address))
        for address in ["dev" + at + "example.com", "dev" + at + "mail.example.org", "dev" + at + "surf.test"]:
            self.assertEqual(checker.findings("Contact: " + address), [])
        # Swift attributes and URL credentials without a domain are not addresses.
        self.assertEqual(checker.findings("completion: " + at + "escaping " + at + "Sendable () -> Void"), [])
        self.assertEqual(checker.findings(at + "testable import Module"), [])

    def test_credential_files_are_blocked(self):
        for name in [".env", ".env.production", "signing.p12", "certificate.pem", ".aws/config", "Secrets.swift"]:
            self.assertTrue(checker.forbidden_path(Path(name)))
        self.assertFalse(checker.forbidden_path(Path(".env.example")))

    def test_editor_and_agent_folders_are_blocked(self):
        for name in [".cursor/rules/notes.md", ".claude/settings.json", ".idea/workspace.xml", ".vscode/settings.json"]:
            self.assertTrue(checker.forbidden_path(Path(name)))
        self.assertFalse(checker.forbidden_path(Path(".github/workflows/ci.yml")))

    def test_symlink_directories_are_rejected_without_following(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "alias").symlink_to(root, target_is_directory=True)
            errors, _ = checker.check(root)
            self.assertTrue(any("symlink" in error for error in errors))

    def test_findings_omit_values(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            value = "constructed-dummy-sensitive-value"
            (root / "config.txt").write_text("PASSWORD=" + value)
            errors, _ = checker.check(root)
            self.assertTrue(errors)
            self.assertNotIn(value, "\n".join(errors))


if __name__ == "__main__":
    unittest.main()
