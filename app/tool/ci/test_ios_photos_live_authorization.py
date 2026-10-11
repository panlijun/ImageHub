"""Live Photos control boundaries with synthetic protocols and actual pipe readers.

No test executes Apple commands or counts as native authorization evidence.
"""

import json
import queue
import threading
import time
import unittest
from unittest import mock

import run_ios_photos_tests as runner
from test_ios_integration import Process

UUID = "7a6b4f55-32e9-4c4e-96ef-2ac114643671"


def signal(phase="preflight", **changes):
    value = {"phase": phase, "callbackStatus": -1, "failureLatched": False, "readBack": True,
        "mainBundleID": runner.host.BUNDLE_ID, "testBundleID": runner.host.BUNDLE_ID + ".RunnerTests",
        "hostMatchesExpected": True, "testBundleMatchesExpected": True, "processID": 123,
        "ownedSimulatorID": UUID, "addOnlyStatus": 3, "readWriteStatus": 0,
        "photoUsageDescriptionPresent": True, "photoAddUsageDescriptionPresent": True}
    value.update(changes)
    return runner.AUTHORIZATION_PREFIX + json.dumps(value)


class StreamingPipe:
    """Producer releases future complete lines; EOF waits for real mock exit."""
    def __init__(self, lines):
        self.events = queue.Queue()
        self.closed = False
        self.feed(lines)

    def feed(self, lines):
        for line in lines:
            self.events.put((line + "\n").encode())

    def readline(self, _limit):
        return self.events.get(timeout=3)

    def close(self):
        self.closed = True


class StreamingProcess(Process):
    def __init__(self, lines):
        super().__init__(running=True)
        self.stdout = StreamingPipe(lines)

    def finish(self):
        super().finish()
        self.stdout.events.put(b"")


