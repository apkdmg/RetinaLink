#!/usr/bin/env python3
"""Offline tests for forced-command policy and console-state interpretation."""
import ast
from pathlib import Path
import re
import unittest

source = (Path(__file__).resolve().parents[1] / 'Tools/dedicated_display_diagnostics.sh').read_text()
embedded = source.split("<<'PY'\n", 1)[1].split('\nPY\n', 1)[0]
tree = ast.parse(embedded)
functions = [node for node in tree.body if isinstance(node, ast.FunctionDef)
             and node.name in {'lock_policy', 'console_session', 'wake_display'}]
namespace = {'re': re}
exec(compile(ast.fix_missing_locations(ast.Module(body=functions, type_ignores=[])),
             'dedicated-diagnostic-parsers', 'exec'), namespace)
lock_policy = namespace['lock_policy']
console_session = namespace['console_session']
wake_display = namespace['wake_display']


class EffectiveLockTests(unittest.TestCase):
    def test_known_formats(self):
        for text, expected in [('screenLock is off', 'disabled'),
                               ('screenLock delay is immediate', 'password-required'),
                               ('screenLock delay is 0 seconds', 'password-required'),
                               ('screenLock delay is 5 seconds', 'password-required')]:
            with self.subTest(text=text):
                self.assertEqual(lock_policy('2026-10-19 sysadminctl[1:2] ' + text, 0, None)['effective'], expected)

    def test_unknown_failed_and_conflicting_reports_do_not_disable_lock(self):
        for text, code in [('', 0), ('Unknown state for screenLock (null)', 0),
                           ('screenLock is off', 1), ('off', 0),
                           ('screenLock is off\nscreenLock delay is immediate', 0)]:
            with self.subTest(text=text, code=code):
                self.assertEqual(lock_policy(text, code, None)['effective'], 'unknown')

    def test_missing_preference_can_use_independent_effective_report(self):
        result = lock_policy('screenLock is off', 0, None)
        self.assertIsNone(result['askForPassword'])
        self.assertEqual(result['effective'], 'disabled')


class ConsoleStateTests(unittest.TestCase):
    def test_root_lock_and_big_sur_login_key(self):
        result = console_session([{'IOConsoleLocked': False, 'IOConsoleUsers': [
            {'kCGSSessionUserIDKey': 502, 'kCGSSessionOnConsoleKey': True,
             'kCGSessionLoginDoneKey': True}]}], 502)
        self.assertIs(result['screenIsLocked'], False)
        self.assertEqual(result['screenLockSource'], 'IOConsoleLocked')
        self.assertIs(result['onConsole'], True)
        self.assertIs(result['loginDone'], True)

    def test_root_lock_is_authoritative(self):
        result = console_session([{'IOConsoleLocked': True, 'IOConsoleUsers': [
            {'kCGSSessionUserIDKey': 502, 'CGSSessionScreenIsLocked': False}]}], 502)
        self.assertIs(result['screenIsLocked'], True)

    def test_missing_root_lock_is_unknown(self):
        result = console_session([{'IOConsoleUsers': [
            {'kCGSSessionUserIDKey': 502, 'CGSSessionScreenIsLocked': False}]}], 502)
        self.assertIsNone(result['screenIsLocked'])
        self.assertEqual(result['screenLockSource'], 'unknown')

    def test_other_account_metadata_is_not_adopted(self):
        result = console_session([{'IOConsoleLocked': False, 'IOConsoleUsers': [
            {'kCGSSessionUserIDKey': 501, 'kCGSessionLoginDoneKey': True}]}], 502)
        self.assertIsNone(result['uid'])
        self.assertIsNone(result['loginDone'])


class WakeRequestTests(unittest.TestCase):
    def exercise(self, awake_after, timeout):
        clock = [0.0]
        reads = [0]
        class Activity:
            released = 0
            def declare(self):
                return 0
            def release(self):
                self.released += 1
                return 0
        activity = Activity()
        def power():
            reads[0] += 1
            awake = reads[0] >= awake_after
            return {'awake': awake, 'asleep': not awake, 'currentPowerState': 4 if awake else 1}
        def pause(seconds):
            clock[0] += seconds
        result = wake_display(power_reader=power, activity_factory=lambda: activity,
                              clock=lambda: clock[0], sleeper=pause, timeout=timeout)
        return result, activity

    def test_observed_wake_and_assertion_release(self):
        result, activity = self.exercise(3, 20)
        self.assertTrue(result['requestSucceeded'])
        self.assertTrue(result['observedDisplayWake'])
        self.assertEqual(len(result['attempts']), 3)
        self.assertEqual(activity.released, 1)
        self.assertTrue(result['assertionReleased'])

    def test_request_success_alone_does_not_prove_wake(self):
        result, activity = self.exercise(999, 2)
        self.assertTrue(result['requestSucceeded'])
        self.assertFalse(result['observedDisplayWake'])
        self.assertEqual(result['elapsedSeconds'], 2)
        self.assertEqual(activity.released, 1)

    def test_retry_budget_is_capped_at_twenty_seconds(self):
        result, activity = self.exercise(999, 90)
        self.assertEqual(result['maximumRetrySeconds'], 20)
        self.assertEqual(result['elapsedSeconds'], 20)
        self.assertEqual(activity.released, 1)


if __name__ == '__main__':
    unittest.main()
