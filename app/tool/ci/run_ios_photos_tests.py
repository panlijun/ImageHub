"""Freeze a real owned Simulator Photos test host, then test without rebuilding.

Synthetic controls do not prove native Photos access. Every native test phase
requires the exact XCTest result, real host/reader closure and owned-app stop.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
import uuid

import run_ios_integration as host
import run_ios_xctest_integration as evidence

Failure = host.Failure
require = evidence.require
DERIVED = Path("build/apple-photos-ci")
ARTIFACTS = Path("build/ci-evidence")
TARGET = "lib/main.dart"
PHASES = {"prepare", "add-only", "authorize", "read-write"}
EXPECTED = {"add-only": 1, "authorize": 1, "read-write": 27}
RESULT_NAMES = {"add-only": "ios-photos-add-only.xcresult", "authorize": "ios-photos-authorize.xcresult",
                "read-write": "ios-file-tests.xcresult"}
SUMMARY_NAMES = {"add-only": "ios-photos-add-only-summary.json", "authorize": "ios-photos-authorize-summary.json",
                 "read-write": "ios-file-test-summary.json"}
TIMEOUT = 900
HASH_LIMIT = 256 * 1024 * 1024
ADD_TEST = "RunnerTests/RunnerTests/testITApplePhotosRealAddOnlyCommitPreservesSourceAndRetiresStage"
UI_TEST = "PhotosAuthorizationUITests/PhotosAuthorizationUITests/testOwnedPhotosAuthorizationFromExpectedSystemAlert"
UI_BUNDLE_ID = host.BUNDLE_ID + ".PhotosAuthorizationUITests"
PHOTOS_SWIFT_CONDITIONS = "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DEBUG IMAGEHUB_PHOTOS_UI_CI"
CONTEXT_FIELDS = frozenset({"formatVersion", "runId", "runAttempt", "ownedUuid", "ownedRecord", "target",
                            "configuration", "platform", "derivedData", "versionsSha256"})


class XcodeFailure(Failure):
    def __init__(self, classification, host_and_reader_closed):
        super().__init__(classification)
        self.host_and_reader_closed = host_and_reader_closed


def validate_environment(phase):
    require(phase in PHASES, "photos-phase-invalid")
    require(sys.platform == "darwin" and os.environ.get("CI") == "true", "requires-darwin-ci")
    require(Path.cwd().resolve() == Path(__file__).resolve().parents[2], "requires-app-working-directory")
    for path in (Path(TARGET), Path("versions.json")):
        evidence.ordinary_path(path.absolute(), directory=False)


def context(record):
    return {"formatVersion": 1, "runId": record["runId"], "runAttempt": record["runAttempt"],
            "ownedUuid": record["udid"], "ownedRecord": record,
            "target": TARGET, "configuration": "Debug", "platform": "iphonesimulator",
            "derivedData": DERIVED.as_posix(),
            "versionsSha256": hashlib.sha256(evidence.read_closed_file(Path("versions.json"))).hexdigest()}


def same_json(left, right):
    # JSON bool/int equality in Python must not weaken saved-proof types.
    return json.dumps(left, sort_keys=True) == json.dumps(right, sort_keys=True)


def arguments(phase, record, result=None):
    require(phase in PHASES, "photos-phase-invalid")
    value = record.get("udid")
    require(type(value) is str and re.fullmatch(evidence.UUID_PATTERN, value), "owned-destination-uuid-invalid")
    action = "build-for-testing" if phase == "prepare" else "test-without-building"
    args = ["xcodebuild", action, "-workspace", "ios/Runner.xcworkspace", "-scheme", "ImageHubPhotosCI",
            "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={value.upper()},arch=arm64",
            "-derivedDataPath", str(DERIVED), "-parallel-testing-enabled", "NO",
            "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES",
            f"FLUTTER_TARGET={TARGET}", PHOTOS_SWIFT_CONDITIONS]
    if phase != "prepare":
        require(result is not None, "photos-result-path-required")
        selected = {"add-only": ADD_TEST, "authorize": UI_TEST, "read-write": "RunnerTests"}[phase]
        args += ["-only-testing:" + selected,
                 "-resultBundlePath", str(result)]
    return args


def executable_digest(path, companion=None):
    """Hash twice with bounded streaming; no executable bytes enter diagnostics."""
    before = evidence.ordinary_path(path.absolute(), directory=False)
    require(0 < before.st_size <= HASH_LIMIT, "photos-executable-size")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_BINARY", 0)
    descriptor = os.open(path, flags)
    with os.fdopen(descriptor, "rb") as stream:
        require(evidence.signature(os.fstat(stream.fileno())) == evidence.signature(before), "photos-executable-changed")
        values = []
        for _ in range(2):
            stream.seek(0)
            digest = hashlib.sha256()
            count = 0
            deadline = time.monotonic() + 60
            while True:
                if companion is not None:
                    companion.drain()
                block = stream.read(64 * 1024)
                if not block:
                    break
                count += len(block)
                require(count <= HASH_LIMIT and time.monotonic() < deadline, "photos-executable-budget")
                digest.update(block)
            require(count == before.st_size, "photos-executable-changed")
            values.append(digest.hexdigest())
        require(values[0] == values[1] and
                evidence.signature(os.fstat(stream.fileno())) == evidence.signature(before), "photos-executable-changed")
    require(evidence.signature(evidence.ordinary_path(path.absolute(), directory=False)) == evidence.signature(before),
            "photos-executable-changed")
    return {"byteCount": before.st_size, "sha256": values[0]}


def fingerprint(bundle, companion=None):
    evidence.ordinary_path(bundle.absolute(), directory=True)
    require(not (bundle / "embedded.mobileprovision").exists() and
            not (bundle / "embedded.mobileprovision").is_symlink(), "photos-profile-present")
    raw = evidence.read_closed_file(bundle / "Info.plist")
    info = evidence.strict_plist(raw)
    require(info.get("CFBundleIdentifier") == host.BUNDLE_ID and info.get("CFBundleExecutable") == "Runner",
            "photos-bundle-identity-mismatch")
    versions = evidence.strict_json(evidence.read_closed_file(Path("versions.json")))
    try:
        version = host.verify("ios", bundle, versions)
    except Exception:
        raise Failure("photos-version-mismatch") from None
    options = {"companion": companion} if companion is not None else {}
    executable = executable_digest(bundle / "Runner", **options)
    host.run_command(["codesign", "--verify", "--strict", "--verbose=2", str(bundle.absolute())],
                     "photos-signing-verify", 60, publish=False, **options)
    metadata = evidence.signing_metadata(host.run_command(
        ["codesign", "--display", "--verbose=4", str(bundle.absolute())], "photos-signing-display", 60, publish=False, **options))
    entitlements = evidence.displayed_entitlements(host.run_command(
        ["codesign", "--display", "--entitlements", ":-", str(bundle.absolute())],
        "photos-signing-entitlements", 60, publish=False, **options))
    require(evidence.read_closed_file(bundle / "Info.plist") == raw and
            executable_digest(bundle / "Runner", **options) == executable, "photos-host-changed")
    return {"executable": executable, "infoPlist": {"byteCount": len(raw), "sha256": hashlib.sha256(raw).hexdigest()},
            "nativeVersion": version, "strictVerificationPassed": True,
            "codesign": metadata, "signatureEntitlements": entitlements}


def built_bundle():
    return DERIVED.absolute() / "Build/Products/Debug-iphonesimulator/Runner.app"


def generated_entitlements():
    root = DERIVED.absolute() / "Build/Intermediates.noindex/Runner.build/Debug-iphonesimulator/Runner.build"
    evidence.ordinary_path(root, directory=True)
    return {name: evidence.entitlement_evidence(evidence.read_closed_file(root / name))
            if (root / name).exists() or (root / name).is_symlink() else None
            for name in ("Runner.app.xcent", "Runner.app.xcent-simulated")}


def installed_container_shape(raw, owned_uuid):
    """Validate a recorded location without accessing a possibly retired path."""
    require(type(raw) is str and len(raw) <= 4096 and len(raw.splitlines()) == 1, "photos-container-output-invalid")
    value = raw.strip()
    require(value == raw and value.startswith("/"), "photos-container-output-invalid")
    require(not any(ord(character) < 32 or ord(character) == 127 for character in value) and "\\" not in value,
            "photos-container-output-invalid")
    match = re.fullmatch(r"(.*/Library/Developer/CoreSimulator/Devices/)(" + evidence.UUID_PATTERN +
                         r")/data/Containers/Bundle/Application/(" + evidence.UUID_PATTERN + r")/Runner\.app", value)
    require(match is not None and str(uuid.UUID(match.group(2))) == str(uuid.UUID(owned_uuid)),
            "photos-container-outside-owned-device")
    path = Path(value)
    require(path.as_posix() == value and ".." not in path.parts, "photos-container-output-invalid")
    return path


def installed_path(raw, owned_uuid):
    require(type(raw) is str and len(raw) <= 4096 and len(raw.splitlines()) == 1, "photos-container-output-invalid")
    path = installed_container_shape(raw.rstrip("\r\n"), owned_uuid)
    evidence.ordinary_path(path, directory=True)
    return path


def installed_bundle(record, companion=None):
    options = {"companion": companion} if companion is not None else {}
    host.guard_owned(record, **options)
    raw = host.run_command(["xcrun", "simctl", "get_app_container", record["udid"], host.BUNDLE_ID, "app"],
                           "photos-app-container", 60, publish=False, **options)
    host.guard_owned(record, **options)
    return installed_path(raw, record["udid"])


AUTHORIZATION_PREFIX = "IMAGEHUB_PHOTOS_AUTHORIZATION "
AUTHORIZATION_TYPES = {"phase": str, "callbackStatus": int, "failureLatched": bool,
    "readBack": bool, "mainBundleID": str, "testBundleID": str,
    "hostMatchesExpected": bool, "testBundleMatchesExpected": bool, "processID": int,
    "ownedSimulatorID": str, "addOnlyStatus": int, "readWriteStatus": int,
    "photoUsageDescriptionPresent": bool, "photoAddUsageDescriptionPresent": bool}
class PhotosCompanion:
    """Every nested command drains to the same evidence and observer, never acts."""
    def __init__(self, command, lines, observer):
        self.command, self.lines, self.observer = command, lines, observer

    @property
    def failure(self):
        return self.command.failure or self.observer.failure

    def drain(self):
        self.command.drain(callback=self.observer.observe, collect=self.lines)


class AuthorizationObserver:
    """Strict read-only protocol observer; failures latch through final drain."""
    def __init__(self, record):
        self.record = record
        self.origin = time.monotonic()
        self.events = []
        self.observations = []
        self.failure = None

    def fail(self, classification):
        self.failure = self.failure or classification

    def observe(self, line):
        if not line.startswith(self.prefix.rstrip()):
            return
        try:
            require(line.startswith(self.prefix), self.classification + "-signal-invalid")
            value = evidence.strict_json(line[len(self.prefix):])
            require(type(value) is dict and set(value) == set(self.types) and
                    all(type(value[key]) is expected for key, expected in self.types.items()),
                    self.classification + "-signal-invalid")
            self.validate(value)
            self.observations.append(value)
            self.events.append({"phase": value["phase"],
                "elapsedMilliseconds": int((time.monotonic() - self.origin) * 1000)})
        except Failure as error:
            self.fail(str(error))
        except (Exception, KeyboardInterrupt, SystemExit):
            self.fail(self.classification + "-observer-unexpected")


UI_AUTHORIZATION_PREFIX = "IMAGEHUB_PHOTOS_UI_AUTHORIZATION "
UI_AUTHORIZATION_TYPES = {"formatVersion": int, "phase": str, "ownedSimulatorID": str,
    "mainBundleID": str, "mainProcessID": int, "photoUsageDescriptionPresent": bool,
    "photoAddUsageDescriptionPresent": bool, "addOnlyStatus": int, "readWriteStatus": int,
    "requestCount": int, "callbackCount": int, "callbackStatus": int, "requestDispatched": bool,
    "failureLatched": bool, "callbackWithinDeadline": bool, "testBundleID": str,
    "testProcessID": int, "expectedAlertNeeded": bool, "expectedAlertHandled": bool}


class UIPhotosAuthorization(AuthorizationObserver):
    """Actual UI-read snapshots require one SDK callback, never a CLI grant."""
    prefix = UI_AUTHORIZATION_PREFIX
    types = UI_AUTHORIZATION_TYPES
    classification = "photos-ui"

    def validate(self, value):
        require(value["formatVersion"] == 1 and value["ownedSimulatorID"] == self.record["udid"] and
                value["mainBundleID"] == host.BUNDLE_ID and value["testBundleID"] == UI_BUNDLE_ID and
                value["mainProcessID"] > 0 and value["testProcessID"] > 0 and
                value["photoUsageDescriptionPresent"] and value["photoAddUsageDescriptionPresent"],
                "photos-ui-identity-invalid")
        require(value["failureLatched"] is False and value["addOnlyStatus"] == 3,
                "photos-ui-sdk-failure-latched")
        if not self.observations:
            require(value["phase"] == "ready" and value["readWriteStatus"] in (0, 3) and
                    value["requestCount"] == 0 and value["callbackCount"] == 0 and value["callbackStatus"] == -1 and
                    value["requestDispatched"] is False and value["callbackWithinDeadline"] is False and
                    value["expectedAlertNeeded"] is (value["readWriteStatus"] == 0) and
                    value["expectedAlertHandled"] is False, "photos-ui-ready-invalid")
        else:
            ready = self.observations[0]
            require(value["mainProcessID"] == ready["mainProcessID"] and
                    value["testProcessID"] == ready["testProcessID"], "photos-ui-pid-changed")
            require(len(self.observations) == 1 and value["phase"] == "confirmed" and
                    value["readWriteStatus"] == 3 and value["requestCount"] == 1 and value["callbackCount"] == 1 and
                    value["callbackStatus"] == 3 and value["requestDispatched"] is True and
                    value["callbackWithinDeadline"] is True and
                    value["expectedAlertNeeded"] is ready["expectedAlertNeeded"] and
                    value["expectedAlertHandled"] is ready["expectedAlertNeeded"], "photos-ui-confirmation-invalid")

    def finish(self):
        if len(self.observations) != 2:
            self.fail("photos-ui-sdk-request-unconfirmed")


class FullPhotosAuthorization(AuthorizationObserver):
    """The full suite observes already-authorized SDK state in one host PID."""
    prefix = AUTHORIZATION_PREFIX
    types = AUTHORIZATION_TYPES
    classification = "photos-full"

    def validate(self, value):
        require(value["ownedSimulatorID"] == self.record["udid"] and value["processID"] > 0 and
                value["mainBundleID"] == host.BUNDLE_ID and
                value["testBundleID"] == host.BUNDLE_ID + ".RunnerTests" and
                all(value[key] is True for key in ("hostMatchesExpected", "testBundleMatchesExpected",
                    "photoUsageDescriptionPresent", "photoAddUsageDescriptionPresent")),
                "photos-full-identity-invalid")
        if self.observations:
            require(value["processID"] == self.observations[0]["processID"], "photos-full-host-pid-changed")
        require(value["phase"] == "preflight" and value["failureLatched"] is False and
                value["callbackStatus"] == -1 and value["addOnlyStatus"] == 3 and value["readWriteStatus"] == 3,
                "photos-full-preauthorized-sdk-required")

    def finish(self):
        if sum(value["readBack"] for value in self.observations) != 5:
            self.fail("photos-full-five-readback-preflights-required")


def execute_xcode(args, phase, *, observer=None):
    command = None
    lines = []
    failure = None
    closed = False
    code = None
    stage = "photos-xcode-" + phase
    def drain():
        if observer is None:
            command.drain(collect=lines)
        else:
            companion.drain()
    try:
        command = host.Running(args, stage, publish=False)
        companion = PhotosCompanion(command, lines, observer) if observer is not None else None
        deadline = time.monotonic() + TIMEOUT
        while True:
            drain()
            if observer is not None:
                require(observer.failure is None, observer.failure)
            if command.failure:
                raise Failure(command.failure)
            if command.closed():
                break
            require(time.monotonic() < deadline, stage + "-timeout")
            time.sleep(0.01)
        code = command.process.wait(timeout=0)
        require(code == 0, stage + "-exit-nonzero")
    except Failure as error:
        failure = error
    except (Exception, KeyboardInterrupt, SystemExit):
        failure = Failure(stage + "-unexpected")
    finally:
        if command is not None:
            try:
                for _ in range(2):
                    if command.process.poll() is None:
                        if _ == 0:
                            command.process.terminate()
                        else:
                            command.process.kill()
                    deadline = time.monotonic() + host.CLOSE_TIMEOUT
                    while not command.closed() and time.monotonic() < deadline:
                        drain()
                        time.sleep(0.01)
                    if command.closed():
                        break
                drain()
                if observer is not None:
                    observer.finish()
                if observer is not None and observer.failure is not None:
                    failure = failure or Failure(observer.failure)
                command.reader.thread.join(timeout=0)
                closed = command.closed()
                if closed:
                    code = command.process.wait(timeout=0)
                    if command.failure:
                        failure = failure or Failure(command.failure)
                else:
                    failure = Failure(stage + "-close-unconfirmed")
            except (Exception, KeyboardInterrupt, SystemExit):
                closed = False
                failure = Failure(stage + "-close-unconfirmed")
        try:
            header = {"formatVersion": 1, "phase": phase, "hostAndReaderClosed": closed,
                      "exitCode": code, "failure": str(failure) if failure else None}
            if observer is not None:
                header["authorizationControl"] = observer.events
                header["authorizationObservations"] = observer.observations
            raw = (json.dumps(header, sort_keys=True) + "\n" +
                   "\n".join(host.redact(line) for line in lines) + "\n").encode()
            evidence.fresh_file(ARTIFACTS / f"ios-photos-{phase}-xcode.log", raw, host.OUTPUT_LIMIT * 3 + 4096)
        except Failure as error:
            failure = failure or error
        except (Exception, KeyboardInterrupt, SystemExit):
            failure = failure or Failure(stage + "-log-unexpected")
    if failure:
        raise XcodeFailure(str(failure), closed)
    require(closed and code == 0, stage + "-close-unconfirmed")
    try:
        host.emit("photos-xcode-exit", f"{phase}: exitCode=0; hostAndReaderClosed=true")
    except (Exception, KeyboardInterrupt, SystemExit):
        raise XcodeFailure(stage + "-log-unexpected", closed) from None
    return True


def read_prepared(record, observation=None, expected_digest=None):
    raw = evidence.read_closed_file(ARTIFACTS / "ios-photos-prepared.json")
    digest = hashlib.sha256(raw).hexdigest()
    if observation is not None:
        observation["preparedSha256"] = digest
        observation["preparedSha256MatchesExpected"] = digest == expected_digest if expected_digest is not None else None
    proof = evidence.exact_fields(evidence.strict_json(raw), CONTEXT_FIELDS |
                                  {"builtHost", "installedHost", "installedContainer", "generatedEntitlements",
                                   "buildHostAndReaderClosed", "installHostAndReaderClosed"}, "photos-prepared-fields")
    for key, value in context(record).items():
        require(same_json(proof[key], value), "photos-prepared-context-changed")
    require(proof["buildHostAndReaderClosed"] is True and proof["installHostAndReaderClosed"] is True,
            "photos-prepared-not-closed")
    installed_container_shape(proof["installedContainer"], record["udid"])
    return proof, digest


def frozen_observation(record, phase, expected_digest=None, *, expected_context=None, companion=None):
    """Read every component independently, retaining only curated closed evidence.

    Location equality is diagnostic. Content, signing, generated entitlements,
    context and the original prepared bytes remain strict frozen requirements.
    The caller publishes this only after actual Xcode host/reader closure.
    """
    if expected_context is not None:
        require(type(expected_context) is dict and set(expected_context) == CONTEXT_FIELDS, "photos-observation-context-invalid")
    bound_context = context(record) if expected_context is None else expected_context
    observation = {**bound_context, "phase": phase, "preparedSha256": None,
                   "preparedSha256MatchesExpected": None,
                   "preparedFinalSha256": None, "preparedFinalReadState": "unobserved",
                   "preparedFinalMatchesInitial": None, "preparedFinalMatchesExpected": None,
                   "initialInstalledContainer": None, "currentInstalledContainer": None,
                   "readStates": {name: "unobserved" for name in
                                  ("prepared", "builtHost", "installedHost", "generatedEntitlements")},
                   "builtMatchesPrepared": None, "installedMatchesPrepared": None,
                   "builtMatchesInstalled": None, "containerMatchesInitial": None,
                   "generatedEntitlementsMatchPrepared": None,
                   "builtHost": None, "installedHost": None, "generatedEntitlements": None,
                   "allFrozenFieldsVerified": False}
    failure = None
    proof = None
    options = {"companion": companion} if companion is not None else {}
    def read(name, operation):
        nonlocal failure
        try:
            value = operation()
            observation["readStates"][name] = "observed"
            return value
        except Failure as error:
            failure = failure or error
        except (Exception, KeyboardInterrupt, SystemExit):
            failure = failure or Failure("photos-" + name + "-read-unexpected")
        observation["readStates"][name] = "readFailed"
        return None
    prepared = read("prepared", lambda: read_prepared(record, observation, expected_digest))
    if prepared is not None:
        proof, digest = prepared
        observation["preparedSha256"] = digest
        observation["preparedSha256MatchesExpected"] = digest == expected_digest if expected_digest is not None else None
        observation["initialInstalledContainer"] = proof["installedContainer"]
    observation["builtHost"] = read("builtHost", lambda: fingerprint(built_bundle(), **options))
    def installed_host():
        installed = installed_bundle(record, **options)
        observation["currentInstalledContainer"] = str(installed)
        return fingerprint(installed, **options)
    observation["installedHost"] = read("installedHost", installed_host)
    observation["generatedEntitlements"] = read("generatedEntitlements", generated_entitlements)
    # Confirm the original proof did not change while the other components
    # were read. This is closed-file stability, not an atomic bundle snapshot.
    try:
        raw = evidence.read_closed_file(ARTIFACTS / "ios-photos-prepared.json")
        final_digest = hashlib.sha256(raw).hexdigest()
        observation["preparedFinalSha256"] = final_digest
        observation["preparedFinalReadState"] = "observed"
        if observation["preparedSha256"] is not None:
            observation["preparedFinalMatchesInitial"] = final_digest == observation["preparedSha256"]
        if expected_digest is not None:
            observation["preparedFinalMatchesExpected"] = final_digest == expected_digest
        if observation["preparedFinalMatchesInitial"] is False or observation["preparedFinalMatchesExpected"] is False:
            failure = failure or Failure("photos-prepared-proof-changed")
    except Failure as error:
        observation["preparedFinalReadState"] = "readFailed"
        failure = failure or error
    except (Exception, KeyboardInterrupt, SystemExit):
        observation["preparedFinalReadState"] = "readFailed"
        failure = failure or Failure("photos-prepared-final-read-unexpected")
    built, actual, generated = (observation[name] for name in ("builtHost", "installedHost", "generatedEntitlements"))
    if proof is not None:
        if built is not None:
            observation["builtMatchesPrepared"] = same_json(proof["builtHost"], built)
        if actual is not None:
            observation["installedMatchesPrepared"] = same_json(proof["installedHost"], actual)
        if observation["currentInstalledContainer"] is not None:
            observation["containerMatchesInitial"] = proof["installedContainer"] == observation["currentInstalledContainer"]
        if generated is not None:
            observation["generatedEntitlementsMatchPrepared"] = same_json(proof["generatedEntitlements"], generated)
    if built is not None and actual is not None:
        observation["builtMatchesInstalled"] = same_json(built, actual)
    content_matches = all(observation[name] is True for name in
                          ("builtMatchesPrepared", "installedMatchesPrepared", "builtMatchesInstalled",
                           "generatedEntitlementsMatchPrepared"))
    if expected_digest is not None and proof is not None and observation["preparedSha256MatchesExpected"] is not True:
        failure = failure or Failure("photos-prepared-proof-changed")
    if not content_matches:
        failure = failure or Failure("photos-prepared-host-changed")
    observation["allFrozenFieldsVerified"] = failure is None and content_matches and observation["preparedFinalMatchesInitial"] is True
    return proof, observation, failure


def check_prepared(record):
    proof, observation, failure = frozen_observation(record, None)
    if failure:
        raise failure
    return proof, observation["preparedSha256"]


def check_frozen(record, digest):
    proof, observation, failure = frozen_observation(record, None, digest)
    if failure:
        raise failure
    return proof


def check_closed_phase(record, proof, digest, phase):
    require(phase in ("add-only", "authorize"), "photos-prior-phase-invalid")
    raw = evidence.read_closed_file(ARTIFACTS / f"ios-photos-{phase}-host-observation.json")
    prior = evidence.strict_json(evidence.read_closed_file(ARTIFACTS / f"ios-photos-{phase}-result.json"))
    extras = {}
    if phase == "authorize":
        require(type(prior) is dict and type(prior.get("authorizationObservations")) is list,
                "photos-authorize-proof-required")
        observer = UIPhotosAuthorization(record)
        for value in prior["authorizationObservations"]:
            observer.observe(UI_AUTHORIZATION_PREFIX + json.dumps(value, sort_keys=True))
        observer.finish()
        require(observer.failure is None, "photos-authorize-sdk-proof-required")
        summary_raw = evidence.read_closed_file(ARTIFACTS / SUMMARY_NAMES[phase])
        try:
            evidence.xctest.verify(evidence.strict_json(summary_raw), EXPECTED[phase])
        except Exception:
            raise Failure("photos-authorize-summary-required") from None
        extras = {"authorizationObservations": observer.observations,
                  "xctestSummarySha256": hashlib.sha256(summary_raw).hexdigest()}
    require(same_json(prior, {**context(record), "phase": phase, "preparedSha256": digest,
                      "hostObservationSha256": hashlib.sha256(raw).hexdigest(),
                      "xcodeExitCode": 0, "hostAndReaderClosed": True, "ownedAppStopped": True,
                      "xctestPassed": EXPECTED[phase], "xctestFailed": 0, "xctestSkipped": 0,
                      **extras}), "photos-" + phase + "-proof-required")
    actual = evidence.strict_json(raw)
    require(type(actual) is dict, "photos-" + phase + "-observation-required")
    current = actual.get("currentInstalledContainer")
    installed_container_shape(current, record["udid"])
    expected = {**context(record), "phase": phase, "preparedSha256": digest,
                "preparedSha256MatchesExpected": True,
                "preparedFinalSha256": digest, "preparedFinalReadState": "observed",
                "preparedFinalMatchesInitial": True, "preparedFinalMatchesExpected": True,
                "initialInstalledContainer": proof["installedContainer"], "currentInstalledContainer": current,
                "readStates": {name: "observed" for name in
                               ("prepared", "builtHost", "installedHost", "generatedEntitlements")},
                "builtMatchesPrepared": True, "installedMatchesPrepared": True,
                "builtMatchesInstalled": True, "containerMatchesInitial": current == proof["installedContainer"],
                "generatedEntitlementsMatchPrepared": True, "builtHost": proof["builtHost"],
                "installedHost": proof["installedHost"], "generatedEntitlements": proof["generatedEntitlements"],
                "allFrozenFieldsVerified": True}
    require(same_json(actual, expected), "photos-" + phase + "-observation-required")


def check_add_only(record, proof, digest):
    check_closed_phase(record, proof, digest, "add-only")


def collect_summary(record, phase, result):
    evidence.ordinary_path(result.absolute(), directory=True)
    host.guard_owned(record)
    raw = host.run_command(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)],
                           "photos-xctest-summary", 60, publish=False)
    require(len(raw.encode()) <= evidence.SUMMARY_LIMIT, "photos-xctest-summary-size")
    summary = evidence.strict_json(raw)
    evidence.fresh_json(ARTIFACTS / SUMMARY_NAMES[phase], summary)
    try:
        evidence.xctest.verify(summary, EXPECTED[phase])
    except Exception:
        raise Failure("photos-xctest-not-all-passed") from None
    return summary


def require_fresh_outputs(names):
    for name in names:
        path = ARTIFACTS / name
        require(not path.exists() and not path.is_symlink(), "photos-artifact-not-fresh")


def prepare(record):
    require_fresh_outputs(["ios-photos-prepare-xcode.log", "ios-photos-prepare-built-host.json",
                           "ios-photos-prepare-installed-host.json", "ios-photos-privacy-help.log",
                           "ios-photos-prepared.json"])
    require(not DERIVED.exists() and not DERIVED.is_symlink(), "photos-derived-data-not-fresh")
    evidence.ordinary_path(DERIVED.parent.absolute(), directory=True)
    host.guard_owned(record)
    DERIVED.mkdir(exist_ok=False)
    execute_xcode(arguments("prepare", record), "prepare")
    built = fingerprint(built_bundle())
    generated = generated_entitlements()
    evidence.fresh_json(ARTIFACTS / "ios-photos-prepare-built-host.json",
                        {**context(record), "builtHost": built, "generatedEntitlements": generated,
                         "buildHostAndReaderClosed": True})
    host.guard_owned(record)
    host.run_command(["xcrun", "simctl", "install", record["udid"], str(built_bundle())],
                     "photos-install", 120, report_exit=True)
    installed = installed_bundle(record)
    actual = fingerprint(installed)
    evidence.fresh_json(ARTIFACTS / "ios-photos-prepare-installed-host.json",
                        {**context(record), "builtHost": built, "installedHost": actual,
                         "installedContainer": str(installed), "installHostAndReaderClosed": True,
                         "hostFingerprintMatches": same_json(actual, built)})
    require(actual == built and fingerprint(built_bundle()) == built, "photos-installed-host-mismatch")
    host.guard_owned(record)
    help_text = host.run_command(["xcrun", "simctl", "help", "privacy"], "photos-privacy-help", 60, publish=False)
    require(bool(help_text.strip()), "photos-privacy-help-empty")
    evidence.fresh_file(ARTIFACTS / "ios-photos-privacy-help.log", host.redact(help_text).encode(), host.OUTPUT_LIMIT)
    proof = {**context(record), "builtHost": built, "installedHost": actual, "installedContainer": str(installed),
             "generatedEntitlements": generated, "buildHostAndReaderClosed": True, "installHostAndReaderClosed": True}
    evidence.fresh_json(ARTIFACTS / "ios-photos-prepared.json", proof)
    host.emit("photos-result", "prepare: actual closed build/install and matching ad-hoc host recorded")
    return proof


def test_phase(record, phase):
    proof, digest = check_prepared(record)
    expected_context = {key: proof[key] for key in CONTEXT_FIELDS}
    if phase in ("authorize", "read-write"):
        check_add_only(record, proof, digest)
    if phase == "read-write":
        check_closed_phase(record, proof, digest, "authorize")
    result = ARTIFACTS / RESULT_NAMES[phase]
    require_fresh_outputs([RESULT_NAMES[phase], SUMMARY_NAMES[phase], f"ios-photos-{phase}-xcode.log",
                           f"ios-photos-{phase}-identity.json", f"ios-photos-{phase}-host-observation.json",
                           f"ios-photos-{phase}-result.json"])
    failure = None
    attempted = False
    summary_attempted = False
    observation_digest = None
    test_host_closed = False
    observer = UIPhotosAuthorization(record) if phase == "authorize" else (
        FullPhotosAuthorization(record) if phase == "read-write" else None)
    def report(event, message):
        nonlocal failure
        try:
            host.emit(event, message)
        except (Exception, KeyboardInterrupt, SystemExit):
            failure = failure or Failure("photos-diagnostic-emit-unexpected")
    try:
        # Revalidate the frozen actual host before every permission mutation.
        # Permission preparation happens between closed hosts. The full suite
        # never mutates privacy or restarts a host to recover a failed request.
        operations = [("reset", "photos"), ("grant", "photos-add")] if phase in ("add-only", "authorize") else []
        for action, service in operations:
            check_frozen(record, digest)
            host.guard_owned(record)
            host.run_command(["xcrun", "simctl", "privacy", record["udid"], action, service, host.BUNDLE_ID],
                             "photos-privacy-" + action + "-" + service, 60, report_exit=True)
        check_frozen(record, digest)
        host.guard_owned(record)
        attempted = True
        try:
            options = {"observer": observer} if observer is not None else {}
            test_host_closed = execute_xcode(arguments(phase, record, result), phase, **options) is True
        except XcodeFailure as error:
            test_host_closed = error.host_and_reader_closed is True
            raise
        require(test_host_closed, "photos-xcode-" + phase + "-close-unconfirmed")
        summary_attempted = True
        collect_summary(record, phase, result)
    except Failure as error:
        failure = error
    except (Exception, KeyboardInterrupt, SystemExit):
        failure = Failure("photos-controller-unexpected")
    finally:
        if attempted and test_host_closed:
            if not summary_attempted:
                try:
                    collect_summary(record, phase, result)
                except Failure as error:
                    failure = failure or error
                    report("photos-summary-failure", str(error))
                except (Exception, KeyboardInterrupt, SystemExit):
                    failure = failure or Failure("photos-summary-unexpected")
                    report("photos-summary-failure", "photos-summary-unexpected")
            try:
                actual, observation, identity_failure = frozen_observation(record, phase, digest, expected_context=expected_context)
                # A failed observation is still closed evidence; write it before
                # propagating its failure, and always continue owned-app stop.
                failure = failure or identity_failure
                observation_path = ARTIFACTS / f"ios-photos-{phase}-host-observation.json"
                evidence.fresh_json(observation_path, observation)
                observation_raw = evidence.read_closed_file(observation_path)
                require(same_json(evidence.strict_json(observation_raw), observation), "photos-host-observation-changed")
                observation_digest = hashlib.sha256(observation_raw).hexdigest()
                if identity_failure:
                    raise identity_failure
                evidence.fresh_json(ARTIFACTS / f"ios-photos-{phase}-identity.json",
                                    {**context(record), "phase": phase, "preparedSha256": digest,
                                     "initialInstalledContainer": actual["installedContainer"],
                                     "currentInstalledContainer": observation["currentInstalledContainer"],
                                     "builtHost": observation["builtHost"], "installedHost": observation["installedHost"],
                                     "generatedEntitlements": observation["generatedEntitlements"]})
            except Failure as error:
                failure = failure or error
                report("photos-identity-failure", str(error))
            except (Exception, KeyboardInterrupt, SystemExit):
                failure = failure or Failure("photos-identity-unexpected")
                report("photos-identity-failure", "photos-identity-unexpected")
            try:
                host.terminate_owned_app(record, None, diagnostic=True, emit_callback=report)
                report("stage", "ownedappstopped")
            except Failure as error:
                failure = failure or Failure("owned-app-stop-unconfirmed")
                report("photos-stop-failure", str(error))
            except (Exception, KeyboardInterrupt, SystemExit):
                failure = failure or Failure("owned-app-stop-unconfirmed")
                report("photos-stop-failure", "photos-stop-unexpected")
    if failure:
        raise failure
    require(type(observation_digest) is str, "photos-host-observation-required")
    summary = {**context(record), "phase": phase, "preparedSha256": digest,
               "hostObservationSha256": observation_digest,
               "xcodeExitCode": 0, "hostAndReaderClosed": True, "ownedAppStopped": True,
               "xctestPassed": EXPECTED[phase], "xctestFailed": 0, "xctestSkipped": 0}
    if phase == "authorize":
        summary["authorizationObservations"] = observer.observations
        summary["xctestSummarySha256"] = hashlib.sha256(
            evidence.read_closed_file(ARTIFACTS / SUMMARY_NAMES[phase])).hexdigest()
    evidence.fresh_json(ARTIFACTS / f"ios-photos-{phase}-result.json", summary)
    host.emit("photos-result", f"{phase}: exact XCTest {EXPECTED[phase]} passed; host IO and owned app stopped")
    return summary


def run_phase(phase):
    try:
        validate_environment(phase)
        record = host.read_owned_record()
        host.guard_owned(record)
        evidence.ordinary_path(ARTIFACTS.absolute(), directory=True)
        return prepare(record) if phase == "prepare" else test_phase(record, phase)
    except Failure:
        raise
    except (Exception, KeyboardInterrupt, SystemExit):
        raise Failure("photos-controller-unexpected") from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=sorted(PHASES), required=True)
    args = parser.parse_args()
    try:
        run_phase(args.phase)
    except Failure as error:
        host.emit("failure", str(error))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
