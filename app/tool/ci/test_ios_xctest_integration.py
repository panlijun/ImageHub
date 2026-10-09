"""Synthetic controller tests; never claim real iOS execution or business proof."""

import base64
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from unittest import mock

import run_ios_xctest_integration as runner
from test_ios_integration import Process, Pipe, NOT_RUNNING


def encoded_payload(origin):
    values = {}
    packages = {}
    for mode in ("full", "metadata"):
        raw = (origin + "-" + mode + "-synthetic-controller-bytes").encode()
        values[mode] = base64.b64encode(raw).decode()
        packages[mode] = {"fileName": f"{mode}.zip", "byteCount": len(raw),
                          "sha256": hashlib.sha256(raw).hexdigest(),
                          "manifest": {"formatVersion": 2, "mode": mode,
                                       "assets": [None] * 4, "versions": [None] * 5}}
    envelope = {"fixtureVersion": 1,
                "expectation": {"fixtureVersion": 1, "originPlatform": origin, "packages": packages},
                "bytes": values}
    return base64.b64encode(json.dumps(envelope).encode()).decode()


def consumer_document(origin, expectation):
    return {"fixtureVersion": 1, "results": [
        {"originPlatform": origin, "consumerPlatform": "ios", "mode": mode,
         "sha256": expectation["packages"][mode]["sha256"],
         "byteCount": expectation["packages"][mode]["byteCount"], "assets": 4, "versions": 5,
         "restoredSettings": sorted(runner.SETTINGS), "skippedSettings": [], "closedAndReopened": True}
        for mode in ("full", "metadata")]}


def dart_proof(suite="native"):
    names = runner.NATIVE_NAMES if suite == "native" else runner.BACKUP_NAMES
    return {"suite": suite, "results": dict.fromkeys(names, "success"), "callbacks": 4}


def proof_line(value):
    return runner.RESULT_PREFIX + json.dumps(value)