class LiveTests(unittest.TestCase):
    def setUp(self):
        self.live = runner.LivePhotosAuthorization({"udid": UUID}, "frozen-digest", {})
        self.companion = mock.Mock()
        self.companion.command.process.poll.return_value = None
        self.companion.command.failure = None
        self.guard = mock.patch.object(runner.host, "guard_owned").start()
        self.frozen = mock.patch.object(runner, "frozen_observation",
            return_value=({}, {"allFrozenFieldsVerified": True}, None)).start()
        self.command = mock.patch.object(runner.host, "run_command").start()
        self.addCleanup(mock.patch.stopall)

    def request(self):
        self.live.observe(signal())
        self.live.observe(signal("request-start"))
        self.live.observe(signal("request-dispatched"))

    def confirm(self):
        self.live.observe(signal("request-callback", callbackStatus=3, readWriteStatus=3))
        self.live.observe(signal("request-confirmed", callbackStatus=3, readWriteStatus=3))

    def test_valid_signal_act_once_exact_owned_command_and_confirm(self):
        self.request()
        self.live.act(self.companion)
        self.live.act(self.companion)
        self.command.assert_called_once()
        self.assertEqual(self.command.call_args.args[0],
            ["xcrun", "simctl", "privacy", UUID, "grant", "photos", runner.host.BUNDLE_ID])
        self.assertIs(self.command.call_args.kwargs["companion"], self.companion)
        self.assertTrue(self.command.call_args.kwargs["report_exit"])
        self.assertTrue(all(call.kwargs["companion"] is self.companion for call in self.guard.call_args_list))
        self.assertIs(self.frozen.call_args.kwargs["companion"], self.companion)
        self.confirm()
        self.live.finish()
        self.assertIsNone(self.live.failure)
        self.assertTrue(all(type(event["elapsedMilliseconds"]) is int for event in self.live.events))

    def test_bool_int_and_exact_fields_reject(self):
        mutations = [{"processID": True}, {"callbackStatus": False}, {"readWriteStatus": False},
            {"addOnlyStatus": True}, {"readBack": 1}, {"failureLatched": 0},
            {"photoUsageDescriptionPresent": 1}, {"extra": True}]
        for change in mutations:
            with self.subTest(change=change):
                live = runner.LivePhotosAuthorization({"udid": UUID}, "digest", {})
                live.observe(signal("request-dispatched", **change))
                self.assertIsNotNone(live.failure)
                live.act(self.companion)
        self.command.assert_not_called()

    def test_malformed_unknown_phase_and_foreign_identity_reject(self):
        for line in (runner.AUTHORIZATION_PREFIX + "{} trailing", runner.AUTHORIZATION_PREFIX + "{}",
                     signal("unknown"), signal(ownedSimulatorID=UUID.upper()), signal(processID=0),
                     signal(mainBundleID="other"), signal(testBundleMatchesExpected=False),
                     signal(photoAddUsageDescriptionPresent=False)):
            with self.subTest(line=line):
                live = runner.LivePhotosAuthorization({"udid": UUID}, "digest", {})
                live.observe(line)
                self.assertIsNotNone(live.failure)

    def test_duplicate_json_field_rejects(self):
        self.live.observe(signal().replace('"phase": "preflight"', '"phase": "preflight", "phase": "preflight"'))
        self.assertIsNotNone(self.live.failure)

    def test_request_dispatched_without_start_rejects(self):
        self.live.observe(signal("request-dispatched"))
        self.assertIsNotNone(self.live.failure)

    def test_start_alone_does_not_act(self):
        self.live.observe(signal("request-start"))
        self.live.act(self.companion)
        self.command.assert_not_called()

    def test_pid_change_is_latched_after_success(self):
        self.request()
        self.confirm()
        self.live.observe(signal(processID=124, readWriteStatus=3))
        self.live.finish()
        self.assertEqual(self.live.failure, "photos-live-host-pid-changed")

    def test_second_start_or_dispatched_is_latched(self):
        for phase in ("request-start", "request-dispatched"):
            with self.subTest(phase=phase):
                self.setUp_live()
                self.request()
                self.live.observe(signal(phase))
                self.assertEqual(self.live.failure, "photos-live-second-or-invalid-request")

    def setUp_live(self):
        self.live = runner.LivePhotosAuthorization({"udid": UUID}, "frozen-digest", {})

    def test_callback_before_grant_suppresses_action(self):
        self.request()
        self.confirm()
        self.live.act(self.companion)
        self.command.assert_not_called()
        self.live.finish()
        self.assertIsNone(self.live.failure)

    def test_callback_before_dispatched_can_close_without_action(self):
        self.live.observe(signal("request-start"))
        self.live.observe(signal("request-callback", callbackStatus=3, readWriteStatus=3))
        self.live.observe(signal("request-dispatched", readWriteStatus=3))
        self.live.observe(signal("request-confirmed", callbackStatus=3, readWriteStatus=3))
        self.live.act(self.companion)
        self.command.assert_not_called()
        self.assertIsNone(self.live.failure)

    def test_dispatched_authorized_before_callback_can_confirm_without_grant(self):
        self.live.observe(signal("request-start"))
        self.live.observe(signal("request-dispatched", readWriteStatus=3))
        self.live.act(self.companion)
        self.assertEqual(self.live.dispatched_read_write_status, 3)
        self.confirm()
        self.live.finish()
        self.assertIsNone(self.live.failure)
        self.command.assert_not_called()

    def test_dispatched_authorized_without_callback_deadline_or_finish_fails_without_grant(self):
        for deadline in (False, True):
            with self.subTest(deadline=deadline):
                self.setUp_live()
                self.live.observe(signal("request-start"))
                self.live.observe(signal("request-dispatched", readWriteStatus=3))
                if deadline:
                    self.live.dispatched_at -= 30
                self.live.act(self.companion)
                self.live.finish()
                self.assertEqual(self.live.failure, "photos-live-request-deadline" if deadline else
                                 "photos-live-sdk-request-unconfirmed")
        self.command.assert_not_called()

    def test_timeout_or_wait_failed_or_rejected_before_action(self):
        for phase in ("request-timeout", "request-wait-failed", "request-rejected"):
            with self.subTest(phase=phase):
                self.setUp_live()
                self.request()
                self.live.observe(signal(phase, failureLatched=True))
                self.live.act(self.companion)
                self.assertIsNotNone(self.live.failure)
        self.command.assert_not_called()

    def test_callback_or_timeout_during_frozen_validation_suppresses_grant(self):
        for close in (self.confirm, lambda: self.live.observe(signal("request-timeout", failureLatched=True))):
            with self.subTest(close=close):
                self.setUp_live()
                self.request()
                def freeze(*args, **kwargs):
                    close()
                    return {}, {"allFrozenFieldsVerified": True}, None
                self.frozen.side_effect = freeze
                self.live.act(self.companion)
                self.live.act(self.companion)
        self.command.assert_not_called()

    def test_thirty_second_deadline_before_or_during_validation(self):
        for during in (False, True):
            with self.subTest(during=during):
                self.setUp_live()
                self.request()
                if during:
                    def freeze(*args, **kwargs):
                        self.live.dispatched_at -= 30
                        return {}, {"allFrozenFieldsVerified": True}, None
                    self.frozen.side_effect = freeze
                else:
                    self.live.dispatched_at -= 30
                self.live.act(self.companion)
                self.assertEqual(self.live.failure, "photos-live-request-deadline")
        self.command.assert_not_called()

    def test_guard_fingerprint_and_unconfirmed_freeze_failure_latch(self):
        for source, failure in ((self.guard, runner.Failure("ownership-invalid")),
                                (self.frozen, runner.Failure("photos-host-changed"))):
            with self.subTest(source=source):
                self.setUp_live()
                self.request()
                source.side_effect = failure
                self.live.act(self.companion)
                self.assertEqual(self.live.failure, str(failure))
                source.side_effect = None
        self.setUp_live()
        self.request()
        self.frozen.return_value = {}, {"allFrozenFieldsVerified": False}, None
        self.live.act(self.companion)
        self.assertEqual(self.live.failure, "photos-live-frozen-unconfirmed")
        self.command.assert_not_called()

    def test_grant_exit_failure_or_close_unconfirmed_never_reenter(self):
        for classification in ("photos-live-privacy-grant-exit-nonzero", "photos-live-privacy-grant-close-unconfirmed"):
            with self.subTest(classification=classification):
                self.setUp_live()
                self.request()
                self.command.reset_mock()
                self.command.side_effect = runner.Failure(classification)
                self.live.act(self.companion)
                self.live.act(self.companion)
                self.confirm()
                self.assertEqual(self.live.failure, classification)
                self.command.assert_called_once()

    def test_xcode_exit_during_freeze_refuses_grant(self):
        self.request()
        self.companion.command.process.poll.return_value = 0
        self.live.act(self.companion)
        self.assertEqual(self.live.failure, "photos-live-xcode-ended-before-grant")
        self.command.assert_not_called()

    def test_grant_zero_without_callback_stays_unconfirmed(self):
        self.request()
        self.live.act(self.companion)
        self.live.finish()
        self.assertEqual(self.live.failure, "photos-live-sdk-request-unconfirmed")

    def test_late_callback_during_blocking_work_cannot_clear_deadline(self):
        self.request()
        def grant(*args, **kwargs):
            self.live.dispatched_at -= 30
            self.confirm()
        self.command.side_effect = grant
        self.live.act(self.companion)
        self.live.finish()
        self.assertEqual(self.live.failure, "photos-live-request-deadline")

    def test_old_start_does_not_shorten_new_dispatched_wait(self):
        self.live.observe(signal("request-start"))
        self.live.started -= 31
        self.live.observe(signal("request-dispatched"))
        self.live.act(self.companion)
        self.command.assert_called_once()
        self.confirm()
        self.live.finish()
        self.assertIsNone(self.live.failure)

    def test_unknown_error_never_stringified(self):
        class Unsafe(Exception):
            def __str__(self):
                raise AssertionError("Do not stringify unknown errors")
        self.request()
        self.frozen.side_effect = Unsafe()
        self.live.act(self.companion)
        self.assertEqual(self.live.failure, "photos-live-control-unexpected")

    def test_no_signal_or_already_authorized_preserves_original_path(self):
        self.live.act(self.companion)
        self.live.observe(signal(readWriteStatus=3))
        self.live.act(self.companion)
        self.live.finish()
        self.command.assert_not_called()
        self.assertIsNone(self.live.failure)


