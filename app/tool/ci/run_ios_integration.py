"""Attach Flutter's host driver to this CI attempt's console-launched iOS app.

Control tests can mock processes; only a real Apple CI run supplies native
integration evidence. No retry, runtime change, uninstall or device reset occurs.
"""

import argparse
import json
import os
from pathlib import Path
import plistlib
import queue
import re
import subprocess
import sys
import threading
import time

import boot_ios_simulator as boot
from verify_apple_versions import verify


BUNDLE_ID = "io.imagehost.imagehost"
BUNDLE = Path("build/ios/iphonesimulator/Runner.app")
SUITES = {
    "native": ("integration_test/apple_native_smoke_test.dart",
               "test_driver/apple_native_driver.dart"),
    "backup": ("integration_test/generated_backup_interop_matrix_test.dart",
               "test_driver/backup_interop_driver.dart"),
}
LINE_LIMIT = 256 * 1024
OUTPUT_LIMIT = 8 * 1024 * 1024
STARTUP_TIMEOUT = 120
COMMAND_TIMEOUT = 600
CLOSE_TIMEOUT = 30
VM_RE = re.compile(r"(?:The )?Dart VM service is listening on (\S+)")
VM_URL = re.compile(r"http://(?:127\.0\.0\.1|localhost):([0-9]{1,5})/([A-Za-z0-9_-]+={0,2})/")
REDACT_URL = re.compile(r"https?://(?:127\.0\.0\.1|localhost):[^\s\"'<>]+", re.IGNORECASE)
PID_RE = re.compile(re.escape(BUNDLE_ID) + r": ([1-9][0-9]*)")


class Failure(Exception):
    """Fixed classification; never stringify SDK/process exceptions or args."""


def redact(value):
    return REDACT_URL.sub("<loopback-vm-uri>", value)


def emit(stage, value):
    # Preserve entire synthetic BACKUP fixture lines for the outer tee/capture.
    print(f"[{stage}] {redact(value)}", flush=True)


def startup_evidence(line):
    pid = PID_RE.fullmatch(line.strip())
    vm = VM_RE.search(line)
    uri = None
    if vm:
        candidate = vm.group(1)
        valid = VM_URL.fullmatch(candidate)
        if not valid or not 1 <= int(valid.group(1)) <= 65535:
            raise Failure("startup-invalid-vm-uri")
        uri = candidate
    return int(pid.group(1)) if pid else None, uri


class OutputReader:
    """One bounded pipe reader, still draining after a budget violation.

    The queue is bounded (16 lines); each byte read and decoded line is bounded.
    Complete lines alone can supply startup evidence. Total accepted output is
    limited to 8 MiB per process, and overflow is a failure, never success with
    truncated evidence. A daemon only permits reporting an uncertain close; it
    does not count as a confirmed reader/process shutdown.
    """

    def __init__(self, stream):
        self.stream = stream
        self.events = queue.Queue(maxsize=16)
        self.thread = threading.Thread(target=self._read, daemon=True)
        self.thread.start()

    def _read(self):
        total = 0
        overflow = False
        try:
            while True:
                raw = self.stream.readline(LINE_LIMIT + 1)
                if not raw:
                    break
                total += len(raw)
                complete = raw.endswith(b"\n")
                if total > OUTPUT_LIMIT or len(raw) > LINE_LIMIT:
                    if not overflow:
                        self.events.put(("error", "output-budget-exceeded", True))
                    overflow = True
                if overflow:
                    continue  # Drain real IO; do not publish a partial fixture.
                self.events.put(("line", raw.decode("utf-8", errors="replace").rstrip("\r\n"), complete))
        except Exception:
            self.events.put(("error", "output-read-failed", True))
        finally:
            try:
                self.stream.close()
            except Exception:
                self.events.put(("error", "output-close-failed", True))
            self.events.put(("eof", "", True))


class Running:
    def __init__(self, arguments, stage, *, publish=True):
        self.stage = stage
        self.publish = publish
        self.eof = False
        self.failure = None
        try:
            self.process = subprocess.Popen(arguments, stdout=subprocess.PIPE,
                                            stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                            shell=False)
        except Exception:
            raise Failure(stage + "-spawn-failed") from None
        self.reader = OutputReader(self.process.stdout)

    def drain(self, callback=None, collect=None):
        # Bounded batch ensures continuous output cannot postpone the deadline.
        for _ in range(32):
            try:
                kind, value, complete = self.reader.events.get_nowait()
            except queue.Empty:
                break
            if kind == "error":
                self.failure = self.stage + "-" + value
            elif kind == "eof":
                self.eof = True
            else:
                if self.publish:
                    emit(self.stage, value)
                if collect is not None:
                    collect.append(value)
                if callback is not None and complete:
                    callback(value)

    def closed(self):
        return self.process.poll() is not None and self.eof and not self.reader.thread.is_alive()


