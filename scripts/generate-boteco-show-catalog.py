#!/usr/bin/env python3
"""Generate the private Boteco Jul3 show catalog from the supplied goJam PDF.

The PDF uses two- and three-column layouts.  Chord glyphs are orange, which
lets us retain their semantic role while turning the pages into an editable,
linear show chart.  The manifest is intentionally specific to this show.
"""

from __future__ import annotations

import argparse
import json
import re
import uuid
from pathlib import Path

import pdfplumber


SONGS = [
    ("querendo-te-amar", "Querendo Te Amar", 2),
    ("de-tanto-te-querer", "De Tanto Te Querer", 3),
    ("seu-astral", "Seu Astral", 4),
    ("tem-que-ser-voce", "Tem Que Ser Você", 5),
    ("fotos", "Fotos", 6),
    ("borboletas", "Borboletas", 7),
    ("madri", "Madri", 8),
    ("chora-me-liga", "Chora, Me Liga", 9),
    ("pode-chorar", "Pode Chorar", 10),
    ("voa-beija-flor", "Voa Beija-flor", 11),
    ("chove-chove", "Chove, Chove", 12),
    ("eu-quero-so-voce", "Eu Quero Só Você", 13),
    ("fugidinha", "Fugidinha", 14),
    ("de-copo-em-copo", "De Copo Em Copo", 15),
    ("volta-por-baixo", "Volta Por Baixo", 16),
    ("ate-voce-voltar", "Até Você Voltar", 17),
    ("quarta-cadeira", "Quarta Cadeira (part. Jorge e Mateus)", 18),
    ("pactos", "Pactos (part. Jorge & Mateus)", 19),
    ("s-de-saudade", '"S" de Saudade (part. Zé Neto e Cristiano)', 20),
    ("sinais", "Sinais", 21),
    ("voce-nao-sabe-o-que-e-amor", "Você Não Sabe o Que É Amor", 22),
    ("paradigmas", "Paradigmas", 23),
    ("cedo-ou-tarde", "Cedo Ou Tarde", 24),
    ("te-assumi-pro-brasil", "Te Assumi Pro Brasil", 25),
    ("palpite", "Palpite", 26),
    ("quem-de-nos-dois", "Quem de Nós Dois", 27),
    ("so-hoje", "Só Hoje", 28),
    ("facil", "Fácil", 29),
    ("agora", "Agora", 30),
    ("dormi-na-praca", "Dormi Na Praça", 31),
    ("convite-de-casamento", "Convite de Casamento", 32),
    ("um-degrau-na-escada", "Um Degrau Na Escada", 34),
    ("minha-estrela-perdida", "Minha Estrela Perdida", 35),
    ("e-o-amor", "É o Amor", 36),
    ("dona-maria", "Dona Maria (part. Jorge)", 37),
    ("im-yours", "I'm Yours", 38),
    ("coracao", "Coração", 39),
    ("ai-se-eu-te-pego", "Ai Se Eu Te Pego", 40),
    ("largado-as-tracas", "Largado Às Traças", 41),
    ("status-que-eu-nao-queria", "Status Que Eu Não Queria", 42),
    ("para-pensa-e-volta", "Para, Pensa e Volta (part. Marília Mendonça)", 43),
    ("supera", "Supera", 44),
    ("pessimo-negocio", "Péssimo Negócio", 45),
    ("jogado-na-rua", "Jogado Na Rua", 46),
    ("casa-amarela", "Casa Amarela", 47),
    ("sem-radar", "Sem Radar", 48),
    ("carta-branca", "Carta Branca", 49),
    ("boate-azul", "Boate Azul", 50),
    ("telefone-mudo", "Telefone Mudo", 51),
    ("fio-de-cabelo", "Fio de Cabelo", 52),
    ("nuvem-de-lagrimas", "Nuvem de Lágrimas", 53),
    ("evidencias", "Evidências", 54),
    ("sinonimos", "Sinônimos", 56),
    ("grades-do-coracao", "Grades do Coração", 58),
    ("coracao-radiante", "Coração Radiante", 59),
    ("falta-voce", "Falta Você", 60),
    ("flor", "Flor", 61),
]

CATALOG_ID = "boteco-jul3-gojam"
ORANGE_RED_MIN = 0.8
KEY_OVERRIDES = {"sinonimos": "D"}


def deterministic_uuid(index: int) -> str:
    return str(uuid.UUID(f"b07ec000-0000-4000-8000-{index:012x}"))


def occupancy_boundary(chars: list[dict], start: int, end: int) -> tuple[float, int]:
    values: list[tuple[float, int]] = []
    for x in range(start, end):
        score = sum(
            1
            for char in chars
            for sample in range(x - 3, x + 4)
            if char["x0"] <= sample <= char["x1"]
        ) / 7
        values.append((score, x))
    return min(values)


