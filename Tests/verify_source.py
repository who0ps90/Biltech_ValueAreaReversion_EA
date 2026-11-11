#!/usr/bin/env python3
"""Structural packaging checks only. This is not an MQL5 compiler or backtest."""
from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def check_delimiters(source: str, filename: str) -> None:
    """Ignore MQL comments/string/character literals while checking delimiters."""
    stack = []
    index = 0
    line = 1
    pairs = {")": "(", "]": "[", "}": "{"}
    while index < len(source):
        char = source[index]
        line += char == "\n"
        if source[index:index + 2] == "//":
            end = source.find("\n", index)
            index = len(source) if end == -1 else end
            continue
        if source[index:index + 2] == "/*":
            end = source.find("*/", index + 2)
            if end == -1:
                raise ValueError(f"{filename}:{line}: unterminated comment")
            line += source[index:end + 2].count("\n")
            index = end + 2
            continue
        if char in "\"'":
            quote = char
            start = line
            index += 1
            while index < len(source) and source[index] != quote:
                if source[index] == "\\":
                    index += 2
                else:
                    line += source[index] == "\n"
                    index += 1
            if index >= len(source):
                raise ValueError(f"{filename}:{start}: unterminated literal")
        elif char in "([{":
            stack.append((char, line))
        elif char in ")]}" and (not stack or stack.pop()[0] != pairs[char]):
            raise ValueError(f"{filename}:{line}: mismatched delimiter {char}")
        index += 1
    if stack:
        char, at = stack[-1]
        raise ValueError(f"{filename}:{at}: unclosed delimiter {char}")


def main() -> int:
    expected = ["Biltech_ValueAreaReversion_EA.mq5", "README.md",
                "Docs/Validation.md", "Docs/ResearchProtocol.md",
                "Docs/AssumptionsAndLimitations.md", "Tests/BVSelfTest.mq5",
                "Tests/analyze_logs.py", "Examples/blackouts.example.csv"]
    errors = [f"missing deliverable: {name}" for name in expected if not (ROOT / name).is_file()]
    files = sorted([*ROOT.glob("*.mq5"), *ROOT.glob("Include/*.mqh"),
                    *ROOT.glob("Tests/*.mq5"), *ROOT.glob("Tests/*.mqh")])
    sources = {}
    for path in files:
        source = path.read_text(encoding="utf-8-sig")
        sources[path] = source
        try:
            check_delimiters(source, str(path.relative_to(ROOT)))
        except ValueError as exc:
            errors.append(str(exc))
        for name in re.findall(r'^\s*#include\s+"([^"]+)"', source, flags=re.MULTILINE):
            included = (path.parent / name.replace("\\", "/")).resolve()
            if not included.is_file():
                errors.append(f"{path.name}: missing quoted include: {name}")
        if re.search(r"\bWebRequest\s*\(|^\s*#import\b", source, flags=re.MULTILINE):
            errors.append(f"{path.name}: external request/import present; review restricted research scope")
    main_source = sources.get(ROOT / "Biltech_ValueAreaReversion_EA.mq5", "")
    for handler in ("OnInit", "OnTick", "OnDeinit"):
        if not re.search(r"\b" + handler + r"\s*\(", main_source):
            errors.append(f"missing main handler: {handler}")
    if "MQL_TESTER" not in main_source:
        errors.append("tester-only initialization marker missing; manually review execution restriction")
    inputs = {match[1] for match in re.findall(
        r"\binput\s+(\w+)\s+(\w+)\s*=\s*([^;]+);", main_source)}
    if not inputs:
        errors.append("no scalar inputs parsed from main source")
    presets = sorted((ROOT / "Presets").glob("*.set"))
    if len(presets) != 3:
        errors.append(f"expected three research presets, found {len(presets)}")
    for path in presets:
        content = path.read_text(encoding="utf-8-sig")
        if "UNVALIDATED" not in content:
            errors.append(f"{path.name}: missing UNVALIDATED label")
        seen = set()
        for line in content.splitlines():
            if not line.strip() or line.lstrip().startswith((";", "#")):
                continue
            name, separator, _ = line.partition("=")
            if not separator:
                errors.append(f"{path.name}: malformed preset line {line!r}")
            elif name not in inputs:
                errors.append(f"{path.name}: unknown input {name}")
            elif name in seen:
                errors.append(f"{path.name}: duplicate input {name}")
            seen.add(name)
    if errors:
        print("STRUCTURAL CHECK FAILED:")
        print("\n".join(f"- {error}" for error in errors))
        return 1
    print(f"PASS: packaging, {len(files)} MQL source delimiter/include scans, {len(inputs)} parsed inputs, "
          f"{len(presets)} preset input-name checks.")
    print("This command does not perform MQL5 compilation, native self-tests, MT5 execution, visual audit or backtests.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
