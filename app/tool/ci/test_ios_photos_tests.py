"""Owned synthetic Photos controller checks; no real Apple/Photos operations."""

import contextlib
import hashlib
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
        self.shape_locations = {str(self.installed): self.container.rstrip("\n")}
        real_shape = runner.installed_container_shape
        def container_shape(raw, identifier):
            # Saved fixture locations use owned local IO paths. Validate their
            # corresponding native canonical grammar, without historical IO.
            real_shape(self.shape_locations.get(raw, raw) if type(raw) is str else raw, identifier)
            return Path(raw)
        self.stack.enter_context(mock.patch.object(runner, "installed_container_shape", side_effect=container_shape))
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

    def observation(self, phase="add-only"):
        return json.loads((runner.ARTIFACTS / f"ios-photos-{phase}-host-observation.json").read_text())

    def relocate(self):
        previous = self.installed
        self.installed = self.root / "synthetic-relocated/Runner.app"
        self.installed.parent.mkdir()
        previous.rename(self.installed)
        self.container = self.container.replace("12345678-1234-4234-8234-123456789012", "23456789-1234-4234-8234-123456789012")
        self.shape_locations[str(self.installed)] = self.container.rstrip("\n")
        self.assertFalse(previous.exists())

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
        for phase, result in (("add-only", add), ("read-write", read)):
            raw = (runner.ARTIFACTS / f"ios-photos-{phase}-host-observation.json").read_bytes()
            self.assertEqual(result["hostObservationSha256"], hashlib.sha256(raw).hexdigest())
            observation = self.observation(phase)
            self.assertIs(observation["allFrozenFieldsVerified"], True)
            self.assertEqual(set(observation["readStates"].values()), {"observed"})

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
        observation = self.observation()
        self.assertIs(observation["installedMatchesPrepared"], False)
        self.assertIs(observation["builtMatchesInstalled"], False)
        self.assertIs(observation["generatedEntitlementsMatchPrepared"], True)
        self.assertEqual(set(observation["readStates"].values()), {"observed"})

    def test_same_owned_container_relocation_keeps_original_prepared_bytes(self):
        self.prepared()
        path = runner.ARTIFACTS / "ios-photos-prepared.json"
        initial = path.read_bytes()
        initial_location = json.loads(initial)["installedContainer"]
        self.test_mutation = self.relocate
        result = runner.run_phase("add-only")
        self.assertEqual(path.read_bytes(), initial)
        self.assertEqual(result["preparedSha256"], hashlib.sha256(initial).hexdigest())
        observation = self.observation()
        self.assertIs(observation["containerMatchesInitial"], False)
        self.assertIs(observation["allFrozenFieldsVerified"], True)
        self.assertEqual(observation["initialInstalledContainer"], initial_location)
        self.assertEqual(observation["currentInstalledContainer"], str(self.installed))
        identity = json.loads((runner.ARTIFACTS / "ios-photos-add-only-identity.json").read_text())
        self.assertEqual(identity["initialInstalledContainer"], initial_location)
        self.assertEqual(identity["currentInstalledContainer"], str(self.installed))
        self.test_mutation = None
        self.assertEqual(runner.run_phase("read-write")["xctestPassed"], 27)

    def test_relocation_before_permission_is_accepted(self):
        self.prepared()
        self.relocate()
        runner.run_phase("add-only")
        self.assertEqual(len(self.commands("privacy")), 2)
        self.assertIs(self.observation()["containerMatchesInitial"], False)

    def test_corrupt_historical_container_is_refused_without_permission(self):
        self.prepared()
        path = runner.ARTIFACTS / "ios-photos-prepared.json"
        original = json.loads(path.read_text())
        native = self.container.rstrip("\n")
        for invalid in (None, 1, {}, native + "\n", native.replace("/Bundle/", "/Data/"),
                        native.replace(self.record["udid"], "12345678-1234-4234-8234-123456789012"),
                        native.replace("/data/", "/../data/"), native + "/extra"):
            with self.subTest(invalid=invalid):
                path.write_text(json.dumps(dict(original, installedContainer=invalid)))
                self.failure("add-only", "photos-container-")
                self.assertFalse(self.commands("privacy"))

    def test_relocated_changed_info_is_observed_but_refused(self):
        self.prepared()
        def mutate():
            self.relocate()
            info = dict(self.info, SyntheticDifferentValue=True)
            (self.installed / "Info.plist").write_bytes(plistlib.dumps(info))
        self.test_mutation = mutate
        self.failure("add-only", "photos-prepared-host-changed")
        observation = self.observation()
        self.assertEqual(observation["readStates"]["installedHost"], "observed")
        self.assertIs(observation["containerMatchesInitial"], False)
        self.assertIs(observation["installedMatchesPrepared"], False)
        self.assertIs(observation["generatedEntitlementsMatchPrepared"], True)

    def test_relocated_executable_change_is_observed_and_refused(self):
        self.prepared()
        def mutate():
            self.relocate()
            (self.installed / "Runner").write_bytes(b"changed embedded signature or executable bytes")
        self.test_mutation = mutate
        self.failure("add-only", "photos-prepared-host-changed")
        observation = self.observation()
        self.assertIs(observation["containerMatchesInitial"], False)
        self.assertIs(observation["installedMatchesPrepared"], False)
        self.assertIs(observation["generatedEntitlementsMatchPrepared"], True)

    def test_relocated_strict_codesign_failure_is_refused_and_stopped(self):
        self.prepared()
        def mutate():
            self.relocate()
            self.signing_code = 1
        self.test_mutation = mutate
        self.failure("add-only", "photos-signing-verify-exit-nonzero")
        observation = self.observation()
        self.assertEqual(observation["readStates"]["builtHost"], "readFailed")
        self.assertEqual(observation["readStates"]["installedHost"], "readFailed")
        self.assertIs(observation["generatedEntitlementsMatchPrepared"], True)
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_relocated_version_change_is_read_failed_and_entitlements_still_observed(self):
        self.prepared()
        def mutate():
            self.relocate()
            (self.installed / "Info.plist").write_bytes(plistlib.dumps(dict(self.info, CFBundleVersion="99")))
        self.test_mutation = mutate
        self.failure("add-only", "photos-version-mismatch")
        observation = self.observation()
        self.assertEqual(observation["readStates"]["installedHost"], "readFailed")
        self.assertIsNone(observation["installedMatchesPrepared"])
        self.assertIsNone(observation["installedHost"])
        self.assertIs(observation["generatedEntitlementsMatchPrepared"], True)
        self.assertIs(observation["allFrozenFieldsVerified"], False)

    def test_relocated_signature_metadata_change_is_read_failed(self):
        self.prepared()
        def mutate():
            self.relocate()
            self.installed_display = SIGNING_DISPLAY.replace("adhoc", "sha256")
        self.test_mutation = mutate
        self.failure("add-only", "signing-not-adhoc")
        self.assertEqual(self.observation()["readStates"]["installedHost"], "readFailed")
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_relocated_entitlements_change_is_observed_and_refused(self):
        self.prepared()
        self.test_mutation = self.relocate
        real = runner.evidence.displayed_entitlements
        # Change only after Xcode starts; all pre-permission reads stay real.
        def changed(raw):
            actual = real(raw)
            if any(args[0] == "xcodebuild" and args[1] == "test-without-building" for args in self.calls):
                return runner.evidence.entitlement_evidence(plistlib.dumps(dict(SIGNING_ENTITLEMENTS, **{"get-task-allow": False})))
            return actual
        with mock.patch.object(runner.evidence, "displayed_entitlements", side_effect=changed):
            self.failure("add-only", "photos-prepared-host-changed")
        observation = self.observation()
        self.assertIs(observation["builtMatchesPrepared"], False)
        self.assertIs(observation["installedMatchesPrepared"], False)
        self.assertIs(observation["generatedEntitlementsMatchPrepared"], True)

    def test_relocated_generated_entitlements_existence_change_is_refused(self):
        self.prepared()
        def mutate():
            self.relocate()
            root = runner.DERIVED / "Build/Intermediates.noindex/Runner.build/Debug-iphonesimulator/Runner.build"
            (root / "Runner.app.xcent-simulated").unlink()
        self.test_mutation = mutate
        self.failure("add-only", "photos-prepared-host-changed")
        observation = self.observation()
        self.assertEqual(observation["readStates"]["generatedEntitlements"], "observed")
        self.assertIs(observation["generatedEntitlementsMatchPrepared"], False)
        self.assertIsNone(observation["generatedEntitlements"]["Runner.app.xcent-simulated"])

    def test_relocated_generated_entitlements_bytes_change_is_refused(self):
        self.prepared()
        def mutate():
            self.relocate()
            root = runner.DERIVED / "Build/Intermediates.noindex/Runner.build/Debug-iphonesimulator/Runner.build"
            (root / "Runner.app.xcent").write_bytes(plistlib.dumps(dict(SIGNING_ENTITLEMENTS, **{"get-task-allow": False})))
        self.test_mutation = mutate
        self.failure("add-only", "photos-prepared-host-changed")
        self.assertIs(self.observation()["generatedEntitlementsMatchPrepared"], False)

    def test_prepared_raw_changes_during_test_are_observed_and_refused(self):
        self.prepared()
        path = runner.ARTIFACTS / "ios-photos-prepared.json"
        self.test_mutation = lambda: path.write_text(json.dumps(json.loads(path.read_text()), separators=(",", ":")))
        self.failure("add-only", "photos-prepared-proof-changed")
        observation = self.observation()
        self.assertIs(observation["preparedSha256MatchesExpected"], False)
        self.assertIs(observation["builtMatchesPrepared"], True)
        self.assertIs(observation["allFrozenFieldsVerified"], False)
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_prepared_change_during_actual_fingerprint_read_is_detected_by_final_read(self):
        self.prepared()
        path = runner.ARTIFACTS / "ios-photos-prepared.json"
        initial = path.read_bytes()
        real = runner.fingerprint
        def read(bundle):
            value = real(bundle)
            if bundle == runner.built_bundle() and any(args[0] == "xcodebuild" and args[1] == "test-without-building" for args in self.calls):
                path.write_bytes(initial + b"\n")
            return value
        with mock.patch.object(runner, "fingerprint", side_effect=read):
            self.failure("add-only", "photos-prepared-proof-changed")
        observation = self.observation()
        self.assertIs(observation["preparedSha256MatchesExpected"], True)
        self.assertIs(observation["preparedFinalMatchesInitial"], False)
        self.assertIs(observation["preparedFinalMatchesExpected"], False)
        self.assertEqual(observation["preparedFinalReadState"], "observed")
        self.assertIs(observation["generatedEntitlementsMatchPrepared"], True)
        self.assertIs(observation["allFrozenFieldsVerified"], False)
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_prepared_final_read_failure_cannot_verify_frozen_fields(self):
        self.prepared()
        real = runner.generated_entitlements
        def read():
            value = real()
            if any(args[0] == "xcodebuild" and args[1] == "test-without-building" for args in self.calls):
                (runner.ARTIFACTS / "ios-photos-prepared.json").unlink()
            return value
        with mock.patch.object(runner, "generated_entitlements", side_effect=read):
            self.failure("add-only", "evidence-path-unavailable")
        observation = self.observation()
        self.assertEqual(observation["readStates"]["prepared"], "observed")
        self.assertEqual(observation["preparedFinalReadState"], "readFailed")
        self.assertIsNone(observation["preparedFinalMatchesInitial"])
        self.assertIsNone(observation["preparedFinalSha256"])
        self.assertIs(observation["allFrozenFieldsVerified"], False)
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_prepared_read_failure_keeps_unknown_comparisons_and_stops(self):
        self.prepared()
        self.test_mutation = lambda: (runner.ARTIFACTS / "ios-photos-prepared.json").unlink()
        self.failure("add-only", "evidence-path-unavailable")
        observation = self.observation()
        self.assertEqual(observation["readStates"]["prepared"], "readFailed")
        self.assertIsNone(observation["preparedSha256"])
        self.assertIsNone(observation["preparedSha256MatchesExpected"])
        self.assertIsNone(observation["builtMatchesPrepared"])
        self.assertIsNone(observation["generatedEntitlementsMatchPrepared"])
        self.assertIs(observation["builtMatchesInstalled"], True)
        self.assertEqual(len(self.commands("terminate")), 1)

    def assert_versions_failure_observation(self, initial):
        observation = self.observation()
        for key in runner.CONTEXT_FIELDS:
            self.assertEqual(observation[key], initial[key])
        for component in ("prepared", "builtHost", "installedHost"):
            self.assertEqual(observation["readStates"][component], "readFailed")
        self.assertEqual(observation["readStates"]["generatedEntitlements"], "observed")
        self.assertEqual(observation["preparedFinalReadState"], "observed")
        self.assertIsNone(observation["builtHost"])
        self.assertIsNone(observation["installedHost"])
        self.assertIsNone(observation["generatedEntitlementsMatchPrepared"])
        self.assertIs(observation["allFrozenFieldsVerified"], False)
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_versions_missing_after_test_keeps_bound_partial_observation_and_stops(self):
        self.prepared()
        initial = json.loads((runner.ARTIFACTS / "ios-photos-prepared.json").read_text())
        self.test_mutation = lambda: Path("versions.json").unlink()
        self.failure("add-only", "evidence-path-unavailable")
        self.assert_versions_failure_observation(initial)

    def test_versions_linked_after_test_keeps_bound_partial_observation_and_stops(self):
        self.prepared()
        initial = json.loads((runner.ARTIFACTS / "ios-photos-prepared.json").read_text())
        changed = [False]
        self.test_mutation = lambda: changed.__setitem__(0, True)
        real = runner.evidence.ordinary_path
        def ordinary(path, *arguments, **options):
            if changed[0] and path.name == "versions.json":
                raise runner.Failure("evidence-path-linked")
            return real(path, *arguments, **options)
        with mock.patch.object(runner.evidence, "ordinary_path", side_effect=ordinary):
            self.failure("add-only", "evidence-path-linked")
        self.assert_versions_failure_observation(initial)

    def test_versions_closed_read_failure_after_test_keeps_bound_partial_observation_and_stops(self):
        self.prepared()
        initial = json.loads((runner.ARTIFACTS / "ios-photos-prepared.json").read_text())
        changed = [False]
        self.test_mutation = lambda: changed.__setitem__(0, True)
        real = runner.evidence.read_closed_file
        def read(path, *arguments, **options):
            if changed[0] and path.name == "versions.json":
                raise runner.Failure("synthetic-versions-closed-read-failed")
            return real(path, *arguments, **options)
        with mock.patch.object(runner.evidence, "read_closed_file", side_effect=read):
            self.failure("add-only", "synthetic-versions-closed-read-failed")
        self.assert_versions_failure_observation(initial)

    def test_built_read_failure_does_not_short_circuit_other_components(self):
        self.prepared()
        self.test_mutation = lambda: (runner.built_bundle() / "Runner").unlink()
        self.failure("add-only", "evidence-path-unavailable")
        observation = self.observation()
        self.assertEqual(observation["readStates"]["builtHost"], "readFailed")
        self.assertEqual(observation["readStates"]["installedHost"], "observed")
        self.assertIs(observation["generatedEntitlementsMatchPrepared"], True)

    def test_foreign_current_container_post_test_is_refused_and_stop_still_runs(self):
        self.prepared()
        def mutate():
            self.container = self.container.replace(self.record["udid"], "12345678-1234-4234-8234-123456789012")
        self.test_mutation = mutate
        self.failure("add-only", "photos-container-outside-owned-device")
        observation = self.observation()
        self.assertEqual(observation["readStates"]["installedHost"], "readFailed")
        self.assertIsNone(observation["currentInstalledContainer"])
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_observation_write_failure_preserves_main_failure_and_stops(self):
        self.prepared()
        self.test_code = 65
        real = runner.evidence.fresh_json
        def write(path, value):
            if path.name.endswith("host-observation.json"):
                raise runner.Failure("synthetic-observation-write-failed")
            return real(path, value)
        with mock.patch.object(runner.evidence, "fresh_json", side_effect=write):
            self.failure("add-only", "photos-xcode-add-only-exit-nonzero")
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_unknown_xcode_constructor_failure_does_not_claim_closed_or_observe(self):
        self.prepared()
        class Unsafe(Exception):
            def __str__(self):
                raise AssertionError("Must not stringify unknown constructor failure.")
        real = runner.host.Running
        def start(args, *arguments, **options):
            if args[0] == "xcodebuild":
                raise Unsafe()
            return real(args, *arguments, **options)
        before = len(self.commands("get_app_container"))
        with mock.patch.object(runner.host, "Running", side_effect=start):
            self.failure("add-only", "photos-xcode-add-only-unexpected")
        # Initial and three pre-test checks query, but there is no post-test observation.
        self.assertEqual(len(self.commands("get_app_container")), before + 4)
        self.assertFalse(self.commands("terminate"))
        self.assertFalse((runner.ARTIFACTS / "ios-photos-add-only-host-observation.json").exists())

    def test_xcode_return_without_closed_confirmation_never_queries_post_test(self):
        self.prepared()
        before = len(self.commands("get_app_container"))
        with mock.patch.object(runner, "execute_xcode", return_value=False):
            self.failure("add-only", "photos-xcode-add-only-close-unconfirmed")
        self.assertEqual(len(self.commands("get_app_container")), before + 4)
        self.assertFalse(self.commands("terminate"))
        self.assertFalse((runner.ARTIFACTS / "ios-photos-add-only-host-observation.json").exists())

    def test_xcode_close_wait_exception_does_not_publish_or_query_post_test(self):
        self.prepared()
        class Unsafe(Exception):
            def __str__(self):
                raise AssertionError("Do not stringify unconfirmed close exception.")
        real = runner.host.Running
        def start(args, *arguments, **options):
            command = real(args, *arguments, **options)
            if args[0] == "xcodebuild":
                def wait(*unused, **kwargs):
                    raise Unsafe()
                command.process.wait = wait
            return command
        before = len(self.commands("get_app_container"))
        with mock.patch.object(runner.host, "Running", side_effect=start):
            self.failure("add-only", "photos-xcode-add-only-close-unconfirmed")
        self.assertEqual(len(self.commands("get_app_container")), before + 4)
        self.assertFalse(self.commands("terminate"))
        self.assertFalse((runner.ARTIFACTS / "ios-photos-add-only-host-observation.json").exists())
        header = json.loads((runner.ARTIFACTS / "ios-photos-add-only-xcode.log").read_text().splitlines()[0])
        self.assertIs(header["hostAndReaderClosed"], False)

    def test_closed_xcode_unknown_log_failure_preserves_main_failure_and_stops(self):
        self.prepared()
        self.test_code = 65
        self.stop_output = b"unknown stop response\n"
        class Unsafe(Exception):
            def __str__(self):
                raise AssertionError("Must not stringify unknown log failure.")
        real = runner.evidence.fresh_file
        def write(path, *arguments, **options):
            if path.name == "ios-photos-add-only-xcode.log":
                raise Unsafe()
            return real(path, *arguments, **options)
        with mock.patch.object(runner.evidence, "fresh_file", side_effect=write):
            self.failure("add-only", "photos-xcode-add-only-exit-nonzero")
        self.assertTrue(self.observation()["allFrozenFieldsVerified"])
        self.assertEqual(len(self.commands("terminate")), 1)

    def log_generation_failure(self, kind, test_code=0):
        self.prepared()
        self.test_code = test_code
        class Unsafe(Exception):
            def __str__(self):
                raise AssertionError("Must not stringify unknown log generation failure.")
        class EncodedFailure(str):
            def __add__(self, other):
                return EncodedFailure(super().__add__(other))
            def encode(self, *arguments, **options):
                raise Unsafe()
        dumps = runner.json.dumps
        redact = runner.host.redact
        def serialize(value, *arguments, **options):
            if type(value) is dict and value.get("phase") == "add-only" and "exitCode" in value:
                if kind == "header":
                    raise Unsafe()
                if kind == "encode":
                    return EncodedFailure(dumps(value, *arguments, **options))
            return dumps(value, *arguments, **options)
        def hide(value):
            if kind == "redact" and value == "Synthetic test":
                raise Unsafe()
            return redact(value)
        with mock.patch.object(runner.json, "dumps", side_effect=serialize), \
                mock.patch.object(runner.host, "redact", side_effect=hide):
            self.failure("add-only", "photos-xcode-add-only-exit-nonzero" if test_code else "photos-xcode-add-only-log-unexpected")
        self.assertTrue(self.observation()["allFrozenFieldsVerified"])
        self.assertEqual(len(self.commands("terminate")), 1)
        self.assertTrue(all(process.stdout.closed and process.waited for process in self.processes))

    def test_closed_xcode_header_generation_failure_retains_actual_closed_and_stops(self):
        self.log_generation_failure("header")

    def test_closed_xcode_redact_generation_failure_retains_actual_closed_and_stops(self):
        self.log_generation_failure("redact")

    def test_closed_xcode_encode_generation_failure_retains_actual_closed_and_stops(self):
        self.log_generation_failure("encode")

    def test_nonzero_xcode_and_header_generation_failure_keep_nonzero(self):
        self.log_generation_failure("header", 65)

    def test_nonzero_xcode_and_redact_generation_failure_keep_nonzero(self):
        self.log_generation_failure("redact", 65)

    def test_nonzero_xcode_and_encode_generation_failure_keep_nonzero(self):
        self.log_generation_failure("encode", 65)

    def test_persistent_post_stdout_write_failure_still_executes_owned_stop(self):
        self.prepared()
        original = runner.sys.stdout
        class BrokenOutput:
            def write(self, value):
                raise BrokenPipeError()
            def flush(self):
                raise BrokenPipeError()
        self.test_mutation = lambda: setattr(runner.sys, "stdout", BrokenOutput())
        try:
            self.failure("add-only", "photos-xcode-add-only-log-unexpected")
        finally:
            runner.sys.stdout = original
        self.assertEqual(len(self.commands("terminate")), 1)
        self.assertEqual(self.commands("terminate")[0], ["xcrun", "simctl", "terminate", self.record["udid"], runner.host.BUNDLE_ID])
        self.assertIs(self.observation()["allFrozenFieldsVerified"], False)
        self.assertTrue(all(process.stdout.closed and process.waited for process in self.processes))

    def test_persistent_post_stdout_flush_failure_still_executes_owned_stop(self):
        self.prepared()
        original = runner.sys.stdout
        class BrokenOutput:
            def write(self, value):
                return len(value)
            def flush(self):
                raise BrokenPipeError()
        self.test_mutation = lambda: setattr(runner.sys, "stdout", BrokenOutput())
        try:
            self.failure("add-only", "photos-xcode-add-only-log-unexpected")
        finally:
            runner.sys.stdout = original
        self.assertEqual(len(self.commands("terminate")), 1)
        self.assertIs(self.observation()["allFrozenFieldsVerified"], False)
        self.assertTrue(all(process.stdout.closed and process.waited for process in self.processes))

    def test_persistent_post_emit_failure_still_executes_owned_guard_and_stop(self):
        self.prepared()
        changed = [False]
        self.test_mutation = lambda: changed.__setitem__(0, True)
        class Unsafe(Exception):
            def __str__(self):
                raise AssertionError("Must not stringify persistent emit failure.")
        real = runner.host.emit
        def emit(event, value):
            if changed[0]:
                raise Unsafe()
            return real(event, value)
        with mock.patch.object(runner.host, "emit", side_effect=emit):
            self.failure("add-only", "photos-xcode-add-only-log-unexpected")
        self.assertTrue(self.observation()["allFrozenFieldsVerified"])
        self.assertEqual(len(self.commands("terminate")), 1)
        self.assertTrue(all(process.stdout.closed and process.waited for process in self.processes))

    def test_persistent_post_emit_failure_cannot_bypass_changed_owned_identity(self):
        self.prepared()
        changed = [False]
        def mutate():
            changed[0] = True
            self.marker.write_text(json.dumps(dict(self.record, runAttempt="999")))
        self.test_mutation = mutate
        real = runner.host.emit
        def emit(event, value):
            if changed[0]:
                raise BrokenPipeError()
            return real(event, value)
        with mock.patch.object(runner.host, "emit", side_effect=emit):
            self.failure("add-only", "photos-xcode-add-only-log-unexpected")
        self.assertFalse(self.commands("terminate"))
        self.assertIs(self.observation()["allFrozenFieldsVerified"], False)

    def test_guard_failure_after_test_still_keeps_available_component_observations(self):
        self.prepared()
        self.test_mutation = lambda: self.marker.write_text(json.dumps(dict(self.record, runAttempt="999")))
        self.failure("add-only", "ownership-invalid")
        observation = self.observation()
        self.assertEqual(observation["readStates"]["installedHost"], "readFailed")
        self.assertIsNone(observation["installedMatchesPrepared"])
        self.assertIs(observation["builtMatchesPrepared"], True)
        self.assertIs(observation["generatedEntitlementsMatchPrepared"], True)
        self.assertFalse(self.commands("terminate"))

    def test_stop_failure_does_not_replace_preexisting_identity_failure(self):
        self.prepared()
        self.test_mutation = lambda: (self.installed / "Runner").write_bytes(b"changed host")
        self.stop_output = b"unknown stop response\n"
        self.failure("add-only", "photos-prepared-host-changed")
        self.assertIs(self.observation()["allFrozenFieldsVerified"], False)
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_observation_write_failure_alone_refuses_success_and_stops(self):
        self.prepared()
        real = runner.evidence.fresh_json
        def write(path, value):
            if path.name.endswith("host-observation.json"):
                raise runner.Failure("synthetic-observation-write-failed")
            return real(path, value)
        with mock.patch.object(runner.evidence, "fresh_json", side_effect=write):
            self.failure("add-only", "synthetic-observation-write-failed")
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_observation_readback_failure_keeps_closed_observation_but_refuses_success(self):
        self.prepared()
        real = runner.evidence.read_closed_file
        def read(path, *arguments, **options):
            if path.name.endswith("host-observation.json"):
                raise runner.Failure("synthetic-observation-readback-failed")
            return real(path, *arguments, **options)
        with mock.patch.object(runner.evidence, "read_closed_file", side_effect=read):
            self.failure("add-only", "synthetic-observation-readback-failed")
        self.assertTrue(self.observation()["allFrozenFieldsVerified"])
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_observation_changed_after_write_is_not_bound_to_success(self):
        self.prepared()
        real = runner.evidence.fresh_json
        def write(path, value):
            real(path, value)
            if path.name.endswith("host-observation.json"):
                path.write_text(json.dumps(dict(value, allFrozenFieldsVerified=False)))
        with mock.patch.object(runner.evidence, "fresh_json", side_effect=write):
            self.failure("add-only", "photos-host-observation-changed")
        self.assertFalse(self.observation()["allFrozenFieldsVerified"])
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_unknown_observation_write_exception_is_not_stringified_and_stops(self):
        self.prepared()
        class Unsafe(Exception):
            def __str__(self):
                raise AssertionError("Do not stringify unknown observation write exception.")
        real = runner.evidence.fresh_json
        def write(path, value):
            if path.name.endswith("host-observation.json"):
                raise Unsafe()
            return real(path, value)
        with mock.patch.object(runner.evidence, "fresh_json", side_effect=write):
            self.failure("add-only", "photos-identity-unexpected")
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_identity_diagnostic_emit_failure_keeps_main_failure_and_stops(self):
        self.prepared()
        self.test_mutation = lambda: (self.installed / "Runner").write_bytes(b"changed host")
        class Unsafe(Exception):
            def __str__(self):
                raise AssertionError("Do not stringify diagnostic emit failure.")
        real = runner.host.emit
        def emit(event, message):
            if event == "photos-identity-failure":
                raise Unsafe()
            return real(event, message)
        with mock.patch.object(runner.host, "emit", side_effect=emit):
            self.failure("add-only", "photos-prepared-host-changed")
        self.assertIs(self.observation()["allFrozenFieldsVerified"], False)
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_observation_write_and_identity_failure_keep_identity_failure(self):
        self.prepared()
        self.test_mutation = lambda: (self.installed / "Runner").write_bytes(b"changed host")
        real = runner.evidence.fresh_json
        def write(path, value):
            if path.name.endswith("host-observation.json"):
                raise runner.Failure("synthetic-observation-write-failed")
            return real(path, value)
        with mock.patch.object(runner.evidence, "fresh_json", side_effect=write):
            self.failure("add-only", "photos-prepared-host-changed")
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_unknown_read_exception_is_not_stringified_and_remaining_reads_complete(self):
        self.prepared()
        class Unsafe(Exception):
            def __str__(self):
                raise AssertionError("Do not stringify unknown read exception.")
        real = runner.fingerprint
        def read(bundle):
            if bundle == runner.built_bundle() and any(args[0] == "xcodebuild" and args[1] == "test-without-building" for args in self.calls):
                raise Unsafe()
            return real(bundle)
        with mock.patch.object(runner, "fingerprint", side_effect=read):
            self.failure("add-only", "photos-builtHost-read-unexpected")
        observation = self.observation()
        self.assertEqual(observation["readStates"]["builtHost"], "readFailed")
        self.assertEqual(observation["readStates"]["installedHost"], "observed")
        self.assertIs(observation["generatedEntitlementsMatchPrepared"], True)
        self.assertEqual(len(self.commands("terminate")), 1)

    def test_prior_observation_digest_change_refuses_read_write_before_permission(self):
        self.prepared()
        runner.run_phase("add-only")
        path = runner.ARTIFACTS / "ios-photos-add-only-host-observation.json"
        path.write_text(json.dumps(json.loads(path.read_text()), separators=(",", ":")))
        count = len(self.commands("privacy"))
        self.failure("read-write", "photos-add-only-proof-required")
        self.assertEqual(len(self.commands("privacy")), count)

    def test_prior_observation_semantics_reject_even_with_matching_digest(self):
        self.prepared()
        runner.run_phase("add-only")
        path = runner.ARTIFACTS / "ios-photos-add-only-host-observation.json"
        result_path = runner.ARTIFACTS / "ios-photos-add-only-result.json"
        original = json.loads(path.read_text())
        native = self.container.rstrip("\n")
        mutations = [{**original, "allFrozenFieldsVerified": 1}, {**original, "phase": "read-write"},
                     {**original, "builtMatchesPrepared": False}, {**original, "unexpected": True},
                     {**original, "runId": "999"},
                     {**original, "readStates": dict(original["readStates"], installedHost="unobserved")},
                     {**original, "currentInstalledContainer": native.replace(self.record["udid"], "12345678-1234-4234-8234-123456789012")}]
        for mutation in mutations:
            with self.subTest(fields=mutation):
                path.write_text(json.dumps(mutation))
                result = json.loads(result_path.read_text())
                result["hostObservationSha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
                result_path.write_text(json.dumps(result))
                self.failure("read-write", "photos-add-only-observation-required|photos-container-")
                self.assertEqual(len(self.commands("privacy")), 2)

    def test_existing_observation_is_never_overwritten_or_permission_sent(self):
        self.prepared()
        path = runner.ARTIFACTS / "ios-photos-add-only-host-observation.json"
        path.write_bytes(b"existing closed evidence")
        self.failure("add-only", "photos-artifact-not-fresh")
        self.assertEqual(path.read_bytes(), b"existing closed evidence")
        self.assertFalse(self.commands("privacy"))

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
        self.assertFalse((runner.ARTIFACTS / "ios-photos-add-only-host-observation.json").exists())


class ParsingTests(unittest.TestCase):
    def test_historical_container_shape_has_no_filesystem_access(self):
        identifier = "7a6b4f55-32e9-4c4e-96ef-2ac114643671"
        raw = (f"/Users/runner/Library/Developer/CoreSimulator/Devices/{identifier}"
               "/data/Containers/Bundle/Application/12345678-1234-4234-8234-123456789012/Runner.app")
        with mock.patch.object(runner.evidence, "ordinary_path", side_effect=AssertionError("Historical path is retired.")):
            self.assertEqual(runner.installed_container_shape(raw, identifier).as_posix(), raw)
        for invalid in (None, 1, {}, raw + "\n", raw.replace("/Users/runner/", "/Users/runner\t/"), raw.replace("/Users/", "/Users\\/")):
            with self.subTest(invalid=invalid), self.assertRaises(runner.Failure):
                runner.installed_container_shape(invalid, identifier)

    def test_current_container_requires_actual_ordinary_path(self):
        identifier = "7a6b4f55-32e9-4c4e-96ef-2ac114643671"
        raw = (f"/Users/runner/Library/Developer/CoreSimulator/Devices/{identifier}"
               "/data/Containers/Bundle/Application/12345678-1234-4234-8234-123456789012/Runner.app")
        for failure in ("evidence-path-linked", "evidence-path-not-ordinary", "evidence-path-unavailable"):
            with self.subTest(failure=failure), mock.patch.object(runner.evidence, "ordinary_path", side_effect=runner.Failure(failure)):
                with self.assertRaisesRegex(runner.Failure, failure):
                    runner.installed_path(raw + "\n", identifier)

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
