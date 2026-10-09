"""Run compiled Dart integration suites through the official iOS XCTest runner.

Control tests provide synthetic evidence only. Real Apple CI must independently
prove the Xcode exit, exact Dart results, XCTest result and owned-app shutdown.
No VM discovery, install/launch, retry, reset or simulator deletion occurs here.
"""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import time
import uuid

import run_ios_integration as host
import verify_apple_file_tests as xctest


Failure = host.Failure
RESULT_PREFIX = "IMAGEHUB_DART_XCTEST_RESULTS:"
EXPORT_PREFIX = "IMAGEHUB_BACKUP_EXPORTED_FIXTURE:"
NATIVE_NAMES = frozenset({
    "IT-004 UT-036/075 partial Apple real Pigeon file bridge ownership rejection",
    "IT-001/002 UT-004/012/102 partial Apple native storage SQLite pixels gallery and IO protection",
    "UT/IT partial Apple native Keychain isolated write new-instance read delete",
    "UT/IT partial Apple passive native network read listen cancel",
})
FOREIGN_ORIGINS = frozenset({"windows", "android", "macos"})
BACKUP_NAMES = frozenset({
    "CT-006 ios actual closed full and metadata exports",
    *(f"CT-006/IT-005/BAK-005 {origin} to ios actual full metadata restore reopen"
      for origin in FOREIGN_ORIGINS),
})
SETTINGS = frozenset({"uploadConcurrency", "processingConcurrency", "quality",
                      "longestSide", "processingMode", "cacheLimitMiB",
                      "defaultOutputRetention", "networkUploadPolicy"})
EVIDENCE_NAMES = frozenset({"export.json", "windows.json", "android.json", "macos.json"})
EVIDENCE_DIRECTORY = "imagehub-ios-xctest-evidence-v1"
FILE_LIMIT = 256 * 1024
MATRIX_LIMIT = 6 * 1024 * 1024
BUILD_TIMEOUT = 600
XCODE_TIMEOUT = 780
SUMMARY_LIMIT = 256 * 1024
UUID_PATTERN = r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"


def require(condition, classification):
    if not condition:
        raise Failure(classification)


def strict_json(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "json-duplicate-key")
            result[key] = value
        return result
    try:
        return json.loads(raw, object_pairs_hook=unique,
                          parse_constant=lambda value: (_ for _ in ()).throw(Failure("json-nonfinite")))
    except Failure:
        raise
    except Exception:
        raise Failure("json-invalid") from None


def exact_fields(value, fields, code):
    require(type(value) is dict and set(value) == set(fields), code)
    return value


def verify_dart_results(output, suite):
    require(suite in host.SUITES, "suite-invalid")
    # A malformed occurrence cannot be ignored in favour of a later valid row.
    lines = [line for line in output.splitlines() if RESULT_PREFIX in line]
    require(len(lines) == 1 and lines[0].startswith(RESULT_PREFIX), "dart-proof-count-or-prefix")
    value = exact_fields(strict_json(lines[0][len(RESULT_PREFIX):]),
                         {"suite", "results", "callbacks"}, "dart-proof-fields")
    require(value["suite"] == suite, "dart-proof-suite")
    require(type(value["callbacks"]) is int and value["callbacks"] == 4, "dart-proof-callbacks")
    expected = NATIVE_NAMES if suite == "native" else BACKUP_NAMES
    results = exact_fields(value["results"], expected, "dart-proof-names")
    require(all(type(result) is str and result == "success" for result in results.values()),
            "dart-proof-not-success")
    return value


def ordinary_path(path, *, directory):
    """Inspect every absolute component without following a link/reparse point."""
    path = Path(path)
    require(path.is_absolute(), "evidence-path-not-absolute")
    try:
        for entry in (*reversed(path.parents), path):
            value = entry.lstat()
            require(not stat.S_ISLNK(value.st_mode) and
                    not getattr(value, "st_file_attributes", 0) & 0x400,
                    "evidence-path-linked")
            wanted_directory = entry != path or directory
            require(stat.S_ISDIR(value.st_mode) if wanted_directory else stat.S_ISREG(value.st_mode),
                    "evidence-path-not-ordinary")
        return value
    except Failure:
        raise
    except Exception:
        raise Failure("evidence-path-unavailable") from None


