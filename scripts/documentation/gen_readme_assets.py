#!/usr/bin/env python3
"""Generate deterministic, offline SVG assets for the RLS showcase."""

from __future__ import annotations

import csv
import math
from html import escape
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "docs" / "assets"
WIDTH = 1200
BG = "#f8fafc"
INK = "#172033"
MUTED = "#526175"
BLUE = "#2563a6"
TEAL = "#167d74"
GREEN = "#2f855a"
RED = "#b5413b"
GOLD = "#b7791f"
LINE = "#c7d0dc"
PANEL = "#ffffff"


def header(title: str, subtitle: str, height: int = 640) -> list[str]:
    return [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{height}" viewBox="0 0 {WIDTH} {height}" role="img" aria-labelledby="title desc">',
        f'<title id="title">{escape(title)}</title>',
        f'<desc id="desc">{escape(subtitle)}</desc>',
        '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="#526175"/></marker></defs>',
        f'<rect width="{WIDTH}" height="{height}" fill="{BG}"/>',
        f'<text x="48" y="54" font-family="Arial, sans-serif" font-size="28" font-weight="700" fill="{INK}">{escape(title)}</text>',
        f'<text x="48" y="82" font-family="Arial, sans-serif" font-size="15" fill="{MUTED}">{escape(subtitle)}</text>',
    ]


def text(lines: list[str], x: float, y: float, value: str, size: int = 15, color: str = INK,
         weight: int = 400, anchor: str = "start") -> None:
    lines.append(
        f'<text x="{x:.1f}" y="{y:.1f}" text-anchor="{anchor}" font-family="Arial, sans-serif" '
        f'font-size="{size}" font-weight="{weight}" fill="{color}">{escape(value)}</text>'
    )


def box(lines: list[str], x: float, y: float, w: float, h: float, title: str,
        details: list[str], accent: str = BLUE) -> None:
    lines.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="7" fill="{PANEL}" stroke="{LINE}" stroke-width="1.5"/>')
    lines.append(f'<rect x="{x}" y="{y}" width="6" height="{h}" rx="3" fill="{accent}"/>')
    text(lines, x + 18, y + 27, title, 16, INK, 700)
    for index, detail in enumerate(details):
        text(lines, x + 18, y + 51 + index * 20, detail, 12, MUTED)


