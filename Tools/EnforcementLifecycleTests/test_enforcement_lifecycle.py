"""Run under a logged-in macOS account: python3 Tools/EnforcementLifecycleTests/test_enforcement_lifecycle.py"""
import fcntl
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
AGENT = ROOT / "Services/com.prakashjoshipax.Fence.enforcement.plist"


@unittest.skipUnless(sys.platform == "darwin", "requires macOS launchd")
class EnforcementLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        build = tempfile.TemporaryDirectory(prefix="fence-lifecycle-build-")
        cls.addClassCleanup(build.cleanup)
        cls.executable = Path(build.name) / "Fence"
        boundaries = {
            "App/FenceApp.swift", "Detection/ContextMonitor.swift",
            "Enforcement/PauseController.swift", "Enforcement/FenceInstallation.swift",
        }
        source = ROOT / "Fence"
        sources = sorted(p for p in source.rglob("*.swift") if str(p.relative_to(source)) not in boundaries)
        subprocess.run(["swiftc", "-swift-version", "5", "-strict-concurrency=complete", "-warnings-as-errors",
                        "-o", cls.executable, *sources, HERE / "HeadlessBoundaries.swift"], check=True)

    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="fence-lifecycle-", dir="/private/tmp")
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.domain = f"gui/{os.getuid()}"
        self.label = "test.fence.lifecycle." + uuid.uuid4().hex
        self.target = f"{self.domain}/{self.label}"
        self.addCleanup(self.clean_fixture_preferences)
        app = self.root / "FenceLifecycle.app"
        job = plistlib.loads(AGENT.read_bytes())
        self.assertEqual(job["ProgramArguments"], ["Fence", "--enforcement-agent"])
        self.assertIs(job["KeepAlive"], True)
        self.assertEqual(job["BundleProgram"], "Contents/MacOS/Fence")
        self.binary = app / job.pop("BundleProgram")
        self.binary.parent.mkdir(parents=True)
        shutil.copy2(self.executable, self.binary)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": self.label, "CFBundleExecutable": "Fence", "CFBundleVersion": "1",
            "CFBundlePackageType": "APPL", "LSUIElement": True, "FenceTestDirectory": str(self.root),
        }))

        dashboard_log = (self.root / "dashboard.log").open("w")
        self.addCleanup(dashboard_log.close)
        self.dashboard = subprocess.Popen([self.binary, "--fixture-dashboard"], stderr=dashboard_log)
        self.addCleanup(self.stop_dashboard)
        self.wait_for(lambda: (self.root / "dashboard-ready").exists(), "headless dashboard startup")
        # SMAppService resolves BundleProgram relative to its signed bundle. For an
        # ephemeral launchctl job, resolve that one path here and keep its restart policy.
        job.update(Label=self.label, Program=str(self.binary), StandardErrorPath=str(self.root / "agent.log"))
        self.plist = self.root / "job.plist"
        self.plist.write_bytes(plistlib.dumps(job))
        self.addCleanup(self.remove_test_job)
        self.bootstrap()
        self.initial_pid = self.wait_for(self.job_pid, "launchd to report its first PID")
        self.probe("game", expected="app:test.fence.game", expected_pid=self.initial_pid)

    def wait_for(self, predicate, description, timeout=30):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if value := predicate():
                return value
            time.sleep(0.05)
        logs = [p.read_text()[-1200:] for p in self.root.glob("*.log")]
        self.fail(f"Timed out waiting for {description}. " + "\n".join(logs))

    def clean_fixture_preferences(self):
        # AppKit can persist per-bundle defaults even when no windows are shown.
        if (Path.home() / "Library/Preferences" / (self.label + ".plist")).exists():
            subprocess.run(["defaults", "delete", self.label], check=True, timeout=5)

    def bootstrap(self):
        subprocess.run(["launchctl", "bootstrap", self.domain, self.plist], check=True, timeout=15)

    def remove_test_job(self):
        if self.launch_status().returncode == 0:
            self.unload()

    def unload(self):
        subprocess.run(["launchctl", "bootout", self.target], check=True, timeout=20)
        self.wait_for(lambda: self.launch_status().returncode != 0, "test job removal")

    def launch_status(self):
        return subprocess.run(["launchctl", "print", self.target], capture_output=True, text=True, timeout=5)

    def job_pid(self):
        state = self.launch_status()
        match = re.search(r"^\s*pid = (\d+)$", state.stdout, re.MULTILINE)
        return int(match[1]) if state.returncode == 0 and match else None

    def stop_dashboard(self):
        if self.dashboard.poll() is None:
            self.dashboard.kill()
        self.dashboard.wait(timeout=5)

    def probe(self, kind, path="", *, expected, expected_pid=None, timeout=30):
        token = uuid.uuid4().hex
        temporary = self.root / "probe.tmp"
        temporary.write_text(json.dumps(dict(token=token, kind=kind, path=path)))
        temporary.replace(self.root / "probe.json")

        def fresh_response():
            result = self.root / "response.json"
            if result.exists():
                record = json.loads(result.read_text())
                if record["token"] == token and (expected_pid is None or record["pid"] == expected_pid):
                    return record

        record = self.wait_for(fresh_response, f"{kind} {path} decision", timeout)
        self.assertEqual(record["action"], expected)
        self.assertIs(record["accessory"], True)
        self.assertEqual(record["visibleWindows"], 0)
        self.assertIs(record["canQuit"], False)
        self.assertFalse((self.root / "unexpected-dashboard").exists(), "dashboard was automatically reopened")
        return record

    def test_dashboard_force_quit_keeps_same_enforcer(self):
        self.stop_dashboard()
        self.assertEqual(self.dashboard.returncode, -9)
        for kind, path, expected in [
            ("browser", "/feed", "path:fixture.invalid/feed"),
            ("browser", "/inbox", "allow"), ("game", "", "app:test.fence.game"),
        ]:
            with self.subTest(kind=kind, path=path):
                self.assertEqual(self.probe(kind, path, expected=expected)["pid"], self.initial_pid)
        # Include more than two production engine ticks to catch delayed UI relaunch requests.
        time.sleep(2.2)
        self.assertEqual(self.job_pid(), self.initial_pid)
        self.assertFalse((self.root / "unexpected-dashboard").exists())

    def test_open_dashboard_takes_over_then_returns_monitor_to_agent(self):
        # The real dashboard engine rejects a normal Terminal termination signal while active.
        self.dashboard.send_signal(signal.SIGTERM)
        self.probe("browser", "/inbox", expected="allow", expected_pid=self.initial_pid)
        self.assertIsNone(self.dashboard.poll())

        # Hold the job out of launchd until the dashboard proves it took over.
        # Otherwise a fast restart could legitimately eliminate the fallback interval.
        self.unload()
        self.probe("browser", "/feed", expected="path:fixture.invalid/feed", expected_pid=self.dashboard.pid)
        self.bootstrap()
        replacement = self.wait_for(self.replacement_pid, "replacement agent to launch")
        self.probe("browser", "/feed", expected="path:fixture.invalid/feed", expected_pid=replacement)
        self.assertIsNone(self.dashboard.poll())

    def replacement_pid(self):
        pid = self.job_pid()
        return pid if pid and pid != self.initial_pid else None

    def test_force_quit_soon_after_agent_start(self):
        self.stop_dashboard()
        self.check_launchd_recovery()

    def test_force_quit_after_agent_has_been_running(self):
        self.stop_dashboard()
        # Exercise a job that has outlived the normal launchd respawn throttle as well.
        time.sleep(12)
        self.assertEqual(self.job_pid(), self.initial_pid)
        self.check_launchd_recovery()

    def check_launchd_recovery(self):
        started = time.monotonic()
        subprocess.run(["launchctl", "kill", "SIGKILL", self.target], check=True, timeout=5)

        replacement = self.wait_for(self.replacement_pid, "launchd to start a different PID")
        result = self.probe("browser", "/feed", expected="path:fixture.invalid/feed")
        self.assertEqual(result["pid"], replacement)
        print(f"\n  launchd replaced PID {self.initial_pid} with {replacement}; "
              f"first confirmed blocked probe after {time.monotonic() - started:.2f}s", flush=True)
        self.assertEqual(self.probe("game", expected="app:test.fence.game")["pid"], replacement)
        self.assertEqual(self.probe("browser", "/inbox", expected="allow")["pid"], replacement)

    def update_rule(self, **changes):
        rules = self.root / "blocks.json"
        with (self.root / "blocks.json.lock").open("r+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            entries = json.loads(rules.read_text())
            entries[0].update(changes)
            temp = self.root / "settings.tmp"
            temp.write_text(json.dumps(entries))
            temp.replace(rules)

    def monitor_is_idle(self):
        with (self.root / "monitor.lock").open("r") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return True
            except BlockingIOError:
                return False

    def test_agent_restores_exact_trashed_app_during_unlocked_block(self):
        self.stop_dashboard()
        app = self.root / "FenceLifecycle.app"
        trash = self.root / "FixtureTrash"
        trash.mkdir()
        decoy = trash / app.name
        decoy.mkdir()
        original_inode = app.stat().st_ino
        moved = trash / "FenceLifecycle 2.app"
        app.rename(moved)
        self.wait_for(app.is_dir, "original bundle to return")
        self.assertEqual(app.stat().st_ino, original_inode)
        self.assertFalse(moved.exists())
        self.assertTrue(decoy.is_dir())
        self.probe("game", expected="app:test.fence.game", expected_pid=self.initial_pid)

    def test_recovery_leaves_ordinary_moves_and_destination_conflicts_alone(self):
        self.stop_dashboard()
        app = self.root / "FenceLifecycle.app"
        moved = self.root / "Relocated.app"
        app.rename(moved)
        time.sleep(2.2)
        self.assertTrue(moved.is_dir())
        self.assertFalse(app.exists())

        app.mkdir()
        marker = app / "replacement"
        marker.touch()
        trash = self.root / "FixtureTrash"
        trash.mkdir()
        moved.rename(trash / moved.name)
        time.sleep(2.2)
        self.assertTrue(marker.exists())
        self.assertTrue((trash / moved.name).is_dir())

    def test_idle_trash_move_stays_removed_if_another_session_starts(self):
        self.stop_dashboard()
        self.update_rule(isEnabled=False)
        self.wait_for(self.monitor_is_idle, "unlocked block to stop")
        app = self.root / "FenceLifecycle.app"
        trash = self.root / "FixtureTrash"
        trash.mkdir()
        app.rename(trash / app.name)
        self.update_rule(isEnabled=True)
        self.probe("game", expected="app:test.fence.game", expected_pid=self.initial_pid)
        time.sleep(2.2)
        self.assertFalse(app.exists())
        self.assertTrue((trash / app.name).is_dir())

    def test_open_app_restores_from_trash_when_agent_is_unavailable(self):
        self.unload()
        self.probe("game", expected="app:test.fence.game", expected_pid=self.dashboard.pid)
        app = self.root / "FenceLifecycle.app"
        trash = self.root / "FixtureTrash"
        trash.mkdir()
        app.rename(trash / app.name)
        self.wait_for(app.is_dir, "open app to restore its own bundle")
        self.assertFalse((trash / app.name).exists())

    def test_running_agent_finishes_unlocked_timer_after_fixture_app_is_removed(self):
        self.stop_dashboard()
        # Foundation's default JSON date is seconds since 2001-01-01 UTC.
        deadline = time.time() + 8
        self.update_rule(schedule={"manual": {}}, manualRunEndsAt=deadline - 978307200)
        app = self.root / "FenceLifecycle.app"
        shutil.rmtree(app)
        self.assertFalse(app.exists())
        self.probe("browser", "/feed", expected="path:fixture.invalid/feed", expected_pid=self.initial_pid)
        self.assertLess(time.time(), deadline)

        self.wait_for(lambda: not json.loads((self.root / "blocks.json").read_text())[0]["isEnabled"],
                      "agent to finish the timer without its app bundle")
        self.assertGreaterEqual(time.time(), deadline)
        self.wait_for(self.monitor_is_idle, "monitor to stop at expiry")
        self.assertEqual(self.job_pid(), self.initial_pid)
        self.assertFalse((self.root / "unexpected-dashboard").exists())

    def test_agent_observes_disabled_and_reenabled_rule_without_dashboard(self):
        self.stop_dashboard()
        self.update_rule(isEnabled=False)
        self.wait_for(self.monitor_is_idle, "agent to release the monitor")
        self.assertEqual(self.job_pid(), self.initial_pid)
        self.update_rule(isEnabled=True)
        self.assertEqual(self.probe("game", expected="app:test.fence.game")["pid"], self.initial_pid)


if __name__ == "__main__":
    unittest.main(verbosity=2)