def signature(value):
    shared = (value.st_dev, value.st_ino, value.st_mode, value.st_size, value.st_mtime_ns)
    # This entry point requires Darwin. Windows synthetic control files use
    # Python 3.12's inconsistent creation/change-time stat APIs; only that host's
    # controls omit ctime. Apple/POSIX retains the full change-time protection.
    return shared if os.name == "nt" else (*shared, value.st_ctime_ns)


def open_directory(path):
    """On Apple traverse through no-follow directory handles, closing ancestors."""
    ordinary_path(path, directory=True)
    if os.name != "posix":
        return None  # Portable synthetic control tests still reject all links.
    descriptor = None
    try:
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        descriptor = os.open(path.anchor, flags)
        for part in path.parts[1:]:
            child = os.open(part, flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        require(signature(os.fstat(descriptor)) == signature(path.lstat()), "evidence-directory-changed")
        return descriptor
    except Failure:
        if descriptor is not None:
            os.close(descriptor)
        raise
    except Exception:
        if descriptor is not None:
            os.close(descriptor)
        raise Failure("evidence-directory-open-failed") from None


def read_closed_file(path, limit=FILE_LIMIT, *, directory_fd=None):
    """Read twice; count, identity/stat and digest must remain unchanged."""
    path = Path(path).absolute()
    before = ordinary_path(path, directory=False)
    require(0 < before.st_size <= limit, "evidence-file-size")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_BINARY", 0)
    descriptor = None
    try:
        descriptor = (os.open(path.name, flags, dir_fd=directory_fd)
                      if directory_fd is not None else os.open(path, flags))
        require(signature(os.fstat(descriptor)) == signature(before), "evidence-file-changed")
        with os.fdopen(descriptor, "rb") as stream:
            descriptor = None
            first = stream.read(limit + 1)
            require(len(first) == before.st_size and len(first) <= limit, "evidence-file-size")
            stream.seek(0)
            second = stream.read(limit + 1)
            require(len(second) == len(first) and hashlib.sha256(first).digest() == hashlib.sha256(second).digest()
                    and signature(os.fstat(stream.fileno())) == signature(before), "evidence-file-changed")
        require(signature(ordinary_path(path, directory=False)) == signature(before), "evidence-file-changed")
        return first
    except Failure:
        raise
    except Exception:
        raise Failure("evidence-file-read-failed") from None
    finally:
        if descriptor is not None:
            os.close(descriptor)


def fresh_file(path, raw, limit=SUMMARY_LIMIT):
    require(type(raw) is bytes and len(raw) <= limit, "artifact-size")
    path = Path(path).absolute()
    ordinary_path(path.parent, directory=True)
    require(not path.exists() and not path.is_symlink(), "artifact-already-exists")
    try:
        with path.open("xb") as stream:
            require(stream.write(raw) == len(raw), "artifact-short-write")
            stream.flush()
            os.fsync(stream.fileno())
    except Failure:
        raise
    except Exception:
        raise Failure("artifact-write-failed") from None


def fresh_json(path, value):
    fresh_file(path, (json.dumps(value, sort_keys=True, indent=2) + "\n").encode())


def canonical_base64(value, limit, code):
    require(type(value) is str and 0 < len(value) <= limit and
            re.fullmatch(r"[A-Za-z0-9+/]+={0,2}", value) is not None, code)
    try:
        raw = base64.b64decode(value, validate=True)
    except Exception:
        raise Failure(code) from None
    require(base64.b64encode(raw).decode("ascii") == value, code)
    return raw


def verify_payload(encoded, origin=None):
    raw = canonical_base64(encoded, MATRIX_LIMIT, "payload-base64")
    require(len(raw) <= 4 * 1024 * 1024, "payload-size")
    envelope = exact_fields(strict_json(raw), {"fixtureVersion", "expectation", "bytes"}, "payload-fields")
    require(type(envelope["fixtureVersion"]) is int and envelope["fixtureVersion"] == 1, "payload-version")
    expectation = exact_fields(envelope["expectation"], {"fixtureVersion", "originPlatform", "packages"},
                               "expectation-fields")
    require(type(expectation["fixtureVersion"]) is int and expectation["fixtureVersion"] == 1,
            "expectation-version")
    require(type(expectation["originPlatform"]) is str and
            expectation["originPlatform"] in FOREIGN_ORIGINS | {"ios"} and
            (origin is None or expectation["originPlatform"] == origin), "payload-origin")
    packages = exact_fields(expectation["packages"], {"full", "metadata"}, "payload-modes")
    values = exact_fields(envelope["bytes"], {"full", "metadata"}, "payload-byte-modes")
    for mode in ("full", "metadata"):
        row = exact_fields(packages[mode], {"fileName", "byteCount", "sha256", "manifest"}, "package-fields")
        require(type(row["byteCount"]) is int and 0 < row["byteCount"] < 1024 * 1024,
                "package-byte-count")
        require(type(row["sha256"]) is str and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]) is not None,
                "package-sha-format")
        require(type(row["fileName"]) is str and
                (row["fileName"] == f"{mode}.zip" or
                 re.fullmatch(r"ImageHub-" + mode + "-" + UUID_PATTERN + r"\.zip", row["fileName"]) is not None),
                "package-file-name")
        data = canonical_base64(values[mode], 2 * 1024 * 1024, "package-base64")
        require(len(data) == row["byteCount"] and hashlib.sha256(data).hexdigest() == row["sha256"],
                "package-digest")
        manifest = row["manifest"]
        require(type(manifest) is dict and type(manifest.get("formatVersion")) is int and
                manifest["formatVersion"] == 2 and manifest.get("mode") == mode and
                type(manifest.get("assets")) is list and len(manifest["assets"]) == 4 and
                type(manifest.get("versions")) is list and len(manifest["versions"]) == 5,
                "package-manifest-shape")
    return expectation


