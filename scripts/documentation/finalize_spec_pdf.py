#!/usr/bin/env python3
"""Scrub PDF metadata, embed the Markdown fingerprint, and write release hashes."""

from __future__ import annotations

import argparse
import csv
import hashlib
from pathlib import Path

from pypdf import PdfReader, PdfWriter


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--markdown", type=Path, required=True)
    parser.add_argument("--docx", type=Path, required=True)
    parser.add_argument("--input-pdf", type=Path, required=True)
    parser.add_argument("--output-pdf", type=Path, required=True)
    parser.add_argument("--fingerprint-csv", type=Path, required=True)
    args = parser.parse_args()
    markdown_digest = sha256(args.markdown)
    reader = PdfReader(args.input_pdf)
    writer = PdfWriter()
    writer.clone_document_from_reader(reader)
    writer.metadata = {}
    writer.add_metadata(
        {
            "/Title": "RLS ASIC/FPGA Portable RTL Specification",
            "/Subject": f"Markdown-SHA256:{markdown_digest}",
            "/Keywords": f"Markdown-SHA256:{markdown_digest}",
            "/Author": "",
            "/Creator": "",
            "/Producer": "",
        }
    )
    with args.output_pdf.open("wb") as stream:
        writer.write(stream)
    rows = [
        {"artifact": args.markdown.name, "sha256": markdown_digest, "embedded_markdown_sha256": "SOURCE"},
        {"artifact": args.docx.name, "sha256": sha256(args.docx), "embedded_markdown_sha256": markdown_digest},
        {"artifact": args.output_pdf.name, "sha256": sha256(args.output_pdf), "embedded_markdown_sha256": markdown_digest},
    ]
    args.fingerprint_csv.parent.mkdir(parents=True, exist_ok=True)
    with args.fingerprint_csv.open("w", newline="", encoding="utf-8") as stream:
        writer_csv = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer_csv.writeheader()
        writer_csv.writerows(rows)
    print(f"SPEC_PDF_FINALIZED pages={len(reader.pages)} markdown_sha256={markdown_digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