class ProofTests(unittest.TestCase):
    def test_exact_results_both_suites(self):
        for suite in ("native", "backup"):
            with self.subTest(suite=suite):
                value = dart_proof(suite)
                self.assertEqual(runner.verify_dart_results(proof_line(value), suite), value)

    def test_missing_empty_extra_failed_wrong_suite_wrong_callback(self):
        changes = [lambda p: p.update(results={}),
                   lambda p: p["results"].pop(next(iter(p["results"]))),
                   lambda p: p["results"].update(extra="success"),
                   lambda p: p["results"].update({next(iter(p["results"])): "failure"}),
                   lambda p: p.update(suite="backup"), lambda p: p.update(callbacks=3),
                   lambda p: p.update(callbacks=True), lambda p: p.update(extra=True)]
        for index, change in enumerate(changes):
            with self.subTest(index=index):
                value = dart_proof()
                change(value)
                with self.assertRaises(runner.Failure):
                    runner.verify_dart_results(proof_line(value), "native")

    def test_absent_duplicate_prefix_nested_duplicate_json_invalid_nonfinite(self):
        valid = proof_line(dart_proof())
        name = next(iter(runner.NATIVE_NAMES))
        samples = ["", valid + "\n" + valid, "noise " + valid,
                   valid + "\n" + runner.RESULT_PREFIX + "{}",
                   runner.RESULT_PREFIX + '{"suite":"native","suite":"native"}',
                   runner.RESULT_PREFIX + '{"results":{' + json.dumps(name) + ':"success",' +
                   json.dumps(name) + ':"success"}}', runner.RESULT_PREFIX + "{invalid}",
                   runner.RESULT_PREFIX + '{"callbacks":NaN}']
        for index, value in enumerate(samples):
            with self.subTest(index=index), self.assertRaises(runner.Failure):
                runner.verify_dart_results(value, "native")

    def test_payload_success_and_sha_size_mode_origin_canonical_rejection(self):
        encoded = encoded_payload("ios")
        self.assertEqual(runner.verify_payload(encoded, "ios")["originPlatform"], "ios")
        with self.assertRaises(runner.Failure):
            runner.verify_payload(encoded, "windows")
        mutations = [lambda p: p["expectation"]["packages"]["full"].update(sha256="a" * 64),
                     lambda p: p["expectation"]["packages"]["full"].update(byteCount=True),
                     lambda p: p["bytes"].pop("metadata"),
                     lambda p: p["expectation"].update(originPlatform="linux"),
                     lambda p: p.update(fixtureVersion=True),
                     lambda p: p["expectation"]["packages"]["full"]["manifest"].update(mode="metadata")]
        for index, mutation in enumerate(mutations):
            value = json.loads(base64.b64decode(encoded))
            mutation(value)
            bad = base64.b64encode(json.dumps(value).encode()).decode()
            with self.subTest(index=index), self.assertRaises(runner.Failure):
                runner.verify_payload(bad)
        with self.assertRaises(runner.Failure):
            runner.verify_payload(encoded + "\n")

    def test_consumer_exact_and_all_mismatches(self):
        expected = runner.verify_payload(encoded_payload("windows"))
        value = consumer_document("windows", expected)
        self.assertEqual(runner.verify_consumer(value, "windows", expected), value)
        changes = {"originPlatform": "android", "consumerPlatform": "macos", "mode": "other",
                   "sha256": "b" * 64, "byteCount": 1, "assets": 3, "versions": 4,
                   "restoredSettings": sorted(runner.SETTINGS)[:-1], "skippedSettings": ["quality"],
                   "closedAndReopened": False}
        for field, replacement in changes.items():
            value = consumer_document("windows", expected)
            value["results"][0][field] = replacement
            with self.subTest(field=field), self.assertRaises(runner.Failure):
                runner.verify_consumer(value, "windows", expected)
        for mutate in (lambda p: p["results"].pop(),
                       lambda p: p["results"].append(p["results"][0]),
                       lambda p: p["results"][1].update(mode="full"),
                       lambda p: p["results"][0].update(extra=True),
                       lambda p: p.update(fixtureVersion=True)):
            value = consumer_document("windows", expected)
            mutate(value)
            with self.assertRaises(runner.Failure):
                runner.verify_consumer(value, "windows", expected)

    def test_command_targets_owned_destination_and_compile_macros(self):
        for suite, (target, _) in runner.host.SUITES.items():
            with self.subTest(suite=suite):
                record = {"udid": "51249190-a529-4f37-9fa5-f9114ee9e8d9"}
                command = runner.xcode_arguments(suite, target, record, Path("result.xcresult"))
                self.assertEqual(command[command.index("-destination") + 1],
                                 "platform=iOS Simulator,id=51249190-A529-4F37-9FA5-F9114EE9E8D9,arch=arm64")
                self.assertEqual(record["udid"], "51249190-a529-4f37-9fa5-f9114ee9e8d9")
                self.assertIn(f"FLUTTER_TARGET={target}", command)
                self.assertIn("OTHER_LDFLAGS=$(inherited) -ObjC", command)
                self.assertIn("-only-testing:RunnerTests/ImageHubFlutterIntegrationTests/testCompiledDartSuiteCompletes", command)
                self.assertEqual(command[-1], "OTHER_CFLAGS=$(inherited) -DIMAGEHUB_FLUTTER_INTEGRATION_CI=1 "
                                 f"-DIMAGEHUB_FLUTTER_INTEGRATION_{suite.upper()}=1")
                self.assertIn("--dart-define=IMAGEHUB_XCTEST_EVIDENCE=true", runner.build_arguments(target))
                self.assertFalse(any(flag in command for flag in ("install", "launch", "uninstall", "erase")))
        with self.assertRaises(runner.Failure):
            runner.xcode_arguments("backup", runner.host.SUITES["native"][0], {"udid": "owned"}, Path("r"))

    def test_destination_rejects_non_uuid_without_fallback(self):
        target = runner.host.SUITES["native"][0]
        for value in ("booted", "owned-uuid", "", None,
                      "51249190-a529-4f37-9fa5-f9114ee9e8d9,OS=latest"):
            with self.subTest(value=value), self.assertRaises(runner.Failure):
                runner.xcode_arguments("native", target, {"udid": value}, Path("result.xcresult"))

    def test_signature_windows_only_ctime_difference_is_ignored(self):
        original = mock.Mock(st_dev=1, st_ino=2, st_mode=0o100644, st_size=9,
                             st_mtime_ns=10, st_ctime_ns=11)
        ctime_changed = mock.Mock(st_dev=1, st_ino=2, st_mode=0o100644, st_size=9,
                                  st_mtime_ns=10, st_ctime_ns=12)
        # Patch only signature evaluation; constructing Paths under a fake OS
        # would exercise a different platform implementation and is avoided.
        with mock.patch.object(runner.os, "name", "nt"):
            self.assertEqual(runner.signature(original), runner.signature(ctime_changed))
            for field in ("st_dev", "st_ino", "st_mode", "st_size", "st_mtime_ns"):
                changed = mock.Mock(st_dev=1, st_ino=2, st_mode=0o100644, st_size=9,
                                    st_mtime_ns=10, st_ctime_ns=11)
                setattr(changed, field, getattr(original, field) + 1)
                with self.subTest(field=field):
                    self.assertNotEqual(runner.signature(original), runner.signature(changed))
        with mock.patch.object(runner.os, "name", "posix"):
            self.assertNotEqual(runner.signature(original), runner.signature(ctime_changed))
            self.assertEqual(len(runner.signature(original)), 6)