def matrix_expectations(path):
    raw = read_closed_file(Path(path).absolute(), MATRIX_LIMIT).decode("utf-8", errors="strict")
    # Only the fixed generated program grammar is accepted, no Dart execution.
    match = re.fullmatch(r'\s*import [\'"]backup_interop_test\.dart[\'"] as interop;\s*'
                         r'void main\(\) => interop\.runBackupInteropMatrix\(\[\s*'
                         r'((?:[\'"][A-Za-z0-9+/]+={0,2}[\'"],\s*){3,4})'
                         r'\], exportCurrent: true\);\s*', raw)
    require(match is not None, "matrix-source-shape")
    payloads = re.findall(r'[\'"]([A-Za-z0-9+/]+={0,2})[\'"]', match.group(1))
    result = {}
    for encoded in payloads:
        expectation = verify_payload(encoded)
        origin = expectation["originPlatform"]
        require(origin not in result, "matrix-duplicate-origin")
        result[origin] = expectation
    require(set(result) - {"ios"} == FOREIGN_ORIGINS, "matrix-foreign-origins")
    return result


def verify_consumer(value, origin, expectation):
    document = exact_fields(value, {"fixtureVersion", "results"}, "consumer-fields")
    require(type(document["fixtureVersion"]) is int and document["fixtureVersion"] == 1, "consumer-version")
    rows = document["results"]
    require(type(rows) is list and len(rows) == 2, "consumer-modes")
    modes = set()
    for row in rows:
        exact_fields(row, {"originPlatform", "consumerPlatform", "mode", "sha256", "byteCount", "assets",
                           "versions", "restoredSettings", "skippedSettings", "closedAndReopened"}, "consumer-row-fields")
        require(row["originPlatform"] == origin and row["consumerPlatform"] == "ios", "consumer-origin")
        mode = row["mode"]
        require(type(mode) is str and mode in {"full", "metadata"} and mode not in modes, "consumer-modes")
        modes.add(mode)
        package = expectation["packages"][mode]
        require(type(row["byteCount"]) is int and row["byteCount"] == package["byteCount"] and
                row["sha256"] == package["sha256"], "consumer-digest")
        require(type(row["assets"]) is int and row["assets"] == 4 and
                type(row["versions"]) is int and row["versions"] == 5 and
                row["closedAndReopened"] is True, "consumer-reopen-counts")
        restored = row["restoredSettings"]
        require(type(restored) is list and len(restored) == 8 and
                all(type(item) is str for item in restored) and set(restored) == SETTINGS and
                type(row["skippedSettings"]) is list and row["skippedSettings"] == [], "consumer-settings")
    return document


