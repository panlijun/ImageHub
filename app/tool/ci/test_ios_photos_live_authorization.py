"""Read-only Photos protocol controls with actual bounded pipe reader threads.

Apple child processes are synthetic; these checks prove no native authorization.
"""

import json
import queue
import threading
import time
import unittest
from unittest import mock

import run_ios_photos_tests as runner
from test_ios_integration import Pipe, Process

UUID = "7a6b4f55-32e9-4c4e-96ef-2ac114643671"
RECORD = {"udid": UUID}


def ui_value(phase="ready", initial=0, **changes):
    value = {"formatVersion": 1, "phase": phase, "ownedSimulatorID": UUID,
        "mainBundleID": runner.host.BUNDLE_ID, "mainProcessID": 123,
        "photoUsageDescriptionPresent": True, "photoAddUsageDescriptionPresent": True,
        "addOnlyStatus": 3, "readWriteStatus": initial, "requestCount": 0,
        "callbackCount": 0, "callbackStatus": -1, "requestDispatched": False,
        "failureLatched": False, "callbackWithinDeadline": False,
        "testBundleID": runner.UI_BUNDLE_ID, "testProcessID": 456,
        "expectedAlertNeeded": initial == 0, "expectedAlertHandled": False}
    if phase == "confirmed":
        value.update(readWriteStatus=3, requestCount=1, callbackCount=1,
            callbackStatus=3, requestDispatched=True, callbackWithinDeadline=True,
            expectedAlertHandled=initial == 0)
    value.update(changes)
    return value


def full_value(**changes):
    value = {"phase": "preflight", "callbackStatus": -1, "failureLatched": False,
        "readBack": True, "mainBundleID": runner.host.BUNDLE_ID,
        "testBundleID": runner.host.BUNDLE_ID + ".RunnerTests",
        "hostMatchesExpected": True, "testBundleMatchesExpected": True,
        "processID": 123, "ownedSimulatorID": UUID, "addOnlyStatus": 3,
        "readWriteStatus": 3, "photoUsageDescriptionPresent": True,
        "photoAddUsageDescriptionPresent": True}
    value.update(changes)
    return value


def signal(observer, value):
    return observer.prefix + json.dumps(value)


def ui_lines(initial=0):
    return [signal(runner.UIPhotosAuthorization, ui_value(initial=initial)),
            signal(runner.UIPhotosAuthorization, ui_value("confirmed", initial=initial))]


class StreamingPipe:
    """Complete future lines and EOF are supplied by the synthetic producer."""
    def __init__(self, lines, delay=0):
        self.events = queue.Queue()
        self.closed = False
        self.delay = delay
        self.feed(lines)

    def feed(self, lines):
        for line in lines:
            self.events.put((line + "\n").encode())

    def readline(self, _limit):
        raw = self.events.get(timeout=3)
        if raw.startswith(b"slow-output-"):
            time.sleep(self.delay)
        return raw

    def close(self):
        self.closed = True


class StreamingProcess(Process):
    def __init__(self, lines, *, code=0, delay=0, final_lines=()):
        super().__init__(running=True, code=code)
        self.stdout = StreamingPipe(lines, delay)
        self.final_lines = final_lines

    def finish(self):
        if self.running:
            self.stdout.feed(self.final_lines)
            super().finish()
            self.stdout.events.put(b"")


