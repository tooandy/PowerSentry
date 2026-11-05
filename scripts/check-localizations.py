#!/usr/bin/env python3
"""Validate the shipped English and Simplified Chinese macOS localization tables."""
from pathlib import Path
import plistlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("en", "zh-Hans")
FORMAT_TOKEN = re.compile(
    r"%(?:\d+\$)?(?:[-+0 #]*\d*(?:\.\d+)?)?(?:hh|h|ll|l|z|t|j)?[@diuoxXfFeEgGcCsSp]"
)


def parse_strings(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    pairs = re.findall(
        r'^\s*"((?:\\.|[^"])*)"\s*=\s*"((?:\\.|[^"])*)"\s*;',
        text,
        re.MULTILINE,
    )
    return {key: value for key, value in pairs}


def placeholders(value: str) -> tuple[str, ...]:
    return tuple(FORMAT_TOKEN.findall(value))


def main() -> int:
    errors: list[str] = []
    tables: dict[str, dict[str, str]] = {}
    base_keys: set[str] | None = None

    for language in LANGUAGES:
        directory = ROOT / "Resources" / f"{language}.lproj"
        localizable = directory / "Localizable.strings"
        info = directory / "InfoPlist.strings"
        if not localizable.is_file() or not info.is_file():
            errors.append(f"{language}: missing Localizable.strings or InfoPlist.strings")
            continue

        current = parse_strings(localizable)
        tables[language] = current
        if base_keys is None:
            base_keys = set(current)
        else:
            missing = base_keys - set(current)
            extra = set(current) - base_keys
            if missing:
                errors.append(f"{language}: missing keys: {sorted(missing)}")
            if extra:
                errors.append(f"{language}: unexpected keys: {sorted(extra)}")

        info_keys = set(parse_strings(info))
        required_info = {"CFBundleDisplayName", "CFBundleName"}
        if not required_info.issubset(info_keys):
            errors.append(f"{language}: InfoPlist.strings missing {sorted(required_info - info_keys)}")

    source_keys: set[str] = set()
    if set(tables) == set(LANGUAGES):
        english = tables["en"]
        chinese = tables["zh-Hans"]
        for key in set(english) & set(chinese):
            if placeholders(english[key]) != placeholders(chinese[key]):
                errors.append(
                    f"format placeholders differ for {key}: "
                    f"en={placeholders(english[key])}, zh-Hans={placeholders(chinese[key])}"
                )

        for source in (ROOT / "Sources").rglob("*.swift"):
            source_keys.update(
                key for key in re.findall(r'\btrf?\("([^"]+)"', source.read_text(encoding="utf-8"))
                if "\\(" not in key
            )
        missing_source = source_keys - set(english)
        if missing_source:
            errors.append(f"source references missing localization keys: {sorted(missing_source)}")

    try:
        with (ROOT / "Resources" / "Info.plist").open("rb") as stream:
            info_plist = plistlib.load(stream)
        if info_plist.get("CFBundleDevelopmentRegion") != "en":
            errors.append("Info.plist: CFBundleDevelopmentRegion must be en for English fallback")
        if set(info_plist.get("CFBundleLocalizations", [])) != set(LANGUAGES):
            errors.append("Info.plist: CFBundleLocalizations must contain en and zh-Hans")
        if info_plist.get("LSUIElement") is not True:
            errors.append("Info.plist: LSUIElement must remain true (menu-bar-only app)")
    except Exception as error:  # noqa: BLE001 - report malformed plist as a validation error
        errors.append(f"Info.plist could not be parsed: {error}")

    if errors:
        print("Localization validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(
        f"PASS: {len(tables['en'])} matching localization keys, "
        f"{len(source_keys)} source references, 2 languages, format placeholders match"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
