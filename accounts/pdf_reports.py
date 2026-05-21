from __future__ import annotations

import shutil
import subprocess
import tempfile
from io import BytesIO
from pathlib import Path

from django.conf import settings
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen import canvas
from reportlab.platypus import (
    BaseDocTemplate,
    Flowable,
    Frame,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

from .html_reports import (
    _bullet_fallback as _html_bullet_fallback,
    _default_lead as _html_default_lead,
    _matched_sections as _html_matched_sections,
    _metrics_for_box as _html_metrics_for_box,
    _pair_lookup as _html_pair_lookup,
    _section_lead_and_items as _html_section_lead_and_items,
    _structured_table as _html_structured_table,
    _timeline_fallback as _html_timeline_fallback,
    _transcript_notes as _html_transcript_notes,
    build_health_report_html,
    parse_markdown_sections,
)
from .report_templates import ReportBoxSpec, ReportTemplate, box_spec, page_specs_for_problem, template_for_problem


INK = colors.HexColor("#0B372D")
MUTED = colors.HexColor("#60716B")
LINE = colors.HexColor("#DCEDE2")
PAPER = colors.HexColor("#FBFCF8")
WHITE = colors.white
WARNING = colors.HexColor("#F6A72D")
BAD = colors.HexColor("#E4583F")


def _styles(template: ReportTemplate) -> dict[str, ParagraphStyle]:
    return {
        "PageTitle": ParagraphStyle(
            "PageTitle",
            fontName="Helvetica-Bold",
            fontSize=15,
            leading=18,
            textColor=INK,
            spaceAfter=0,
        ),
        "CardTitle": ParagraphStyle(
            "CardTitle",
            fontName="Helvetica-Bold",
            fontSize=11,
            leading=13,
            textColor=INK,
        ),
        "Body": ParagraphStyle(
            "Body",
            fontName="Helvetica",
            fontSize=9,
            leading=12,
            textColor=INK,
        ),
        "Small": ParagraphStyle(
            "Small",
            fontName="Helvetica",
            fontSize=8,
            leading=10,
            textColor=INK,
        ),
        "SmallRight": ParagraphStyle(
            "SmallRight",
            parent=ParagraphStyle("SmallRightBase"),
            fontName="Helvetica",
            fontSize=8,
            leading=10,
            textColor=MUTED,
            alignment=TA_RIGHT,
        ),
        "Pill": ParagraphStyle(
            "Pill",
            fontName="Helvetica-Bold",
            fontSize=7.5,
            leading=9,
            textColor=colors.HexColor(template.primary_hex),
            alignment=TA_CENTER,
        ),
    }


def _draw_page_chrome(pdf: canvas.Canvas, doc, template: ReportTemplate) -> None:
    pdf.saveState()
    page_width, page_height = A4

    pdf.setFillColor(colors.HexColor("#F7FBF8"))
    pdf.rect(0, page_height - 22 * mm, page_width, 22 * mm, stroke=0, fill=1)
    pdf.setFillColor(colors.HexColor(template.primary_hex))
    pdf.rect(0, page_height - 4.5 * mm, page_width, 4.5 * mm, stroke=0, fill=1)

    pdf.setFont("Helvetica-Bold", 12)
    pdf.setFillColor(INK)
    pdf.drawString(doc.leftMargin, page_height - 13 * mm, _clean(template.title))

    pdf.setFont("Helvetica", 8)
    pdf.setFillColor(MUTED)
    pdf.drawRightString(
        page_width - doc.rightMargin,
        page_height - 13 * mm,
        f"Problem: {_clean(template.problem_name)}",
    )

    pdf.setStrokeColor(LINE)
    pdf.line(doc.leftMargin, 13 * mm, page_width - doc.rightMargin, 13 * mm)
    pdf.setFont("Helvetica", 8)
    pdf.drawString(doc.leftMargin, 9 * mm, "AI-generated structured health report")
    pdf.drawRightString(page_width - doc.rightMargin, 9 * mm, f"Page {doc.page}")
    pdf.restoreState()


class HeroBlock(Flowable):
    def __init__(self, report, template: ReportTemplate, values: dict, score: int):
        super().__init__()
        self.report = report
        self.template = template
        self.values = values
        self.score = score
        self.width = 0
        self.height = 32 * mm

    def wrap(self, availWidth, availHeight):
        self.width = availWidth
        return availWidth, self.height

    def draw(self):
        canv = self.canv
        canv.saveState()

        primary = colors.HexColor(self.template.primary_hex)
        light = colors.HexColor(self.template.light_hex)

        canv.setFillColor(light)
        canv.setStrokeColor(colors.HexColor("#DCEBE2"))
        canv.roundRect(0, 0, self.width, self.height, 4 * mm, stroke=1, fill=1)

        title = _clean(self.report.title or self.template.title)
        subtitle = _clean(self.values.get("daily_goal") or self.values.get("plan_focus") or "Structured clinical summary and action plan")
        note = _clean(self.values.get("primary_problem") or self.template.problem_name)

        canv.setFillColor(INK)
        canv.setFont("Helvetica-Bold", 15)
        canv.drawString(8 * mm, self.height - 9 * mm, title[:80])

        canv.setFont("Helvetica", 9)
        canv.setFillColor(MUTED)
        canv.drawString(8 * mm, self.height - 15 * mm, subtitle[:110])
        canv.drawString(8 * mm, self.height - 21 * mm, f"Focus: {note[:90]}")

        pill_text = f"Health Score {self.score}"
        pill_width = stringWidth(pill_text, "Helvetica-Bold", 9) + 12 * mm
        pill_x = max(self.width - pill_width - 8 * mm, 8 * mm)
        pill_y = self.height - 16 * mm
        canv.setFillColor(primary)
        canv.roundRect(pill_x, pill_y, pill_width, 8 * mm, 3.5 * mm, stroke=0, fill=1)
        canv.setFillColor(WHITE)
        canv.setFont("Helvetica-Bold", 9)
        canv.drawCentredString(pill_x + pill_width / 2, pill_y + 2.6 * mm, pill_text)

        canv.restoreState()


def _bullet_table(items: tuple[str, ...], template: ReportTemplate, styles: dict[str, ParagraphStyle]):
    rows = [[Paragraph(f"- {_xml(item)}", styles["Small"])] for item in items if _clean(item).strip()]
    if not rows:
        rows = [[Paragraph("No structured details captured yet.", styles["Small"])]]
    table = Table(rows, colWidths=[160 * mm])
    table.setStyle(
        TableStyle(
            [
                ("ROWBACKGROUNDS", (0, 0), (-1, -1), [WHITE, colors.HexColor("#F8FCF9")]),
                ("BOX", (0, 0), (-1, -1), 0.35, colors.HexColor("#E3EEE8")),
                ("INNERGRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#EAF2ED")),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]
        )
    )
    return table