class OwnedTemp(unittest.TestCase):
    def setUp(self):
        self.checkout = Path(__file__).resolve().parents[3]
        self.temp = tempfile.TemporaryDirectory(prefix="imagehub-ios-xctest-control-", dir=self.checkout)
        self.root = Path(self.temp.name).resolve(strict=True)
        self.assertEqual(self.root.parent, self.checkout)
        self.addCleanup(self.cleanup_workspace)
        self.old_cwd = Path.cwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, self.old_cwd)
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)

    def cleanup_workspace(self):
        candidate = Path(self.temp.name)
        if candidate.is_symlink() or candidate.resolve(strict=True).parent != self.checkout:
            raise AssertionError("Refusing cleanup outside verified synthetic checkout directory.")
        self.temp.cleanup()

    def create_evidence(self):
        directory = self.root / runner.EVIDENCE_DIRECTORY
        directory.mkdir()
        for name in runner.EVIDENCE_NAMES:
            (directory / name).write_bytes(b'{"synthetic":true}')
        return directory


class FileTests(OwnedTemp):
    def test_exact_files_and_no_overwrite(self):
        directory = self.create_evidence()
        self.assertEqual(set(runner.read_evidence(directory)), runner.EVIDENCE_NAMES)
        path = self.root / "fresh.json"
        runner.fresh_json(path, {"synthetic": True})
        with self.assertRaises(runner.Failure):
            runner.fresh_json(path, {"overwritten": True})
        self.assertEqual(json.loads(path.read_text()), {"synthetic": True})

    def test_unknown_missing_oversize_empty_file(self):
        directory = self.create_evidence()
        extra = directory / "unknown"
        extra.write_bytes(b"unknown")
        with self.assertRaises(runner.Failure):
            runner.read_evidence(directory)
        extra.unlink()
        path = directory / "export.json"
        for contents in (b"", b"a" * (runner.FILE_LIMIT + 1)):
            path.write_bytes(contents)
            with self.assertRaises(runner.Failure):
                runner.read_evidence(directory)
        path.unlink()
        with self.assertRaises(runner.Failure):
            runner.read_evidence(directory)

    def test_link_file_and_ancestor_rejected_without_following(self):
        target = self.root / "linked-target"
        target.write_bytes(b"do-not-follow")
        link = self.root / "link"
        # Symbolic-link support is host dependent. The synthetic lstat branch
        # still exercises refusal on Windows without elevated symlink creation.
        fake = mock.Mock(st_mode=0o120777, st_file_attributes=0)
        with mock.patch.object(Path, "lstat", return_value=fake), self.assertRaises(runner.Failure):
            runner.read_closed_file(link)
        fake = mock.Mock(st_mode=0o040755, st_file_attributes=0x400)
        with mock.patch.object(Path, "lstat", return_value=fake), self.assertRaises(runner.Failure):
            runner.ordinary_path(self.root, directory=True)

    def test_stat_change_and_digest_change_refuse(self):
        path = self.root / "closed"
        path.write_bytes(b"synthetic")
        real_signature = runner.signature
        calls = []
        def changing_signature(value):
            calls.append(1)
            result = real_signature(value)
            return (*result[:-1], result[-1] + 1) if len(calls) == 3 else result
        with mock.patch.object(runner, "signature", side_effect=changing_signature), self.assertRaises(runner.Failure):
            runner.read_closed_file(path)
        first = mock.Mock()
        second = mock.Mock()
        first.digest.return_value = b"first"
        second.digest.return_value = b"second"
        with mock.patch.object(runner.hashlib, "sha256", side_effect=[first, second]), self.assertRaises(runner.Failure):
            runner.read_closed_file(path)

    def test_container_exact_owned_path_rejects_foreign_traversal_and_extra(self):
        owned = "7a6b4f55-32e9-4c4e-96ef-2ac114643671"
        exact = f"/Users/runner/Library/Developer/CoreSimulator/Devices/{owned}/data/Containers/Data/Application/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        with mock.patch.object(runner, "ordinary_path"):
            # Parsing this fixed Apple path is a pure control check even on Windows.
            with mock.patch.object(runner, "Path", wraps=__import__("pathlib").PurePosixPath):
                self.assertEqual(str(runner.container_path(exact + "\n", owned)), exact)
        for value in (exact.replace(owned, "ffffffff-ffff-ffff-ffff-ffffffffffff"), exact + "/extra",
                      exact + "\n" + exact, "relative", exact + "/../other", " " + exact,
                      "/Library/Other/" + owned):
            with self.subTest(value=value), self.assertRaises(runner.Failure):
                runner.container_path(value, owned)

    def test_matrix_exact_grammar_foreign_sources_digest_and_duplicates(self):
        path = self.root / "matrix.dart"
        def write(origins, extra=""):
            rows = ",\n".join(json.dumps(encoded_payload(origin)) for origin in origins) + ",\n"
            path.write_text('import "backup_interop_test.dart" as interop;\n'
                            'void main() => interop.runBackupInteropMatrix([\n' + rows +
                            '], exportCurrent: true);\n' + extra, encoding="utf-8")
        write(["windows", "android", "macos"])
        self.assertEqual(set(runner.matrix_expectations(path)), runner.FOREIGN_ORIGINS)
        write(["windows", "android", "macos", "ios"])
        self.assertEqual(set(runner.matrix_expectations(path)), runner.FOREIGN_ORIGINS | {"ios"})
        for origins, extra in [(["windows", "android", "android"], ""),
                               (["windows", "android", "ios"], ""),
                               (["windows", "android", "macos"], "unknownDart();")]:
            write(origins, extra)
            with self.assertRaises(runner.Failure):
                runner.matrix_expectations(path)

    def test_collect_validated_bytes_and_bounded_capture_without_terminal_payload(self):
        root = self.root / "artifacts"
        root.mkdir()
        evidence = {"export.json": json.dumps({"fixtureVersion": 1, "encoded": encoded_payload("ios")}).encode()}
        expectations = {origin: runner.verify_payload(encoded_payload(origin)) for origin in runner.FOREIGN_ORIGINS}
        for origin, expected in expectations.items():
            evidence[f"{origin}.json"] = json.dumps(consumer_document(origin, expected)).encode()
        with mock.patch.object(runner.host, "guard_owned"), mock.patch.object(runner.host, "run_command", return_value="container"), \
                mock.patch.object(runner, "container_path", return_value=self.root), \
                mock.patch.object(runner, "read_evidence", return_value=evidence), \
                mock.patch.object(runner, "matrix_expectations", return_value=expectations):
            summary = runner.collect_backup_evidence({"udid": "synthetic-owned"}, root)
        self.assertTrue(summary["closedAndReopened"])
        self.assertEqual(set(p.name for p in (root / "ios-dart-backup-evidence").iterdir()), runner.EVIDENCE_NAMES)
        self.assertEqual((root / "ios-backup-export-capture.log").read_text(), runner.EXPORT_PREFIX + encoded_payload("ios") + "\n")


