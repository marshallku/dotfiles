import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("desktop", Path(__file__).parents[1] / "desktop.py")
desktop = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(desktop)


class DesktopTests(unittest.TestCase):
    def test_arithmetic_precedence_and_negative_numbers(self):
        self.assertEqual(desktop.calculate("12 * (8 + 3)"), "132")
        self.assertEqual(desktop.calculate("-3 + 1 / 2"), "-2.5")

    def test_arithmetic_rejects_code_and_unbounded_operations(self):
        for expression in ("__import__('os').getcwd()", "9 ** 999999", "(9 ** 10) ** 10 ** 10", "1 / 0", "True", "(-1) ** 0.5"):
            with self.subTest(expression=expression):
                with self.assertRaises((ValueError, ArithmeticError)):
                    desktop.calculate(expression)

    def test_dunst_variants_are_plain_text_and_newest_first(self):
        def row(identifier, timestamp):
            return {
                "id": {"data": identifier}, "timestamp": {"data": timestamp},
                "appname": {"data": "Chat"}, "summary": {"data": "<b>Build</b> &amp; test"},
                "body": {"data": "<a href='https://example.com'>Open</a>"},
                "urgency": {"data": "CRITICAL"},
            }
        rows = desktop.notifications({"data": [[row(1, 20_000_000), row(2, 30_000_000)]]}, 1000, 100)
        self.assertEqual([row["id"] for row in rows], [2, 1])
        self.assertEqual(rows[0]["summary"], "Build & test")
        self.assertEqual(rows[0]["body"], "Open")
        self.assertEqual(rows[0]["time"], 930_000)
        self.assertTrue(rows[0]["critical"])

    def test_clipboard_ids_cannot_be_commands(self):
        rows = desktop.clipboard_rows("10\ttext with spaces\n11\t[[ binary data ]]\n;rm\tbad\nmissing tab")
        self.assertEqual([row["id"] for row in rows], ["10", "11"])

    def test_cliphist_bridge_preserves_multiline_content_and_sensitive_state(self):
        binary = shutil.which("cliphist") or str(Path.home() / ".local/bin/cliphist")
        if not Path(binary).exists():
            self.skipTest("cliphist is not installed")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake_copy = root / "wl-copy"
            fake_copy.write_text('#!/bin/sh\ncat > "$TEST_COPIED"\n')
            fake_copy.chmod(0o755)
            env = dict(os.environ, XDG_CACHE_HOME=directory, TEST_COPIED=str(root / "copied"),
                       PATH=directory + ":" + os.environ["PATH"])
            content = b"clipboard integration test\nsecond line"
            subprocess.run([binary, "store"], input=content, env=env, check=True)
            subprocess.run([binary, "store"], input=b"sensitive", env=dict(env, CLIPBOARD_STATE="sensitive"), check=True)
            rows = desktop.clipboard_rows(subprocess.check_output([binary, "list"], env=env).decode())
            self.assertEqual(len(rows), 1)
            result = subprocess.check_output([str(SPEC.origin), "clipboard-copy", rows[0]["id"]], env=env)
            self.assertTrue(json.loads(result)["ok"])
            self.assertEqual((root / "copied").read_bytes(), content)
            subprocess.run([str(SPEC.origin), "clipboard-delete", rows[0]["id"]], env=env, check=True, capture_output=True)
            self.assertEqual(subprocess.check_output([binary, "list"], env=env), b"")


if __name__ == "__main__":
    unittest.main()