class PipeTests(unittest.TestCase):
    def test_callback_or_timeout_arriving_during_nested_command_close_suppresses_grant(self):
        for succeeds in (True, False):
            with self.subTest(succeeds=succeeds):
                live = runner.LivePhotosAuthorization({"udid": UUID}, "digest", {})
                process = StreamingProcess([signal("request-start"), signal("request-dispatched")])
                nested = Process(running=True)
                real_terminate = nested.terminate
                def terminate():
                    if succeeds:
                        process.stdout.feed([signal("request-callback", callbackStatus=3, readWriteStatus=3),
                                            signal("request-confirmed", callbackStatus=3, readWriteStatus=3)])
                    else:
                        process.stdout.feed([signal("request-timeout", failureLatched=True)])
                    real_terminate()
                nested.terminate = terminate
                with mock.patch.object(runner.host.subprocess, "Popen", side_effect=[process, nested]):
                    xcode = runner.host.Running(["synthetic"], "synthetic-xcode", publish=False)
                    child = runner.host.Running(["synthetic"], "synthetic-guard", publish=False)
                companion = runner.PhotosCompanion(xcode, [], live)
                def freeze(*args, **options):
                    runner.host.close_host(child, companion=options["companion"])
                    return {}, {"allFrozenFieldsVerified": True}, None
                with mock.patch.object(runner.host, "guard_owned"), \
                        mock.patch.object(runner, "frozen_observation", side_effect=freeze), \
                        mock.patch.object(runner.host, "run_command") as grant:
                    try:
                        deadline = time.monotonic() + 1
                        while not live.dispatched and time.monotonic() < deadline:
                            companion.drain()
                            time.sleep(0.001)
                        self.assertTrue(live.dispatched)
                        live.act(companion)
                        self.assertTrue(live.confirmed if succeeds else live.failure is not None)
                        grant.assert_not_called()
                        self.assertTrue(nested.stdout.closed and nested.waited)
                    finally:
                        process.finish()
                        deadline = time.monotonic() + 1
                        while not xcode.closed() and time.monotonic() < deadline:
                            companion.drain()
                            xcode.reader.thread.join(timeout=0.01)
                        companion.drain()
                        self.assertTrue(xcode.closed())

    def run_stream(self, *, malformed=False, grant_code=0, grant_close_uncertain=False):
        live = runner.LivePhotosAuthorization({"udid": UUID}, "digest", {})
        first = signal("unknown") if malformed else signal("request-start")
        process = StreamingProcess([first, signal("request-dispatched")])
        granted = Process(code=grant_code)
        if grant_close_uncertain:
            gate = threading.Event()
            from test_ios_integration import Pipe
            granted.stdout = Pipe(b"", gate)
        lines = ["during-command-" + str(i) for i in range(100)]
        real_command = runner.host.run_command
        real_running = runner.host.Running
        running = []
        def start(*args, **kwargs):
            command = real_running(*args, **kwargs)
            running.append(command)
            return command
        def grant(args, *positional, **options):
            process.stdout.feed(lines + [signal("request-callback", callbackStatus=3, readWriteStatus=3),
                                        signal("request-confirmed", callbackStatus=3, readWriteStatus=3)])
            if not grant_close_uncertain:
                process.finish()
            return real_command(args, *positional, **options)
        logs = []
        with mock.patch.object(runner.host.subprocess, "Popen", side_effect=[process, granted]), \
                mock.patch.object(runner.host, "Running", side_effect=start), \
                mock.patch.object(runner.host, "guard_owned", side_effect=lambda record, **kw: kw["companion"].drain()), \
                mock.patch.object(runner, "frozen_observation", return_value=({}, {"allFrozenFieldsVerified": True}, None)), \
                mock.patch.object(runner.host, "run_command", side_effect=grant) as command, \
                mock.patch.object(runner, "TIMEOUT", 0.5), mock.patch.object(runner.host, "CLOSE_TIMEOUT", 0.03), \
                mock.patch.object(runner.evidence, "fresh_file", side_effect=lambda _path, raw, _limit: logs.append(raw)), \
                mock.patch.object(runner.host, "emit"):
            try:
                if malformed or grant_code or grant_close_uncertain:
                    with self.assertRaises(runner.XcodeFailure) as result:
                        runner.execute_xcode(["synthetic"], "read-write", live=live)
                    self.assertTrue(result.exception.host_and_reader_closed)
                else:
                    self.assertTrue(runner.execute_xcode(["synthetic"], "read-write", live=live))
            finally:
                if grant_close_uncertain:
                    gate.set()
                    for child in running:
                        child.reader.thread.join(timeout=1)
        return live, process, granted, command.call_count, logs[0].decode(), lines

    def test_blocking_command_and_real_close_drain_all_xcode_lines(self):
        live, process, grant, calls, log, lines = self.run_stream()
        self.assertEqual(calls, 1)
        self.assertTrue(process.stdout.closed and process.waited and grant.stdout.closed and grant.waited)
        for line in lines:
            self.assertEqual(log.splitlines().count(line), 1)
        self.assertTrue(live.confirmed)
        header = json.loads(log.splitlines()[0])
        self.assertIsNone(header["failure"])
        self.assertTrue(any(event["phase"] == "grant-command-close" for event in header["liveAuthorizationControl"]))

    def test_grant_actual_nonzero_even_callback_and_confirm_never_success(self):
        live, process, grant, calls, log, _ = self.run_stream(grant_code=9)
        self.assertEqual(calls, 1)
        self.assertEqual(live.failure, "photos-live-privacy-grant-exit-nonzero")
        self.assertTrue(process.stdout.closed and grant.stdout.closed)
        self.assertIn("exitCode=9; hostAndReaderClosed=true", log)

    def test_command_real_reader_close_uncertainty_stays_failure(self):
        live, process, _, calls, _, _ = self.run_stream(grant_close_uncertain=True)
        self.assertEqual(calls, 1)
        self.assertEqual(live.failure, "photos-live-privacy-grant-close-unconfirmed")
        self.assertTrue(process.stdout.closed and process.waited)

    def test_observer_failure_does_not_lose_final_lines_or_mutate(self):
        live, process, _, calls, log, _ = self.run_stream(malformed=True)
        self.assertEqual(calls, 0)
        self.assertTrue(process.stdout.closed and process.waited)
        self.assertIn(signal("request-dispatched"), log)
        self.assertEqual(live.failure, "photos-live-phase-invalid")

    def test_incomplete_signal_is_collected_but_never_observed(self):
        process = Process(signal("request-dispatched").encode())
        live = runner.LivePhotosAuthorization({"udid": UUID}, "digest", {})
        lines = []
        with mock.patch.object(runner.host.subprocess, "Popen", return_value=process):
            command = runner.host.Running(["synthetic"], "synthetic", publish=False)
            companion = runner.PhotosCompanion(command, lines, live)
            command.reader.thread.join(timeout=1)
            companion.drain()
            self.assertTrue(command.closed())
        self.assertEqual(lines, [signal("request-dispatched")])
        self.assertIsNone(live.started)
        self.assertIsNone(live.failure)

    def test_final_drain_only_request_signal_cannot_trigger_mutation(self):
        live = runner.LivePhotosAuthorization({"udid": UUID}, "digest", {})
        command = mock.Mock()
        command.failure = None
        command.process.poll.return_value = 0
        command.process.wait.return_value = 0
        command.closed.return_value = True
        calls = []
        def drain(callback=None, collect=None):
            calls.append(True)
            if len(calls) == 2:
                for line in (signal("request-start"), signal("request-dispatched")):
                    collect.append(line)
                    callback(line)
        command.drain.side_effect = drain
        with mock.patch.object(runner.host, "Running", return_value=command), \
                mock.patch.object(runner.host, "run_command") as mutation, \
                mock.patch.object(runner.evidence, "fresh_file"), mock.patch.object(runner.host, "emit"):
            with self.assertRaisesRegex(runner.XcodeFailure, "photos-live-sdk-request-unconfirmed"):
                runner.execute_xcode(["synthetic"], "read-write", live=live)
            mutation.assert_not_called()
        self.assertTrue(live.dispatched)


if __name__ == "__main__":
    unittest.main()