def close_host(command, companion=None):
    """Stop only the owned host child; drain its pipe and confirm actual exit."""
    if command.process.poll() is None:
        command.process.terminate()
    deadline = time.monotonic() + CLOSE_TIMEOUT
    while not command.closed() and time.monotonic() < deadline:
        command.drain()
        if companion is not None:
            companion.drain()
        time.sleep(0.01)
    if not command.closed():
        if command.process.poll() is None:
            command.process.kill()
        deadline = time.monotonic() + CLOSE_TIMEOUT
        while not command.closed() and time.monotonic() < deadline:
            command.drain()
            if companion is not None:
                companion.drain()
            time.sleep(0.01)
    command.drain()
    if companion is not None:
        companion.drain()
    command.reader.thread.join(timeout=0)
    if not command.closed():
        raise Failure(command.stage + "-close-unconfirmed")
    command.process.wait(timeout=0)


def run_command(arguments, stage, timeout, *, publish=True, companion=None,
                accept_nonzero=None, companion_errors=True):
    command = Running(arguments, stage, publish=publish)
    collected = [] if not publish or accept_nonzero is not None else None
    deadline = time.monotonic() + timeout
    try:
        while True:
            command.drain(collect=collected)
            if companion is not None:
                companion.drain()
                if companion.failure and companion_errors:
                    raise Failure(companion.failure)
                # --no-keep-app-running may stop the app before the driver
                # finishes exiting. Still require the host driver's real exit 0.
                # Console exit alone never supplies a test result, of any code.
            if command.failure:
                raise Failure(command.failure)
            if command.closed():
                break
            if time.monotonic() >= deadline:
                raise Failure(stage + "-timeout")
            time.sleep(0.01)
        code = command.process.wait(timeout=0)
        output = "\n".join(collected) if collected is not None else ""
        if code != 0 and not (accept_nonzero and accept_nonzero(code, output)):
            raise Failure(stage + "-exit-nonzero")
        return output
    finally:
        close_host(command, companion=companion)


def read_owned_record():
    try:
        boot.run_identity()
        marker = boot.marker_path()
        if not marker.is_file():
            raise Failure("ownership-marker-missing")
        record = boot.validate_record(json.loads(marker.read_text(encoding="utf-8")))
        if os.environ.get("IMAGEHOST_IOS_SIMULATOR") != record["udid"]:
            raise Failure("ownership-selected-uuid-mismatch")
        return record
    except Failure:
        raise
    except (Exception, SystemExit):
        raise Failure("ownership-invalid") from None


def guard_owned(expected, companion=None):
    record = read_owned_record()  # Before even the read-only native query.
    if record != expected:
        raise Failure("ownership-changed")
    raw = run_command(["xcrun", "simctl", "list", "devices", "--json"],
                      "ownership-query", 60, publish=False, companion=companion,
                      companion_errors=False)
    try:
        device = boot.owned_device(record, json.loads(raw))
        if device.get("state") != "Booted" or device.get("isAvailable") is not True:
            raise Failure("ownership-device-not-booted")
    except Failure:
        raise
    except (Exception, SystemExit):
        raise Failure("ownership-device-invalid") from None
    # Marker changes while the query is running must also block the next action.
    if read_owned_record() != expected:
        raise Failure("ownership-changed")


def validate_environment(suite):
    if sys.platform != "darwin" or os.environ.get("CI") != "true":
        raise Failure("requires-darwin-ci")
    if suite not in SUITES:
        raise Failure("suite-invalid")
    expected_root = Path(__file__).resolve().parents[2]
    if Path.cwd().resolve() != expected_root:
        raise Failure("requires-app-working-directory")
    target, driver = SUITES[suite]
    for relative in (target, driver, "versions.json"):
        path = Path(relative)
        if any(ancestor.is_symlink() for ancestor in (path, *path.parents)) or not path.is_file():
            raise Failure("fixed-input-unavailable")
    return target, driver


