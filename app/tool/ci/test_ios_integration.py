"""Bounded controller tests with synthetic pipes, never real Apple/Flutter IO."""

import contextlib
import io
import json
import os
from pathlib import Path
import plistlib
import tempfile
import threading
import unittest
from unittest import mock

import run_ios_integration as runner


URI = "http://127.0.0.1:54321/OnlySyntheticAuth=/"
NOT_RUNNING = (
    "An error was encountered processing the command (domain=NSPOSIXErrorDomain, code=3):\n"
    "Application termination failed.\n"
    "Underlying error (domain=NSPOSIXErrorDomain, code=3):\n"
    "    No such process\n"
)
FOUND_NOTHING = (
    "An error was encountered processing the command (domain=NSPOSIXErrorDomain, code=3):\n"
    "Simulator device failed to terminate io.imagehost.imagehost.\n"
    "found nothing to terminate\n"
    "Underlying error (domain=NSPOSIXErrorDomain, code=3):\n"
    '\tThe request to terminate "io.imagehost.imagehost" failed. found nothing to terminate\n'
    "\tfound nothing to terminate\n"
)


class Pipe:
    def __init__(self, contents, gate=None):
        self.contents = io.BytesIO(contents)
        self.gate = gate
        self.closed = False

    def readline(self, limit):
        result = self.contents.readline(limit)
        if not result and self.gate is not None:
            self.gate.wait(5)  # Test safety bound, not the controller's IO proof.
        return result

    def close(self):
        self.closed = True
        self.contents.close()


class Process:
    def __init__(self, output=b"", code=0, running=False):
        self.code = code
        self.running = running
        self.gate = threading.Event() if running else None
        self.stdout = Pipe(output, self.gate)
        self.terminated = False
        self.killed = False
        self.waited = False

    def poll(self):
        return None if self.running else self.code

    def wait(self, timeout=None):
        if self.running:
            raise AssertionError("Test process was waited before real mock exit.")
        self.waited = True
        return self.code

    def terminate(self):
        self.terminated = True
        self.finish()

    def kill(self):
        self.killed = True
        self.finish()

    def finish(self):
        self.running = False
        if self.gate:
            self.gate.set()


