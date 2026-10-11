"""Synthetic refusal controls plus read-only checks of historical real evidence.

Fresh control files are retained under app/build/validation. No control result
is evidence of native execution, hardware acceptance, or actual image values.
"""

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest
from unittest import mock
import uuid


sys.dont_write_bytecode = True
SCRIPT = Path(__file__).absolute().with_name("verify-release-backup-matrix.py")
ROOT = SCRIPT.parents[2]
spec = importlib.util.spec_from_file_location("backup_matrix_verifier", SCRIPT)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)
MATRIX = "app/integration_test/generated_backup_interop_matrix_test.dart"
REAL = {
    "windows": ["docs/validation/release-interop-android-to-windows.log",
                "docs/validation/release-interop-macos-to-windows.log",
                "docs/validation/release-interop-ios-to-windows.log"],
    "android": ["docs/validation/release-interop-four-origin-to-android.log"],
    "macos": ["docs/validation/release-ci-eighth-macos-backup-interop.log"],
    "ios": ["docs/validation/release-ci-eighth-windows-to-ios.json",
            "docs/validation/release-ci-eighth-android-to-ios.json",
            "docs/validation/release-ci-eighth-macos-to-ios.json"],
}


class BackupMatrixControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.owner = ROOT / "app" / "build" / "validation" / ("backup-matrix-controls-" + uuid.uuid4().hex)
        cls.owner.mkdir(parents=True, exist_ok=False)
        cls.counter = 0
        cls.expectations, cls.matrix_raw = verifier.load_frozen(ROOT / MATRIX)
        print("control-owner: " + str(cls.owner), flush=True)

    def fresh(self, raw, suffix="json"):
        type(self).counter += 1
        path = self.owner / ("case-%04d.%s" % (self.counter, suffix))
        verifier.frozen.fresh_file(path, raw, verifier.LIMIT)
        return path.relative_to(ROOT).as_posix()

    def config_file(self, config):
        return self.fresh(json.dumps(config).encode())

    def rows(self, origin="windows", consumer="android"):
        return [{"originPlatform": origin, "consumerPlatform": consumer, "mode": mode,
                 "sha256": self.expectations[origin]["packages"][mode]["sha256"],
                 "byteCount": self.expectations[origin]["packages"][mode]["byteCount"],
                 "assets": 4, "versions": 5, "restoredSettings": sorted(verifier.frozen.SETTINGS),
                 "skippedSettings": [], "closedAndReopened": True} for mode in verifier.MODES]

    def document(self, rows, consumer="android"):
        if consumer == "ios":
            return {"fixtureVersion": 1, "results": rows}
        return {"results" if consumer == "windows" else "backupInteropResults": rows}

    def parse(self, document, consumer="android"):
        return verifier.parse_evidence(json.dumps(document).encode(), consumer, self.expectations)

    def refused(self, callable_, classification=None):
        with self.assertRaises(verifier.Failure) as raised:
            callable_()
        if classification:
            self.assertEqual(str(raised.exception), classification)

    def real_config(self):
        return {"formatVersion": 1, "matrix": MATRIX, "consumers": copy.deepcopy(REAL)}

    def test_actual_partial_is_11_directions_22_modes(self):
        result = verifier.verify(ROOT, self.config_file(self.real_config()))
        self.assertEqual((result["frozenOrigins"], result["directions"], result["modes"], result["complete"]),
                         (4, 11, 22, False))
        self.assertEqual(result["missingDirections"], [{"originPlatform": "ios", "consumerPlatform": "macos"}])
        self.assertEqual({row["mode"] for row in result["missingModes"]}, {"full", "metadata"})
        self.assertEqual({platform: len(rows) for platform, rows in result["consumerRows"].items()},
                         {"windows": 6, "android": 6, "macos": 4, "ios": 6})
        self.assertEqual(len(result["evidenceFingerprints"]), 8)
        self.assertEqual(result["matrixFingerprint"]["sha256"], hashlib.sha256(self.matrix_raw).hexdigest())

    def test_actual_complete_required_refused(self):
        self.refused(lambda: verifier.verify(ROOT, self.config_file(self.real_config()), require_complete=True),
                     "matrix-incomplete")

    def test_cli_actual_partial_and_strict_no_output(self):
        config = self.config_file(self.real_config())
        output = (self.owner / "cli-partial.json").relative_to(ROOT).as_posix()
        command = [sys.executable, "-B", str(SCRIPT), "--root", str(ROOT), "--config", config, "--output", output]
        passed = subprocess.run(command, capture_output=True, text=True, timeout=30)
        self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)
        self.assertEqual(passed.stdout.strip(), "backup-matrix: directions=11 modes=22 complete=false")
        strict_output = (self.owner / "cli-complete.json").relative_to(ROOT).as_posix()
        command[-1] = strict_output
        rejected = subprocess.run([*command, "--require-complete"], capture_output=True, text=True, timeout=30)
        self.assertEqual(rejected.returncode, 1)
        self.assertEqual(rejected.stdout.strip(), "backup-matrix: refused: matrix-incomplete")
        self.assertFalse((ROOT / strict_output).exists())

    def test_synthetic_complete_24_modes(self):
        config = {"formatVersion": 1, "matrix": MATRIX, "consumers": {}}
        for consumer in verifier.PLATFORMS:
            paths = []
            for origin in verifier.PLATFORMS:
                if origin != consumer:
                    paths.append(self.fresh(json.dumps(self.document(self.rows(origin, consumer), consumer)).encode()))
            config["consumers"][consumer] = paths
        result = verifier.verify(ROOT, self.config_file(config), require_complete=True)
        self.assertEqual((result["directions"], result["modes"], result["complete"]), (12, 24, True))
        self.assertEqual(result["missingModes"], [])
        self.assertIn("Offline", result["boundary"])

    def test_three_frozen_origins_refused_even_partial(self):
        raw = self.matrix_raw.decode()
        payloads = re.findall(r"['\"]([A-Za-z0-9+/]+={0,2})['\"]", raw)
        kept = [value for value in payloads if verifier.frozen.verify_payload(value)["originPlatform"] != "ios"]
        three = ("import 'backup_interop_test.dart' as interop;\nvoid main() => "
                 "interop.runBackupInteropMatrix([" + "".join("'%s'," % value for value in kept) +
                 "], exportCurrent: true);\n").encode()
        config = self.real_config()
        config["matrix"] = self.fresh(three, "dart")
        self.refused(lambda: verifier.verify(ROOT, self.config_file(config)), "matrix-requires-four-origins")

    def test_missing_direction_stays_partial(self):
        config = self.real_config()
        config["consumers"]["windows"].pop()
        result = verifier.verify(ROOT, self.config_file(config))
        self.assertEqual((result["directions"], result["modes"], result["complete"]), (10, 20, False))

    def test_missing_consumer_config_refused(self):
        config = self.real_config()
        del config["consumers"]["macos"]
        self.refused(lambda: verifier.verify(ROOT, self.config_file(config)), "config-consumers")

    def test_empty_consumer_paths_refused(self):
        config = self.real_config()
        config["consumers"]["ios"] = []
        self.refused(lambda: verifier.verify(ROOT, self.config_file(config)), "config-consumer-paths")

    def test_future_config_refused(self):
        config = self.real_config()
        config["formatVersion"] = 2
        self.refused(lambda: verifier.verify(ROOT, self.config_file(config)), "config-version")

    def test_boolean_config_version_refused(self):
        config = self.real_config()
        config["formatVersion"] = True
        self.refused(lambda: verifier.verify(ROOT, self.config_file(config)), "config-version")

    def test_unknown_config_field_refused(self):
        config = self.real_config()
        config["extra"] = 1
        self.refused(lambda: verifier.verify(ROOT, self.config_file(config)), "config-fields")

    def test_duplicate_config_json_key_refused(self):
        config = self.fresh(b'{"formatVersion":1,"formatVersion":1,"matrix":"x","consumers":{}}')
        self.refused(lambda: verifier.verify(ROOT, config), "json-duplicate-key")

    def test_duplicate_consumer_json_key_refused(self):
        raw = json.dumps(self.document(self.rows())).replace('"assets": 4', '"assets": 4, "assets": 4', 1)
        self.refused(lambda: verifier.parse_evidence(raw.encode(), "android", self.expectations), "json-duplicate-key")

    def test_missing_setting_refused(self):
        rows = self.rows()
        rows[0]["restoredSettings"].pop()
        self.refused(lambda: self.parse(self.document(rows)), "consumer-settings")

    def test_duplicate_setting_refused(self):
        rows = self.rows()
        rows[0]["restoredSettings"][0] = rows[0]["restoredSettings"][1]
        self.refused(lambda: self.parse(self.document(rows)), "consumer-settings")

    def test_skipped_setting_refused(self):
        rows = self.rows()
        rows[0]["skippedSettings"] = ["quality"]
        self.refused(lambda: self.parse(self.document(rows)), "consumer-settings")

    def test_setting_type_refused(self):
        rows = self.rows()
        rows[0]["restoredSettings"][0] = True
        self.refused(lambda: self.parse(self.document(rows)), "consumer-settings")

    def test_false_close_refused(self):
        rows = self.rows()
        rows[0]["closedAndReopened"] = False
        self.refused(lambda: self.parse(self.document(rows)), "consumer-reopen-counts")

    def test_integer_close_refused(self):
        rows = self.rows()
        rows[0]["closedAndReopened"] = 1
        self.refused(lambda: self.parse(self.document(rows)), "consumer-reopen-counts")

    def test_changed_sha_refused(self):
        rows = self.rows()
        rows[0]["sha256"] = "0" * 64
        self.refused(lambda: self.parse(self.document(rows)), "consumer-digest")

    def test_changed_byte_count_refused(self):
        rows = self.rows()
        rows[0]["byteCount"] += 1
        self.refused(lambda: self.parse(self.document(rows)), "consumer-digest")

    def test_boolean_integer_fields_refused(self):
        for field in ("byteCount", "assets", "versions"):
            with self.subTest(field=field):
                rows = self.rows()
                rows[0][field] = True
                self.refused(lambda: self.parse(self.document(rows)))

    def test_row_extra_or_missing_field_refused(self):
        for missing in (False, True):
            with self.subTest(missing=missing):
                rows = self.rows()
                if missing:
                    del rows[0]["assets"]
                else:
                    rows[0]["extra"] = None
                self.refused(lambda: self.parse(self.document(rows)), "consumer-row-fields")

    def test_same_group_duplicate_mode_refused(self):
        rows = self.rows()
        rows[1] = copy.deepcopy(rows[0])
        self.refused(lambda: self.parse(self.document(rows)), "consumer-group-modes")

    def test_mixed_origin_group_refused(self):
        rows = [self.rows("windows")[0], self.rows("macos")[1]]
        self.refused(lambda: self.parse(self.document(rows)), "consumer-group-modes")

    def test_cross_container_same_value_deduplicated(self):
        config = self.real_config()
        rows = self.rows("windows", "macos")
        document = json.dumps(self.document(rows, "macos"))
        config["consumers"]["macos"] = [self.fresh((document + "\n" + document + "\n").encode())]
        result = verifier.verify(ROOT, self.config_file(config))
        self.assertEqual(len(result["consumerRows"]["macos"]), 2)

    def test_cross_container_conflict_refused(self):
        config = self.real_config()
        rows = self.rows("windows", "macos")
        one = json.dumps(self.document(rows, "macos"))
        rows[0]["restoredSettings"].reverse()
        two = json.dumps(self.document(rows, "macos"))
        config["consumers"]["macos"] = [self.fresh((one + "\n" + two + "\n").encode())]
        self.refused(lambda: verifier.verify(ROOT, self.config_file(config)), "consumer-conflicting-duplicate")

    def test_aggregate_duplicate_group_refused(self):
        rows = self.rows()
        self.refused(lambda: self.parse(self.document([rows, rows])), "consumer-container-duplicate")

    def test_unknown_container_refused(self):
        self.refused(lambda: self.parse({"unknownConsumer": self.rows()}), "consumer-container-fields")

    def test_unknown_container_field_refused(self):
        document = self.document(self.rows())
        document["extra"] = True
        self.refused(lambda: self.parse(document), "consumer-container-fields")

    def test_mixed_aggregate_layers_refused(self):
        rows = self.rows()
        self.refused(lambda: self.parse(self.document([rows, rows[0]])), "consumer-container-groups")

    def test_four_aggregate_groups_refused(self):
        self.refused(lambda: self.parse(self.document([self.rows()] * 4)), "consumer-container-groups")

    def test_aggregate_non_android_refused(self):
        self.refused(lambda: self.parse(self.document([self.rows("windows", "macos")], "macos"), "macos"),
                     "consumer-container-groups")

    def test_extra_mode_refused(self):
        rows = self.rows()
        rows[0]["mode"] = "preview"
        self.refused(lambda: self.parse(self.document(rows)), "consumer-mode")

    def test_third_mode_row_refused(self):
        rows = self.rows()
        rows.append(copy.deepcopy(rows[0]))
        self.refused(lambda: self.parse(self.document(rows)), "consumer-group-modes")

    def test_wrong_consumer_refused(self):
        rows = self.rows()
        rows[0]["consumerPlatform"] = "ios"
        self.refused(lambda: self.parse(self.document(rows)), "consumer-platform")

    def test_self_origin_refused(self):
        rows = self.rows("android", "android")
        self.refused(lambda: self.parse(self.document(rows)), "consumer-origin")

    def test_unknown_platform_refused(self):
        rows = self.rows()
        rows[0]["originPlatform"] = "linux"
        self.refused(lambda: self.parse(self.document(rows)), "consumer-origin")

    def test_future_ios_container_refused(self):
        document = self.document(self.rows("windows", "ios"), "ios")
        document["fixtureVersion"] = 2
        self.refused(lambda: self.parse(document, "ios"), "consumer-container-version")

    def test_pretty_ios_json_accepted(self):
        document = self.document(self.rows("windows", "ios"), "ios")
        self.assertEqual(len(verifier.parse_evidence(json.dumps(document, indent=2).encode(), "ios",
                                                    self.expectations)), 2)

    def test_flutter_prefix_and_progress_accepted(self):
        raw = ("ordinary progress without consumer marker\nI/flutter ( 123): " +
               json.dumps(self.document(self.rows())) + "\n").encode()
        self.assertEqual(len(verifier.parse_evidence(raw, "android", self.expectations)), 2)

    def test_bad_json_or_trailing_text_refused(self):
        for raw in (b'{"backupInteropResults":', json.dumps(self.document(self.rows())).encode() + b" trailing"):
            with self.subTest(rawLength=len(raw)):
                self.refused(lambda: verifier.parse_evidence(raw, "android", self.expectations), "json-invalid")

    def test_unknown_consumer_marker_refused(self):
        self.refused(lambda: verifier.parse_evidence(b"IMAGEHUB_BACKUP_RESULTS: unknown\n", "android",
                                                     self.expectations), "consumer-marker-invalid")

    def test_unknown_prefix_refused(self):
        raw = ("unobserved-prefix " + json.dumps(self.document(self.rows()))).encode()
        self.refused(lambda: verifier.parse_evidence(raw, "android", self.expectations), "consumer-prefix-invalid")

    def test_export_fixture_does_not_count(self):
        self.refused(lambda: verifier.parse_evidence(b"IMAGEHUB_BACKUP_EXPORTED_FIXTURE: YQ==\n", "android",
                                                     self.expectations), "evidence-no-consumer-results")

    def test_utf8_invalid_refused(self):
        self.refused(lambda: verifier.parse_evidence(b"\xff", "android", self.expectations), "evidence-utf8-invalid")

    def test_path_escape_unc_device_ads_alias_refused(self):
        for path in ("../AGENTS.md", "app/../AGENTS.md", "/etc/passwd", "C:\\file.json", "\\\\host\\file.json",
                     "\\\\?\\C:\\file.json", "app/x:stream", "app//file.json", "app/file.json.", "app/NUL.json"):
            with self.subTest(path=path):
                self.refused(lambda: verifier.relative_path(ROOT, path))

    def test_missing_path_and_directory_input_refused(self):
        for path in ("app/not-a-real-matrix-proof.json", "app"):
            with self.subTest(path=path):
                self.refused(lambda: verifier.relative_path(ROOT, path))

    def test_occupied_output_preserved(self):
        relative = self.fresh(b"owned sentinel unchanged")
        self.refused(lambda: verifier.publish(ROOT, relative, {}), "output-already-exists")
        self.assertEqual((ROOT / relative).read_bytes(), b"owned sentinel unchanged")

    def test_occupied_output_cli_preserved(self):
        relative = self.fresh(b"sentinel")
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--root", str(ROOT), "--config", "bad-config",
                                 "--output", relative], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.strip(), "backup-matrix: refused: output-already-exists")
        self.assertEqual((ROOT / relative).read_bytes(), b"sentinel")

    def test_reparse_attribute_refused(self):
        original = Path.lstat
        protected = ROOT / MATRIX
        def observed(path, *args, **kwargs):
            value = original(path, *args, **kwargs)
            if path == protected:
                value = mock.Mock(wraps=value)
                value.st_mode = original(path).st_mode
                value.st_file_attributes = 0x400
            return value
        with mock.patch.object(Path, "lstat", observed):
            self.refused(lambda: verifier.relative_path(ROOT, MATRIX), "evidence-path-linked")

    def test_linked_ancestor_refused(self):
        original = Path.lstat
        protected = ROOT / "app" / "integration_test"
        def observed(path, *args, **kwargs):
            value = original(path, *args, **kwargs)
            if path == protected:
                value = mock.Mock(wraps=value)
                value.st_mode = 0o120777
                value.st_file_attributes = 0
            return value
        with mock.patch.object(Path, "lstat", observed):
            self.refused(lambda: verifier.relative_path(ROOT, MATRIX), "evidence-path-linked")

    def test_duplicate_evidence_path_refused(self):
        config = self.real_config()
        config["consumers"]["windows"].append(config["consumers"]["windows"][0])
        self.refused(lambda: verifier.verify(ROOT, self.config_file(config)), "config-duplicate-evidence")

    def test_missing_mode_refused(self):
        self.refused(lambda: self.parse(self.document(self.rows()[:1])), "consumer-group-modes")

    def test_changed_counts_refused(self):
        for field in ("assets", "versions"):
            with self.subTest(field=field):
                rows = self.rows()
                rows[0][field] += 1
                self.refused(lambda: self.parse(self.document(rows)), "consumer-reopen-counts")

    def test_changed_file_detected_by_closed_reader(self):
        relative = self.fresh(b"unchanged input")
        original = verifier.frozen.signature
        calls = 0
        def changing_signature(value):
            nonlocal calls
            calls += 1
            signature = original(value)
            return (*signature, 1 if calls == 2 else 0)
        with mock.patch.object(verifier.frozen, "signature", changing_signature):
            self.refused(lambda: verifier.read_file(ROOT / relative), "evidence-file-changed")

    def test_inputs_rechecked_before_publish(self):
        config = self.config_file(self.real_config())
        original = verifier.read_file
        reads = 0
        def changed_read(path):
            nonlocal reads
            if path == ROOT / config:
                reads += 1
                if reads == 2:
                    return original(path) + b" "
            return original(path)
        with mock.patch.object(verifier, "read_file", changed_read):
            self.refused(lambda: verifier.verify(ROOT, config), "verification-input-changed")

    def test_nonfinite_json_refused(self):
        self.refused(lambda: verifier.parse_evidence(b'{"backupInteropResults":NaN}', "android", self.expectations),
                     "json-nonfinite")

    def test_oversize_input_refused(self):
        relative = self.fresh(b"x", "log")
        with mock.patch.object(verifier, "LIMIT", 0):
            self.refused(lambda: verifier.read_file(ROOT / relative), "evidence-file-size")

    def test_unknown_exception_never_stringified(self):
        class Unsafe(Exception):
            def __str__(self):
                raise AssertionError("unknown exception stringify prohibited")
        with mock.patch.object(verifier, "verify", side_effect=Unsafe()), mock.patch("builtins.print") as output:
            code = verifier.main(["--root", str(ROOT), "--config", "any", "--output",
                                  (self.owner / "unexpected.json").relative_to(ROOT).as_posix()])
        self.assertEqual(code, 1)
        output.assert_called_once_with("backup-matrix: refused: verification-unexpected-failure")


if __name__ == "__main__":
    unittest.main(verbosity=2)
