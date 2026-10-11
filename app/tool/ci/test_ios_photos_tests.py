"""Owned synthetic Photos controller checks; no real Apple/Photos operations."""

import contextlib
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import threading
import unittest
from unittest import mock

import run_ios_photos_tests as runner
from test_ios_integration import Process, Pipe, FOUND_NOTHING
from test_ios_xctest_integration import OwnedTemp, SIGNING_DISPLAY, SIGNING_ENTITLEMENTS


class ControllerTests(OwnedTemp):
    def setUp(self):
        super().setUp()
        self.record = {"formatVersion": 1, "runId": "123", "runAttempt": "2",
                       "udid": "7a6b4f55-32e9-4c4e-96ef-2ac114643671",
                       "name": "ImageHub-CI-123-2-1234abcd",
                       "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-26-2",
                       "deviceType": "com.apple.CoreSimulator.SimDeviceType.iPhone-17"}
        self.marker = self.root / runner.host.boot.MARKER_NAME
        self.marker.write_text(json.dumps(self.record))
        self.stack.enter_context(mock.patch.dict(os.environ, {"CI": "true", "RUNNER_TEMP": str(self.root),
            "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "2", "IMAGEHOST_IOS_SIMULATOR": self.record["udid"]}))
        self.stack.enter_context(mock.patch.object(runner.sys, "platform", "darwin"))
        self.stack.enter_context(mock.patch.object(runner, "__file__", str(self.root / "tool/ci/run_ios_photos_tests.py")))
        self.stack.enter_context(mock.patch.object(runner, "TIMEOUT", 0.06))
        self.stack.enter_context(mock.patch.object(runner.host, "CLOSE_TIMEOUT", 0.04))
        Path("lib").mkdir()
        Path(runner.TARGET).write_text("// Synthetic normal entry; never run.\n")
        self.versions = {"platforms": {"ios": {"version": "0.1.0", "build": 1}},
                         "kernel": {"version": "0.1.0", "revision": 1}}
        Path("versions.json").write_text(json.dumps(self.versions))
        runner.ARTIFACTS.mkdir(parents=True)
        self.info = {"CFBundleIdentifier": runner.host.BUNDLE_ID, "CFBundleExecutable": "Runner",
                     "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
                     "ImageHubKernelVersion": "0.1.0", "ImageHubKernelRevision": "1"}
        self.installed = self.root / "synthetic-installed/Runner.app"
        self.container = (f"/Users/runner/Library/Developer/CoreSimulator/Devices/{self.record['udid']}"
                          "/data/Containers/Bundle/Application/12345678-1234-4234-8234-123456789012/Runner.app\n")
        real_path = runner.installed_path
        def installed_path(raw, identifier):
            # Keep the real strict response parser; map only its ordinary-dir IO
            # to this Windows-compatible, explicitly test-owned fixture.
            with mock.patch.object(runner.evidence, "ordinary_path"):
                real_path(raw, identifier)
            return self.installed
        self.stack.enter_context(mock.patch.object(runner, "installed_path", side_effect=installed_path))
        self.calls = []
        self.processes = []
        self.state = "Booted"
        self.build_code = 0
        self.test_code = 0
        self.build_timeout = False
        self.test_timeout = False
        self.install_code = 0
        self.privacy_code = 0
        self.privacy_failure_operation = None
        self.privacy_mutation = None
        self.stop_code = 3
        self.stop_output = FOUND_NOTHING.encode()
        self.summary_changes = {}
        self.summary_code = 0
        self.built_display = SIGNING_DISPLAY
        self.installed_display = SIGNING_DISPLAY
        self.signing_code = 0
        self.installed_mutation = None
        self.test_mutation = None
        self.test_output = b"Synthetic test\n"
        self.output = io.StringIO()
        self.stack.enter_context(contextlib.redirect_stdout(self.output))
        self.stack.enter_context(mock.patch.object(runner.host.subprocess, "Popen", side_effect=self.popen))

    def build_fixture(self):
        bundle = runner.built_bundle()
        bundle.mkdir(parents=True)
        (bundle / "Runner").write_bytes(b"synthetic closed Mach-O placeholder")
        (bundle / "Info.plist").write_bytes(plistlib.dumps(self.info))
        generated = runner.DERIVED / "Build/Intermediates.noindex/Runner.build/Debug-iphonesimulator/Runner.build"
        generated.mkdir(parents=True)
        for name in ("Runner.app.xcent", "Runner.app.xcent-simulated"):
            (generated / name).write_bytes(plistlib.dumps(SIGNING_ENTITLEMENTS))

    def popen(self, args, **options):
        self.assertIs(options["shell"], False)
        self.calls.append(args)
        if args[0] == "xcodebuild":
            if args[1] == "build-for-testing":
                self.build_fixture()
                process = Process(b"Synthetic build\n", code=self.build_code, running=self.build_timeout)
            else:
                Path(args[args.index("-resultBundlePath") + 1]).mkdir()
                if self.test_mutation:
                    self.test_mutation()
                process = Process(self.test_output, code=self.test_code, running=self.test_timeout)
        elif args[0] == "codesign":
            if args[1] == "--verify":
                process = Process(code=self.signing_code)
            elif args[2] == "--verbose=4":
                display = self.installed_display if args[-1] == str(self.installed) else self.built_display
                process = Process(display.encode())
            else:
                process = Process(b"Executable=synthetic-verified-host\n")
        elif args[:4] == ["xcrun", "simctl", "list", "devices"]:
            process = Process(json.dumps({"devices": {self.record["runtime"]: [{"udid": self.record["udid"],
                "name": self.record["name"], "deviceTypeIdentifier": self.record["deviceType"],
                "isAvailable": True, "state": self.state}]}}).encode())
        elif args[:3] == ["xcrun", "simctl", "install"]:
            self.installed.mkdir(parents=True)
            for name in ("Runner", "Info.plist"):
                shutil.copyfile(runner.built_bundle() / name, self.installed / name)
            if self.installed_mutation:
                self.installed_mutation()
            process = Process(code=self.install_code)
        elif args[:3] == ["xcrun", "simctl", "get_app_container"]:
            self.assertEqual(args[-2:], [runner.host.BUNDLE_ID, "app"])
            process = Process(self.container.encode())
        elif args[:4] == ["xcrun", "simctl", "help", "privacy"]:
            process = Process(b"Synthetic help: photos photos-add grant reset\n")
        elif args[:3] == ["xcrun", "simctl", "privacy"]:
            if self.privacy_mutation:
                self.privacy_mutation()
            code = self.privacy_code if self.privacy_failure_operation is None or tuple(args[-3:-1]) == self.privacy_failure_operation else 0
            process = Process(code=code)
        elif args[:3] == ["xcrun", "simctl", "terminate"]:
            process = Process(self.stop_output, code=self.stop_code)
        elif args[:3] == ["xcrun", "xcresulttool", "get"]:
            count = 27 if args[-1].endswith("ios-file-tests.xcresult") else 1
            summary = {"totalTestCount": count, "passedTests": count, "failedTests": 0, "skippedTests": 0}
            summary.update(self.summary_changes)
            process = Process(json.dumps(summary).encode(), code=self.summary_code)
        else:
            raise AssertionError("Unexpected native command in synthetic Photos control.")
        self.processes.append(process)
        return process

    def commands(self, action):
        return [args for args in self.calls if args[:3] == ["xcrun", "simctl", action]]

    def failure(self, phase, code):
        with self.assertRaisesRegex(runner.Failure, code):
            runner.run_phase(phase)
        self.assertFalse((runner.ARTIFACTS / f"ios-photos-{phase}-result.json").exists())

    def prepared(self):
        runner.run_phase("prepare")
        self.assertFalse(self.commands("terminate"))
        self.assertFalse(self.commands("privacy"))
        self.assertTrue((runner.ARTIFACTS / "ios-photos-prepared.json").is_file())

    def test_exact_three_phases_same_host_commands_results_and_closed_readers(self):
        self.prepared()
        add = runner.run_phase("add-only")
        read = runner.run_phase("read-write")
        self.assertEqual((add["xctestPassed"], read["xctestPassed"]), (1, 27))
        xcodes = [args for args in self.calls if args[0] == "xcodebuild"]
        self.assertEqual([args[1] for args in xcodes], ["build-for-testing", "test-without-building", "test-without-building"])
        for args in xcodes:
            self.assertIn("FLUTTER_TARGET=lib/main.dart", args)
            self.assertIn("CODE_SIGNING_ALLOWED=YES", args)
            self.assertIn("CODE_SIGN_IDENTITY=-", args)
            self.assertIn("CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES", args)
            self.assertEqual(args[args.index("-derivedDataPath") + 1], str(runner.DERIVED))
            self.assertIn(self.record["udid"].upper(), args[args.index("-destination") + 1])
        self.assertIn("-only-testing:" + runner.ADD_TEST, xcodes[1])
        self.assertIn("-only-testing:RunnerTests", xcodes[2])
        self.assertEqual([args[-3:] for args in self.commands("privacy")],
                         [["reset", "photos", runner.host.BUNDLE_ID], ["grant", "photos-add", runner.host.BUNDLE_ID],
                          ["grant", "photos", runner.host.BUNDLE_ID]])
        self.assertTrue(all(p.stdout.closed and p.waited for p in self.processes))
        self.assertEqual(len(self.commands("install")), 1)
        self.assertEqual(len(self.commands("terminate")), 2)
        self.assertTrue(add["ownedAppStopped"] and read["ownedAppStopped"])

    def test_illegal_phase_and_missing_normal_entry_never_spawn(self):
        self.failure("arbitrary", "photos-phase-invalid")
        self.assertEqual(self.calls, [])
        Path(runner.TARGET).unlink()
        self.failure("prepare", "evidence-path-unavailable")
        self.assertEqual(self.calls, [])

    def test_foreign_attempt_selected_uuid_and_changed_device_never_build(self):
        self.stack.enter_context(mock.patch.dict(os.environ, {"GITHUB_RUN_ATTEMPT": "3"}))
        self.failure("prepare", "ownership-invalid")
        self.assertEqual(self.calls, [])

    def test_foreign_selected_uuid_never_mutates(self):
        os.environ["IMAGEHOST_IOS_SIMULATOR"] = "12345678-1234-4234-8234-123456789012"
        self.failure("prepare", "ownership-selected-uuid-mismatch")
        self.assertEqual(self.calls, [])

    def test_shutdown_device_never_builds(self):
        self.state = "Shutdown"
        self.failure("prepare", "ownership-device-not-booted")
        self.assertFalse(any(args[0] == "xcodebuild" for args in self.calls))

    def test_existing_derived_data_is_preserved_and_refused(self):
        runner.DERIVED.mkdir()
        (runner.DERIVED / "unknown").write_bytes(b"retain")
        self.failure("prepare", "photos-derived-data-not-fresh")
        self.assertTrue((runner.DERIVED / "unknown").is_file())

    def test_existing_phase_output_is_preserved_before_permission(self):
        self.prepared()
        output = runner.ARTIFACTS / "ios-photos-add-only-xcode.log"
        output.write_bytes(b"Unknown existing output; preserve")
        self.failure("add-only", "photos-artifact-not-fresh")
        self.assertEqual(output.read_bytes(), b"Unknown existing output; preserve")
        self.assertFalse(self.commands("privacy"))

    def test_xcode_log_redacts_vm_authentication_uri(self):
        self.prepared()
        self.test_output = b"VM http://127.0.0.1:54321/OnlySyntheticAuth=/\n"
        runner.run_phase("add-only")
        raw = (runner.ARTIFACTS / "ios-photos-add-only-xcode.log").read_text()
        self.assertNotIn("SyntheticAuth", raw)
        self.assertIn("<loopback-vm-uri>", raw)

    def test_build_nonzero_and_timeout_never_install(self):
        self.build_code = 65
        self.failure("prepare", "photos-xcode-prepare-exit-nonzero")
        self.assertFalse(self.commands("install"))
        self.assertTrue((runner.ARTIFACTS / "ios-photos-prepare-xcode.log").is_file())

    def test_build_timeout_never_installs(self):
        self.build_timeout = True
        self.failure("prepare", "photos-xcode-prepare-timeout")
        self.assertFalse(self.commands("install"))
        self.assertTrue(self.processes[-1].terminated and self.processes[-1].stdout.closed)

    def test_wrong_built_bundle_and_version_never_install(self):
        self.info["CFBundleIdentifier"] = "io.other.app"
        self.failure("prepare", "photos-bundle-identity-mismatch")
        self.assertFalse(self.commands("install"))

    def test_built_version_mismatch_never_installs(self):
        self.info["CFBundleVersion"] = "99"
        self.failure("prepare", "photos-version-mismatch")
        self.assertFalse(self.commands("install"))

    def test_built_bad_signature_never_installs(self):
        self.built_display = SIGNING_DISPLAY.replace("adhoc", "sha256")
        self.failure("prepare", "signing-not-adhoc")
        self.assertFalse(self.commands("install"))

    def test_codesign_verify_failure_never_installs(self):
        self.signing_code = 1
        self.failure("prepare", "photos-signing-verify-exit-nonzero")
        self.assertFalse(self.commands("install"))

    def test_installed_different_bytes_refuse_prepared(self):
        self.installed_mutation = lambda: (self.installed / "Runner").write_bytes(b"different executable")
        self.failure("prepare", "photos-installed-host-mismatch")
        self.assertFalse((runner.ARTIFACTS / "ios-photos-prepared.json").exists())
        document = json.loads((runner.ARTIFACTS / "ios-photos-prepare-installed-host.json").read_text())
        self.assertIs(document["hostFingerprintMatches"], False)

    def test_installed_wrong_bundle_refuses_prepared(self):
        def change():
            info = dict(self.info, CFBundleIdentifier="io.other.app")
            (self.installed / "Info.plist").write_bytes(plistlib.dumps(info))
        self.installed_mutation = change
        self.failure("prepare", "photos-bundle-identity-mismatch")

    def test_installed_team_identity_refuses_prepared(self):
        self.installed_display = SIGNING_DISPLAY.replace("not set", "TEAM")
        self.failure("prepare", "signing-team-present")

    def test_foreign_container_refuses_prepared(self):
        self.container = self.container.replace(self.record["udid"], "12345678-1234-4234-8234-123456789012")
        self.failure("prepare", "photos-container-outside-owned-device")

    def test_install_failure_never_produces_prepared(self):
        self.install_code = 1
        self.failure("prepare", "photos-install-exit-nonzero")
        self.assertFalse((runner.ARTIFACTS / "ios-photos-prepared.json").exists())

    def test_read_write_requires_closed_add_only_proof(self):
        self.prepared()
        self.failure("read-write", "evidence-path-unavailable")
        self.assertFalse(self.commands("privacy"))

    def test_changed_prepared_context_or_host_type_refuses_before_permission(self):
        self.prepared()
        path = runner.ARTIFACTS / "ios-photos-prepared.json"
        saved = json.loads(path.read_text())
        for mutation in ({**saved, "runAttempt": "999"},
                         {**saved, "builtHost": {**saved["builtHost"], "strictVerificationPassed": 1}},
                         {**saved, "unexpected": True}):
            path.write_text(json.dumps(mutation))
            with self.subTest(mutation=mutation.keys()):
                self.failure("add-only", "photos-prepared-")
                self.assertFalse(self.commands("privacy"))

    def test_changed_installed_host_prevents_permission(self):
        self.prepared()
        (self.installed / "Runner").write_bytes(b"changed after prepare")
        self.failure("add-only", "photos-prepared-host-changed")
        self.assertFalse(self.commands("privacy"))

    def test_privacy_nonzero_never_starts_test(self):
        self.prepared()
        self.privacy_code = 1
        self.failure("add-only", "photos-privacy-reset-photos-exit-nonzero")
        self.assertEqual(len([args for args in self.calls if args[0] == "xcodebuild"]), 1)
        self.assertFalse(self.commands("terminate"))

    def test_add_only_grant_failure_never_starts_test(self):
        self.prepared()
        self.privacy_code = 1
        self.privacy_failure_operation = ("grant", "photos-add")
        self.failure("add-only", "photos-privacy-grant-photos-add-exit-nonzero")
        self.assertEqual(len(self.commands("privacy")), 2)
        self.assertEqual(len([args for args in self.calls if args[0] == "xcodebuild"]), 1)

    def test_read_write_grant_failure_never_starts_full_suite(self):
        self.prepared()
        runner.run_phase("add-only")
        self.privacy_code = 1
        self.privacy_failure_operation = ("grant", "photos")
        self.failure("read-write", "photos-privacy-grant-photos-exit-nonzero")
        self.assertEqual(len([args for args in self.calls if args[0] == "xcodebuild"]), 2)

    def test_prepared_raw_changes_during_permission_are_rejected(self):
        self.prepared()
        path = runner.ARTIFACTS / "ios-photos-prepared.json"
        self.privacy_mutation = lambda: path.write_text(json.dumps(json.loads(path.read_text()), separators=(",", ":")))
        self.failure("add-only", "photos-prepared-proof-changed")
        self.assertEqual(len(self.commands("privacy")), 1)

    def test_install_close_failure_cannot_publish_prepared(self):
        real_close = runner.host.close_host
        def close(command, companion=None):
            real_close(command, companion)
            if command.stage == "photos-install":
                raise runner.Failure("photos-install-close-unconfirmed")
        with mock.patch.object(runner.host, "close_host", side_effect=close):
            self.failure("prepare", "photos-install-close-unconfirmed")
        self.assertFalse((runner.ARTIFACTS / "ios-photos-prepared.json").exists())
        self.assertFalse(self.commands("get_app_container"))

    def test_test_timeout_retains_failure_and_confirms_only_actual_stop(self):
        self.prepared()
        self.test_timeout = True
        self.failure("add-only", "photos-xcode-add-only-timeout")
        self.assertEqual(len(self.commands("terminate")), 1)
        header = json.loads((runner.ARTIFACTS / "ios-photos-add-only-xcode.log").read_text().splitlines()[0])
        self.assertIs(header["hostAndReaderClosed"], True)
        self.assertEqual(header["failure"], "photos-xcode-add-only-timeout")

    def test_ownership_changes_at_permission_guard_no_permission_sent(self):
        self.prepared()
        self.marker.write_text(json.dumps(dict(self.record, runAttempt="999")))
        self.failure("add-only", "ownership-invalid")
        self.assertFalse(self.commands("privacy"))

    def test_nonzero_test_retains_readable_summary_but_never_success(self):
        self.prepared()
        self.test_code = 65
        self.summary_changes = {"passedTests": 0, "failedTests": 1}
        self.failure("add-only", "photos-xcode-add-only-exit-nonzero")
        summary = json.loads((runner.ARTIFACTS / "ios-photos-add-only-summary.json").read_text())
        self.assertEqual(summary["failedTests"], 1)
        self.assertEqual(len(self.commands("terminate")), 1)
        self.assertTrue((runner.ARTIFACTS / "ios-photos-add-only-identity.json").is_file())

    def test_wrong_count_failure_or_skip_never_success(self):
        self.prepared()
        self.summary_changes = {"passedTests": 0, "skippedTests": 1}
        self.failure("add-only", "photos-xctest-not-all-passed")
        self.assertTrue((runner.ARTIFACTS / "ios-photos-add-only-summary.json").is_file())

    def test_read_write_requires_exact_27(self):
        self.prepared()
        runner.run_phase("add-only")
        self.summary_changes = {"totalTestCount": 26, "passedTests": 26}
        self.failure("read-write", "photos-xctest-not-all-passed")

    def test_unreadable_summary_never_success(self):
        self.prepared()
        self.summary_code = 1
        self.failure("add-only", "photos-xctest-summary-exit-nonzero")
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_changed_test_host_refuses_success_after_result(self):
        self.prepared()
        self.test_mutation = lambda: (self.installed / "Runner").write_bytes(b"changed during test")
        self.failure("add-only", "photos-prepared-host-changed")
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_stop_unknown_response_never_success(self):
        self.prepared()
        self.stop_output = b"found nothing to terminate\nAdditional unknown error\n"
        self.failure("add-only", "owned-app-stop-unconfirmed")

    def test_unknown_exception_never_stringified_or_success(self):
        class Unsafe(Exception):
            def __str__(self):
                raise AssertionError("Must not stringify unknown exception.")
        with mock.patch.object(runner.host, "read_owned_record", side_effect=Unsafe()):
            self.failure("prepare", "photos-controller-unexpected")

    def test_close_unconfirmed_never_collects_summary_or_stops_app(self):
        self.prepared()
        phase = "add-only"
        real = runner.execute_xcode
        def held(args, selected):
            if selected == phase:
                raise runner.Failure("photos-xcode-add-only-close-unconfirmed")
            return real(args, selected)
        with mock.patch.object(runner, "execute_xcode", side_effect=held):
            self.failure(phase, "photos-xcode-add-only-close-unconfirmed")
        self.assertFalse(self.commands("terminate"))
        self.assertFalse(any(args[:3] == ["xcrun", "xcresulttool", "get"] for args in self.calls))


class ParsingTests(unittest.TestCase):
    def test_exact_container_grammar_rejects_foreign_traversal_data_and_extra(self):
        identifier = "7a6b4f55-32e9-4c4e-96ef-2ac114643671"
        raw = (f"/Users/runner/Library/Developer/CoreSimulator/Devices/{identifier}"
               "/data/Containers/Bundle/Application/12345678-1234-4234-8234-123456789012/Runner.app")
        with mock.patch.object(runner.evidence, "ordinary_path"):
            self.assertEqual(runner.installed_path(raw + "\n", identifier).as_posix(), raw)
            for value in (raw.replace(identifier, "12345678-1234-4234-8234-123456789012"),
                          raw.replace("/Bundle/", "/Data/"), raw + "/extra", raw + "\nunknown\n",
                          " " + raw, raw.replace("/data/", "/../data/"), raw.replace("Runner.app", "Other.app")):
                with self.subTest(value=value), self.assertRaises(runner.Failure):
                    runner.installed_path(value, identifier)

    def test_command_never_accepts_arbitrary_phase_or_uuid(self):
        for phase, record in (("unknown", {"udid": "booted"}), ("prepare", {"udid": "booted"})):
            with self.subTest(phase=phase), self.assertRaises(runner.Failure):
                runner.arguments(phase, record)

    def test_actual_reader_must_end_before_xcode_exit_proof(self):
        process = Process()
        gate = threading.Event()
        process.stdout = Pipe(b"", gate)
        running = runner.host.Running
        commands = []
        def create(*args, **kwargs):
            command = running(*args, **kwargs)
            commands.append(command)
            return command
        with mock.patch.object(runner.host.subprocess, "Popen", return_value=process), \
                mock.patch.object(runner.host, "Running", side_effect=create), \
                mock.patch.object(runner, "TIMEOUT", 0.01), \
                mock.patch.object(runner.host, "CLOSE_TIMEOUT", 0.02), \
                mock.patch.object(runner.evidence, "fresh_file") as fresh, \
                mock.patch.object(runner.host, "emit") as emit:
            try:
                with self.assertRaisesRegex(runner.Failure, "photos-xcode-prepare-close-unconfirmed"):
                    runner.execute_xcode(["synthetic"], "prepare")
                self.assertFalse(emit.called)
                header = json.loads(fresh.call_args.args[1].decode().splitlines()[0])
                self.assertFalse(header["hostAndReaderClosed"])
            finally:
                gate.set()
                commands[0].reader.thread.join(timeout=1)
                runner.host.close_host(commands[0])


if __name__ == "__main__":
    unittest.main()
