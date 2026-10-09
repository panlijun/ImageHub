"""Require all expected XCTest cases to pass; a skipped Photos test is not evidence."""

import argparse
import json
from pathlib import Path
import subprocess


def verify(summary: object, expected: int) -> None:
    if not isinstance(summary, dict) or expected <= 0:
        raise ValueError("Invalid XCTest summary or expected case count.")
    required = {
        "totalTestCount": expected,
        "passedTests": expected,
        "failedTests": 0,
        "skippedTests": 0,
    }
    for field, wanted in required.items():
        actual = summary.get(field)
        if type(actual) is not int or actual != wanted:
            raise ValueError(f"XCTest {field} must equal {wanted}; received {actual!r}.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_bundle", type=Path)
    parser.add_argument("--expected", type=int, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    args = parser.parse_args()
    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(args.result_bundle)],
        check=True,
        capture_output=True,
        text=True,
        timeout=60,
    )
    summary = json.loads(result.stdout)
    # Preserve the native summary even when verification rejects a failure,
    # missing case, skipped case, or an unknown output format.
    args.summary.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    verify(summary, args.expected)
    print(f"Confirmed {args.expected} XCTest cases passed, zero failed or skipped.")


if __name__ == "__main__":
    main()
