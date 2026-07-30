#!/usr/bin/env python3
"""Validate the bilingual showcase, evidence tables, assets, scripts, and documents."""

from __future__ import annotations

import csv
import hashlib
import re
import subprocess
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

from pypdf import PdfReader


ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "reports" / "showcase" / "showcase_acceptance.md"
ASSETS = (
    "rls_overview.svg",
    "rls_algorithm_flow.svg",
    "rls_verification_flow.svg",
    "rls_convergence.svg",
    "rls_divider_optimization.svg",
    "rls_fpga_asic_comparison.svg",
)
TOPICS = (
    "overview.md", "architecture.md", "fixed_point.md", "verification.md",
    "asic_results.md", "fpga_results.md", "reproduction.md", "limitations.md",
)
PUBLIC_SCHEMA = (
    "domain", "metric", "variant", "value", "unit", "status", "tool",
    "evidence_file", "claim_boundary",
)


class Checks:
    def __init__(self) -> None:
        self.rows: list[tuple[str, str, str]] = []

    def require(self, name: str, condition: bool, detail: str) -> None:
        self.rows.append((name, "PASS" if condition else "FAIL", detail))

    @property
    def failures(self) -> list[tuple[str, str, str]]:
        return [row for row in self.rows if row[1] == "FAIL"]


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as stream:
        return list(csv.DictReader(stream))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_links(checks: Checks) -> None:
    failures: list[str] = []
    pattern = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)|!\[[^\]]*\]\(([^)]+)\)")
    for path in sorted(ROOT.rglob("*.md")):
        if any(part in {".git", "build"} for part in path.relative_to(ROOT).parts):
            continue
        for match in pattern.finditer(path.read_text(encoding="utf-8")):
            target = (match.group(1) or match.group(2)).strip().split("#", 1)[0]
            if not target or target.startswith(("http://", "https://", "mailto:")):
                continue
            if not (path.parent / target).resolve().exists():
                failures.append(f"{path.relative_to(ROOT).as_posix()} -> {target}")
    checks.require("markdown_links", not failures, "none broken" if not failures else "; ".join(failures[:10]))


def check_powershell(checks: Checks) -> None:
    failures: list[str] = []
    for path in sorted(ROOT.rglob("*.ps1")):
        if any(part in {".git", "build"} for part in path.relative_to(ROOT).parts):
            continue
        escaped = str(path).replace("'", "''")
        command = f"[void][scriptblock]::Create((Get-Content -LiteralPath '{escaped}' -Raw))"
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", command],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False,
        )
        if result.returncode != 0:
            failures.append(path.relative_to(ROOT).as_posix())
    checks.require("powershell_syntax", not failures, "all parse" if not failures else ", ".join(failures))


