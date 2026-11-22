#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Classify XCTest text without treating a timed-out case as an unstarted run.

Xcode can restart its runner after a timeout and append an empty successful
suite. Case events must survive that final zero-tests summary. This is a log
classifier, not an xcresult parser or proof that gameplay assertions passed.
"""
from __future__ import annotations
import argparse
import json
import re
from pathlib import Path


def classify(log: str, exit_code: int) -> dict:
    starts = re.findall(r"^Test Case '(.+)' started(?: at .*)?\.?$", log, re.MULTILINE)
    ends = re.findall(r"^Test Case '(.+)' (passed|failed|skipped) \([\d.]+ seconds\)\.?$", log, re.MULTILINE)
    timeouts = re.findall(r"^Test Case '(.+)' exceeded execution time allowance\b", log, re.MULTILINE)
    summaries = [int(n) for n in re.findall(r"\bExecuted (\d+) tests?\b", log)]
    passed = [name for name, state in ends if state == 'passed']
    failed = [name for name, state in ends if state == 'failed']
    skipped = [name for name, state in ends if state == 'skipped']
    executed = max([*summaries, len(set(starts)), len(set(name for name, _ in ends)), len(set(timeouts)), 0])
    interrupted = exit_code < 0 or exit_code == 130 or bool(re.search(r'Testing cancel(?:led|ed)|\*\* TEST EXECUTE INTERRUPTED \*\*', log, re.IGNORECASE))
    # A completed passing case is required. An empty/skipped suite, exit status
    # alone, or a later passing retry cannot erase an earlier failure/timeout.
    success = exit_code == 0 and bool(passed) and not failed and not timeouts and not interrupted and set(starts) <= set(passed + skipped)
    return dict(
        passed=success, exitCode=exit_code, executedTests=executed,
        startedCaseEvents=len(starts), passedCaseEvents=len(passed),
        failedCaseEvents=len(failed), skippedCaseEvents=len(skipped),
        timedOutCaseEvents=len(timeouts), interrupted=interrupted,
        retryableStartupFailure=exit_code != 0 and executed == 0 and not interrupted,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('--exit-code', type=int, required=True)
    args = parser.parse_args()
    print(json.dumps(classify(args.log.read_text(), args.exit_code), indent=2))


if __name__ == '__main__':
    main()