def column_ranges(page: pdfplumber.page.Page, page_number: int) -> list[tuple[float, float]]:
    chars = [char for char in page.chars if 45 < char["top"] < 760 and char.get("text", "").strip()]
    if page_number == 56:
        # Tablature crosses the gutters on the first Sinônimos page.
        return [(0, 188), (188, 417), (417, page.width)]

    two_score, two_boundary = occupancy_boundary(chars, 270, 325)
    first_score, first_boundary = occupancy_boundary(chars, 190, 246)
    second_score, second_boundary = occupancy_boundary(chars, 340, 411)
    if first_score < 3 and second_score < 3:
        return [(0, first_boundary), (first_boundary, second_boundary), (second_boundary, page.width)]
    if two_score < 3:
        return [(0, two_boundary), (two_boundary, page.width)]
    return [(0, page.width)]


def is_orange(char: dict) -> bool:
    color = char.get("non_stroking_color")
    return isinstance(color, (list, tuple)) and len(color) >= 2 and color[0] >= ORANGE_RED_MIN and color[1] < 0.6


def make_line(kind: str, text: str, serial: int) -> dict:
    return {"id": deterministic_uuid(serial), "kind": kind, "text": text.rstrip()}


def extract_page_lines(
    page: pdfplumber.page.Page,
    page_number: int,
    is_first_page: bool,
    serial: int,
) -> tuple[list[dict], int]:
    result: list[dict] = []
    for left, right in column_ranges(page, page_number):
        crop = page.crop((left, 24, right, min(770, page.height)))
        column: list[dict] = []
        previous_top: float | None = None
        for raw_line in crop.extract_text_lines(layout=True, return_chars=True):
            text = raw_line["text"].strip()
            if not text:
                continue
            chars = raw_line["chars"]
            if is_first_page and (text.startswith("Key:") or any(float(char.get("size", 0)) > 10 for char in chars)):
                continue

            top = float(raw_line["top"])
            if previous_top is not None and top - previous_top > 15 and column and column[-1]["kind"] != "space":
                serial += 1
                column.append(make_line("space", "", serial))

            section_match = re.match(r"^(\[[^]]+\])\s*(.*)$", text)
            if section_match:
                serial += 1
                column.append(make_line("section", section_match.group(1), serial))
                remainder = section_match.group(2).strip()
                if remainder:
                    serial += 1
                    column.append(make_line("chords", remainder, serial))
            else:
                colored = sum(1 for char in chars if char.get("text", "").strip() and is_orange(char))
                visible = sum(1 for char in chars if char.get("text", "").strip())
                kind = "chords" if visible and colored / visible >= 0.5 else "lyrics"
                if text.lower().startswith("intro:"):
                    kind = "section"
                serial += 1
                column.append(make_line(kind, text, serial))
            previous_top = top

        while column and column[-1]["kind"] == "space":
            column.pop()
        if not column:
            continue
        if result and result[-1]["kind"] != "space":
            serial += 1
            result.append(make_line("space", "", serial))
        result.extend(column)
    return result, serial


def extract_key(page: pdfplumber.page.Page) -> str:
    match = re.search(r"\bKey:\s*([A-G](?:#|b)?m?)(?=\s|$)", page.extract_text() or "")
    return match.group(1) if match else ""


def build_catalog(pdf_path: Path) -> dict:
    serial = 1_000
    entries: list[dict] = []
    with pdfplumber.open(pdf_path) as document:
        if len(document.pages) != 62:
            raise ValueError(f"expected 62 PDF pages, found {len(document.pages)}")
        for index, (song_id, title, start_page) in enumerate(SONGS):
            end_page = SONGS[index + 1][2] - 1 if index + 1 < len(SONGS) else len(document.pages) - 1
            chart_lines: list[dict] = []
            for page_number in range(start_page, end_page + 1):
                page_lines, serial = extract_page_lines(
                    document.pages[page_number],
                    page_number,
                    is_first_page=page_number == start_page,
                    serial=serial,
                )
                if chart_lines and page_lines and chart_lines[-1]["kind"] != "space":
                    serial += 1
                    chart_lines.append(make_line("space", "", serial))
                chart_lines.extend(page_lines)
            entries.append(
                {
                    "catalogSongID": song_id,
                    "presetID": deterministic_uuid(index + 1),
                    "songTitle": title,
                    "originalKey": KEY_OVERRIDES.get(song_id, extract_key(document.pages[start_page])),
                    "startPage": start_page,
                    "endPage": end_page,
                    "chartLines": chart_lines,
                }
            )

    return {
        "schemaVersion": 1,
        "catalogID": CATALOG_ID,
        "name": "Boteco Jul3 - goJam",
        "sourceFileName": pdf_path.name,
        "entries": entries,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    catalog = build_catalog(args.pdf)
    if len(catalog["entries"]) != 57:
        raise ValueError("catalog must contain exactly 57 songs")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(catalog['entries'])} songs to {args.output}")


if __name__ == "__main__":
    main()
