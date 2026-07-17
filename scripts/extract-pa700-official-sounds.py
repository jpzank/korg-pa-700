#!/usr/bin/env python3
"""Extract the PA700 v1.5 sound table into a bundled JSON resource.

The official manual's printed pages 953-979 are PDF pages 965-991.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pdfplumber


EXPECTED_COUNTS = {"Factory": 534, "Legacy": 505, "GM/XG": 688}


def clean(value: str | None) -> str:
    return (value or "").strip().replace("\n", " ")


def split_section(section: str) -> tuple[str, str]:
    if section.startswith("Factory"):
        library = "Factory"
    elif section.startswith("Legacy"):
        library = "Legacy"
    elif section.startswith("GM/XG"):
        library = "GM/XG"
    else:
        raise ValueError(f"Unknown section: {section}")
    category = section.split("/", 1)[1] if "/" in section else ""
    return library, category


def extract(pdf_path: Path) -> list[dict[str, object]]:
    sounds: list[dict[str, object]] = []
    section: str | None = None

    with pdfplumber.open(pdf_path) as pdf:
        for pdf_page in range(965, 992):
            printed_page = pdf_page - 12
            for table in pdf.pages[pdf_page - 1].extract_tables():
                for raw_row in table[1:]:
                    if len(raw_row) != 4:
                        continue
                    name, cc0, cc32, pc = map(clean, raw_row)
                    if name and not (cc0 and cc32 and pc):
                        section = name
                        continue
                    if not (name and cc0.isdigit() and cc32.isdigit() and pc.isdigit()):
                        continue
                    if section is None:
                        raise ValueError(f"Sound before section on PDF page {pdf_page}: {name}")
                    library, category = split_section(section)
                    sounds.append(
                        {
                            "name": name,
                            "bankMSB": int(cc0),
                            "bankLSB": int(cc32),
                            "program": int(pc),
                            "library": library,
                            "category": category,
                            "manualPage": printed_page,
                        }
                    )

    counts = {library: sum(sound["library"] == library for sound in sounds) for library in EXPECTED_COUNTS}
    if counts != EXPECTED_COUNTS:
        raise ValueError(f"Unexpected library counts: {counts}")
    addresses = {(sound["bankMSB"], sound["bankLSB"], sound["program"]) for sound in sounds}
    if len(addresses) != len(sounds):
        raise ValueError("The official sound table contains duplicate MIDI addresses")
    return sounds


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    sounds = extract(args.pdf)
    payload = {
        "schemaVersion": 1,
        "model": "PA700",
        "firmware": "1.5.0",
        "source": "KORG Pa700 User Manual v1.5, Musical Resources, pages 953-979",
        "userSlots": {"bankMSB": 121, "bankLSB": "64-67", "program": "0-127", "count": 512},
        "sounds": sounds,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