class ProtocolTests(unittest.TestCase):
    def assert_rejected(self, kind, value, *, after_ready=False, classification=None):
        observer = kind(RECORD)
        if after_ready:
            observer.observe(signal(kind, ui_value()))
        observer.observe(signal(kind, value))
        observer.finish()
        self.assertIsNotNone(observer.failure)
        if classification:
            self.assertEqual(observer.failure, classification)
        return observer

    def test_ui_protocol_has_exact_nineteen_fields(self):
        self.assertEqual(len(ui_value()), 19)
        self.assertEqual(set(ui_value()), set(runner.UI_AUTHORIZATION_TYPES))

    def test_full_protocol_retains_exact_fourteen_fields(self):
        self.assertEqual(len(full_value()), 14)
        self.assertEqual(set(full_value()), set(runner.AUTHORIZATION_TYPES))

    def test_ui_pending_ready_and_real_callback_confirm(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        for line in ui_lines():
            observer.observe(line)
        observer.finish()
        self.assertIsNone(observer.failure)
        self.assertEqual([event["phase"] for event in observer.events], ["ready", "confirmed"])
        self.assertTrue(all(type(event["elapsedMilliseconds"]) is int for event in observer.events))

    def test_ui_already_authorized_still_requires_one_sdk_callback(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        for line in ui_lines(3):
            observer.observe(line)
        observer.finish()
        self.assertIsNone(observer.failure)
        self.assertEqual(observer.observations[1]["callbackCount"], 1)
        self.assertFalse(observer.observations[1]["expectedAlertHandled"])

    def test_ui_no_signal_or_only_ready_is_unconfirmed(self):
        for initial in (None, 0, 3):
            with self.subTest(initial=initial):
                observer = runner.UIPhotosAuthorization(RECORD)
                if initial is not None:
                    observer.observe(signal(observer, ui_value(initial=initial)))
                observer.finish()
                self.assertEqual(observer.failure, "photos-ui-sdk-request-unconfirmed")

    def test_ui_confirmed_without_ready_rejects(self):
        self.assert_rejected(runner.UIPhotosAuthorization, ui_value("confirmed"),
            classification="photos-ui-ready-invalid")

    def test_ui_ready_rejects_invalid_sdk_request_or_alert_state(self):
        changes = [{"readWriteStatus": value} for value in (-1, 1, 2, 4)] + [
            {"requestCount": 1}, {"callbackCount": 1}, {"callbackStatus": 3},
            {"requestDispatched": True}, {"callbackWithinDeadline": True},
            {"expectedAlertNeeded": False}, {"expectedAlertHandled": True},
            {"phase": "request-start"}]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(runner.UIPhotosAuthorization, ui_value(**change),
                    classification="photos-ui-ready-invalid")

    def test_ui_authorized_ready_must_not_claim_alert_needed(self):
        self.assert_rejected(runner.UIPhotosAuthorization,
            ui_value(initial=3, expectedAlertNeeded=True), classification="photos-ui-ready-invalid")

    def test_ui_confirmation_requires_one_dispatch_callback_and_deadline(self):
        changes = [{"readWriteStatus": 0}, {"requestCount": 0}, {"requestCount": 2},
            {"callbackCount": 0}, {"callbackCount": 2}, {"callbackStatus": -1},
            {"callbackStatus": 2}, {"requestDispatched": False},
            {"callbackWithinDeadline": False}, {"expectedAlertNeeded": False},
            {"expectedAlertHandled": False}, {"phase": "ready"}]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(runner.UIPhotosAuthorization, dict(ui_value("confirmed"), **change),
                    after_ready=True, classification="photos-ui-confirmation-invalid")

    def test_ui_already_authorized_without_callback_proof_rejects(self):
        for change in ({"requestCount": 0}, {"callbackCount": 0}, {"callbackStatus": -1},
                       {"requestDispatched": False}, {"expectedAlertHandled": True}):
            with self.subTest(change=change):
                observer = runner.UIPhotosAuthorization(RECORD)
                observer.observe(signal(observer, ui_value(initial=3)))
                observer.observe(signal(observer, ui_value("confirmed", initial=3, **change)))
                observer.finish()
                self.assertEqual(observer.failure, "photos-ui-confirmation-invalid")

    def test_ui_foreign_identity_and_nonpositive_pids_reject(self):
        changes = [{"formatVersion": 2}, {"ownedSimulatorID": UUID.upper()},
            {"ownedSimulatorID": "other"}, {"mainBundleID": "other"},
            {"testBundleID": runner.host.BUNDLE_ID + ".RunnerTests"},
            {"photoUsageDescriptionPresent": False}, {"photoAddUsageDescriptionPresent": False}]
        changes += [{key: value} for key in ("mainProcessID", "testProcessID") for value in (0, -1)]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(runner.UIPhotosAuthorization, ui_value(**change),
                    classification="photos-ui-identity-invalid")

    def test_ui_confirmed_foreign_identity_rejects(self):
        for change in ({"ownedSimulatorID": "other"}, {"mainBundleID": "other"},
                       {"testBundleID": "other"}):
            with self.subTest(change=change):
                self.assert_rejected(runner.UIPhotosAuthorization, ui_value("confirmed", **change),
                    after_ready=True, classification="photos-ui-identity-invalid")

    def test_ui_pid_restart_before_or_after_confirmation_latches(self):
        for key in ("mainProcessID", "testProcessID"):
            for after_confirmed in (False, True):
                with self.subTest(key=key, after_confirmed=after_confirmed):
                    observer = runner.UIPhotosAuthorization(RECORD)
                    observer.observe(ui_lines()[0])
                    if after_confirmed:
                        observer.observe(ui_lines()[1])
                    observer.observe(signal(observer, ui_value("confirmed", **{key: 999})))
                    observer.finish()
                    self.assertEqual(observer.failure, "photos-ui-pid-changed")

    def test_ui_duplicate_ready_or_confirmed_rejects(self):
        for phase in ("ready", "confirmed"):
            with self.subTest(phase=phase):
                observer = runner.UIPhotosAuthorization(RECORD)
                for line in ui_lines():
                    observer.observe(line)
                observer.observe(signal(observer, ui_value(phase)))
                observer.finish()
                self.assertEqual(observer.failure, "photos-ui-confirmation-invalid")

    def test_ui_failure_latched_or_add_only_not_authorized_reject(self):
        for phase in ("ready", "confirmed"):
            for change in ({"failureLatched": True}, {"addOnlyStatus": 0}, {"addOnlyStatus": 2}):
                with self.subTest(phase=phase, change=change):
                    self.assert_rejected(runner.UIPhotosAuthorization, ui_value(phase, **change),
                        after_ready=phase == "confirmed", classification="photos-ui-sdk-failure-latched")

    def test_failure_cannot_be_cleared_by_later_valid_snapshots(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        observer.observe(signal(observer, ui_value(mainBundleID="foreign")))
        first_failure = observer.failure
        for line in ui_lines():
            observer.observe(line)
        observer.finish()
        self.assertEqual(observer.failure, first_failure)
        self.assertEqual(len(observer.observations), 2)

    def test_all_fields_use_exact_types_without_bool_int_coercion(self):
        wrong_types = {int: (True, False, 1.0, "1", None),
                       bool: (0, 1, "true", None), str: (1, False, None)}
        for kind, template in ((runner.UIPhotosAuthorization, ui_value()),
                               (runner.FullPhotosAuthorization, full_value())):
            for key, expected in kind.types.items():
                for wrong in wrong_types[expected]:
                    with self.subTest(kind=kind.__name__, key=key, wrong=wrong):
                        value = dict(template, **{key: wrong})
                        self.assert_rejected(kind, value,
                            classification=kind.classification + "-signal-invalid")

    def test_each_missing_field_or_extra_field_rejects(self):
        for kind, template in ((runner.UIPhotosAuthorization, ui_value()),
                               (runner.FullPhotosAuthorization, full_value())):
            for key in template:
                with self.subTest(kind=kind.__name__, missing=key):
                    value = dict(template)
                    del value[key]
                    self.assert_rejected(kind, value,
                        classification=kind.classification + "-signal-invalid")
            self.assert_rejected(kind, dict(template, extra=True),
                classification=kind.classification + "-signal-invalid")

    def test_each_duplicate_json_field_rejects(self):
        for kind, template in ((runner.UIPhotosAuthorization, ui_value()),
                               (runner.FullPhotosAuthorization, full_value())):
            for key, value in template.items():
                with self.subTest(kind=kind.__name__, key=key):
                    observer = kind(RECORD)
                    raw = json.dumps(template)[:-1] + "," + json.dumps(key) + ":" + json.dumps(value) + "}"
                    observer.observe(kind.prefix + raw)
                    observer.finish()
                    self.assertIsNotNone(observer.failure)
                    self.assertEqual(observer.observations, [])

    def test_malformed_strict_json_or_prefix_rejects(self):
        for kind in (runner.UIPhotosAuthorization, runner.FullPhotosAuthorization):
            for raw in ("{} trailing", "{}", "[]", "null", "{", '{"phase": NaN}',
                        '{"phase": Infinity}', '{"phase": -Infinity}'):
                with self.subTest(kind=kind.__name__, raw=raw):
                    observer = kind(RECORD)
                    observer.observe(kind.prefix + raw)
                    observer.finish()
                    self.assertIsNotNone(observer.failure)
            observer = kind(RECORD)
            observer.observe(kind.prefix.rstrip() + "{}")
            self.assertEqual(observer.failure, kind.classification + "-signal-invalid")

    def test_unrelated_log_lines_are_ignored(self):
        for kind in (runner.UIPhotosAuthorization, runner.FullPhotosAuthorization):
            observer = kind(RECORD)
            observer.observe("ordinary diagnostic")
            self.assertIsNone(observer.failure)
            self.assertEqual(observer.observations, [])

    def test_full_requires_exactly_five_readback_preflights(self):
        for count in (0, 1, 4, 5, 6):
            with self.subTest(count=count):
                observer = runner.FullPhotosAuthorization(RECORD)
                for _ in range(count):
                    observer.observe(signal(observer, full_value()))
                observer.finish()
                self.assertEqual(observer.failure,
                    None if count == 5 else "photos-full-five-readback-preflights-required")

    def test_full_nonreadback_preflights_do_not_count_as_resource_proofs(self):
        observer = runner.FullPhotosAuthorization(RECORD)
        for index in range(15):
            observer.observe(signal(observer, full_value(readBack=index < 5)))
        observer.finish()
        self.assertIsNone(observer.failure)
        self.assertEqual(len(observer.observations), 15)

    def test_full_foreign_identity_or_missing_identity_boolean_rejects(self):
        changes = [{"ownedSimulatorID": UUID.upper()}, {"mainBundleID": "other"},
            {"testBundleID": runner.UI_BUNDLE_ID}, {"processID": 0}, {"processID": -1}]
        changes += [{key: False} for key in ("hostMatchesExpected", "testBundleMatchesExpected",
            "photoUsageDescriptionPresent", "photoAddUsageDescriptionPresent")]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(runner.FullPhotosAuthorization, full_value(**change),
                    classification="photos-full-identity-invalid")

    def test_full_rejects_any_request_phase_callback_or_unauthorized_sdk(self):
        changes = [{"phase": phase} for phase in ("request-start", "request-dispatched",
            "request-callback", "request-confirmed", "request-timeout", "unknown")]
        changes += [{"callbackStatus": 3}, {"failureLatched": True},
            {"addOnlyStatus": 0}, {"readWriteStatus": 0}, {"readWriteStatus": 2}]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(runner.FullPhotosAuthorization, full_value(**change),
                    classification="photos-full-preauthorized-sdk-required")

    def test_full_pid_restart_after_five_proofs_latches(self):
        observer = runner.FullPhotosAuthorization(RECORD)
        for _ in range(5):
            observer.observe(signal(observer, full_value()))
        observer.observe(signal(observer, full_value(processID=124, readBack=False)))
        observer.finish()
        self.assertEqual(observer.failure, "photos-full-host-pid-changed")

    def test_full_late_failure_cannot_be_cleared_by_five_valid_proofs(self):
        observer = runner.FullPhotosAuthorization(RECORD)
        for _ in range(5):
            observer.observe(signal(observer, full_value()))
        observer.observe(signal(observer, full_value(failureLatched=True)))
        observer.finish()
        self.assertEqual(observer.failure, "photos-full-preauthorized-sdk-required")

    def test_unknown_observer_error_is_fixed_and_never_stringified(self):
        class Unsafe(Exception):
            def __str__(self):
                raise AssertionError("Unknown exception must not be exposed")
        observer = runner.UIPhotosAuthorization(RECORD)
        with mock.patch.object(observer, "validate", side_effect=Unsafe()):
            observer.observe(ui_lines()[0])
        self.assertEqual(observer.failure, "photos-ui-observer-unexpected")


class PipeTests(unittest.TestCase):
    def run_process(self, process, observer, *, failure=None, short=False, timeout=0.2):
        logs = []
        commands = []
        real_running = runner.host.Running
        def start(*args, **options):
            command = real_running(*args, **options)
            commands.append(command)
            return command
        with mock.patch.object(runner.host.subprocess, "Popen", return_value=process), \
                mock.patch.object(runner.host, "Running", side_effect=start), \
                mock.patch.object(runner.host, "run_command") as mutation, \
                mock.patch.object(runner.host, "guard_owned") as guard, \
                mock.patch.object(runner, "frozen_observation") as frozen, \
                mock.patch.object(runner, "TIMEOUT", timeout), \
                mock.patch.object(runner.host, "CLOSE_TIMEOUT", 0.03 if short else 2), \
                mock.patch.object(runner.evidence, "fresh_file", side_effect=lambda _path, raw, _limit: logs.append(raw)), \
                mock.patch.object(runner.host, "emit"):
            if failure is None:
                self.assertTrue(runner.execute_xcode(["synthetic"], "ui-authorization", observer=observer))
                result = None
            else:
                with self.assertRaises(runner.XcodeFailure) as caught:
                    runner.execute_xcode(["synthetic"], "ui-authorization", observer=observer)
                result = caught.exception
                self.assertEqual(str(result), failure)
            mutation.assert_not_called()
            guard.assert_not_called()
            frozen.assert_not_called()
        self.assertEqual(len(logs), 1)
        log = logs[0].decode()
        header = json.loads(log.splitlines()[0])
        self.assertEqual(header["hostAndReaderClosed"], not short)
        if result is not None:
            self.assertEqual(result.host_and_reader_closed, not short)
            self.assertEqual(header["failure"], failure)
        else:
            self.assertIsNone(header["failure"])
        if not short:
            self.assertTrue(process.stdout.closed and process.waited)
            self.assertTrue(commands[0].closed())
            self.assertFalse(commands[0].reader.thread.is_alive())
        return result, header, log, commands[0]

    def test_pending_ui_ready_confirmed_are_observed_from_actual_pipe(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        self.run_process(Process(("\n".join(ui_lines()) + "\n").encode()), observer)
        self.assertEqual(len(observer.observations), 2)

    def test_initial_authorized_still_observes_callback_from_actual_pipe(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        self.run_process(Process(("\n".join(ui_lines(3)) + "\n").encode()), observer)
        self.assertEqual(observer.observations[1]["callbackStatus"], 3)

    def test_full_five_preflights_are_observed_from_actual_pipe(self):
        observer = runner.FullPhotosAuthorization(RECORD)
        lines = [signal(observer, full_value())] * 5
        self.run_process(Process(("\n".join(lines) + "\n").encode()), observer)
        self.assertEqual(len(observer.observations), 5)

    def test_ui_missing_callback_in_real_pipe_refuses_success(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        self.run_process(Process((ui_lines(3)[0] + "\n").encode()), observer,
            failure="photos-ui-sdk-request-unconfirmed")

    def test_actual_nonzero_xcode_exit_with_callback_proof_still_fails(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        _, header, _, _ = self.run_process(Process(("\n".join(ui_lines()) + "\n").encode(), code=9),
            observer, failure="photos-xcode-ui-authorization-exit-nonzero")
        self.assertEqual(header["exitCode"], 9)
        self.assertIsNone(observer.failure)

    def test_nonzero_xcode_slow_hundred_line_reader_closes_and_keeps_failure(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        lines = ["slow-output-" + str(index) for index in range(100)]
        process = StreamingProcess(lines + ui_lines(), code=9, delay=0.002)
        process.finish()
        _, header, log, _ = self.run_process(process, observer,
            failure="photos-xcode-ui-authorization-exit-nonzero", timeout=2)
        self.assertEqual(header["exitCode"], 9)
        for line in lines + ui_lines():
            self.assertEqual(log.splitlines().count(line), 1)
        self.assertEqual(len(observer.observations), 2)

    def test_timeout_final_drain_collects_hundred_slow_lines_and_preserves_failure(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        lines = ["slow-output-" + str(index) for index in range(100)]
        process = StreamingProcess([ui_lines()[0]], delay=0.002,
            final_lines=lines + [ui_lines()[1]])
        _, _, log, _ = self.run_process(process, observer,
            failure="photos-xcode-ui-authorization-timeout", timeout=0.03)
        self.assertTrue(process.terminated)
        for line in lines + ui_lines():
            self.assertEqual(log.splitlines().count(line), 1)
        self.assertEqual(len(observer.observations), 2)
        self.assertIsNone(observer.failure)

    def test_invalid_observer_then_valid_final_drain_cannot_clear_failure(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        invalid = signal(observer, ui_value(mainBundleID="foreign"))
        process = StreamingProcess([invalid], final_lines=ui_lines())
        _, _, log, _ = self.run_process(process, observer, failure="photos-ui-identity-invalid")
        self.assertEqual(observer.failure, "photos-ui-identity-invalid")
        self.assertEqual(len(observer.observations), 2)
        for line in [invalid] + ui_lines():
            self.assertEqual(log.splitlines().count(line), 1)

    def test_late_final_drain_ui_failure_is_validated_and_latched(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        late = signal(observer, ui_value("confirmed", failureLatched=True))
        process = StreamingProcess(ui_lines(), final_lines=[late])
        self.run_process(process, observer, failure="photos-xcode-ui-authorization-timeout", timeout=0.03)
        self.assertEqual(observer.failure, "photos-ui-sdk-failure-latched")

    def test_late_final_drain_full_pid_restart_is_validated(self):
        observer = runner.FullPhotosAuthorization(RECORD)
        process = StreamingProcess([signal(observer, full_value())] * 5,
            final_lines=[signal(observer, full_value(processID=999, readBack=False))])
        self.run_process(process, observer, failure="photos-xcode-ui-authorization-timeout", timeout=0.03)
        self.assertEqual(observer.failure, "photos-full-host-pid-changed")

    def test_final_drain_cannot_hide_duplicate_confirmation(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        lines = ui_lines() + ["ordinary-output"] * 40 + [ui_lines()[1]]
        self.run_process(Process(("\n".join(lines) + "\n").encode()), observer,
            failure="photos-ui-confirmation-invalid")

    def test_incomplete_confirmation_is_collected_but_never_observed(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        lines = ui_lines()
        _, _, log, _ = self.run_process(Process(("\n".join(lines)).encode()), observer,
            failure="photos-ui-sdk-request-unconfirmed")
        self.assertEqual(len(observer.observations), 1)
        self.assertIn(lines[1], log)

    def test_incomplete_only_signal_is_not_sdk_proof(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        _, _, log, _ = self.run_process(Process(ui_lines()[0].encode()), observer,
            failure="photos-ui-sdk-request-unconfirmed")
        self.assertEqual(observer.observations, [])
        self.assertIn(ui_lines()[0], log)

    def test_complete_failure_signal_is_observed_but_incomplete_one_is_not(self):
        for complete in (False, True):
            with self.subTest(complete=complete):
                observer = runner.UIPhotosAuthorization(RECORD)
                bad = signal(observer, ui_value("confirmed", failureLatched=True))
                raw = "\n".join(ui_lines()) + "\n" + bad + ("\n" if complete else "")
                self.run_process(Process(raw.encode()), observer,
                    failure="photos-ui-sdk-failure-latched" if complete else None)
                self.assertEqual(observer.failure, "photos-ui-sdk-failure-latched" if complete else None)

    def test_blocked_real_reader_close_is_bounded_and_never_success(self):
        gate = threading.Event()
        process = Process()
        process.stdout = Pipe(("\n".join(ui_lines()) + "\n").encode(), gate)
        observer = runner.UIPhotosAuthorization(RECORD)
        command = None
        started = time.monotonic()
        try:
            _, header, _, command = self.run_process(process, observer,
                failure="photos-xcode-ui-authorization-close-unconfirmed", short=True, timeout=0.03)
            self.assertLess(time.monotonic() - started, 2)
            self.assertFalse(header["hostAndReaderClosed"])
            self.assertTrue(command.reader.thread.is_alive())
            self.assertFalse(process.waited)
        finally:
            gate.set()
            if command is not None:
                command.reader.thread.join(timeout=2)
                self.assertFalse(command.reader.thread.is_alive())

    def test_blocked_reader_preserves_observer_failure_and_close_uncertainty(self):
        gate = threading.Event()
        process = Process()
        process.stdout = Pipe((signal(runner.UIPhotosAuthorization,
            ui_value(mainBundleID="foreign")) + "\n").encode(), gate)
        observer = runner.UIPhotosAuthorization(RECORD)
        command = None
        try:
            _, _, _, command = self.run_process(process, observer,
                failure="photos-xcode-ui-authorization-close-unconfirmed", short=True)
            self.assertEqual(observer.failure, "photos-ui-identity-invalid")
        finally:
            gate.set()
            if command is not None:
                command.reader.thread.join(timeout=2)
                self.assertFalse(command.reader.thread.is_alive())

    def test_companion_nested_command_drain_is_read_only_and_keeps_late_failure(self):
        observer = runner.UIPhotosAuthorization(RECORD)
        process = StreamingProcess(ui_lines())
        nested = Process(running=True)
        real_terminate = nested.terminate
        late = signal(observer, ui_value("confirmed", mainProcessID=999))
        def terminate():
            process.stdout.feed([late])
            real_terminate()
        nested.terminate = terminate
        with mock.patch.object(runner.host.subprocess, "Popen", side_effect=[process, nested]), \
                mock.patch.object(runner.host, "CLOSE_TIMEOUT", 2), \
                mock.patch.object(runner.host, "run_command") as mutation:
            xcode = runner.host.Running(["synthetic"], "synthetic-xcode", publish=False)
            child = runner.host.Running(["synthetic"], "synthetic-child", publish=False)
            lines = []
            companion = runner.PhotosCompanion(xcode, lines, observer)
            try:
                runner.host.close_host(child, companion=companion)
                deadline = time.monotonic() + 2
                while observer.failure is None and time.monotonic() < deadline:
                    companion.drain()
                    time.sleep(0.001)
                self.assertEqual(companion.failure, "photos-ui-pid-changed")
                self.assertTrue(child.closed() and nested.waited and nested.stdout.closed)
                mutation.assert_not_called()
            finally:
                process.finish()
                runner.host.close_host(xcode, companion=companion)
                self.assertTrue(xcode.closed() and process.waited and process.stdout.closed)
            self.assertEqual(lines, ui_lines() + [late])


if __name__ == "__main__":
    unittest.main()