def _small_pill(text: str, template: ReportTemplate, styles: dict[str, ParagraphStyle]):
    pill = Table([[Paragraph(f'<font color="{template.primary_hex}"><b>{_xml(text)}</b></font>', styles["Pill"])]])
    pill.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor(template.light_hex)),
                ("BOX", (0, 0), (-1, -1), 0.45, colors.HexColor("#D9EADF")),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    return pill


def build_health_report_pdf(report) -> bytes:
    html = build_health_report_html(report)
    rendered = _render_pdf_with_playwright(html)
    if rendered:
        return rendered
    return _build_health_report_pdf_fallback(report)


def _render_pdf_with_playwright(html: str) -> bytes | None:
    npx = shutil.which("npx") or shutil.which("npx.cmd")
    if not npx:
        return None

    with tempfile.TemporaryDirectory(prefix="flicko-report-") as temp_dir:
        temp_path = Path(temp_dir)
        html_path = temp_path / "report.html"
        pdf_path = temp_path / "report.pdf"
        html_path.write_text(html, encoding="utf-8")
        command = [
            npx,
            "playwright",
            "pdf",
            "--paper-format",
            "A4",
            "--wait-for-selector",
            ".report-shell",
            "--timeout",
            "60000",
            html_path.as_uri(),
            str(pdf_path),
        ]
        try:
            subprocess.run(
                command,
                cwd=settings.BASE_DIR.parent.parent,
                check=True,
                capture_output=True,
                text=True,
                timeout=90,
            )
        except Exception:
            return None
        if not pdf_path.exists():
            return None
        output = pdf_path.read_bytes()
        return output if output.startswith(b"%PDF") else None


def _build_health_report_pdf_fallback(report) -> bytes:
    template = template_for_problem(report.problem_name or report.title)
    values = report.dashboard_values if isinstance(report.dashboard_values, dict) else {}
    score = _score_value(values)
    markdown = (
        getattr(report, "report_markdown", None)
        or getattr(report, "intake_summary", "")
        or ""
    )
    sections = parse_markdown_sections(markdown)
    reminders = _safe_list(getattr(report, "reminders", ()))
    transcript_notes = _html_transcript_notes(getattr(report, "transcript", ()))
    pair_lookup = _html_pair_lookup(values, sections)
    buffer = BytesIO()
    document = BaseDocTemplate(
        buffer,
        pagesize=A4,
        title=_clean(report.title or template.title),
        leftMargin=14 * mm,
        rightMargin=14 * mm,
        topMargin=31 * mm,
        bottomMargin=18 * mm,
    )
    frame = Frame(
        document.leftMargin,
        document.bottomMargin,
        document.width,
        document.height,
        leftPadding=0,
        rightPadding=0,
        topPadding=0,
        bottomPadding=0,
    )
    document.addPageTemplates(
        [
            PageTemplate(
                id="flicko-report",
                frames=[frame],
                onPage=lambda pdf, doc: _draw_page_chrome(pdf, doc, template),
            )
        ]
    )
    document.build(
        _structured_story(
            report=report,
            template=template,
            values=values,
            sections=sections,
            reminders=reminders,
            transcript_notes=transcript_notes,
            pair_lookup=pair_lookup,
            score=score,
        )
    )
    return buffer.getvalue()