def verify_bundle():
    # Reject links in every generated bundle ancestor and executable, too.
    for path in (BUNDLE, *BUNDLE.parents):
        if path.is_symlink():
            raise Failure("build-bundle-linked")
    if not BUNDLE.is_dir():
        raise Failure("build-bundle-missing")
    try:
        versions = json.loads(Path("versions.json").read_text(encoding="utf-8"))
        verify("ios", BUNDLE, versions)
        with (BUNDLE / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        executable = BUNDLE / "Runner"
        if info.get("CFBundleExecutable") != "Runner" or executable.is_symlink() or not executable.is_file():
            raise Failure("build-executable-invalid")
    except Failure:
        raise
    except Exception:
        raise Failure("build-version-invalid") from None


def await_startup(console):
    pid = None
    uri = None

    def observe(line):
        nonlocal pid, uri
        candidate_pid, candidate_uri = startup_evidence(line)
        if candidate_pid is not None:
            if pid is not None and pid != candidate_pid:
                raise Failure("startup-pid-conflict")
            pid = candidate_pid
        if candidate_uri is not None:
            if uri is not None and uri != candidate_uri:
                raise Failure("startup-vm-conflict")
            uri = candidate_uri

    deadline = time.monotonic() + STARTUP_TIMEOUT
    while True:
        console.drain(callback=observe)
        if console.failure:
            raise Failure(console.failure)
        if console.process.poll() is not None or console.eof:
            raise Failure("startup-console-ended")
        if pid is not None and uri is not None:
            return pid, uri
        if time.monotonic() >= deadline:
            raise Failure("startup-timeout")
        time.sleep(0.01)


def known_not_running(code, output):
    # Apple simctl's specific ESRCH response; arbitrary errors mentioning
    # "not running" or "No such process" must not grant successful cleanup.
    pattern = (r"An error was encountered processing the command "
               r"\(domain=NSPOSIXErrorDomain, code=3\):\s*"
               r"Application termination failed\.\s*"
               r"Underlying error \(domain=NSPOSIXErrorDomain, code=3\):\s*"
               r"No such process")
    return code != 0 and re.fullmatch(pattern, output.strip()) is not None


def terminate_owned_app(record, console):
    guard_owned(record, companion=console)
    return run_command(["xcrun", "simctl", "terminate", record["udid"], BUNDLE_ID],
                       "owned-app-stop", 60, publish=False,
                       accept_nonzero=known_not_running, companion=console,
                       companion_errors=False)


def end_console(console):
    deadline = time.monotonic() + CLOSE_TIMEOUT
    while not console.closed() and time.monotonic() < deadline:
        console.drain()
        time.sleep(0.01)
    console.drain()
    console.reader.thread.join(timeout=0)
    if not console.closed():
        raise Failure("console-close-unconfirmed")
    code = console.process.wait(timeout=0)
    if console.failure:
        raise Failure(console.failure)
    return code


def run_suite(suite):
    target, driver = validate_environment(suite)
    record = read_owned_record()
    console = None
    launched = False
    failure = None
    try:
        guard_owned(record)
        help_text = run_command(["xcrun", "simctl", "help", "launch"],
                                "launch-help", 60, publish=False)
        if not all(re.search(re.escape(flag) + r"(?:\s|[=,:]|$)", help_text)
                   for flag in ("--console-pty", "--terminate-running-process")):
            raise Failure("launch-required-flags-unavailable")
        guard_owned(record)
        run_command(["flutter", "build", "ios", "--simulator", "--debug",
                     "--no-codesign", "--target", target], "build", COMMAND_TIMEOUT)
        emit("stage", "buildclosed")
        verify_bundle()
        emit("stage", "versionverified")
        guard_owned(record)
        run_command(["xcrun", "simctl", "install", record["udid"], str(BUNDLE)],
                    "install", 60)
        emit("stage", "appinstall")
        guard_owned(record)
        console = Running(["xcrun", "simctl", "launch", "--console-pty",
                           "--terminate-running-process", record["udid"], BUNDLE_ID,
                           "--enable-dart-profiling", "--disable-vm-service-publication",
                           "--enable-checked-mode", "--verify-entry-points"], "console")
        launched = True
        pid, uri = await_startup(console)
        emit("stage", f"launchedPID={pid}")
        emit("stage", "VMobserved")
        guard_owned(record, companion=console)
        if console.failure:
            raise Failure(console.failure)
        run_command(["flutter", "drive", "--use-existing-app", uri,
                     "--driver", driver, "-d", record["udid"], "--no-keep-app-running"],
                    "driver", COMMAND_TIMEOUT, companion=console)
        emit("stage", "driverexit0")
    except Failure as error:
        failure = error
        emit("failure", str(error))
    except (Exception, KeyboardInterrupt, SystemExit):
        failure = Failure("controller-interrupted-or-unexpected")
        emit("failure", str(failure))
    finally:
        if launched:
            try:
                terminate_owned_app(record, console)
                emit("stage", "ownedappstopped")
            except (Exception, SystemExit):
                failure = failure or Failure("owned-app-stop-unconfirmed")
                emit("failure", "owned-app-stop-unconfirmed")
        if console is not None:
            try:
                code = end_console(console)
                emit("stage", f"consoleended consoleExitCode={code}")
            except (Exception, SystemExit):
                failure = failure or Failure("console-close-unconfirmed")
                emit("failure", "console-close-unconfirmed")
    if failure:
        raise failure
    emit("result", "host driver exited 0 and owned application/console closed; Apple CI integration suite completed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=tuple(SUITES), required=True)
    arguments = parser.parse_args()
    try:
        run_suite(arguments.suite)
    except Failure as error:
        emit("failure", str(error))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