def container_path(output, owned_uuid):
    require(type(output) is str and len(output) <= 4096 and len(output.splitlines()) == 1,
            "container-output-invalid")
    value = output.strip()
    require(value == output.rstrip("\r\n") and value.startswith("/"), "container-output-invalid")
    match = re.fullmatch(r"(.*/Library/Developer/CoreSimulator/Devices/)(" + UUID_PATTERN +
                         r")/data/Containers/Data/Application/(" + UUID_PATTERN + r")", value)
    require(match is not None and str(uuid.UUID(match.group(2))) == str(uuid.UUID(owned_uuid)),
            "container-outside-owned-device")
    path = Path(value)
    require(str(path) == value and ".." not in path.parts, "container-output-invalid")
    ordinary_path(path, directory=True)
    return path


def read_evidence(directory):
    directory = Path(directory).absolute()
    before = ordinary_path(directory, directory=True)
    descriptor = open_directory(directory)
    try:
        names = os.listdir(descriptor if descriptor is not None else directory)
        require(len(names) == 4 and set(names) == EVIDENCE_NAMES, "evidence-directory-items")
        result = {name: read_closed_file(directory / name, directory_fd=descriptor) for name in sorted(names)}
        names_after = os.listdir(descriptor if descriptor is not None else directory)
        require(set(names_after) == EVIDENCE_NAMES and len(names_after) == 4 and
                signature(ordinary_path(directory, directory=True)) == signature(before),
                "evidence-directory-changed")
        return result
    finally:
        if descriptor is not None:
            os.close(descriptor)


def collect_backup_evidence(record, artifact_root):
    host.guard_owned(record)
    raw = host.run_command(["xcrun", "simctl", "get_app_container", record["udid"], host.BUNDLE_ID, "data"],
                           "owned-app-container", 60, publish=False)
    host.guard_owned(record)
    container = container_path(raw, record["udid"])
    files = read_evidence(container / "Library" / "Caches" / EVIDENCE_DIRECTORY)
    matrix = matrix_expectations(host.SUITES["backup"][0])
    export = exact_fields(strict_json(files["export.json"]), {"fixtureVersion", "encoded"}, "export-fields")
    require(type(export["fixtureVersion"]) is int and export["fixtureVersion"] == 1, "export-version")
    exported = verify_payload(export["encoded"], "ios")
    consumers = {}
    for origin in sorted(FOREIGN_ORIGINS):
        consumers[origin] = verify_consumer(strict_json(files[f"{origin}.json"]), origin, matrix[origin])
    destination = Path(artifact_root) / "ios-dart-backup-evidence"
    ordinary_path(destination.parent.absolute(), directory=True)
    try:
        destination.mkdir(exist_ok=False)
    except Exception:
        raise Failure("evidence-artifact-directory-not-fresh") from None
    for name, contents in files.items():
        fresh_file(destination / name, contents, FILE_LIMIT)
    fresh_file(Path(artifact_root) / "ios-backup-export-capture.log",
               (EXPORT_PREFIX + export["encoded"] + "\n").encode(), FILE_LIMIT + len(EXPORT_PREFIX) + 1)
    return {"fixtureVersion": 1, "exportOrigin": "ios", "foreignOrigins": sorted(consumers),
            "modesPerOrigin": 2, "closedAndReopened": True,
            "exportPackages": {mode: {key: exported["packages"][mode][key] for key in ("sha256", "byteCount")}
                               for mode in ("full", "metadata")}}


def build_arguments(target):
    return ["flutter", "build", "ios", "--simulator", "--debug", "--no-codesign", "--target", target,
            "--dart-define=IMAGEHUB_XCTEST_EVIDENCE=true"]