def _structured_story(
    *,
    report,
    template: ReportTemplate,
    values: dict,
    sections: tuple,
    reminders: tuple[str, ...],
    transcript_notes: tuple[str, ...],
    pair_lookup: dict[str, str],
    score: int,
) -> list:
    styles = _styles(template)
    story: list = [HeroBlock(report, template, values, score), Spacer(1, 8)]
    for page_index, page_spec in enumerate(page_specs_for_problem(template.problem_name)):
        if page_index:
            story.append(PageBreak())
        story.extend(
            [
                _page_heading(page_spec.eyebrow, page_spec.title, template, styles),
                Spacer(1, 6),
            ]
        )
        for box_id in page_spec.box_ids:
            story.extend(
                [
                    _report_box_card(
                        spec=box_spec(box_id),
                        template=template,
                        values=values,
                        sections=sections,
                        reminders=reminders,
                        transcript_notes=transcript_notes,
                        pair_lookup=pair_lookup,
                        score=score,
                        styles=styles,
                    ),
                    Spacer(1, 6),
                ]
            )
    story.append(_footer_notice(template, styles))
    return story


def _report_box_card(
    *,
    spec: ReportBoxSpec,
    template: ReportTemplate,
    values: dict,
    sections: tuple,
    reminders: tuple[str, ...],
    transcript_notes: tuple[str, ...],
    pair_lookup: dict[str, str],
    score: int,
    styles: dict[str, ParagraphStyle],
):
    matched_sections = _html_matched_sections(spec, sections)
    lead, items = _html_section_lead_and_items(matched_sections)
    lead_text = lead or _html_default_lead(spec)
    body: list = []

    if lead_text:
        body.extend([Paragraph(_xml(lead_text), styles["Body"]), Spacer(1, 4)])

    if spec.kind == "metrics":
        metrics = _html_metrics_for_box(spec, template, values, pair_lookup, score)
        rows = tuple(
            (
                item["label"],
                item["value"],
                "Needs verification" if item["missing"] else "Captured from saved data",
            )
            for item in metrics
        )
        body.append(
            _report_table(
                ("Metric", "Current record", "Use"),
                rows,
                template,
                styles,
            )
        )
        return _card(spec.title, body, template, styles, full_width=True)

    if spec.kind in {"table", "meal_plan", "week_plan"}:
        headers, rows, note = _html_structured_table(
            spec,
            template=template,
            values=values,
            sections=sections,
            matched_sections=matched_sections,
            reminders=reminders,
            transcript_notes=transcript_notes,
            pair_lookup=pair_lookup,
            score=score,
        )
        body.append(_report_table(headers, rows, template, styles))
        if note:
            body.extend([Spacer(1, 4), Paragraph(_xml(note), styles["Small"])])
        return _card(spec.title, body, template, styles, full_width=True)

    if spec.kind == "timeline":
        if not items:
            items = _html_timeline_fallback(spec, reminders, transcript_notes)
        body.append(_bullet_table(items, template, styles))
        return _card(spec.title, body, template, styles, full_width=True)

    if spec.kind == "doctor":
        doctor_items = items or tuple(template.doctor_questions)
        body.append(_bullet_table(doctor_items, template, styles))
        return _card(spec.title, body, template, styles, full_width=True)

    if not items:
        items = _html_bullet_fallback(spec, template, reminders, transcript_notes, sections)
    body.append(_bullet_table(items, template, styles))
    return _card(spec.title, body, template, styles, full_width=True)


def _report_table(
    headers: tuple[str, ...],
    rows: tuple[tuple[str, ...], ...],
    template: ReportTemplate,
    styles: dict[str, ParagraphStyle],
):
    table_rows: list[list[Paragraph]] = [
        [Paragraph(f'<font color="#FFFFFF"><b>{_xml(header)}</b></font>', styles["Small"]) for header in headers]
    ]
    for row in rows:
        padded = list(row) + [""] * max(0, len(headers) - len(row))
        table_rows.append([Paragraph(_xml(cell), styles["Small"]) for cell in padded[: len(headers)]])

    col_widths = _table_widths(len(headers))
    table = Table(table_rows, colWidths=col_widths, repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor(template.primary_hex)),
                ("TEXTCOLOR", (0, 0), (-1, 0), WHITE),
                ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#DCEBE2")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [WHITE, colors.HexColor("#F8FCF9")]),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]
        )
    )
    return table


