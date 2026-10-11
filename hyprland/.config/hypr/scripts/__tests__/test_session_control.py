import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).parents[1] / "session-control.sh"


class SessionControlTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls"
        local_bin = self.root / ".local/bin"
        local_bin.mkdir(parents=True)
        recorder = '#!/bin/bash\nprintf "%s %s\\n" "$(basename "$0")" "$*" >> "$TEST_LOG"\n'
        for command in ("systemctl", "loginctl", "hyprlock", "hyprctl", "notify-send"):
            target = self.bin / command
            target.write_text(recorder + 'echo ok\n')
            target.chmod(0o755)
        (self.bin / "systemctl").write_text(recorder + '''
if [[ "$TEST_IDLE_START_FAIL" == "1" && "$*" == "--user start hypridle.service" ]]; then
    exit 1
fi
''')
        (self.bin / "hyprlock").write_text(recorder + '[[ "$TEST_LOCKER_FAIL" != "1" ]]\n')
        coctl = local_bin / "coctl"
        coctl.write_text(recorder)
        coctl.chmod(0o755)
        pidof = self.bin / "pidof"
        pidof.write_text('#!/bin/bash\n[[ "$TEST_LOCKED" == "1" ]]\n')
        pidof.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.root), XDG_RUNTIME_DIR=str(self.root),
                        PATH=str(self.bin) + ":" + os.environ["PATH"], TEST_LOG=str(self.log), TEST_LOCKED="0")

    def invoke(self, command):
        subprocess.run([str(SCRIPT), command], env=self.env, check=True, capture_output=True)
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_manual_lock_starts_idle_service_and_locks_directly(self):
        calls = self.invoke("request-lock")
        self.assertLess(calls.index("systemctl --user start hypridle.service"), calls.index("hyprlock "))
        self.assertIn("coctl presence away", calls)
        self.assertEqual(calls[-1], "coctl presence active")

    def test_idle_start_failure_cannot_skip_lock(self):
        self.env["TEST_IDLE_START_FAIL"] = "1"
        self.assertIn("hyprlock ", self.invoke("request-lock"))

    def test_failed_locker_stops_short_idle_timer_and_reports_error(self):
        self.env["TEST_LOCKER_FAIL"] = "1"
        result = subprocess.run([str(SCRIPT), "lock"], env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 1)
        calls = self.log.read_text().splitlines()
        self.assertIn("systemctl --user stop hypridle-locked.service", calls)
        self.assertTrue(any(call.startswith("notify-send -u critical") for call in calls))
        self.assertNotIn("coctl presence active", calls)

    def test_lock_does_not_spawn_second_locker(self):
        self.env["TEST_LOCKED"] = "1"
        self.assertEqual(self.invoke("lock"), [])

    def test_locked_starts_short_idle_timer_and_marks_away(self):
        self.assertEqual(self.invoke("locked"), ["systemctl --user start hypridle-locked.service", "coctl presence away"])

    def test_input_on_locked_screen_does_not_mark_active(self):
        self.env["TEST_LOCKED"] = "1"
        self.assertEqual(self.invoke("resumed"), [])

    def test_unlock_stops_short_timer_before_marking_active(self):
        calls = self.invoke("unlocked")
        self.assertEqual(calls[0], "systemctl --user stop hypridle-locked.service")
        self.assertIn("dpms", calls[1])
        self.assertEqual(calls[-1], "coctl presence active")


if __name__ == "__main__":
    unittest.main()
