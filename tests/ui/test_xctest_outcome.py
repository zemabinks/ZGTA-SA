#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored XCTest transcripts; no private app logs or captures embedded."""
import sys
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.development.read_xctest_outcome import classify

CASE = "-[AuthoredTests AuthoredCase]"
START = f"Test Case '{CASE}' started.\n"
PASS = f"Test Case '{CASE}' passed (1.234 seconds).\n"
FAIL = f"Test Case '{CASE}' failed (1.234 seconds).\n"
TIMEOUT = f"Test Case '{CASE}' exceeded execution time allowance of 1 minute.\n"
EMPTY = 'Executed 0 tests, with 0 failures (0 unexpected) in 0.000 seconds\n'


class OutcomeTests(unittest.TestCase):
    def test_normal_pass(self):
        value = classify(START + PASS + 'Executed 1 test, with 0 failures', 0)
        self.assertTrue(value['passed']); self.assertEqual(value['executedTests'], 1)
        self.assertFalse(value['retryableStartupFailure'])
    def test_timeout_then_empty_restart_is_an_executed_failure(self):
        value = classify(START + TIMEOUT + EMPTY, 65)
        self.assertFalse(value['passed']); self.assertEqual(value['executedTests'], 1)
        self.assertEqual(value['timedOutCaseEvents'], 1); self.assertFalse(value['retryableStartupFailure'])
    def test_completed_failure_then_empty_restart(self):
        value = classify(START + FAIL + EMPTY, 65)
        self.assertEqual(value['executedTests'], 1); self.assertFalse(value['retryableStartupFailure'])
    def test_empty_success_never_proves_execution(self):
        value = classify(EMPTY, 0)
        self.assertFalse(value['passed']); self.assertFalse(value['retryableStartupFailure'])
    def test_unstarted_failure_may_retry(self):
        self.assertTrue(classify('Runner failed to start\n' + EMPTY, 65)['retryableStartupFailure'])
    def test_controlled_stop_may_not_retry(self):
        for code, log in [(-2, ''), (130, ''), (65, 'Testing cancelled\n' + EMPTY)]:
            self.assertFalse(classify(log, code)['retryableStartupFailure'])
    def test_started_but_not_completed_is_failure(self):
        value = classify(START + EMPTY, 0)
        self.assertFalse(value['passed']); self.assertEqual(value['executedTests'], 1)
    def test_diagnostic_case_name_does_not_count(self):
        value = classify('Error: '+START+EMPTY, 65)
        self.assertEqual(value['executedTests'], 0)
    def test_later_passing_retry_does_not_erase_timeout(self):
        self.assertFalse(classify(START+TIMEOUT+START+PASS, 0)['passed'])
    def test_all_skipped_is_not_gameplay_pass(self):
        value = classify(START+f"Test Case '{CASE}' skipped (0.001 seconds).\n", 0)
        self.assertFalse(value['passed']); self.assertEqual(value['skippedCaseEvents'], 1)
    def test_nonzero_exit_rejects_passed_case(self):
        self.assertFalse(classify(START+PASS, 65)['passed'])
    def test_later_zero_summary_preserves_earlier_count(self):
        value = classify('Executed 2 tests, with 1 failure\n'+EMPTY, 65)
        self.assertEqual(value['executedTests'], 2); self.assertFalse(value['retryableStartupFailure'])


if __name__ == '__main__':
    unittest.main()
