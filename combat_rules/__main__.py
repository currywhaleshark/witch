import argparse
import json
from pathlib import Path

from .scenarios import load_fixture, replay


def main() -> int:
    parser = argparse.ArgumentParser(description="Replay engine-independent combat rule scenarios")
    parser.add_argument("--fixture", type=Path, default=Path(__file__).resolve().parents[1] / "tests/fixtures/combat_rules.json")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        report = replay(load_fixture(args.fixture))
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report["summary"], ensure_ascii=False, indent=2))
        for case in report["cases"]:
            print(f"{'PASS' if case['passed'] else 'FAIL'} {case['id']}")
            for step in case["steps"]:
                for error in step["errors"]:
                    print(f"  step {step['step']}: {error}")
        return 1 if report["summary"]["failed"] else 0
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"Combat fixture error: {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