def xcode_arguments(suite, target, record, result_bundle):
    require(suite in host.SUITES and target == host.SUITES[suite][0], "fixed-target-mismatch")
    macro = "NATIVE" if suite == "native" else "BACKUP"
    return ["xcodebuild", "test", "-workspace", "ios/Runner.xcworkspace", "-scheme", "Runner",
            "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={record['udid']},arch=arm64",
            "-derivedDataPath", f"build/apple-dart-{suite}",
            "-only-testing:RunnerTests/ImageHubFlutterIntegrationTests/testCompiledDartSuiteCompletes",
            "-parallel-testing-enabled", "NO", "-resultBundlePath", str(result_bundle),
            "CODE_SIGNING_ALLOWED=NO", f"FLUTTER_TARGET={target}",
            "OTHER_LDFLAGS=$(inherited) -ObjC",
            f"OTHER_CFLAGS=$(inherited) -DIMAGEHUB_FLUTTER_INTEGRATION_CI=1 -DIMAGEHUB_FLUTTER_INTEGRATION_{macro}=1"]


def run_xcode(arguments, log_path):
    """Bounded real host/reader closure plus fresh diagnostic log on all exits."""
    command = None
    collected = []
    complete_lines = []
    failure = None
    closed = False
    code = None
    def observe(line):
        complete_lines.append(line)
        # Fixtures are retained intact in the artifact, never printed to terminal.
        if EXPORT_PREFIX in line or len(line) > 4096:
            host.emit("xcode-dart", "bounded-long-or-fixture-line-retained-in-artifact")
        else:
            host.emit("xcode-dart", line)
    def drain():
        command.drain(callback=observe, collect=collected)
    try:
        command = host.Running(arguments, "xcode-dart", publish=False)
        deadline = time.monotonic() + XCODE_TIMEOUT
        while True:
            drain()
            if command.failure:
                raise Failure(command.failure)
            if command.closed():
                break
            if time.monotonic() >= deadline:
                raise Failure("xcode-dart-timeout")
            time.sleep(0.01)
        code = command.process.wait(timeout=0)
        require(code == 0, "xcode-dart-exit-nonzero")
    except Failure as error:
        failure = error
    except (Exception, KeyboardInterrupt, SystemExit):
        failure = Failure("xcode-dart-interrupted-or-unexpected")
    finally:
        if command is not None:
            try:
                if command.process.poll() is None:
                    command.process.terminate()
                deadline = time.monotonic() + host.CLOSE_TIMEOUT
                while not command.closed() and time.monotonic() < deadline:
                    drain()
                    time.sleep(0.01)
                if not command.closed():
                    if command.process.poll() is None:
                        command.process.kill()
                    deadline = time.monotonic() + host.CLOSE_TIMEOUT
                    while not command.closed() and time.monotonic() < deadline:
                        drain()
                        time.sleep(0.01)
                drain()
                command.reader.thread.join(timeout=0)
                closed = command.closed()
                if closed:
                    code = command.process.wait(timeout=0)
                    if command.failure:
                        failure = failure or Failure(command.failure)
                else:
                    failure = Failure("xcode-dart-close-unconfirmed")
            except (Exception, KeyboardInterrupt, SystemExit):
                failure = Failure("xcode-dart-close-unconfirmed")
        header = {"formatVersion": 1, "hostAndReaderClosed": closed,
                  "acceptedOutputComplete": closed and command is not None and command.failure is None and failure is None,
                  "exitCode": code, "failure": str(failure) if failure else None}
        # OutputReader enforces 8 MiB raw input. UTF-8 replacement may expand an
        # invalid byte to three encoded bytes; the artifact preserves that bounded
        # decoded diagnostic without pretending truncation is full evidence.
        raw_log = (json.dumps(header, sort_keys=True) + "\n" +
                   "\n".join(host.redact(line) for line in collected) + "\n").encode()
        try:
            fresh_file(log_path, raw_log, host.OUTPUT_LIMIT * 3 + 4096)
        except Failure as error:
            failure = failure or error
    if failure:
        raise failure
    require(closed and code == 0, "xcode-dart-close-unconfirmed")
    require(sum(RESULT_PREFIX in line for line in collected) ==
            sum(RESULT_PREFIX in line for line in complete_lines), "dart-proof-incomplete-line")
    return "\n".join(complete_lines)


