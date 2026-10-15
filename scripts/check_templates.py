#!/usr/bin/env python3
"""Check that every code example shipped inside the skill is at least syntactically valid.

- ```yaml / ```yml blocks: parsed with PyYAML (placeholders like <name> are neutralised first)
- ```json blocks: parsed with json (blocks containing <placeholders> or "..." are skipped,
  since they are illustrative fragments)

Usage: python3 scripts/check_templates.py   (requires: pip install pyyaml)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
BLOCK_RE = re.compile(r"^(`{3,}|~{3,})(yaml|yml|json)\s*\n(.*?)^\1\s*$", re.S | re.M)


def main() -> int:
    failures = 0
    checked = 0
    for md in sorted((ROOT / "skills").rglob("*.md")):
        text = md.read_text(encoding="utf-8")
        for match in BLOCK_RE.finditer(text):
            lang, body = match.group(2), match.group(3)
            line = text.count("\n", 0, match.start()) + 1
            try:
                if lang in ("yaml", "yml"):
                    yaml.safe_load(re.sub(r"<([^<>\n]+)>", r"x\1x", body))
                else:
                    if "<" in body or "..." in body:
                        continue
                    json.loads(body)
                checked += 1
            except Exception as exc:  # noqa: BLE001 - report any parser error
                failures += 1
                print(f"FAIL {md.relative_to(ROOT)}:{line} ({lang}): {exc}")
    print(f"Checked {checked} code blocks, {failures} failure(s).")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