class Harness(unittest.TestCase):
    def setUp(self):
        # Keep synthetic files inside the writable checkout on restricted hosts;
        # cleanup is only this test-created unique directory after mocked IO ends.
        self.checkout = Path(__file__).resolve().parents[3]
        self.temp = tempfile.TemporaryDirectory(prefix="imagehub-ios-control-",
                                                dir=self.checkout)
        self.root = Path(self.temp.name).resolve(strict=True)
        self.assertEqual(self.root.parent, self.checkout)
        self.addCleanup(self.cleanup_owned_workspace)
        self.previous = Path.cwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, self.previous)
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(mock.patch.object(runner.sys, "platform", "darwin"))
        self.stack.enter_context(mock.patch.object(runner, "__file__", str(self.root / "tool/ci/run_ios_integration.py")))
        self.stack.enter_context(mock.patch.object(runner, "STARTUP_TIMEOUT", 0.1))
        self.stack.enter_context(mock.patch.object(runner, "COMMAND_TIMEOUT", 0.2))
        self.stack.enter_context(mock.patch.object(runner, "CLOSE_TIMEOUT", 0.1))
        self.record = {
            "formatVersion": 1, "runId": "123", "runAttempt": "2",
            "udid": "7a6b4f55-32e9-4c4e-96ef-2ac114643671",
            "name": "ImageHub-CI-123-2-1234abcd",
            "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-26-2",
            "deviceType": "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
        }
        self.marker = self.root / runner.boot.MARKER_NAME
        self.marker.write_text(json.dumps(self.record), encoding="utf-8")
        self.stack.enter_context(mock.patch.dict(os.environ, {
            "CI": "true", "RUNNER_TEMP": str(self.root),
            "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "2",
            "IMAGEHOST_IOS_SIMULATOR": self.record["udid"],
        }))
        for target, driver in runner.SUITES.values():
            for relative in (target, driver):
                path = Path(relative)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("// Synthetic fixed-path control input.\n", encoding="utf-8")
        self.versions = {"platforms": {"ios": {"version": "0.1.0", "build": 1}},
                         "kernel": {"version": "0.1.0", "revision": 1}}
        Path("versions.json").write_text(json.dumps(self.versions), encoding="utf-8")
        runner.BUNDLE.mkdir(parents=True)
        self.plist = {"CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
                      "ImageHubKernelVersion": "0.1.0", "ImageHubKernelRevision": "1",
                      "CFBundleIdentifier": runner.BUNDLE_ID, "CFBundleExecutable": "Runner"}
        self.write_plist()
        (runner.BUNDLE / "Runner").write_bytes(b"closed synthetic executable")
        self.calls = []
        self.processes = []
        self.controllers = []
        self.console = None
        self.state = "Booted"
        self.device_name = self.record["name"]
        self.console_bytes = (f"{runner.BUNDLE_ID}: 20450\n"
                              f"flutter: The Dart VM service is listening on {URI}\n").encode()
        self.early_console = False
        self.console_at_driver_end = False
        self.console_end_code = 0
        self.driver_code = 0
        self.driver_timeout = False
        self.build_timeout = False
        self.change_marker_after_driver = False
        self.driver_bytes = f"Connected to {URI}\nSynthetic test completed\n".encode()
        self.terminate_code = 0
        self.terminate_bytes = b""
        self.launch_help = b"--console-pty\n--terminate-running-process\n"
        self.stack.enter_context(mock.patch.object(runner.subprocess, "Popen", side_effect=self.popen))
        real_running = runner.Running

        def tracked_running(*arguments, **options):
            command = real_running(*arguments, **options)
            self.controllers.append(command)
            return command

        self.stack.enter_context(mock.patch.object(runner, "Running", side_effect=tracked_running))
        self.output = io.StringIO()
        self.stack.enter_context(contextlib.redirect_stdout(self.output))

    def cleanup_owned_workspace(self):
        candidate = Path(self.temp.name)
        if candidate.is_symlink() or candidate.resolve(strict=True).parent != self.checkout:
            raise AssertionError("Refusing cleanup outside the verified test workspace.")
        self.temp.cleanup()

    def write_plist(self):
        with (runner.BUNDLE / "Info.plist").open("wb") as stream:
            plistlib.dump(self.plist, stream)

    def popen(self, arguments, **kwargs):
        self.assertFalse(kwargs["shell"])
        self.assertEqual(kwargs["stderr"], runner.subprocess.STDOUT)
        self.calls.append(arguments)
        if arguments[:4] == ["xcrun", "simctl", "list", "devices"]:
            contents = json.dumps({"devices": {self.record["runtime"]: [{
                "udid": self.record["udid"], "name": self.device_name,
                "state": self.state, "isAvailable": True,
                "deviceTypeIdentifier": self.record["deviceType"]}]}}).encode()
            process = Process(contents)
        elif arguments[:3] == ["xcrun", "simctl", "help"]:
            process = Process(self.launch_help)
        elif arguments[:3] == ["flutter", "build", "ios"]:
            process = Process(b"Synthetic build output\n", running=self.build_timeout)
        elif arguments[:3] == ["xcrun", "simctl", "install"]:
            process = Process()
        elif arguments[:3] == ["xcrun", "simctl", "launch"]:
            process = Process(self.console_bytes, running=not self.early_console)
            self.console = process
        elif arguments[:2] == ["flutter", "drive"]:
            if self.change_marker_after_driver:
                self.marker.write_text(json.dumps(dict(self.record, runAttempt="1")), encoding="utf-8")
            if self.console_at_driver_end:
                self.console.code = self.console_end_code
                self.console.finish()
            process = Process(self.driver_bytes, self.driver_code, running=self.driver_timeout)
        elif arguments[:3] == ["xcrun", "simctl", "terminate"]:
            self.console.finish()
            process = Process(self.terminate_bytes, self.terminate_code)
        else:
            raise AssertionError("Unexpected native command in synthetic control test.")
        self.processes.append(process)
        return process

    def run_failure(self, expected, suite="native"):
        with self.assertRaisesRegex(runner.Failure, expected):
            runner.run_suite(suite)
        self.assertNotIn("[result]", self.output.getvalue())

    def test_success_has_fixed_command_order_existing_app_and_closed_readers(self):
        runner.run_suite("native")
        actions = [args[2] if args[0] == "xcrun" else args[1]
                   for args in self.calls if args[:4] != ["xcrun", "simctl", "list", "devices"]]
        self.assertEqual(actions, ["help", "build", "install", "launch", "drive", "terminate"])
        all_actions = [args[2] if args[0] == "xcrun" else args[1] for args in self.calls]
        self.assertEqual(all_actions, ["list", "help", "list", "build", "list", "install",
                                       "list", "launch", "list", "drive", "list", "terminate"])
        drive = next(args for args in self.calls if args[:2] == ["flutter", "drive"])
        self.assertEqual(drive, ["flutter", "drive", "--use-existing-app", URI,
                                "--driver", runner.SUITES["native"][1], "-d",
                                self.record["udid"], "--no-keep-app-running"])
        self.assertNotIn("--target", drive)
        text = self.output.getvalue()
        for stage in ("buildclosed", "versionverified", "appinstall", "launchedPID=20450",
                      "VMobserved", "driverexit0", "ownedappstopped", "consoleended"):
            self.assertIn(stage, text)
        self.assertNotIn("OnlySyntheticAuth", text)
        self.assertIn("<loopback-vm-uri>", text)
        self.assertTrue(all(process.stdout.closed and process.waited for process in self.processes))
        self.assertFalse(any(process.killed for process in self.processes))
        for args in self.calls:
            self.assertNotIn("all", args)
            self.assertNotIn("booted", args)
            self.assertNotIn("uninstall", args)
            if args[:3] in (["xcrun", "simctl", "install"], ["xcrun", "simctl", "terminate"]):
                self.assertEqual(args[3], self.record["udid"])

    def test_backup_entire_large_fixture_reaches_external_output(self):
        fixture = "IMAGEHUB_BACKUP_SYNTHETIC:" + "a" * 35000
        self.driver_bytes += (fixture + "\n").encode()
        runner.run_suite("backup")
        self.assertIn(fixture, self.output.getvalue())
        drive = next(args for args in self.calls if args[:2] == ["flutter", "drive"])
        self.assertEqual(drive[drive.index("--driver") + 1], runner.SUITES["backup"][1])

    def test_wrong_platform_ci_and_arbitrary_suite_rejected_before_native_command(self):
        with mock.patch.object(runner.sys, "platform", "win32"):
            self.run_failure("requires-darwin-ci")
        with mock.patch.dict(os.environ, {"CI": "false"}):
            self.run_failure("requires-darwin-ci")
        self.run_failure("suite-invalid", "../guessed-driver.dart")
        self.assertEqual(self.calls, [])

    def test_wrong_working_directory_rejected(self):
        other = self.root / "other"
        other.mkdir()
        os.chdir(other)
        self.run_failure("requires-app-working-directory")
        self.assertEqual(self.calls, [])

    def test_missing_fixed_driver_does_not_guess(self):
        Path(runner.SUITES["native"][1]).unlink()
        self.run_failure("fixed-input-unavailable")
        self.assertEqual(self.calls, [])

    def test_foreign_attempt_and_selected_uuid_rejected_before_system_query(self):
        foreign = dict(self.record, runAttempt="1")
        self.marker.write_text(json.dumps(foreign), encoding="utf-8")
        self.run_failure("ownership-invalid")
        self.marker.write_text(json.dumps(self.record), encoding="utf-8")
        with mock.patch.dict(os.environ, {"IMAGEHOST_IOS_SIMULATOR": "unowned"}):
            self.run_failure("ownership-selected-uuid-mismatch")
        self.assertEqual(self.calls, [])

    def test_shutdown_or_changed_device_identity_blocks_build(self):
        self.state = "Shutdown"
        self.run_failure("ownership-device-not-booted")
        self.state = "Booted"
        self.device_name = "User iPhone"
        self.run_failure("ownership-device-invalid")
        self.assertTrue(all(args[:4] == ["xcrun", "simctl", "list", "devices"] for args in self.calls))

    def test_missing_launch_capabilities_block_build(self):
        self.launch_help = b"--console\n--terminate-running-process\n"
        self.run_failure("launch-required-flags-unavailable")
        self.assertFalse(any(args[0] == "flutter" for args in self.calls))

    def test_built_version_and_executable_mismatch_never_install(self):
        self.plist["CFBundleVersion"] = "2"
        self.write_plist()
        self.run_failure("build-version-invalid")
        self.plist["CFBundleVersion"] = "1"
        self.plist["CFBundleExecutable"] = "guessed"
        self.write_plist()
        self.run_failure("build-executable-invalid")
        self.assertFalse(any(args[:3] == ["xcrun", "simctl", "install"] for args in self.calls))

    def test_vm_before_pid_is_accepted_with_both_evidence(self):
        self.console_bytes = (f"The Dart VM service is listening on {URI}\n"
                              f"{runner.BUNDLE_ID}: 20450\n").encode()
        runner.run_suite("native")

    def test_vm_without_pid_and_pid_without_vm_hit_startup_deadline(self):
        for contents in (f"The Dart VM service is listening on {URI}\n",
                         f"{runner.BUNDLE_ID}: 20450\n", "another.app: 20450\n"):
            with self.subTest(contents=contents):
                self.console_bytes = contents.encode()
                self.run_failure("startup-timeout")
        self.assertFalse(any(args[:2] == ["flutter", "drive"] for args in self.calls))

    def test_incomplete_vm_line_cannot_grant_startup(self):
        self.console_bytes = f"{runner.BUNDLE_ID}: 20450\nThe Dart VM service is listening on {URI}".encode()
        self.run_failure("startup-timeout")

    def test_early_console_exit_is_not_startup_success(self):
        self.early_console = True
        self.run_failure("startup-console-ended")
        self.assertFalse(any(args[:2] == ["flutter", "drive"] for args in self.calls))

    def test_driver_nonzero_is_failure_and_still_closes_console(self):
        self.driver_code = 1
        self.run_failure("driver-exit-nonzero")
        self.assertIn("consoleended", self.output.getvalue())

    def test_driver_timeout_stops_only_host_child_and_owned_app(self):
        self.driver_timeout = True
        self.run_failure("driver-timeout")
        self.assertTrue(any(process.terminated for process in self.processes))
        self.assertIn("ownedappstopped", self.output.getvalue())
        self.assertIn("consoleended", self.output.getvalue())

    def test_build_timeout_does_not_install_or_launch(self):
        self.build_timeout = True
        self.run_failure("build-timeout")
        self.assertFalse(any(args[:3] in (["xcrun", "simctl", "install"],
                                         ["xcrun", "simctl", "launch"])
                             for args in self.calls))
        self.assertTrue(any(process.terminated for process in self.processes))

    def test_changed_final_owner_never_terminates_guessed_application(self):
        self.change_marker_after_driver = True
        try:
            self.run_failure("owned-app-stop-unconfirmed")
            self.assertFalse(any(args[:3] == ["xcrun", "simctl", "terminate"] for args in self.calls))
            self.assertEqual(json.loads(self.marker.read_text(encoding="utf-8"))["runAttempt"], "1")
            self.assertIn("console-close-unconfirmed", self.output.getvalue())
            self.assertFalse(self.console.terminated or self.console.killed)
        finally:
            # Retire only this test's in-memory synthetic pipe, not a real app.
            self.console.finish()
            command = next(item for item in self.controllers if item.stage == "console")
            runner.end_console(command)
            self.assertFalse(command.reader.thread.is_alive())

    def test_console_ends_first_and_driver_zero_still_requires_driver_exit(self):
        self.console_at_driver_end = True
        runner.run_suite("native")
        self.assertIn("driverexit0", self.output.getvalue())
        self.assertTrue(self.console.waited)

    def test_console_ends_first_and_driver_nonzero_still_fails(self):
        self.console_at_driver_end = True
        self.driver_code = 1
        self.run_failure("driver-exit-nonzero")
        self.assertNotIn("driverexit0", self.output.getvalue())

    def test_console_nonzero_ends_first_and_driver_zero_is_independent_evidence(self):
        self.console_at_driver_end = True
        self.console_end_code = 143
        runner.run_suite("native")
        self.assertIn("driverexit0", self.output.getvalue())
        self.assertIn("consoleExitCode=143", self.output.getvalue())

    def test_console_nonzero_ends_first_and_driver_timeout_still_fails(self):
        self.console_at_driver_end = True
        self.console_end_code = 143
        self.driver_timeout = True
        self.run_failure("driver-timeout")
        self.assertNotIn("driverexit0", self.output.getvalue())
        self.assertIn("consoleExitCode=143", self.output.getvalue())

    def test_known_not_running_is_accepted_after_driver_stop(self):
        self.console_at_driver_end = True
        self.terminate_code = 3
        self.terminate_bytes = NOT_RUNNING.encode()
        runner.run_suite("native")
        self.assertIn("ownedappstopped", self.output.getvalue())

    def test_unknown_termination_failure_is_not_success(self):
        self.terminate_code = 1
        self.terminate_bytes = b"Unknown service failed: No such process\n"
        self.run_failure("owned-app-stop-unconfirmed")
        self.assertNotIn("ownedappstopped", self.output.getvalue())
        self.assertIn("consoleended", self.output.getvalue())

    def test_default_stop_diagnostics_do_not_change_console_flow(self):
        self.terminate_bytes = f"Synthetic stop output {URI}\n".encode()
        runner.run_suite("native")
        text = self.output.getvalue()
        self.assertIn("ownedappstopped", text)
        self.assertNotIn("Synthetic stop output", text)
        self.assertNotIn("[owned-app-stop-phase]", text)
        self.assertNotIn("[owned-app-stop-exit]", text)

    def test_diagnostic_unknown_stop_publishes_redacted_output_and_real_exit(self):
        self.console = Process(running=True)
        self.terminate_code = 1
        self.terminate_bytes = f"Unknown service failed: No such process {URI}\n".encode()
        with self.assertRaisesRegex(runner.Failure, "owned-app-stop-exit-nonzero"):
            runner.terminate_owned_app(self.record, None, diagnostic=True)
        text = self.output.getvalue()
        self.assertIn("guard-started", text)
        self.assertIn("guard-confirmed", text)
        self.assertIn("terminate-started", text)
        self.assertIn("Unknown service failed: No such process <loopback-vm-uri>", text)
        self.assertIn("exitCode=1; hostAndReaderClosed=true", text)
        self.assertNotIn("SyntheticAuth", text)
        self.assertTrue(all(command.closed() for command in self.controllers))

    def test_diagnostic_exact_esrch_preserves_full_matching_input(self):
        self.console = Process(running=True)
        self.terminate_code = 3
        self.terminate_bytes = NOT_RUNNING.encode()
        output = runner.terminate_owned_app(self.record, None, diagnostic=True)
        self.assertTrue(runner.known_not_running(3, output))
        self.assertIn("Underlying error (domain=NSPOSIXErrorDomain, code=3):", self.output.getvalue())
        self.assertIn("exitCode=3; hostAndReaderClosed=true", self.output.getvalue())

    def test_diagnostic_failed_guard_never_sends_terminate(self):
        self.state = "Shutdown"
        with self.assertRaises(runner.Failure):
            runner.terminate_owned_app(self.record, None, diagnostic=True)
        self.assertFalse(any(call[:3] == ["xcrun", "simctl", "terminate"] for call in self.calls))
        text = self.output.getvalue()
        self.assertIn("guard-started", text)
        self.assertNotIn("guard-confirmed", text)
        self.assertNotIn("terminate-started", text)
        self.assertNotIn("[owned-app-stop-exit]", text)

    def test_driver_log_uri_auth_is_redacted_even_on_failure(self):
        self.driver_code = 1
        self.driver_bytes += f"http://localhost:12345/AnotherSyntheticAuth=/\n".encode()
        self.run_failure("driver-exit-nonzero")
        self.assertNotIn("SyntheticAuth", self.output.getvalue())
        self.assertIn("<loopback-vm-uri>", self.output.getvalue())

    def test_line_and_total_budget_violations_block_startup_and_drain(self):
        for contents in (b"a" * (runner.LINE_LIMIT + 1) + b"\n",
                         (b"a" * 100000 + b"\n") * (runner.OUTPUT_LIMIT // 100000 + 1)):
            with self.subTest(length=len(contents)), \
                    mock.patch.object(runner, "STARTUP_TIMEOUT", 2):
                self.console_bytes = contents
                self.run_failure("console-output-budget-exceeded")
                self.assertTrue(self.console.stdout.closed)


class ParsingTests(unittest.TestCase):
    def test_strict_loopback_auth_uri(self):
        valid = (URI, "http://localhost:1/a_/", "http://127.0.0.1:65535/auth-/")
        for uri in valid:
            with self.subTest(uri=uri):
                self.assertEqual(runner.startup_evidence("The Dart VM service is listening on " + uri), (None, uri))
        invalid = (
            "http://example.com:123/auth/", "http://127.0.0.1:0/auth/",
            "http://localhost:65536/auth/", "http://localhost:123/a/?q=secret",
            "http://localhost:123/a/#fragment", "http://user@localhost:123/auth/",
            "http://127.0.0.1.evil:123/auth/", "http://localhost:123/../",
            "http://localhost:123/a%2f/", "http://[::1]:123/a/",
            "https://localhost:123/auth/", "http://localhost:123/a/b/",
        )
        for uri in invalid:
            with self.subTest(uri=uri), self.assertRaises(runner.Failure):
                runner.startup_evidence("The Dart VM service is listening on " + uri)

    def test_pid_requires_exact_application_and_positive_number(self):
        for line in ("io.other.app: 123", runner.BUNDLE_ID + ": 0",
                     runner.BUNDLE_ID + ": -1", "prefix " + runner.BUNDLE_ID + ": 123",
                     runner.BUNDLE_ID + ": 123 extra"):
            self.assertEqual(runner.startup_evidence(line), (None, None))

    def test_not_running_response_is_exact(self):
        self.assertTrue(runner.known_not_running(3, NOT_RUNNING))
        self.assertTrue(runner.known_not_running(1, NOT_RUNNING))  # Preserve old behavior.
        self.assertFalse(runner.known_not_running(0, NOT_RUNNING))
        self.assertFalse(runner.known_not_running(3, "No such process"))
        self.assertFalse(runner.known_not_running(3, NOT_RUNNING + "Other failure"))

    def test_observed_six_line_esrch_requires_exact_exit_and_response(self):
        self.assertTrue(runner.known_not_running(3, FOUND_NOTHING))
        for code in (0, 1, 2, 4, -3):
            with self.subTest(code=code):
                self.assertFalse(runner.known_not_running(code, FOUND_NOTHING))
        self.assertFalse(runner.known_not_running(3, "found nothing to terminate"))

    def test_observed_esrch_rejects_domain_code_bundle_and_tab_mismatches(self):
        lines = FOUND_NOTHING.splitlines()
        mutations = []
        for index in (0, 3):
            mutations.append((index, lines[index].replace("NSPOSIXErrorDomain", "NSCocoaErrorDomain")))
            mutations.append((index, lines[index].replace("code=3", "code=1")))
        for index in (1, 4):
            mutations.append((index, lines[index].replace("io.imagehost.imagehost", "io.other.app")))
            mutations.append((index, lines[index].replace("io.imagehost.imagehost", "ioXimagehostXimagehost")))
        for index in (4, 5):
            mutations.append((index, lines[index].replace("\t", "    ")))
        for index, replacement in mutations:
            altered = lines.copy()
            altered[index] = replacement
            with self.subTest(index=index, replacement=replacement):
                self.assertFalse(runner.known_not_running(3, "\n".join(altered)))
        self.assertFalse(runner.known_not_running(3, FOUND_NOTHING.replace("io.imagehost.imagehost", "io.other.app")))

    def test_observed_esrch_rejects_missing_extra_reordered_and_mixed_lines(self):
        lines = FOUND_NOTHING.splitlines()
        mutations = ["\n".join(lines[:index] + lines[index + 1:]) for index in range(len(lines))]
        mutations += ["\n".join(lines[:index] + ["Additional unknown error"] + lines[index:])
                      for index in range(len(lines) + 1)]
        mutations += ["\n".join(lines[:2] + [lines[3], lines[2]] + lines[4:]),
                      NOT_RUNNING + FOUND_NOTHING, FOUND_NOTHING + NOT_RUNNING,
                      FOUND_NOTHING.replace("found nothing to terminate", "No such process", 1)]
        for index, response in enumerate(mutations):
            with self.subTest(mutation=index):
                self.assertFalse(runner.known_not_running(3, response))

    def test_unconfirmed_console_close_is_failure_without_force_killing(self):
        process = Process(b"", running=True)
        with mock.patch.object(runner.subprocess, "Popen", return_value=process):
            console = runner.Running(["synthetic-owned-console"], "console")
        try:
            with mock.patch.object(runner, "CLOSE_TIMEOUT", 0.02), \
                    self.assertRaisesRegex(runner.Failure, "console-close-unconfirmed"):
                runner.end_console(console)
            self.assertFalse(process.terminated or process.killed)
            self.assertTrue(console.reader.thread.is_alive())
        finally:
            process.finish()
            with mock.patch.object(runner, "CLOSE_TIMEOUT", 0.2):
                runner.end_console(console)
        self.assertFalse(console.reader.thread.is_alive())
        self.assertTrue(process.stdout.closed and process.waited)

    def test_exit_diagnostic_waits_for_actual_reader_end(self):
        process = Process()
        gate = threading.Event()
        process.stdout = Pipe(b"", gate)
        started = threading.Event()
        commands = []
        messages = []
        failures = []
        real_running = runner.Running

        def create(*arguments, **options):
            command = real_running(*arguments, **options)
            commands.append(command)
            started.set()
            return command

        def emit(stage, value):
            if stage.endswith("-exit"):
                self.assertTrue(commands[0].closed())
                self.assertTrue(process.stdout.closed and process.waited)
            messages.append((stage, value))

        def execute():
            try:
                runner.run_command(["synthetic"], "synthetic", 1,
                                   publish=False, report_exit=True)
            except BaseException as error:
                failures.append(error)

        with mock.patch.object(runner.subprocess, "Popen", return_value=process), \
                mock.patch.object(runner, "Running", side_effect=create), \
                mock.patch.object(runner, "emit", side_effect=emit):
            worker = threading.Thread(target=execute)
            worker.start()
            try:
                self.assertTrue(started.wait(1))
                self.assertFalse(commands[0].closed())
                self.assertFalse(messages)
            finally:
                gate.set()
                worker.join(timeout=2)
            self.assertFalse(worker.is_alive())
        self.assertEqual(failures, [])
        self.assertEqual(messages, [("synthetic-exit", "exitCode=0; hostAndReaderClosed=true")])

    def test_unconfirmed_reader_cannot_print_exit_proof(self):
        process = Process()
        gate = threading.Event()
        process.stdout = Pipe(b"", gate)
        commands = []
        real_running = runner.Running

        def create(*arguments, **options):
            command = real_running(*arguments, **options)
            commands.append(command)
            return command

        with mock.patch.object(runner.subprocess, "Popen", return_value=process), \
                mock.patch.object(runner, "Running", side_effect=create), \
                mock.patch.object(runner, "CLOSE_TIMEOUT", 0.02), \
                mock.patch.object(runner, "emit") as emit:
            try:
                with self.assertRaisesRegex(runner.Failure, "synthetic-close-unconfirmed"):
                    runner.run_command(["synthetic"], "synthetic", 0.01,
                                       publish=False, report_exit=True)
                self.assertFalse(emit.called)
                self.assertTrue(commands[0].reader.thread.is_alive())
            finally:
                gate.set()
                commands[0].reader.thread.join(timeout=1)
                runner.close_host(commands[0])


if __name__ == "__main__":
    unittest.main()
