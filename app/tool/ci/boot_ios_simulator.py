"""Create and verify one owned CI simulator using only installed runtimes."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import uuid


MARKER_NAME = "imagehub-owned-ios-simulator.json"


class SimulatorMigrationFailure(SystemExit):
    """An explicit terminal migration failure, rather than unknown readiness."""


def simctl(*arguments, timeout=60, include_stderr=False):
    print("simctl " + " ".join(arguments), flush=True)
    try:
        result = subprocess.run(
            ["xcrun", "simctl", *arguments],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as error:
        for value in (error.stdout, error.stderr):
            if value:
                print(value.decode(errors="replace") if isinstance(value, bytes) else value, flush=True)
        raise SystemExit("Simulator command exceeded its bounded deadline.") from None
    if result.stdout and (arguments[0] != "list" or result.returncode):
        print(result.stdout, end="", flush=True)
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr, flush=True)
    if result.returncode:
        raise SystemExit(f"Simulator command failed with exit code {result.returncode}.")
    return result.stdout + "\n" + result.stderr if include_stderr else result.stdout


def run_identity():
    run_id = os.environ["GITHUB_RUN_ID"]
    attempt = os.environ["GITHUB_RUN_ATTEMPT"]
    if not re.fullmatch(r"[1-9][0-9]*", run_id) or not re.fullmatch(r"[1-9][0-9]*", attempt):
        raise SystemExit("Invalid CI run identity.")
    return run_id, attempt


def marker_path():
    root = Path(os.environ["RUNNER_TEMP"])
    if not root.is_absolute() or not root.is_dir():
        raise SystemExit("The CI temporary root is unavailable.")
    marker = root / MARKER_NAME
    if marker.is_symlink():
        raise SystemExit("The simulator ownership marker must not be a link.")
    return marker


def validate_record(record):
    run_id, attempt = run_identity()
    expected = {"formatVersion", "runId", "runAttempt", "udid", "name", "runtime", "deviceType"}
    if not isinstance(record, dict) or set(record) != expected or type(record["formatVersion"]) is not int or record["formatVersion"] != 1:
        raise SystemExit("Invalid simulator ownership format.")
    if record["runId"] != run_id or record["runAttempt"] != attempt:
        raise SystemExit("Simulator ownership belongs to another CI attempt.")
    if not isinstance(record["udid"], str) or str(uuid.UUID(record["udid"])) != record["udid"]:
        raise SystemExit("Invalid owned simulator UUID.")
    if not isinstance(record["name"], str) or not re.fullmatch(rf"ImageHub-CI-{run_id}-{attempt}-[0-9a-f]{{8}}", record["name"]):
        raise SystemExit("Invalid owned simulator name.")
    if not isinstance(record["runtime"], str) or not re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9]+(?:-[0-9]+)*", record["runtime"]):
        raise SystemExit("Invalid owned simulator runtime.")
    if not isinstance(record["deviceType"], str) or not re.fullmatch(r"com\.apple\.CoreSimulator\.SimDeviceType\.iPhone-[A-Za-z0-9.-]+", record["deviceType"]):
        raise SystemExit("Invalid owned iPhone type.")
    return record


def owned_device(record, listing):
    validate_record(record)
    matches = [
        (runtime, device)
        for runtime, group in listing["devices"].items()
        for device in group
        if device.get("udid", "").lower() == record["udid"]
    ]
    if len(matches) != 1:
        raise SystemExit("The owned simulator identity could not be confirmed.")
    runtime, device = matches[0]
    if runtime != record["runtime"] or device.get("name") != record["name"] or device.get("deviceTypeIdentifier") != record["deviceType"]:
        raise SystemExit("The simulator ownership fields have changed.")
    state = device.get("state")
    displayed_state = state if state in ("Booted", "Shutdown", "Booting", "Shutting Down", "Creating") else "unknown"
    print(f"Confirmed owned simulator {record['udid']} on {runtime}: {displayed_state}.", flush=True)
    return device


def shutdown_owned(record):
    device = owned_device(record, json.loads(simctl("list", "devices", "--json")))
    if device.get("state") != "Shutdown":
        simctl("shutdown", record["udid"])
    stopped = owned_device(record, json.loads(simctl("list", "devices", "--json")))
    if stopped.get("state") != "Shutdown":
        raise SystemExit("The owned simulator shutdown could not be confirmed.")


def verify_boot_output(output):
    # A real runner returned exit 0 together with this terminal failure.
    if re.search(r"Data Migration Failed|Status=3,\s*isTerminal=YES", output, re.IGNORECASE):
        raise SimulatorMigrationFailure("Simulator data migration failed; readiness was not granted.")


def verify_springboard(output):
    if not any(re.fullmatch(r"[1-9][0-9]*\s+-?[0-9]+\s+com\.apple\.SpringBoard", line.strip()) for line in output.splitlines()):
        raise SystemExit("A running SpringBoard process could not be confirmed.")


def report_failed_boot(record):
    print("Startup remains failed; capture bounded read-only owned-device diagnostics.", flush=True)
    try:
        current = owned_device(record, json.loads(simctl("list", "devices", "--json")))
        if current.get("state") != "Booted":
            print("The failed owned simulator is not Booted; no process probe was issued.", flush=True)
            return
        verify_springboard(simctl("spawn", record["udid"], "launchctl", "list", timeout=30))
        print("A running SpringBoard was observed, but the migration failure still blocks readiness.", flush=True)
    except (Exception, SystemExit):
        print("Read-only failed-boot diagnostics could not be confirmed; startup remains failed.", flush=True)


def version_key(runtime):
    suffix = runtime.rsplit(".iOS-", 1)[1]
    return tuple(int(part) for part in suffix.split("-"))


def select_installed_device(devices, runtime, device_type):
    if not isinstance(runtime, str) or not re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9]+(?:-[0-9]+)*", runtime) or version_key(runtime) < (15,):
        raise SystemExit("The configured iOS runtime is invalid or below the supported minimum.")
    if not isinstance(device_type, str) or not re.fullmatch(r"com\.apple\.CoreSimulator\.SimDeviceType\.iPhone-[A-Za-z0-9.-]+", device_type):
        raise SystemExit("The configured iPhone type is invalid.")
    candidates = [
        device
        for device in devices.get(runtime, [])
        if device.get("isAvailable") is True
        and device.get("name", "").startswith("iPhone")
        and device.get("deviceTypeIdentifier") == device_type
    ]
    if not candidates:
        raise SystemExit("The exact configured iOS runtime and iPhone type are not installed and available; no fallback or download was attempted.")
    return candidates[0]


def prepare(runtime, device_type):
    run_id, attempt = run_identity()
    marker = marker_path()
    if marker.exists():
        raise SystemExit("An existing simulator ownership marker must be resolved first.")
    devices = json.loads(simctl("list", "devices", "available", "--json"))["devices"]
    device = select_installed_device(devices, runtime, device_type)
    print(f"Explicit installed simulator configuration: {runtime}, {device_type}.", flush=True)
    name = f"ImageHub-CI-{run_id}-{attempt}-{uuid.uuid4().hex[:8]}"
    identifier = str(uuid.UUID(simctl("create", name, device_type, runtime).strip()))
    record = validate_record({
        "formatVersion": 1,
        "runId": run_id,
        "runAttempt": attempt,
        "udid": identifier,
        "name": name,
        "runtime": runtime,
        "deviceType": device_type,
    })
    with marker.open("x", encoding="utf-8") as output:
        json.dump(record, output, ensure_ascii=True)
    owned_device(record, json.loads(simctl("list", "devices", "--json")))
    for boot_attempt in range(2):
        try:
            verify_boot_output(simctl("bootstatus", identifier, "-b", timeout=180, include_stderr=True))
            break
        except SimulatorMigrationFailure:
            if boot_attempt == 1:
                report_failed_boot(record)
                raise
            print("First owned boot reported migration failure; no readiness granted. Restart this same owned UUID once.", flush=True)
            shutdown_owned(record)
    current = owned_device(record, json.loads(simctl("list", "devices", "--json")))
    if current.get("state") != "Booted":
        raise SystemExit("The owned simulator is not booted.")
    verify_springboard(simctl("spawn", identifier, "launchctl", "list", timeout=30))
    with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as output:
        output.write(f"IMAGEHOST_IOS_SIMULATOR={identifier}\n")
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as output:
        output.write(f"Owned iOS Simulator: {device['name']}, `{runtime}`, `{identifier}`; explicit installed configuration, verified boot and running SpringBoard. No physical-device evidence.\n")


def cleanup():
    marker = marker_path()
    if not marker.exists():
        print("No owned simulator marker; no device was changed.")
        return
    record = validate_record(json.loads(marker.read_text(encoding="utf-8")))
    shutdown_owned(record)
    simctl("delete", record["udid"])
    remaining = json.loads(simctl("list", "devices", "--json"))["devices"]
    if any(device.get("udid", "").lower() == record["udid"] for group in remaining.values() for device in group):
        raise SystemExit("The owned simulator deletion could not be confirmed.")
    marker.unlink()
    print("The confirmed owned simulator was deleted.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cleanup", action="store_true")
    parser.add_argument("--runtime", help="Exact installed iOS runtime identifier; no fallback or download.")
    parser.add_argument("--device-type", help="Exact installed compatible iPhone type identifier.")
    arguments = parser.parse_args()
    if arguments.cleanup:
        if arguments.runtime is not None or arguments.device_type is not None:
            parser.error("Cleanup uses only the owned marker; selection arguments are not allowed.")
        cleanup()
    else:
        if arguments.runtime is None or arguments.device_type is None:
            parser.error("Startup requires both --runtime and --device-type.")
        prepare(arguments.runtime, arguments.device_type)


if __name__ == "__main__":
    main()
