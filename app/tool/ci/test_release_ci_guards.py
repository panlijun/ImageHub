"""Control checks, never a substitute for native CI execution."""

import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest import mock

import boot_ios_simulator as boot
from verify_apple_versions import verify


class PhotosOwnershipTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.record = {"formatVersion": 1, "runId": "123", "runAttempt": "2",
                       "udid": "7a6b4f55-32e9-4c4e-96ef-2ac114643671",
                       "name": "ImageHub-CI-123-2-1234abcd",
                       "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-26-2",
                       "deviceType": "com.apple.CoreSimulator.SimDeviceType.iPhone-17"}
        self.marker = Path(self.temporary.name) / boot.MARKER_NAME
        self.marker.write_text(json.dumps(self.record), encoding="utf-8")
        environment = {"RUNNER_TEMP": self.temporary.name, "GITHUB_RUN_ID": "123",
                       "GITHUB_RUN_ATTEMPT": "2",
                       "IMAGEHOST_IOS_SIMULATOR": self.record["udid"]}
        patch = mock.patch.dict(os.environ, environment)
        patch.start()
        self.addCleanup(patch.stop)

    def listing(self, state="Booted", name=None):
        return json.dumps({"devices": {self.record["runtime"]: [{
            "udid": self.record["udid"].upper(),
            "name": name or self.record["name"], "state": state,
            "deviceTypeIdentifier": self.record["deviceType"]}]}})

    def test_add_permission_cannot_grant_read(self):
        with mock.patch.object(boot, "simctl", return_value=self.listing()) as command:
            boot.authorize_photos("add-only")
        self.assertEqual(command.call_args_list, [
            mock.call("list", "devices", "--json"),
            mock.call("privacy", self.record["udid"], "grant", "photos-add", "io.imagehost.imagehost")])

    def test_read_permission_is_scoped_to_owned_app(self):
        with mock.patch.object(boot, "simctl", return_value=self.listing()) as command:
            boot.authorize_photos("read-write")
        self.assertEqual(command.call_args,
                         mock.call("privacy", self.record["udid"], "grant", "photos", "io.imagehost.imagehost"))

    def test_another_selected_uuid_rejects_before_system_command(self):
        with mock.patch.dict(os.environ, {"IMAGEHOST_IOS_SIMULATOR": "1ea3954b-390f-41e3-b39d-c8b1b4f72318"}), \
                mock.patch.object(boot, "simctl") as command:
            with self.assertRaises(SystemExit):
                boot.authorize_photos("read-write")
            command.assert_not_called()

    def test_missing_marker_never_grants(self):
        self.marker.unlink()
        with mock.patch.object(boot, "simctl") as command:
            with self.assertRaises(SystemExit):
                boot.authorize_photos("add-only")
            command.assert_not_called()

    def test_changed_device_or_shutdown_never_grants(self):
        for listing in (self.listing(name="User iPhone"), self.listing(state="Shutdown")):
            with self.subTest(listing=listing), \
                    mock.patch.object(boot, "simctl", return_value=listing) as command:
                with self.assertRaises(SystemExit):
                    boot.authorize_photos("read-write")
                self.assertEqual(command.call_args_list, [mock.call("list", "devices", "--json")])

    def test_another_attempt_marker_never_grants(self):
        record = dict(self.record, runAttempt="1")
        self.marker.write_text(json.dumps(record), encoding="utf-8")
        with mock.patch.object(boot, "simctl") as command:
            with self.assertRaises(SystemExit):
                boot.authorize_photos("read-write")
            command.assert_not_called()

    def test_revoke_failure_still_retires_only_confirmed_owned_device(self):
        def command(*args, **kwargs):
            if args == ("list", "devices", "--json"):
                return self.listing() if not deleted[0] else '{"devices":{}}'
            if args[:1] == ("privacy",) and args[3] == "photos":
                raise SystemExit("Controlled revoke failure")
            if args[:1] == ("delete",):
                deleted[0] = True
            return ""
        deleted = [False]
        with mock.patch.object(boot, "simctl", side_effect=command) as calls, \
                mock.patch.object(boot, "shutdown_owned") as shutdown:
            boot.cleanup()
        shutdown.assert_called_once_with(self.record)
        self.assertIn(mock.call("privacy", self.record["udid"], "revoke", "photos", "io.imagehost.imagehost"), calls.call_args_list)
        self.assertIn(mock.call("privacy", self.record["udid"], "revoke", "photos-add", "io.imagehost.imagehost"), calls.call_args_list)
        self.assertIn(mock.call("delete", self.record["udid"]), calls.call_args_list)
        self.assertFalse(self.marker.exists())


class NativeVersionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name) / "ImageHub.app"
        self.app.mkdir()
        self.versions = {"kernel": {"version": "1.2.3", "revision": 7},
                         "platforms": {"macos": {"version": "2.3.4", "build": 9},
                                       "ios": {"version": "3.4.5", "build": 11}}}

    def write(self, platform, **overrides):
        own = self.versions["platforms"][platform]
        actual = {"CFBundleIdentifier": "io.imagehost.imagehost",
                  "CFBundleShortVersionString": own["version"], "CFBundleVersion": str(own["build"]),
                  "ImageHubKernelVersion": "1.2.3", "ImageHubKernelRevision": "7"}
        actual.update(overrides)
        path = self.app / ("Contents/Info.plist" if platform == "macos" else "Info.plist")
        path.parent.mkdir(exist_ok=True)
        with path.open("wb") as output:
            plistlib.dump(actual, output)

    def test_two_platforms_keep_their_own_versions(self):
        for platform in ("macos", "ios"):
            self.write(platform)
            self.assertTrue(verify(platform, self.app, self.versions)["verified"])

    def test_kernel_version_cannot_replace_platform_version(self):
        self.write("ios", CFBundleShortVersionString="1.2.3")
        with self.assertRaises(ValueError):
            verify("ios", self.app, self.versions)

    def test_missing_kernel_revision_cannot_pass(self):
        self.write("macos", ImageHubKernelRevision="")
        with self.assertRaises(ValueError):
            verify("macos", self.app, self.versions)

    def test_changed_application_identity_cannot_pass(self):
        self.write("ios", CFBundleIdentifier="io.imagehub.changed")
        with self.assertRaises(ValueError):
            verify("ios", self.app, self.versions)


if __name__ == "__main__":
    unittest.main()
