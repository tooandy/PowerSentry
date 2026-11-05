#!/usr/bin/env python3
"""Validate all shipped PowerSentry macOS localization tables."""
from pathlib import Path
import plistlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("en", "zh-Hans", "zh-Hant", "es", "ko", "ja", "de", "fr", "nl")
FORMAT_TOKEN = re.compile(
    r"%(?!%)(?:\d+\$)?(?:[-+0#]*\d*(?:\.\d+)?)?(?:hh|h|ll|l|z|t|j)?[@diuoxXfFeEgGcCsSp]"
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
        for language in LANGUAGES[1:]:
            for key in set(english) & set(tables[language]):
                if placeholders(english[key]) != placeholders(tables[language][key]):
                    errors.append(
                        f"format placeholders differ for {key}: "
                        f"en={placeholders(english[key])}, {language}={placeholders(tables[language][key])}"
                    )

        for source in (ROOT / "Sources").rglob("*.swift"):
            source_keys.update(
                key for key in re.findall(r'\btrf?\("([^"]+)"', source.read_text(encoding="utf-8"))
                if "\\(" not in key
            )
        # Dynamic incident statuses are looked up via key interpolation in Swift.
        source_keys.update({
            "incident.status.open", "incident.status.acknowledged",
            "incident.status.resolved", "incident.status.ignored",
            "incident.status.actionTaken"
        })
        missing_source = source_keys - set(english)
        if missing_source:
            errors.append(f"source references missing localization keys: {sorted(missing_source)}")

    try:
        with (ROOT / "Resources" / "Info.plist").open("rb") as stream:
            info_plist = plistlib.load(stream)
        if info_plist.get("CFBundleDevelopmentRegion") != "en":
            errors.append("Info.plist: CFBundleDevelopmentRegion must be en for English fallback")
        if set(info_plist.get("CFBundleLocalizations", [])) != set(LANGUAGES):
            errors.append(f"Info.plist: CFBundleLocalizations must contain {LANGUAGES}")
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
        f"{len(source_keys)} source references, {len(LANGUAGES)} languages, format placeholders match"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
