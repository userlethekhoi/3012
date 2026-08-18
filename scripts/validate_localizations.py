#!/usr/bin/env python3
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "3012" / "Resources" / "Localizable.xcstrings"
VIEW_CALL = re.compile(
    r'(?:Text|Label|Button|Section|Picker|LabeledContent|navigationTitle|alert|confirmationDialog)'
    r'\(\s*"((?:[^"\\]|\\.)*)"',
    re.MULTILINE,
)


def main() -> int:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    if catalog.get("sourceLanguage") != "en":
        print("Localizable.xcstrings sourceLanguage must be en", file=sys.stderr)
        return 1

    strings = catalog.get("strings", {})
    failures: list[str] = []
    for key, record in strings.items():
        localizations = record.get("localizations", {})
        for language in ("vi", "zh-Hans"):
            unit = localizations.get(language, {}).get("stringUnit", {})
            if unit.get("state") != "translated" or not unit.get("value"):
                failures.append(f"{key!r} is missing a translated {language} value")

    used_keys: set[str] = set()
    for path in (ROOT / "3012").rglob("*.swift"):
        used_keys.update(VIEW_CALL.findall(path.read_text(encoding="utf-8")))
    for key in sorted(used_keys - set(strings)):
        failures.append(f"SwiftUI key {key!r} is absent from Localizable.xcstrings")

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"Validated {len(strings)} catalog entries and {len(used_keys)} SwiftUI keys.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