def arrow(lines: list[str], x1: float, y1: float, x2: float, y2: float, dashed: bool = False) -> None:
    dash = ' stroke-dasharray="6 5"' if dashed else ""
    lines.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{MUTED}" stroke-width="2" marker-end="url(#arrow)"{dash}/>')


def finish(lines: list[str], name: str) -> None:
    lines.append("</svg>")
    (ASSETS / name).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def overview() -> None:
    lines = header("RLS Soft IP architecture", "12-tap complex RLS | 150-cycle core | 175-cycle steady update | RTL_OBSERVED_A0", 700)
    labels = [
        ("Reference / Desired", ["24Q13 complex inputs", "single-reference alias"], BLUE),
        ("FIFO / Pack Memory", ["18 SRAM wrappers", "portable semantics"], TEAL),
        ("12-tap FIR", ["prediction Y", "residual E = D - Y"], BLUE),
        ("P times u / Denominator", ["P0 = 8I", "34Q25 denominator"], GOLD),
        ("Radix-4 Divider", ["aligned iterative", "40-edge compatibility"], RED),
        ("Gain K", ["24Q20", "fixed RTL slicing"], TEAL),
        ("Weight Update W", ["12 x complex 36Q27", "serialized output"], BLUE),
        ("P Rank-1 Update", ["40-bit accumulator", "wrap / truncation"], GOLD),
        ("Residual / Status", ["RLS_out + weights", "update counter"], GREEN),
    ]
    positions = [(48 + col * 384, 122 + row * 168) for row in range(3) for col in range(3)]
    for (title_value, details, accent), (x, y) in zip(labels, positions):
        box(lines, x, y, 336, 112, title_value, details, accent)
    for row in range(3):
        arrow(lines, 384, 178 + row * 168, 426, 178 + row * 168)
        arrow(lines, 768, 178 + row * 168, 810, 178 + row * 168)
    arrow(lines, 978, 234, 978, 276)
    arrow(lines, 810, 332, 768, 332)
    arrow(lines, 426, 332, 384, 332)
    arrow(lines, 216, 388, 216, 444)
    arrow(lines, 384, 500, 426, 500)
    arrow(lines, 768, 500, 810, 500)
    lines.append(f'<rect x="48" y="642" width="1104" height="36" rx="6" fill="#e8eef5"/>')
    text(lines, 600, 666, "150-cycle core | 175-cycle steady update | one 208-cycle refill | alias mode", 14, INK, 700, "middle")
    finish(lines, "rls_overview.svg")


def algorithm() -> None:
    lines = header("Algorithm and fixed-point flow", "Explicit formats, lane boundaries, and RTL-prescribed wrap/truncation", 680)
    stages = [
        ("Input u, d", "24Q13", "upper-real / lower-imag", BLUE),
        ("P times u", "P: 36Q29", "40-bit/component sum", TEAL),
        ("Denominator", "34Q25", "lambda + u^H P u", GOLD),
        ("Reciprocal / K", "24Q20", "Radix-4 Q32 -> slice", RED),
        ("Y and E", "36Q25", "E = D - Y", BLUE),
        ("W update", "36Q27", "12 complex taps", TEAL),
        ("P update", "36Q29", "rank-1, wrap/truncate", GOLD),
    ]
    y_values = [120, 195, 270, 345, 420, 495, 570]
    for index, ((title_value, fmt, detail, accent), y) in enumerate(zip(stages, y_values)):
        box(lines, 315, y, 570, 58, title_value, [f"{fmt} | {detail}"], accent)
        if index < len(stages) - 1:
            arrow(lines, 600, y + 58, 600, y_values[index + 1])
    box(lines, 48, 150, 220, 105, "Initialization", ["P0 = 8I", "W0 = 0", "12 taps"], GREEN)
    arrow(lines, 268, 202, 315, 202)
    box(lines, 932, 310, 220, 130, "Arithmetic contract", ["two's-complement wrap", "fixed bit slices", "no saturation", "RTL_OBSERVED_A0"], RED)
    arrow(lines, 885, 374, 932, 374, True)
    finish(lines, "rls_algorithm_flow.svg")


def verification() -> None:
    lines = header("Evidence-first verification flow", "Preserved implementation evidence plus reproducible public portable/divopt checks", 630)
    stages = [
        ("Deterministic vectors", ["two 65,525-sample inputs", "SHA-256 checked"], BLUE),
        ("Original Xilinx RTL", ["generated-IP hierarchy", "preserved locally"], MUTED),
        ("Implementation oracle", ["event alignment", "bit-exact boundary"], GOLD),
        ("Portable / divopt RTL", ["XCI-free", "aligned Radix-4"], TEAL),
        ("ModelSim checker", ["residual / weights / XZ", "schedule"], BLUE),
        ("1,000-update run", ["43.166 / 43.249 dB", "684 / 689"], GREEN),
        ("DC diagnosis", ["area / STA", "SRAM excluded"], RED),
        ("Explicit blockers", ["no full PPA/signoff", "Vivado compare excluded"], GOLD),
    ]
    positions = [(48 + col * 288, 132 + row * 205) for row in range(2) for col in range(4)]
    for item, (x, y) in zip(stages, positions):
        box(lines, x, y, 245, 112, item[0], item[1], item[2])
    for col in range(3):
        arrow(lines, 293 + col * 288, 188, 336 + col * 288, 188)
        arrow(lines, 293 + col * 288, 393, 336 + col * 288, 393)
    arrow(lines, 1065, 244, 1065, 286)
    arrow(lines, 912, 342, 869, 342)
    arrow(lines, 624, 342, 581, 342)
    arrow(lines, 336, 342, 293, 342)
    lines.append(f'<rect x="48" y="548" width="1104" height="42" rx="7" fill="#fef3c7" stroke="#ead18b"/>')
    text(lines, 600, 574, "Fresh portable run does not recreate the excluded generated-XCI FPGA baseline", 14, INK, 700, "middle")
    finish(lines, "rls_verification_flow.svg")


def convergence() -> None:
    metrics_path = ROOT / "reports" / "modelsim" / "convergence_metrics.csv"
    curve_path = ROOT / "reports" / "modelsim" / "convergence_curve.csv"
    with metrics_path.open(newline="", encoding="utf-8-sig") as stream:
        metrics = {row["signal"]: row for row in csv.DictReader(stream) if row["implementation"] == "divopt"}
    with curve_path.open(newline="", encoding="utf-8-sig") as stream:
        rows = list(csv.DictReader(stream))
    series: dict[str, list[tuple[int, float]]] = {key: [] for key in metrics}
    for row in rows:
        update = int(row["update"])
        for signal in series:
            value = row[f"{signal}_moving_rms_50"]
            if value:
                series[signal].append((update, float(value)))

    lines = header("ModelSim residual convergence", "50-update moving RMS generated from the formal convergence CSV", 660)
    left, top, right, bottom = 92, 120, 1148, 540
    lines.append(f'<rect x="{left}" y="{top}" width="{right-left}" height="{bottom-top}" fill="#ffffff" stroke="{LINE}"/>')
    all_values = [value for points in series.values() for _, value in points]
    ymin, ymax = math.log10(min(all_values)), math.log10(max(all_values))

    def xy(update: int, value: float) -> tuple[float, float]:
        x = left + (update - 1) / 999 * (right - left)
        y = bottom - (math.log10(value) - ymin) / (ymax - ymin) * (bottom - top)
        return x, y

    for update in (1, 200, 400, 600, 800, 1000):
        x = left + (update - 1) / 999 * (right - left)
        lines.append(f'<line x1="{x:.1f}" y1="{top}" x2="{x:.1f}" y2="{bottom}" stroke="#e5e9ef"/>')
        text(lines, x, bottom + 23, str(update), 12, MUTED, anchor="middle")
    for tick in range(5):
        level = ymin + tick / 4 * (ymax - ymin)
        y = bottom - tick / 4 * (bottom - top)
        lines.append(f'<line x1="{left}" y1="{y:.1f}" x2="{right}" y2="{y:.1f}" stroke="#e5e9ef"/>')
        text(lines, left - 12, y + 4, f"{10**level:.1f}", 12, MUTED, anchor="end")
    for signal, color in (("dout_sub_data1", BLUE), ("dout_sub_data2", RED)):
        points = " ".join(f"{xy(update, value)[0]:.1f},{xy(update, value)[1]:.1f}" for update, value in series[signal])
        lines.append(f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="2.5"/>')
    for signal, color in (("dout_sub_data1", BLUE), ("dout_sub_data2", RED)):
        steady = int(metrics[signal]["steady_state_update"])
        x = left + (steady - 1) / 999 * (right - left)
        lines.append(f'<line x1="{x:.1f}" y1="{top}" x2="{x:.1f}" y2="{bottom}" stroke="{color}" stroke-width="1.5" stroke-dasharray="7 5"/>')
        db = abs(float(metrics[signal]["late_to_early_db"]))
        text(lines, x + 6, top + (24 if signal.endswith("1") else 48), f"update {steady} | {db:.3f} dB", 13, color, 700)
    text(lines, (left + right) / 2, 594, "RLS update", 14, INK, 700, "middle")
    text(lines, 18, 109, "moving RMS (log scale)", 13, MUTED)
    lines.append(f'<line x1="100" y1="622" x2="135" y2="622" stroke="{BLUE}" stroke-width="4"/>')
    text(lines, 145, 627, "dout_sub_data1", 13, INK)
    lines.append(f'<line x1="320" y1="622" x2="355" y2="622" stroke="{RED}" stroke-width="4"/>')
    text(lines, 365, 627, "dout_sub_data2", 13, INK)
    text(lines, 1148, 627, "IMPLEMENTATION_RESIDUAL_CONVERGENCE_OBSERVED", 12, MUTED, 700, "end")
    finish(lines, "rls_convergence.svg")


def divider() -> None:
    lines = header("Divider architecture optimization", "Expanded quotient pipeline to aligned iterative Radix-4", 610)
    box(lines, 70, 145, 410, 180, "Expanded 40-bit quotient pipeline", ["area 108089.645137", "10 ns WNS -191.04 ns", "40-edge external contract", "COMPLETED_VIOLATED"], RED)
    arrow(lines, 480, 235, 715, 235)
    box(lines, 720, 145, 410, 180, "Aligned Radix-4 iterative divider", ["area 18365.116790", "10 ns WNS +3.13 ns", "40-edge compatibility", "checker 1,160/1,160"], GREEN)
    lines.append(f'<rect x="305" y="365" width="590" height="94" rx="7" fill="#e8eef5" stroke="{LINE}"/>')
    text(lines, 600, 399, "83.009% isolated block-area reduction", 22, INK, 700, "middle")
    text(lines, 600, 431, "same exact Q32 rounding contract | zero mismatch", 15, MUTED, 400, "middle")
    lines.append(f'<rect x="70" y="500" width="1060" height="62" rx="7" fill="#fef3c7" stroke="#ead18b"/>')
    text(lines, 600, 526, "Top 10 ns WNS remains -0.09 ns: divider success is not top-level timing closure", 15, INK, 700, "middle")
    text(lines, 600, 548, "FreePDK45 / GSCL45 typical-only 1.10 V / 27 C | pre-layout diagnosis", 12, MUTED, anchor="middle")
    finish(lines, "rls_divider_optimization.svg")


def comparison() -> None:
    lines = header("FPGA and ASIC evidence are different quantities", "Do not convert LUT/FF/BRAM/DSP into standard-cell area/SRAM/STA", 620)
    box(lines, 55, 130, 440, 315, "FPGA prototype | accepted baseline", ["Vivado 2024.2", "21,535 LUT", "42,855 registers", "103 BRAM Tile", "352 DSP48E2", "65.104 ns constraint", "WNS +55.532 ns | TNS 0", "hold +0.010 ns"], BLUE)
    box(lines, 705, 130, 440, 315, "ASIC portable RTL | frontend diagnosis", ["Design Compiler", "standard-cell logic area", "18 SRAM wrappers / 3,257,856 bits", "top 10 ns WNS -0.09 ns", "SRAM PPA NOT_AVAILABLE", "power NOT_EVALUABLE", "pre-layout, typical-only", "not signoff"], TEAL)
    text(lines, 600, 250, "not equal", 22, RED, 700, "middle")
    lines.append(f'<line x1="535" y1="276" x2="665" y2="276" stroke="{RED}" stroke-width="4"/>')
    lines.append(f'<line x1="535" y1="292" x2="665" y2="292" stroke="{RED}" stroke-width="4"/>')
    lines.append(f'<line x1="650" y1="254" x2="550" y2="314" stroke="{RED}" stroke-width="4"/>')
    lines.append(f'<rect x="55" y="490" width="1090" height="78" rx="7" fill="#fef3c7" stroke="#ead18b"/>')
    text(lines, 600, 520, "New Vivado original/divopt comparison: IN PROGRESS / EXCLUDED", 17, INK, 700, "middle")
    text(lines, 600, 548, "Only the previous accepted FPGA baseline is published", 13, MUTED, anchor="middle")
    finish(lines, "rls_fpga_asic_comparison.svg")


def main() -> int:
    ASSETS.mkdir(parents=True, exist_ok=True)
    overview()
    algorithm()
    verification()
    convergence()
    divider()
    comparison()
    print("SHOWCASE_ASSETS_GENERATED count=6")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
