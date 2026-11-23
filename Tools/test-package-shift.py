"""Check the macOS installer payload without installing or launching Shift."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

TOOLS = Path(__file__).resolve().parent
AGENT = "com.beingpax.Shift.enforcement.plist"


class PackageTests(unittest.TestCase):
    def test_standard_account_cannot_write_packaged_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            app = work / "Shift.app"
            contents = app / "Contents"
            executable = contents / "MacOS/Shift"
            executable.parent.mkdir(parents=True)
            executable.write_bytes(Path("/usr/bin/true").read_bytes())
            executable.chmod(0o777)
            (contents / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "com.beingpax.Shift", "CFBundleExecutable": "Shift",
                "CFBundlePackageType": "APPL", "CFBundleVersion": "18", "CFBundleShortVersionString": "1.0",
            }))
            output = work / "Shift.pkg"
            build = [TOOLS / "package-shift.sh", app, output]
            self.assertNotEqual(subprocess.run(build, capture_output=True).returncode, 0)
            self.assertFalse(output.exists())

            agent = contents / "Library/LaunchAgents" / AGENT
            agent.parent.mkdir(parents=True)
            shutil.copyfile(TOOLS.parent / "Services" / AGENT, agent)
            subprocess.run(build, check=True)
            expanded = work / "expanded"
            subprocess.run(["pkgutil", "--expand", output, expanded], check=True)
            info = ET.parse(expanded / "PackageInfo").getroot()
            self.assertEqual(info.get("install-location"), "/Applications")
            self.assertEqual(info.get("auth"), "root")
            self.assertEqual(info.get("version"), "18")
            self.assertFalse(info.findall("relocate/bundle"))
            bom = subprocess.check_output(["lsbom", "-p", "fmug", expanded / "Bom"], text=True)
            entries = {}
            for line in bom.splitlines():
                path, mode, uid, gid = line.split("\t")
                if path.startswith("./Shift.app"):
                    self.assertEqual(int(uid), 0, path)
                    self.assertEqual(int(mode, 8) & 0o022, 0, path)
                    entries[path] = int(mode, 8)
            self.assertIn("./Shift.app", entries)
            self.assertIn(f"./Shift.app/Contents/Library/LaunchAgents/{AGENT}", entries)
            self.assertTrue(entries["./Shift.app/Contents/MacOS/Shift"] & 0o001)
            self.assertEqual(executable.stat().st_mode & 0o777, 0o777)


if __name__ == "__main__":
    unittest.main()
