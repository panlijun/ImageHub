"""Read-only, bounded field verification of four-origin backup evidence.

This does not execute Dart, extract archives, contact CI, or prove native IO.
All paths are relative to an explicitly supplied ordinary workspace root.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path, PureWindowsPath
import re
import sys


# Reuse the reviewed frozen-package grammar and byte/hash validator, unchanged.
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).absolute().parents[2] / "app" / "tool" / "ci"))
import run_ios_xctest_integration as frozen


Failure = frozen.Failure
require = frozen.require
PLATFORMS = ("windows", "android", "macos", "ios")
MODES = ("full", "metadata")
LIMIT = 8 * 1024 * 1024
ROW_FIELDS = {"originPlatform", "consumerPlatform", "mode", "sha256", "byteCount",
              "assets", "versions", "restoredSettings", "skippedSettings", "closedAndReopened"}
BOUNDARY = ("Offline evidence-field verification only; actual image/settings values, native IO, "
            "host/reader/app closure and hardware acceptance require independent real harness/CLI/CI evidence.")


def root_path(value):
    require(type(value) is str and value and "\x00" not in value, "root-invalid")
    path = Path(value)
    require(path.is_absolute() and not value.startswith(("\\\\", "//")), "root-invalid")
    require(not any(part in {".", ".."} for part in re.split(r"[\\/]", value)), "root-invalid")
    # A local Windows drive is the only permitted colon, never ADS/device/UNC.
    rest = value[2:] if re.match(r"^[A-Za-z]:[\\/]", value) else value
    require(":" not in rest, "root-invalid")
    frozen.ordinary_path(path, directory=True)
    return path


def relative_path(root, value, *, output=False):
    require(type(value) is str and value and "\x00" not in value and ":" not in value,
            "relative-path-invalid")
    require(not Path(value).is_absolute() and not PureWindowsPath(value).drive and
            not value.startswith(("/", "\\")), "relative-path-invalid")
    parts = re.split(r"[\\/]", value)
    require(all(part not in {"", ".", ".."} for part in parts), "relative-path-invalid")
    require(all(part == part.rstrip(" .") and not re.fullmatch(
                r"(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?", part)
                for part in parts), "relative-path-invalid")
    path = root.joinpath(*parts)
    require(path.is_relative_to(root), "path-outside-root")
    frozen.ordinary_path(path.parent if output else path, directory=output)
    if output:
        require(not os.path.lexists(path), "output-already-exists")
    return path


def read_file(path):
    return frozen.read_closed_file(path, LIMIT)


def fingerprint(relative, raw):
    return {"path": relative, "sha256": hashlib.sha256(raw).hexdigest(), "byteCount": len(raw)}


def load_frozen(path):
    before = read_file(path)
    expectations = frozen.matrix_expectations(path)
    require(set(expectations) == set(PLATFORMS), "matrix-requires-four-origins")
    require(read_file(path) == before, "matrix-file-changed")
    return expectations, before


def verify_row(row, consumer, expectations):
    frozen.exact_fields(row, ROW_FIELDS, "consumer-row-fields")
    origin = row["originPlatform"]
    require(type(origin) is str and origin in PLATFORMS and origin != consumer, "consumer-origin")
    require(type(row["consumerPlatform"]) is str and row["consumerPlatform"] == consumer,
            "consumer-platform")
    mode = row["mode"]
    require(type(mode) is str and mode in MODES, "consumer-mode")
    package = expectations[origin]["packages"][mode]
    require(type(row["sha256"]) is str and row["sha256"] == package["sha256"] and
            type(row["byteCount"]) is int and row["byteCount"] == package["byteCount"], "consumer-digest")
    require(type(row["assets"]) is int and row["assets"] == 4 and
            type(row["versions"]) is int and row["versions"] == 5 and
            row["closedAndReopened"] is True, "consumer-reopen-counts")
    restored = row["restoredSettings"]
    require(type(restored) is list and len(restored) == 8 and
            all(type(item) is str for item in restored) and len(set(restored)) == 8 and
            set(restored) == frozen.SETTINGS and type(row["skippedSettings"]) is list and
            row["skippedSettings"] == [], "consumer-settings")
    return (origin, consumer, mode)


def verify_group(group, consumer, expectations):
    require(type(group) is list and len(group) == 2, "consumer-group-modes")
    keys = [verify_row(row, consumer, expectations) for row in group]
    require(keys[0][0] == keys[1][0] and {key[2] for key in keys} == set(MODES),
            "consumer-group-modes")
    return list(zip(keys, group))


def verify_container(document, consumer, expectations):
    require(type(document) is dict, "consumer-container-fields")
    if consumer == "ios":
        frozen.exact_fields(document, {"fixtureVersion", "results"}, "consumer-container-fields")
        require(type(document["fixtureVersion"]) is int and document["fixtureVersion"] == 1,
                "consumer-container-version")
        groups = [document["results"]]
    elif consumer == "windows":
        frozen.exact_fields(document, {"results"}, "consumer-container-fields")
        groups = [document["results"]]
    else:
        frozen.exact_fields(document, {"backupInteropResults"}, "consumer-container-fields")
        value = document["backupInteropResults"]
        require(type(value) is list and value, "consumer-container-groups")
        if all(type(item) is dict for item in value):
            groups = [value]
        else:
            require(consumer == "android" and 1 <= len(value) <= 3 and
                    all(type(item) is list for item in value), "consumer-container-groups")
            groups = value
    rows = []
    seen = set()
    for group in groups:
        verified = verify_group(group, consumer, expectations)
        for key, row in verified:
            require(key not in seen, "consumer-container-duplicate")
            seen.add(key)
            rows.append((key, row))
    return rows


def parse_evidence(raw, consumer, expectations):
    try:
        text = raw.decode("utf-8", errors="strict")
    except Exception:
        raise Failure("evidence-utf8-invalid") from None
    # Native iOS evidence is a JSON file; allow its normal pretty-printed form.
    # Log consumers still require an entire exact container on each result line.
    if consumer == "ios":
        return verify_container(frozen.strict_json(text), consumer, expectations)
    rows = []
    for line in text.splitlines():
        if frozen.EXPORT_PREFIX in line:
            require(not any(marker in line for marker in
                            ('"results"', '"backupInteropResults"', '"consumerPlatform"')),
                    "consumer-marker-invalid")
            continue  # Frozen-source export never counts as a consumer.
        stripped = line.strip()
        position = stripped.find("{")
        marker = any(token in stripped for token in
                     ('"results"', '"backupInteropResults"', '"consumerPlatform"',
                      '"fixtureVersion"', "IMAGEHUB_BACKUP_", "IMAGEHUB_BACKUP_INTEROP"))
        if position < 0:
            require(not marker, "consumer-marker-invalid")
            continue
        prefix = stripped[:position]
        recognized = not prefix or re.fullmatch(r"I/flutter\s*\(\s*[0-9]+\s*\):\s*", prefix)
        if not recognized:
            require(not marker, "consumer-prefix-invalid")
            continue
        document = frozen.strict_json(stripped[position:])
        rows.extend(verify_container(document, consumer, expectations))
    require(rows, "evidence-no-consumer-results")
    return rows


def verify(root, config_relative, *, require_complete=False):
    config_path = relative_path(root, config_relative)
    config_raw = read_file(config_path)
    config = frozen.exact_fields(frozen.strict_json(config_raw),
                                 {"formatVersion", "matrix", "consumers"}, "config-fields")
    require(type(config["formatVersion"]) is int and config["formatVersion"] == 1, "config-version")
    consumers = frozen.exact_fields(config["consumers"], PLATFORMS, "config-consumers")
    matrix_path = relative_path(root, config["matrix"])
    expectations, matrix_raw = load_frozen(matrix_path)
    rows = {}
    fingerprints = []
    seen_paths = set()
    input_snapshots = [(config_path, config_raw), (matrix_path, matrix_raw)]
    for consumer in PLATFORMS:
        paths = consumers[consumer]
        require(type(paths) is list and paths, "config-consumer-paths")
        for relative in paths:
            path = relative_path(root, relative)
            normalized = os.path.normcase(str(path))
            require(normalized not in seen_paths, "config-duplicate-evidence")
            seen_paths.add(normalized)
            raw = read_file(path)
            fingerprints.append({"consumerPlatform": consumer, **fingerprint(relative, raw)})
            input_snapshots.append((path, raw))
            for key, row in parse_evidence(raw, consumer, expectations):
                require(key not in rows or rows[key] == row, "consumer-conflicting-duplicate")
                rows[key] = row
    expected = {(origin, consumer, mode) for origin in PLATFORMS for consumer in PLATFORMS
                if origin != consumer for mode in MODES}
    missing = sorted(expected - set(rows))
    complete = not missing
    require(complete or not require_complete, "matrix-incomplete")
    # Reconfirm every input after the entire verification, before publishing.
    for path, raw in input_snapshots:
        require(read_file(path) == raw, "verification-input-changed")
    directions = {(origin, consumer) for origin, consumer, _ in rows}
    missing_directions = sorted({(origin, consumer) for origin, consumer, _ in missing})
    return {
        "verificationVersion": 1, "frozenOrigins": 4,
        "consumerRows": {consumer: [rows[key] for key in sorted(rows) if key[1] == consumer]
                         for consumer in PLATFORMS},
        "directions": len(directions), "modes": len(rows), "complete": complete,
        "missingDirections": [{"originPlatform": origin, "consumerPlatform": consumer}
                              for origin, consumer in missing_directions],
        "missingModes": [{"originPlatform": origin, "consumerPlatform": consumer, "mode": mode}
                         for origin, consumer, mode in missing],
        "matrixFingerprint": fingerprint(config["matrix"], matrix_raw),
        "evidenceFingerprints": fingerprints, "boundary": BOUNDARY,
    }


def publish(root, output_relative, result):
    path = relative_path(root, output_relative, output=True)
    raw = (json.dumps(result, sort_keys=True, indent=2) + "\n").encode("utf-8")
    require(len(raw) <= LIMIT, "output-size")
    parent_before = frozen.ordinary_path(path.parent, directory=True)
    directory_fd = frozen.open_directory(path.parent)
    descriptor = None
    try:
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_BINARY", 0)
        descriptor = (os.open(path.name, flags, 0o600, dir_fd=directory_fd) if directory_fd is not None
                      else os.open(path, flags, 0o600))
        with os.fdopen(descriptor, "wb") as stream:
            descriptor = None
            require(stream.write(raw) == len(raw), "output-short-write")
            stream.flush()
            os.fsync(stream.fileno())
            signature = frozen.signature(os.fstat(stream.fileno()))
        require(frozen.signature(frozen.ordinary_path(path, directory=False)) == signature,
                "output-file-changed")
        parent_after = frozen.ordinary_path(path.parent, directory=True)
        require((parent_before.st_dev, parent_before.st_ino, parent_before.st_mode) ==
                (parent_after.st_dev, parent_after.st_ino, parent_after.st_mode), "output-parent-changed")
    except Failure:
        raise
    except Exception:
        raise Failure("output-create-or-write-failed") from None
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if directory_fd is not None:
            os.close(directory_fd)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args(argv)
    try:
        root = root_path(args.root)
        # Refuse an occupied/unsafe destination before performing any reads.
        relative_path(root, args.output, output=True)
        result = verify(root, args.config, require_complete=args.require_complete)
        publish(root, args.output, result)
        print("backup-matrix: directions=%d modes=%d complete=%s" %
              (result["directions"], result["modes"], str(result["complete"]).lower()))
        return 0
    except Failure as error:
        # Only failures originating in fixed reviewed classifications reach stdout.
        print("backup-matrix: refused: " + str(error))
        return 1
    except Exception:
        print("backup-matrix: refused: verification-unexpected-failure")
        return 1


if __name__ == "__main__":
    sys.exit(main())
