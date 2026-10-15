#!/usr/bin/env python3
"""Validate every skill under skills/ against the Agent Skills specification (agentskills.io).

Checks:
  - SKILL.md exists and starts with YAML frontmatter
  - name: 1-64 chars, lowercase a-z/0-9/hyphens, no leading/trailing/double hyphen, matches folder
  - description: 1-1024 chars
  - compatibility (optional): <= 500 chars
  - metadata (optional): string -> string map
  - Every references/, assets/ or scripts/ path mentioned in SKILL.md exists
  - SKILL.md body stays under 500 lines (spec recommendation)

Usage: python3 scripts/validate.py [skills_dir]
Exit code 1 on any error. Needs only the Python standard library plus PyYAML if available
(falls back to a minimal parser when PyYAML is missing).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
REF_RE = re.compile(r"`((?:references|assets|scripts)/[A-Za-z0-9_.\-/]+)`")


def parse_frontmatter(text: str) -> tuple[dict, str]:
    if not text.startswith("---\n"):
        raise ValueError("SKILL.md must start with '---' frontmatter")
    end = text.find("\n---", 4)
    if end == -1:
        raise ValueError("frontmatter is not closed with '---'")
    raw, body = text[4:end], text[end + 4:]
    try:
        import yaml  # type: ignore

        data = yaml.safe_load(raw) or {}
    except ImportError:
        data, current = {}, None
        for line in raw.splitlines():
            if not line.strip():
                continue
            if line.startswith("  ") and current:
                k, _, v = line.strip().partition(":")
                data[current][k.strip()] = v.strip().strip('"')
            else:
                k, _, v = line.partition(":")
                current = k.strip()
                data[current] = v.strip() if v.strip() else {}
    if not isinstance(data, dict):
        raise ValueError("frontmatter must be a YAML mapping")
    return data, body


def validate_skill(skill_dir: Path) -> list[str]:
    errors: list[str] = []
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file():
        return [f"{skill_dir}: SKILL.md missing"]
    text = skill_md.read_text(encoding="utf-8")
    try:
        fm, body = parse_frontmatter(text)
    except ValueError as exc:
        return [f"{skill_md}: {exc}"]

    name = fm.get("name")
    if not isinstance(name, str) or not (1 <= len(name) <= 64) or not NAME_RE.match(name):
        errors.append(f"{skill_md}: invalid name {name!r} (lowercase letters, digits, single hyphens, max 64)")
    elif name != skill_dir.name:
        errors.append(f"{skill_md}: name {name!r} must match folder name {skill_dir.name!r}")

    desc = fm.get("description")
    if not isinstance(desc, str) or not (1 <= len(desc) <= 1024):
        errors.append(f"{skill_md}: description must be 1-1024 characters (got {len(desc) if isinstance(desc, str) else 'none'})")
    elif "<" in desc or ">" in desc:
        errors.append(f"{skill_md}: description must not contain angle brackets (some clients reject them)")

    compat = fm.get("compatibility")
    if compat is not None and (not isinstance(compat, str) or not (1 <= len(compat) <= 500)):
        errors.append(f"{skill_md}: compatibility must be 1-500 characters")

    meta = fm.get("metadata")
    if meta is not None and (not isinstance(meta, dict) or not all(isinstance(v, str) for v in meta.values())):
        errors.append(f"{skill_md}: metadata must map strings to strings (quote numbers like \"1.0\")")

    for ref in sorted(set(REF_RE.findall(body))):
        if "<" in ref:
            continue
        if not (skill_dir / ref).exists():
            errors.append(f"{skill_md}: referenced file not found: {ref}")

    lines = body.count("\n")
    if lines > 500:
        errors.append(f"{skill_md}: body is {lines} lines; keep under 500 and move detail into references/")
    return errors


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "skills")
    skills = sorted(p for p in root.iterdir() if p.is_dir())
    if not skills:
        print(f"No skills found in {root}")
        return 1
    all_errors: list[str] = []
    for skill in skills:
        errs = validate_skill(skill)
        all_errors.extend(errs)
        print(f"{'FAIL' if errs else 'OK  '} {skill.name}")
    for e in all_errors:
        print(f"  - {e}")
    return 1 if all_errors else 0


if __name__ == "__main__":
    sys.exit(main())