def prepare_artifacts(suite):
    root = Path("build/ci-evidence")
    # Existing ancestors must be ordinary before mkdir touches the destination.
    ordinary_path(Path("build").absolute(), directory=True)
    if not root.exists():
        root.mkdir()
    ordinary_path(root.absolute(), directory=True)
    result = root / f"ios-dart-{suite}.xcresult"
    for candidate in (result, root / f"ios-dart-{suite}-summary.json", root / f"ios-dart-{suite}-xcode.log",
                      root / f"ios-dart-{suite}-xctest-summary.json"):
        require(not candidate.exists() and not candidate.is_symlink(), "artifact-already-exists")
    if suite == "backup":
        for candidate in (root / "ios-dart-backup-evidence", root / "ios-backup-export-capture.log"):
            require(not candidate.exists() and not candidate.is_symlink(), "artifact-already-exists")
    return root, result


def verify_xctest_result(record, result, root, suite):
    ordinary_path(result.absolute(), directory=True)
    host.guard_owned(record)
    raw = host.run_command(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)],
                           "xctest-summary", 60, publish=False)
    require(len(raw.encode()) <= SUMMARY_LIMIT, "xctest-summary-size")
    summary = strict_json(raw)
    fresh_json(root / f"ios-dart-{suite}-xctest-summary.json", summary)
    try:
        xctest.verify(summary, expected=1)
    except Exception:
        raise Failure("xctest-summary-not-one-passed") from None
    return summary


def run_suite(suite):
    target, _ = host.validate_environment(suite)
    require(target == host.SUITES[suite][0], "fixed-target-mismatch")
    record = host.read_owned_record()
    failure = None
    proof = None
    backup = None
    artifacts = None
    attempted = False
    try:
        host.guard_owned(record)
        host.run_command(build_arguments(target), "build", BUILD_TIMEOUT)
        host.emit("stage", "buildclosed")
        host.verify_bundle()
        host.emit("stage", "versionverified")
        artifacts, result = prepare_artifacts(suite)
        host.guard_owned(record)
        attempted = True
        output = run_xcode(xcode_arguments(suite, target, record, result),
                           artifacts / f"ios-dart-{suite}-xcode.log")
        host.emit("stage", "xcodeclosedexit0")
        proof = verify_dart_results(output, suite)
        verify_xctest_result(record, result, artifacts, suite)
        host.emit("stage", "exactdart4-and-xctest1-confirmed")
        if suite == "backup":
            backup = collect_backup_evidence(record, artifacts)
            host.emit("stage", "backup-closed-evidence-copied-and-digests-verified")
    except Failure as error:
        failure = error
        host.emit("failure", str(error))
    except (Exception, KeyboardInterrupt, SystemExit):
        failure = Failure("controller-interrupted-or-unexpected")
        host.emit("failure", str(failure))
    finally:
        # run_command already waits for the host child AND its output reader.
        # Killing a host is never evidence that the simulator app has stopped.
        if attempted and not (failure and str(failure) == "xcode-dart-close-unconfirmed"):
            try:
                host.terminate_owned_app(record, None)
                host.emit("stage", "ownedappstopped")
            except (Exception, SystemExit):
                failure = failure or Failure("owned-app-stop-unconfirmed")
                host.emit("failure", "owned-app-stop-unconfirmed")
    if failure:
        raise failure
    summary = {"suite": suite, "results": proof["results"], "callbacks": proof["callbacks"],
               "xcodeExitCode": 0, "xctestPassed": 1, "xctestFailed": 0, "xctestSkipped": 0,
               "ownedAppStopped": True}
    if backup is not None:
        summary["backupEvidence"] = backup
    fresh_json(artifacts / f"ios-dart-{suite}-summary.json", summary)
    host.emit("result", f"{suite}: exact Dart 4 and XCTest 1 passed; real host IO and owned app stopped")
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=tuple(host.SUITES), required=True)
    arguments = parser.parse_args()
    try:
        run_suite(arguments.suite)
    except Failure as error:
        host.emit("failure", str(error))
        return 1
    except (Exception, KeyboardInterrupt, SystemExit):
        host.emit("failure", "controller-interrupted-or-unexpected")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