def main() -> int:
    checks = Checks()
    required = [
        ROOT / "README.md", ROOT / "README.en.md", ROOT / "PUBLIC_SCOPE.md",
        ROOT / "reports/showcase/public_results.csv",
        ROOT / "reports/showcase/evidence_index.md",
        ROOT / "docs/rls_asic_spec.md", ROOT / "docs/rls_asic_spec.docx", ROOT / "docs/rls_asic_spec.pdf",
        ROOT / "scripts/simulation/Launch-ConvergenceSimulation.ps1",
        ROOT / "scripts/simulation/Invoke-DividerCheck.ps1",
        ROOT / "reports/modelsim/fresh_run_summary.md",
        ROOT / "reports/asic/divider_fresh_run.md",
    ]
    checks.require("required_files", all(path.exists() for path in required), "core files present")
    docs = [ROOT / language / topic for language in ("docs/zh-CN", "docs/en") for topic in TOPICS]
    checks.require("bilingual_topics", all(path.exists() for path in docs) and len(docs) == 16, "16/16 present")

    zh = (ROOT / "README.md").read_text(encoding="utf-8")
    en = (ROOT / "README.en.md").read_text(encoding="utf-8")
    facts = (
        "RLS12_c_MW_top_divopt", "43.166", "43.249", "83.009", "-0.09",
        "3,257,856", "54.64", "21,535", "IN PROGRESS", "NOT_AVAILABLE",
    )
    checks.require("bilingual_facts", all(fact in zh and fact in en for fact in facts), "quantitative facts aligned")
    checks.require("claim_boundaries", all(value in zh and value in en for value in ("RTL_OBSERVED_A0", "IMPLEMENTATION_RESIDUAL_CONVERGENCE_OBSERVED")), "boundaries explicit")
    checks.require("no_fake_badges", all(token not in zh + en for token in ("Formality-PASS", "GLS-PASS", "silicon--ready", "CI-PASS")), "no unsupported badge")

    public_path = ROOT / "reports/showcase/public_results.csv"
    with public_path.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        public_rows = list(reader)
        schema = tuple(reader.fieldnames or ())
    checks.require("public_results_schema", schema == PUBLIC_SCHEMA, ",".join(schema))
    unavailable_bad = [row for row in public_rows if row["status"] in {"NOT_AVAILABLE", "NOT_EVALUABLE"} and row["value"] == "0"]
    checks.require("not_available_not_zero", not unavailable_bad, "NOT_AVAILABLE is textual")
    evidence_missing = [row["evidence_file"] for row in public_rows if not (ROOT / row["evidence_file"]).exists()]
    checks.require("public_evidence_paths", not evidence_missing, "all evidence paths resolve")

    metric_rows = read_csv(ROOT / "reports/modelsim/convergence_metrics.csv")
    divopt = {row["signal"]: row for row in metric_rows if row["implementation"] == "divopt"}
    expected = {
        "dout_sub_data1": (174918, 684, -43.165677278102656),
        "dout_sub_data2": (174918, 689, -43.248695518319586),
    }
    metrics_ok = len(divopt) == 2
    for signal, (samples, steady, db) in expected.items():
        row = divopt.get(signal, {})
        metrics_ok &= (
            int(row.get("valid_samples", "-1")) == samples
            and int(row.get("steady_state_update", "-1")) == steady
            and abs(float(row.get("late_to_early_db", "nan")) - db) < 1e-12
            and row.get("result") == "CONVERGED"
        )
    checks.require("convergence_metrics", bool(metrics_ok), "43.166/43.249 dB and 684/689")
    curve_rows = read_csv(ROOT / "reports/modelsim/convergence_curve.csv")
    curve_ok = len(curve_rows) == 1000 and all(not curve_rows[index]["dout_sub_data1_moving_rms_50"] for index in range(49))
    curve_ok &= all(curve_rows[index]["dout_sub_data1_moving_rms_50"] for index in range(49, 1000))
    checks.require("convergence_curve", bool(curve_ok), "1,000 deterministic rows")

    asset_paths = [ROOT / "docs/assets" / name for name in ASSETS]
    checks.require("svg_assets", all(path.exists() and path.stat().st_size > 1000 for path in asset_paths), "6/6 nontrivial")
    xml_ok = True
    for path in asset_paths:
        try:
            root = ET.fromstring(path.read_text(encoding="utf-8"))
            xml_ok &= root.tag.endswith("svg")
        except ET.ParseError:
            xml_ok = False
    checks.require("svg_xml", xml_ok, "all parse")
    before = {path.name: path.read_bytes() for path in asset_paths}
    generator = subprocess.run([sys.executable, str(ROOT / "scripts/documentation/gen_readme_assets.py")], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    deterministic = generator.returncode == 0 and all(path.read_bytes() == before[path.name] for path in asset_paths)
    checks.require("svg_determinism", deterministic, "byte-identical regeneration")

    digest = sha256(ROOT / "docs/rls_asic_spec.md")
    docx_path = ROOT / "docs/rls_asic_spec.docx"
    with zipfile.ZipFile(docx_path) as package:
        names = set(package.namelist())
        xml_parts = {name: package.read(name) for name in names if name.endswith(".xml")}
        core = ET.fromstring(package.read("docProps/core.xml"))
    core_text = {node.tag.rsplit("}", 1)[-1]: (node.text or "") for node in core}
    docx_ok = digest.encode("ascii") in xml_parts["word/document.xml"] and digest.encode("ascii") in xml_parts["docProps/core.xml"]
    docx_ok &= not core_text.get("creator") and not core_text.get("lastModifiedBy")
    docx_ok &= "docProps/custom.xml" not in names
    docx_ok &= not any(
        re.search(rb"\brsid[A-Za-z]*=|<[^>]*:?rsid[A-Za-z]*\b", data)
        for data in xml_parts.values()
    )
    checks.require("docx_fingerprint_metadata", bool(docx_ok), "fingerprint present; creator/rsid/custom clean")
    word_ns = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    w = lambda name: f"{{{word_ns}}}{name}"
    document_xml = ET.fromstring(xml_parts["word/document.xml"])
    styles_xml = ET.fromstring(xml_parts["word/styles.xml"])
    sect = document_xml.find(f".//{w('sectPr')}")
    pg_size = sect.find(w("pgSz")) if sect is not None else None
    pg_margin = sect.find(w("pgMar")) if sect is not None else None
    preset_ok = bool(
        pg_size is not None and pg_margin is not None
        and pg_size.get(w("w")) == "12240" and pg_size.get(w("h")) == "15840"
        and all(pg_margin.get(w(name)) == "1440" for name in ("top", "right", "bottom", "left"))
        and pg_margin.get(w("header")) == "708" and pg_margin.get(w("footer")) == "708"
    )
    style_tokens = {
        "Normal": ("22", "172033", "0", "120", "300"),
        "Heading1": ("32", "2E74B5", "360", "200", "240"),
        "Heading2": ("26", "2E74B5", "280", "140", "240"),
        "Heading3": ("24", "1F4D78", "200", "100", "240"),
    }
    for style_id, (size, color, before_value, after_value, line_value) in style_tokens.items():
        style = next((node for node in styles_xml.findall(w("style")) if node.get(w("styleId")) == style_id), None)
        rpr = style.find(w("rPr")) if style is not None else None
        ppr = style.find(w("pPr")) if style is not None else None
        fonts = rpr.find(w("rFonts")) if rpr is not None else None
        spacing = ppr.find(w("spacing")) if ppr is not None else None
        preset_ok &= bool(
            rpr is not None and fonts is not None and spacing is not None
            and fonts.get(w("ascii")) == "Calibri" and fonts.get(w("eastAsia")) == "Microsoft YaHei"
            and rpr.find(w("sz")).get(w("val")) == size
            and rpr.find(w("color")).get(w("val")) == color
            and spacing.get(w("before")) == before_value and spacing.get(w("after")) == after_value
            and spacing.get(w("line")) == line_value
        )
    for table in document_xml.findall(f".//{w('tbl')}"):
        table_pr = table.find(w("tblPr"))
        table_width = table_pr.find(w("tblW")) if table_pr is not None else None
        table_indent = table_pr.find(w("tblInd")) if table_pr is not None else None
        grid = [int(node.get(w("w"))) for node in table.find(w("tblGrid")).findall(w("gridCol"))]
        preset_ok &= bool(
            table_width is not None and table_width.get(w("w")) == "9360"
            and table_indent is not None and table_indent.get(w("w")) == "120"
            and sum(grid) == 9360
        )
        for row in table.findall(w("tr")):
            cell_widths = [int(cell.find(w("tcPr")).find(w("tcW")).get(w("w"))) for cell in row.findall(w("tc"))]
            preset_ok &= cell_widths == grid
    first_paragraph = document_xml.find(f".//{w('body')}/{w('p')}")
    preset_ok &= first_paragraph is not None and first_paragraph.find(f"{w('pPr')}/{w('pBdr')}") is None
    checks.require("docx_compact_preset", bool(preset_ok), "Letter/1in/Calibri+YaHei/styles/fixed tables/no title rule")

    pdf_path = ROOT / "docs/rls_asic_spec.pdf"
    pdf = PdfReader(pdf_path)
    metadata = pdf.metadata or {}
    pdf_text = "\n".join(page.extract_text() or "" for page in pdf.pages)
    page_size_ok = all(abs(float(page.mediabox.width) - 612) < 0.1 and abs(float(page.mediabox.height) - 792) < 0.1 for page in pdf.pages)
    pdf_ok = (
        len(pdf.pages) == 4 and digest in pdf_text
        and digest in str(metadata.get("/Subject", ""))
        and not metadata.get("/Author") and not metadata.get("/Creator") and not metadata.get("/Producer")
        and "/CreationDate" not in metadata and "/ModDate" not in metadata and page_size_ok
    )
    checks.require("pdf_fingerprint_metadata", bool(pdf_ok), "4 Letter pages; metadata scrubbed")
    fingerprint_rows = read_csv(ROOT / "reports/showcase/document_fingerprints.csv")
    fingerprint_ok = len(fingerprint_rows) == 3 and fingerprint_rows[0]["sha256"] == digest
    fingerprint_ok &= fingerprint_rows[1]["sha256"] == sha256(docx_path) and fingerprint_rows[2]["sha256"] == sha256(pdf_path)
    fingerprint_ok &= all(row["embedded_markdown_sha256"] in {"SOURCE", digest} for row in fingerprint_rows)
    checks.require("document_fingerprint_table", bool(fingerprint_ok), "MD/DOCX/PDF hashes current")

    filelist_ok = True
    for filelist in (ROOT / "rtl/filelists/portable.f", ROOT / "rtl/filelists/divopt.f"):
        for line in filelist.read_text(encoding="utf-8").splitlines():
            value = line.strip()
            if value and not value.startswith("#"):
                filelist_ok &= (ROOT / value).exists() and ".xci" not in value.lower()
    checks.require("rtl_filelists", filelist_ok, "relative, existing, XCI-free")

    utf_failures: list[str] = []
    text_extensions = {".md", ".csv", ".py", ".ps1", ".tcl", ".do", ".v", ".sv", ".sdc", ".xdc", ".f", ".svg", ".json", ".mem", ".coe", ".txt"}
    for path in ROOT.rglob("*"):
        relative = path.relative_to(ROOT)
        if path.is_file() and relative.parts[0] not in {".git", "build"} and (path.suffix.lower() in text_extensions or path.name in {".gitignore", ".gitattributes"}):
            try:
                path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                utf_failures.append(relative.as_posix())
    checks.require("utf8_text", not utf_failures, "all public text decodes")
    check_links(checks)
    check_powershell(checks)

    audit_files = ("public_scope_audit.md", "secret_scan.md", "file_size_audit.md")
    audit_ok = all((ROOT / "reports/showcase" / name).exists() and "Status: **PASS**" in (ROOT / "reports/showcase" / name).read_text(encoding="utf-8") for name in audit_files)
    checks.require("security_audits", audit_ok, "3/3 PASS")
    manifest_path = ROOT / "reports/showcase/repository_manifest.sha256"
    manifest_ok = manifest_path.exists()
    manifest_entries: dict[str, str] = {}
    if manifest_ok:
        for line in manifest_path.read_text(encoding="utf-8").splitlines():
            digest_value, separator, relative = line.partition("  ")
            if not separator or len(digest_value) != 64:
                manifest_ok = False
                continue
            manifest_entries[relative] = digest_value
        listed = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
        expected_paths = {
            value.decode("utf-8")
            for value in listed.stdout.split(b"\0")
            if value and value.decode("utf-8") != "reports/showcase/repository_manifest.sha256"
        }
        manifest_ok &= listed.returncode == 0
        manifest_ok &= set(manifest_entries) == expected_paths
        manifest_ok &= all(
            (ROOT / relative).exists() and sha256(ROOT / relative) == digest_value
            for relative, digest_value in manifest_entries.items()
        )
    checks.require("repository_manifest", bool(manifest_ok), f"entries={len(manifest_entries)}")

    status = "PASS" if not checks.failures else "FAIL"
    lines = [
        "# RLS GitHub Showcase acceptance",
        "",
        f"- Status: **{status}**",
        "- Expected terminal state: `RLS_GITHUB_SHOWCASE_COMPLETE_WITH_VIVADO_COMPARISON_PENDING`",
        f"- Checks: {len(checks.rows)}; failures: {len(checks.failures)}",
        "- DOCX/PDF visual QA: Word COM + Poppler, 4/4 pages inspected",
        "- SVG visual QA: 6/6 browser renders inspected",
        "",
        "| Check | Status | Detail |",
        "| --- | --- | --- |",
        *[f"| {name} | {result} | {detail.replace('|', '/')} |" for name, result, detail in checks.rows],
        "",
    ]
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text("\n".join(lines), encoding="utf-8")
    if checks.failures:
        for failure in checks.failures:
            print("FAIL", *failure, file=sys.stderr)
        return 1
    print(f"SHOWCASE_DOCUMENTATION_ACCEPTANCE_PASS checks={len(checks.rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
