import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
PACKAGES = ("hyprland", "hypridle", "hyprlock", "hyprpaper", "quickshell", "dunst", "kitty", "fcitx5")


class DesktopInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "other user"
        self.home.mkdir()
        self.clone = self.root / "clone elsewhere"
        self.clone.mkdir()
        shutil.copy2(REPO / "install-desktop.sh", self.clone)
        for package in PACKAGES:
            shutil.copytree(REPO / package, self.clone / package, ignore=shutil.ignore_patterns("__pycache__"))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "commands"
        commands = ("Hyprland", "hyprctl", "qs", "hypridle", "hyprlock", "hyprpaper", "dunstctl",
                    "wl-paste", "wl-copy", "cliphist", "kitty", "jq", "curl", "notify-send",
                    "dbus-update-activation-environment", "pidof", "flock", "ip", "fc-match", "grim",
                    "slurp", "magick", "brightnessctl", "playerctl", "pactl", "pavucontrol", "htop",
                    "dolphin", "firefox", "fcitx5", "wofi", "systemctl", "systemd-analyze", "sudo")
        for command in commands:
            self.stub(command, 'printf "%s %s\\n" "$(basename "$0")" "$*" >> "$TEST_LOG"\n')
        self.stub("pacman", '''
if [[ "$*" == "-Q hyprland" ]]; then echo 'hyprland 0.56.2-4';
elif [[ "$*" == "-Q quickshell" ]]; then echo 'quickshell 0.3.2-1';
elif [[ "$*" == "-Q hypridle" ]]; then echo 'hypridle 0.1.8-2';
else exit 0; fi
''')
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin) + ":" + os.environ["PATH"],
                        TEST_LOG=str(self.log))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "XDG_CONFIG_HOME", "WALLPAPER_DIR",
                    "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS"):
            self.env.pop(key, None)
        # Isolate the optional GTK dependency probe from host Python packages.
        (self.bin / "gi").mkdir()
        (self.bin / "gi/__init__.py").write_text("def require_version(*args): pass\n")
        (self.bin / "gi/repository.py").write_text("Gtk = GtkLayerShell = None\n")
        self.env["PYTHONPATH"] = str(self.bin)

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -e\n" + body)
        path.chmod(0o755)

    def run_install(self, *args):
        return subprocess.run(["bash", str(self.clone / "install-desktop.sh"), *args],
                              env=self.env, text=True, capture_output=True)

    def test_fresh_home_repeatability_and_read_only_check(self):
        first = self.run_install()
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        for unit in ("clipboard-history.service", "hypridle-locked.service"):
            self.assertTrue((self.home / ".config/systemd/user" / unit).is_file())
        wallpaper = self.home / "Pictures/Wallpapers/.current"
        self.assertEqual(wallpaper.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
        target = wallpaper.readlink()
        self.assertFalse((self.home / ".config/hypr").is_symlink())
        self.assertFalse((self.home / ".config/quickshell/scripts/__tests__").exists())
        again = self.run_install()
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertEqual(wallpaper.readlink(), target)
        self.log.write_text("")
        checked = self.run_install("--check")
        self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
        self.assertNotIn("daemon-reload", self.log.read_text())
        self.assertNotIn("start ", self.log.read_text())
        self.assertNotIn("qs ", self.log.read_text())

    def test_conflict_aborts_without_other_links_or_overwrite(self):
        path = self.home / ".config/dunst/dunstrc"
        path.parent.mkdir(parents=True)
        path.write_text("personal config")
        result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(path.read_text(), "personal config")
        self.assertFalse((self.home / ".config/systemd/user/clipboard-history.service").exists())
        self.assertFalse((self.home / "Pictures").exists())

    def test_existing_local_monitor_and_folded_quickshell(self):
        monitor = self.home / ".config/hypr/monitors_local.lua"
        monitor.parent.mkdir(parents=True)
        monitor.write_text("-- this machine only\n")
        (self.home / ".config/quickshell").symlink_to(
            os.path.relpath(self.clone / "quickshell/.config/quickshell", self.home / ".config"))
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(monitor.read_text(), "-- this machine only\n")
        self.assertFalse((self.clone / "hyprland/.config/hypr/monitors_local.lua").exists())

    def test_missing_dependency_aborts_before_stow(self):
        self.stub("pacman", "exit 1\n")
        result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / ".config").exists())

    def test_no_user_manager_and_wallpaper_override(self):
        self.stub("systemctl", "exit 1\n")
        self.env["WALLPAPER_DIR"] = str(self.root / "unrelated wallpapers")
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("No user systemd manager", result.stdout)
        self.assertTrue((self.home / "Pictures/Wallpapers/.current").is_file())
        self.assertFalse((self.root / "unrelated wallpapers").exists())

    def test_check_fresh_home_does_not_create_files(self):
        result = self.run_install("--check")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_live_check_detects_inactive_services_with_working_shell(self):
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.env["WAYLAND_DISPLAY"] = "fixture-display"
        self.env["HYPRLAND_INSTANCE_SIGNATURE"] = "fixture-instance"
        self.stub("qs", "printf 'target launcher\\ntarget sidebar\\n'\n")
        for inactive in ("hypridle.service", "clipboard-history.service"):
            with self.subTest(inactive=inactive):
                self.stub("systemctl", f'[[ "$*" != "--user is-active --quiet {inactive}" ]]\n')
                checked = self.run_install("--check")
                self.assertNotEqual(checked.returncode, 0)
                self.assertIn("service inactive: " + inactive, checked.stdout)
                self.assertIn("Running shell exposes", checked.stdout)

    def test_wallpaper_preserves_existing_regular_file_and_symlink(self):
        directory = self.home / "Pictures/Wallpapers"
        directory.mkdir(parents=True)
        current = directory / ".current"
        current.write_bytes(b"user image")
        script = self.clone / "hyprland/.config/hypr/scripts/wallpaper.sh"
        subprocess.run([str(script), "ensure"], env=self.env, check=True, capture_output=True)
        self.assertFalse(current.is_symlink())
        self.assertEqual(current.read_bytes(), b"user image")
        current.unlink()
        image = directory / "mine.png"
        image.write_bytes(b"existing")
        current.symlink_to(image)
        subprocess.run([str(script), "ensure"], env=self.env, check=True, capture_output=True)
        self.assertEqual(current.readlink(), image)

    def test_wallpaper_repairs_broken_link_and_rejects_collision(self):
        directory = self.home / "Pictures/Wallpapers"
        directory.mkdir(parents=True)
        current = directory / ".current"
        current.symlink_to(directory / "missing.png")
        script = self.clone / "hyprland/.config/hypr/scripts/wallpaper.sh"
        subprocess.run([str(script), "ensure"], env=self.env, check=True, capture_output=True)
        self.assertTrue(current.is_file())
        current.unlink()
        current.mkdir()
        result = subprocess.run([str(script), "ensure"], env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(current.is_dir())

    def test_default_wallpaper_file_is_never_overwritten(self):
        directory = self.home / "Pictures/Wallpapers"
        directory.mkdir(parents=True)
        fallback = directory / ".default.png"
        fallback.write_bytes(b"user fallback")
        script = self.clone / "hyprland/.config/hypr/scripts/wallpaper.sh"
        subprocess.run([str(script), "ensure"], env=self.env, check=True, capture_output=True)
        self.assertEqual(fallback.read_bytes(), b"user fallback")
        (directory / ".current").unlink()
        fallback.unlink()
        fallback.mkdir()
        result = subprocess.run([str(script), "ensure"], env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(fallback.is_dir())

    def test_terminal_falls_back_and_prefers_executable_copad(self):
        script = self.clone / "hyprland/.config/hypr/scripts/terminal.sh"
        subprocess.run([str(script), "hello world"], env=self.env, check=True)
        self.assertIn("kitty hello world", self.log.read_text())
        copad = self.home / ".local/bin/copad"
        copad.parent.mkdir(parents=True)
        copad.write_text('#!/bin/bash\nprintf "copad\\n" >> "$TEST_LOG"\n')
        copad.chmod(0o755)
        subprocess.run([str(script)], env=self.env, check=True)
        self.assertTrue(self.log.read_text().endswith("copad\n"))


if __name__ == "__main__":
    unittest.main()