def _table_widths(column_count: int) -> list[float]:
    if column_count <= 1:
        return [160 * mm]
    if column_count == 2:
        return [52 * mm, 108 * mm]
    if column_count == 3:
        return [42 * mm, 68 * mm, 50 * mm]
    if column_count == 4:
        return [38 * mm, 40 * mm, 40 * mm, 42 * mm]
    width = 160 * mm / column_count
    return [width] * column_count


def _page_heading(eyebrow: str, title: str, template: ReportTemplate, styles: dict[str, ParagraphStyle]):
    body = Table(
        [
            [
                [
                    Paragraph(f'<font color="{template.primary_hex}"><b>{_xml(eyebrow)}</b></font>', styles["Small"]),
                    Paragraph(_xml(title), styles["PageTitle"]),
                ],
                _small_pill(template.problem_name, template, styles),
            ]
        ],
        colWidths=[124 * mm, 46 * mm],
    )
    body.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("BOTTOMPADDING", (0, 0), (-1, -1), 8)]))
    return body


def _footer_notice(template: ReportTemplate, styles: dict[str, ParagraphStyle]):
    body = Table(
        [
            [
                Paragraph("<b>This report is AI-generated for informational purposes only.</b><br/>Always consult your healthcare professional for medical advice.", styles["Small"]),
                Paragraph("Generated by Flicko AI", styles["SmallRight"]),
            ]
        ],
        colWidths=[115 * mm, 49 * mm],
    )
    body.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor(template.light_hex)),
                ("BOX", (0, 0), (-1, -1), .7, colors.HexColor("#DCEBE2")),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ]
        )
    )
    return body


def _card(
    title: str,
    body,
    template: ReportTemplate,
    styles: dict[str, ParagraphStyle],
    *,
    keep: bool = False,
    full_width: bool = False,
    fill=WHITE,
):
    if not isinstance(body, list):
        body = [body]
    width = 170 * mm if full_width else 82 * mm
    table = Table(
        [
            [Paragraph(f'<font color="{template.primary_hex}"><b>-</b></font> {_xml(title)}', styles["CardTitle"])],
            [body],
        ],
        colWidths=[width],
    )
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), fill),
                ("BOX", (0, 0), (-1, -1), .7, colors.HexColor("#DCEBE2")),
                ("LINEBELOW", (0, 0), (-1, 0), .45, colors.HexColor("#E6EFE9")),
                ("LEFTPADDING", (0, 0), (-1, -1), 9),
                ("RIGHTPADDING", (0, 0), (-1, -1), 9),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]
        )
    )
    return KeepTogether(table) if keep else table


def _score_value(values: dict) -> int:
    for key in ("score", "health_score", "daily_score", "weight_score"):
        value = values.get(key)
        try:
            return max(0, min(100, int(float(value))))
        except (TypeError, ValueError):
            continue
    return 78


def _lookup_value(values: dict, label: str) -> str:
    normalized_label = _normalize_key(label)
    for key, value in values.items():
        normalized_key = _normalize_key(str(key))
        if normalized_key == normalized_label or normalized_label in normalized_key:
            return _format_value(value)
    return ""


def _safe_list(value) -> tuple[str, ...]:
    if not isinstance(value, list):
        return ()
    return tuple(str(item).strip() for item in value if str(item).strip())


def _format_value(value) -> str:
    if isinstance(value, list):
        return ", ".join(str(item) for item in value if str(item).strip())
    if isinstance(value, dict):
        return ", ".join(
            f"{str(key).replace('_', ' ').title()}: {val}" for key, val in value.items()
        )
    return str(value)


def _normalize_key(value: str) -> str:
    return "".join(ch for ch in value.lower() if ch.isalnum())


def _asset_path(*parts: str) -> Path:
    return settings.BASE_DIR.parent / "mobile" / "assets" / "images" / Path(*parts)


def _set_alpha(pdf: canvas.Canvas, value: float) -> None:
    try:
        pdf.setFillAlpha(value)
        pdf.setStrokeAlpha(value)
    except Exception:
        pass


def _xml(value: object) -> str:
    return (
        _clean(value)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


def _clean(value: object) -> str:
    text = str(value)
    replacements = {
        "\u2013": "-",
        "\u2014": "-",
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2022": "-",
        "\u00a0": " ",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    return text.encode("latin-1", "replace").decode("latin-1")