class ControllerTests(OwnedTemp):
    def setUp(self):
        super().setUp()
        self.record = {"udid": "7a6b4f55-32e9-4c4e-96ef-2ac114643671"}
        self.stack.enter_context(mock.patch.object(runner.host, "validate_environment", return_value=runner.host.SUITES["native"]))
        self.stack.enter_context(mock.patch.object(runner.host, "read_owned_record", return_value=self.record))
        self.guard = self.stack.enter_context(mock.patch.object(runner.host, "guard_owned"))
        self.stack.enter_context(mock.patch.object(runner.host, "verify_bundle"))
        self.stack.enter_context(mock.patch.object(runner, "BUILD_TIMEOUT", 0.05))
        self.stack.enter_context(mock.patch.object(runner, "XCODE_TIMEOUT", 0.05))
        self.stack.enter_context(mock.patch.object(runner.host, "CLOSE_TIMEOUT", 0.05))
        Path("build").mkdir()
        self.calls = []
        self.processes = []
        self.build_timeout = False
        self.xcode_timeout = False
        self.xcode_code = 0
        self.xcode_output = proof_line(dart_proof()).encode() + b"\n"
        self.summary = {"totalTestCount": 1, "passedTests": 1, "failedTests": 0, "skippedTests": 0}
        self.stop_code = 0
        self.stop_output = b""
        self.stack.enter_context(mock.patch.object(runner.host.subprocess, "Popen", side_effect=self.popen))
        self.output = io.StringIO()
        self.stack.enter_context(contextlib.redirect_stdout(self.output))

    def popen(self, arguments, **options):
        self.calls.append(arguments)
        self.assertIs(options["shell"], False)
        if arguments[0] == "flutter":
            process = Process(running=self.build_timeout)
        elif arguments[0] == "xcodebuild":
            Path(arguments[arguments.index("-resultBundlePath") + 1]).mkdir()
            process = Process(output=self.xcode_output, code=self.xcode_code, running=self.xcode_timeout)
        elif arguments[:3] == ["xcrun", "xcresulttool", "get"]:
            process = Process(output=json.dumps(self.summary).encode() + b"\n")
        elif arguments[:3] == ["xcrun", "simctl", "terminate"]:
            process = Process(output=self.stop_output, code=self.stop_code)
        else:
            raise AssertionError("Unexpected synthetic native command.")
        self.processes.append(process)
        return process

    def stops(self):
        return [call for call in self.calls if call[:3] == ["xcrun", "simctl", "terminate"]]

    def test_success_requires_all_proofs_and_real_readers_ended(self):
        summary = runner.run_suite("native")
        self.assertTrue(summary["ownedAppStopped"])
        self.assertEqual(summary["xctestPassed"], 1)
        self.assertEqual(len(self.stops()), 1)
        self.assertEqual(self.stops()[0][-2:], [self.record["udid"], runner.host.BUNDLE_ID])
        self.assertTrue(all(process.stdout.closed and process.waited for process in self.processes))
        self.assertTrue(Path("build/ci-evidence/ios-dart-native-summary.json").is_file())

    def test_build_timeout_does_not_start_xcode_or_stop_unlaunched_app(self):
        self.build_timeout = True
        with self.assertRaisesRegex(runner.Failure, "build-timeout"):
            runner.run_suite("native")
        self.assertFalse(any(call[0] == "xcodebuild" for call in self.calls))
        self.assertFalse(self.stops())
        self.assertTrue(self.processes[0].terminated and self.processes[0].stdout.closed)

    def test_xcode_timeout_closes_host_then_stops_owned_app(self):
        self.xcode_timeout = True
        with self.assertRaisesRegex(runner.Failure, "xcode-dart-timeout"):
            runner.run_suite("native")
        self.assertEqual(len(self.stops()), 1)
        self.assertTrue(self.processes[1].terminated and self.processes[1].stdout.closed)
        self.assertFalse(Path("build/ci-evidence/ios-dart-native-summary.json").exists())

    def test_xcode_nonzero_never_accepts_printed_success(self):
        self.xcode_code = 65
        with self.assertRaisesRegex(runner.Failure, "xcode-dart-exit-nonzero"):
            runner.run_suite("native")
        self.assertEqual(len(self.stops()), 1)

    def test_unterminated_proof_cannot_supply_success(self):
        self.xcode_output = proof_line(dart_proof()).encode()
        with self.assertRaisesRegex(runner.Failure, "dart-proof-incomplete-line"):
            runner.run_suite("native")
        self.assertEqual(len(self.stops()), 1)

    def test_xctest_failed_or_skipped_rejects_printed_success(self):
        self.summary.update(passedTests=0, skippedTests=1)
        with self.assertRaisesRegex(runner.Failure, "xctest-summary-not-one-passed"):
            runner.run_suite("native")
        self.assertEqual(len(self.stops()), 1)
        self.assertTrue(Path("build/ci-evidence/ios-dart-native-xctest-summary.json").is_file())

    def test_stop_unknown_rejects_summary(self):
        self.stop_code = 1
        self.stop_output = b"unknown simulator error\n"
        with self.assertRaisesRegex(runner.Failure, "owned-app-stop-unconfirmed"):
            runner.run_suite("native")
        self.assertFalse(Path("build/ci-evidence/ios-dart-native-summary.json").exists())

    def test_exact_esrch_is_confirmed_already_stopped(self):
        self.stop_code = 3
        self.stop_output = NOT_RUNNING.encode()
        self.assertTrue(runner.run_suite("native")["ownedAppStopped"])

    def test_ownership_change_never_sends_stop_to_unknown_device(self):
        calls = []
        def guard(record, **kwargs):
            calls.append(1)
            if len(calls) >= 3:
                raise runner.Failure("ownership-changed")
        self.guard.side_effect = guard
        with self.assertRaisesRegex(runner.Failure, "ownership-changed"):
            runner.run_suite("native")
        self.assertFalse(self.stops())

    def test_unconfirmed_child_reader_prevents_proof_and_app_stop(self):
        with mock.patch.object(runner, "run_xcode", side_effect=runner.Failure("xcode-dart-close-unconfirmed")), \
                self.assertRaisesRegex(runner.Failure, "xcode-dart-close-unconfirmed"):
            runner.run_suite("native")
        self.assertFalse(self.stops())

    def test_reader_must_end_even_when_mock_process_exit_is_zero(self):
        # A synthetic held pipe remains alive after its process reports exit.
        process = Process()
        gate = threading.Event()
        process.stdout = Pipe(b"", gate)
        with mock.patch.object(runner.host.subprocess, "Popen", return_value=process):
            running = runner.host.Running(["synthetic"], "synthetic", publish=False)
            self.assertFalse(running.closed())
            gate.set()
            running.reader.thread.join(timeout=1)
            running.drain()
            self.assertTrue(running.closed())
            runner.host.close_host(running)

    def test_failure_log_preserves_closed_output_and_marks_real_host_state(self):
        self.xcode_code = 65
        self.xcode_output = b"synthetic compilation error: retained diagnostic\n"
        with self.assertRaises(runner.Failure):
            runner.run_suite("native")
        lines = Path("build/ci-evidence/ios-dart-native-xcode.log").read_text().splitlines()
        header = json.loads(lines[0])
        self.assertTrue(header["hostAndReaderClosed"])
        self.assertEqual(header["exitCode"], 65)
        self.assertIn("synthetic compilation error: retained diagnostic", lines)

    def test_large_fixture_retained_in_artifact_without_console_base64(self):
        fixture = runner.EXPORT_PREFIX + encoded_payload("ios")
        self.xcode_output += fixture.encode() + b"\n"
        runner.run_suite("native")
        self.assertNotIn(encoded_payload("ios"), self.output.getvalue())
        self.assertIn(fixture, Path("build/ci-evidence/ios-dart-native-xcode.log").read_text())

    def test_failed_xctest_count_and_noninteger(self):
        for changes in ({"passedTests": 0, "failedTests": 1}, {"totalTestCount": True}, {"totalTestCount": 4}):
            summary = {"totalTestCount": 1, "passedTests": 1, "failedTests": 0, "skippedTests": 0}
            summary.update(changes)
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                runner.xctest.verify(summary, expected=1)


if __name__ == "__main__":
    unittest.main()
