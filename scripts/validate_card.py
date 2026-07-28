#!/usr/bin/env python3
"""Validate a HermesLayout JSON against the Swift source BEFORE sending it to a device.

An unknown enum raw value makes Swift's Codable throw, and HermesLayout decoding is all-or-nothing:
one bad string anywhere fails the WHOLE card, and the only symptom on device is
"url: present but payload undecodable" in the failure view. That has cost two device round-trips
(`"role": "caption2"` — a value that never existed — and one before it), so check locally instead.

Enum cases and node types are scraped from the Swift source at run time rather than duplicated here,
so this cannot drift out of sync with the schema.

    python3 scripts/validate_card.py card.json [more.json ...]

Exit 0 = every file valid. Exit 1 = at least one problem, printed with its JSON path.
"""
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LAYOUT = REPO / "Shared/Sources/HermesShared/HermesLayout.swift"
CODABLE = REPO / "Shared/Sources/HermesShared/HermesLayoutCodable.swift"


def swift_enum_cases(src: str, anchor: str) -> set[str]:
    """Cases of the `String, Codable` enum whose body contains `anchor`."""
    # `[^{}]*` stops at the first brace, so a one-line enum (Weight) cannot swallow the multi-line
    # one declared right after it (Role) — that merge made `bold` validate as a text role.
    for m in re.finditer(r"enum\s+\w+\s*:\s*String[^{]*\{([^{}]*)\}", src, re.S):
        body = m.group(1)
        if anchor not in body:
            continue
        cases: set[str] = set()
        for line in body.splitlines():
            line = re.sub(r"//.*", "", line)
            if "case" not in line:
                continue
            for name in re.findall(r"[A-Za-z_]\w*", line.replace("case", "", 1)):
                cases.add(name)
        return cases
    return set()


def load_schema() -> dict:
    layout = LAYOUT.read_text()
    codable = CODABLE.read_text()
    # Node types are the `case foo` list of the NodeType enum used by the decoder switch.
    node_types = set(re.findall(r"case\s+(\w+)\s*$", "", re.M))
    m = re.search(r"enum\s+NodeType\s*:\s*String[^{]*\{(.*?)\n\s*\}", codable, re.S)
    if m:
        for line in m.group(1).splitlines():
            line = re.sub(r"//.*", "", line)
            if "case" in line:
                node_types |= set(re.findall(r"[A-Za-z_]\w*", line.replace("case", "", 1)))
    return {
        "nodeTypes": node_types,
        "role": swift_enum_cases(layout, "largeTitle"),
        "weight": swift_enum_cases(layout, "semibold"),
        "seatState": swift_enum_cases(layout, "unavailable"),
        "checklistState": swift_enum_cases(layout, "unchecked"),
        "pickerStyle": swift_enum_cases(layout, "grid"),
        "backgroundKind": swift_enum_cases(layout, "atmosphere"),
    }


def validate(layout: dict, S: dict) -> list[str]:
    errs: list[str] = []

    def bad(path: str, field: str, value, allowed: set[str]) -> None:
        errs.append(f"{path}.{field} = {value!r} is not one of {sorted(allowed)}")

    def check_style(style, path: str) -> None:
        if not isinstance(style, dict):
            return
        if "role" in style and style["role"] not in S["role"]:
            bad(path, "role", style["role"], S["role"])
        if "weight" in style and style["weight"] not in S["weight"]:
            bad(path, "weight", style["weight"], S["weight"])

    def walk(node, path: str) -> None:
        if isinstance(node, list):
            for i, n in enumerate(node):
                walk(n, f"{path}[{i}]")
            return
        if not isinstance(node, dict):
            return
        t = node.get("type")
        if t and S["nodeTypes"] and t not in S["nodeTypes"]:
            bad(path, "type", t, S["nodeTypes"])
        check_style(node.get("style"), path)
        if t == "seatChart":
            for ri, row in enumerate(node.get("rows") or []):
                for si, seat in enumerate(row.get("seats") or []):
                    st = seat.get("state")
                    if st is not None and st not in S["seatState"]:
                        bad(f"{path}.rows[{ri}].seats[{si}]", "state", st, S["seatState"])
        if t == "checklist":
            for ii, item in enumerate(node.get("items") or []):
                st = item.get("state")
                if st is not None and st not in S["checklistState"]:
                    bad(f"{path}.items[{ii}]", "state", st, S["checklistState"])
        if t == "optionPicker":
            ps = node.get("pickerStyle")
            if ps is not None and ps not in S["pickerStyle"]:
                bad(path, "pickerStyle", ps, S["pickerStyle"])
        if t == "collapsible" and "sectionId" not in node:
            errs.append(f"{path}: collapsible requires 'sectionId' (NOT 'id')")
        for key in ("children", "child"):
            if key in node:
                walk(node[key], f"{path}.{key}")

    kind = (layout.get("background") or {}).get("kind")
    if kind is not None and kind not in S["backgroundKind"]:
        bad("background", "kind", kind, S["backgroundKind"])
    walk(layout.get("root"), "root")

    # Form contract: a card with fieldId inputs needs exactly one layout-level submit action.
    fields: list[str] = []

    def collect(node) -> None:
        if isinstance(node, list):
            for n in node:
                collect(n)
        elif isinstance(node, dict):
            if node.get("fieldId"):
                fields.append(node["fieldId"])
            for key in ("children", "child"):
                if key in node:
                    collect(node[key])

    collect(layout.get("root"))
    actions = layout.get("actions") or []
    if fields:
        if len(set(fields)) != len(fields):
            errs.append(f"duplicate fieldId values: {fields}")
        if len(actions) != 1:
            errs.append(f"{len(fields)} form field(s) but {len(actions)} layout action(s) — need exactly 1 submit")
        if not layout.get("formId"):
            errs.append("form card is missing 'formId' (needed to correlate the reply)")
    # A scene-less card gets no bubble art at all (GenericGraphic is a 1x1 clear pixel).
    root_kids = (layout.get("root") or {}).get("children") or []
    if root_kids and root_kids[0].get("type") in {"vstack", "hstack", "card", "text", "keyValueRow"}:
        errs.append("WARN first root child is not a scene hero — the bubble preview will be blank")
    return errs


def main() -> int:
    S = load_schema()
    if not S["role"]:
        print("could not scrape enums from Swift source — is the repo path right?", file=sys.stderr)
        return 2
    rc = 0
    for arg in sys.argv[1:]:
        errs = validate(json.loads(Path(arg).read_text()), S)
        hard = [e for e in errs if not e.startswith("WARN")]
        print(f"{arg}: {'OK' if not hard else str(len(hard)) + ' PROBLEM(S)'}"
              f"{' (' + str(len(errs) - len(hard)) + ' warning)' if len(errs) != len(hard) else ''}")
        for e in errs:
            print(f"   {'!' if not e.startswith('WARN') else '~'} {e}")
        if hard:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
