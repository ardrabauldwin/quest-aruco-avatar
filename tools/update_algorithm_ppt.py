"""Update the NaReT algorithm deck to the runtime installed on 2026-09-05."""

from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.util import Inches, Pt


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "Quest_Avatar_Placement_Algorithm_NaReT_Updated.pptx"
OUTPUT = ROOT / "docs" / "Quest_Avatar_Placement_Algorithm_NaReT_Current_2026-09-05.pptx"

BLUE = RGBColor(0x19, 0x76, 0xD2)
NAVY = RGBColor(0x16, 0x32, 0x4F)
BORDER = RGBColor(0xC8, 0xD6, 0xE2)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)


def replace_text(shape, old: str, new: str) -> None:
    """Replace text across a shape's runs without changing its formatting."""
    if not shape.has_text_frame or old not in shape.text:
        raise ValueError(f"Could not find {old!r} in {shape.name}: {shape.text!r}")
    for paragraph in shape.text_frame.paragraphs:
        for run in paragraph.runs:
            if old in run.text:
                run.text = run.text.replace(old, new)
                return

    # The requested text spans multiple runs. Preserve the first run's style and clear the rest.
    paragraph = shape.text_frame.paragraphs[0]
    runs = paragraph.runs
    combined = "".join(run.text for run in runs)
    if old not in combined:
        raise ValueError(f"Could not replace split text {old!r} in {shape.name}")
    runs[0].text = combined.replace(old, new)
    for run in runs[1:]:
        run.text = ""


def set_single_run(shape, text: str) -> None:
    """Replace a one-run label while retaining the existing run style."""
    paragraphs = shape.text_frame.paragraphs
    if len(paragraphs) != 1 or len(paragraphs[0].runs) != 1:
        raise ValueError(f"Expected one run in {shape.name}")
    paragraphs[0].runs[0].text = text


def add_floor_lock_panel(slide) -> None:
    header = slide.shapes.add_shape(
        MSO_SHAPE.ROUNDED_RECTANGLE,
        Inches(9.35), Inches(2.44), Inches(3.38), Inches(0.75),
    )
    header.fill.solid()
    header.fill.fore_color.rgb = BLUE
    header.line.color.rgb = BLUE
    header.text_frame.clear()
    header.text_frame.vertical_anchor = MSO_ANCHOR.MIDDLE
    paragraph = header.text_frame.paragraphs[0]
    paragraph.alignment = PP_ALIGN.CENTER
    run = paragraph.add_run()
    run.text = "FLOOR-LOCK"
    run.font.name = "Aptos"
    run.font.size = Pt(16)
    run.font.bold = True
    run.font.color.rgb = WHITE

    body = slide.shapes.add_shape(
        MSO_SHAPE.ROUNDED_RECTANGLE,
        Inches(9.35), Inches(3.50), Inches(3.38), Inches(2.12),
    )
    body.fill.solid()
    body.fill.fore_color.rgb = WHITE
    body.line.color.rgb = BORDER
    body.text_frame.clear()
    body.text_frame.margin_left = Inches(0.18)
    body.text_frame.margin_right = Inches(0.14)
    body.text_frame.margin_top = Inches(0.13)
    body.text_frame.margin_bottom = Inches(0.10)
    body.text_frame.vertical_anchor = MSO_ANCHOR.MIDDLE
    lines = (
        "Marker local Y → horizontal body direction",
        "Quest UP → vertical reference",
        "Cross product → sideways axis",
        "",
        "Marker pitch + roll discarded",
    )
    for index, text in enumerate(lines):
        paragraph = (
            body.text_frame.paragraphs[0]
            if index == 0
            else body.text_frame.add_paragraph()
        )
        paragraph.alignment = PP_ALIGN.LEFT
        paragraph.space_after = Pt(0)
        run = paragraph.add_run()
        run.text = text
        run.font.name = "Aptos"
        run.font.size = Pt(13.5)
        run.font.color.rgb = NAVY


def main() -> None:
    prs = Presentation(SOURCE)

    # Title slide: identify this as the implemented, measured runtime.
    slide = prs.slides[0]
    replace_text(
        slide.shapes[2],
        "Current detection, reconstruction, rest and filtering algorithm",
        "Floor-locked, grid-selected runtime • installed 5 September 2026",
    )

    # Reconstruction now explicitly includes the CPR floor-orientation constraint.
    slide = prs.slides[2]
    set_single_run(slide.shapes[1], "Reconstruct, fuse and floor-lock the common pose")
    set_single_run(
        slide.shapes[3],
        "Only markers from the exact newest camera result are combined; orientation is then constrained to the floor.",
    )
    add_floor_lock_panel(slide)
    set_single_run(slide.shapes[10], "navel_provider.gd::_fuse • navel_provider.gd::_floor_lock")

    # Grid-selected startup rest flow. Runtime uses a rotation medoid, not tangent median.
    slide = prs.slides[3]
    for shape_index, value in zip((4, 7, 10, 13), ("40", "45", "50", "55")):
        set_single_run(slide.shapes[shape_index], value)
    set_single_run(
        slide.shapes[15],
        "Each estimate uses coordinate-median position + one measured rotation medoid over all collected poses.",
    )
    replace_text(slide.shapes[16], "rotation ≤ 0.5°,35 PERC TIME", "rotation ≤ 0.5°")
    replace_text(slide.shapes[17], "detection 35", "detection 55")
    replace_text(slide.shapes[17], "Detection 50 fallback ≈11.4 s", "Detection 100 fallback ≈20 s")
    set_single_run(
        slide.shapes[18],
        "Grid-selected on both calibration replays • 95–97% stationary confirmation • 0% moving false acceptance",
    )

    # Runtime filter values installed in the APK.
    slide = prs.slides[4]
    slide.shapes[4].text_frame.paragraphs[0].runs[0].text = "FLOOR-LOCKED"
    slide.shapes[4].text_frame.paragraphs[0].runs[1].text = "MEASUREMENT"
    replace_text(slide.shapes[22], "position dead zone 6 mm", "position dead zone 5 mm")
    replace_text(slide.shapes[22], "rotation dead zone 0.5°", "rotation dead zone 1.5°")
    replace_text(
        slide.shapes[22],
        "Current values: window 7",
        "Selected values: window 7 • radius 0.10 m",
    )

    slide = prs.slides[5]
    replace_text(slide.shapes[12], "0.2864789 m", "0.10 m")
    replace_text(slide.shapes[12], "5 mm", "1.75 mm")
    set_single_run(
        slide.shapes[13],
        "simple_pose_stabilizer.gd::_medoid • 0.10 m selected across old/new calibration replays",
    )

    slide = prs.slides[6]
    slide.shapes[4].text_frame.paragraphs[0].runs[0].text = "≤5 mm position"
    slide.shapes[4].text_frame.paragraphs[0].runs[1].text = "≤1.5° rotation"

    # Correct the earlier claim that the re-anchor floor blocks all stationary bias.
    slide = prs.slides[7]
    set_single_run(
        slide.shapes[10],
        "LIMIT: the newest stationary test exposed stable viewpoint errors up to 114 mm. The re-anchor floor cannot reject a large, stable wrong pose; marker agreement must be fixed before fusion.",
    )

    slide = prs.slides[8]
    slide.shapes[14].text_frame.paragraphs[0].runs[1].text = "55–100 detections"
    slide.shapes[14].text_frame.paragraphs[0].runs[2].text = "≈11–20 s"

    slide = prs.slides[9]
    set_single_run(
        slide.shapes[9],
        "Floor-lock sets local Z down and local Y to horizontal body heading before this fixed model correction is applied.",
    )

    # Replace the provisional table with the measured conclusion and the remaining open problem.
    slide = prs.slides[10]
    set_single_run(slide.shapes[1], "What the latest experiments selected")
    set_single_run(
        slide.shapes[3],
        "Stationary + 617.5 mm movement replays selected the filter; hiding and compression recordings were hold-out checks.",
    )
    set_single_run(slide.shapes[9], "start / step / fallback")
    set_single_run(slide.shapes[10], "40 / 5 / 100")
    set_single_run(slide.shapes[11], "Selected*")
    set_single_run(slide.shapes[13], "window • radius • dead zones • smoothing")
    set_single_run(slide.shapes[14], "7 • 0.10 m • 5 mm / 1.5° • 0.8 s")
    slide.shapes[14].text_frame.paragraphs[0].runs[0].font.size = Pt(10.5)
    set_single_run(slide.shapes[15], "Selected*")
    set_single_run(slide.shapes[17], "prior • re-anchor floor")
    set_single_run(slide.shapes[19], "Retained")
    set_single_run(slide.shapes[21], "mean • robust • agreement-gated")
    set_single_run(slide.shapes[23], "Open issue")
    set_single_run(
        slide.shapes[24],
        "Hold-out result: filtering cannot remove stable 2–12 cm disagreement between marker estimates",
    )
    set_single_run(
        slide.shapes[25],
        "*Best supported values for this dataset; marker-fusion reliability remains unresolved",
    )

    # The next-work slide now follows directly from the measured failure mode.
    slide = prs.slides[12]
    set_single_run(slide.shapes[4], "ARCHIVE INSTALLED BUILD")
    set_single_run(
        slide.shapes[5],
        "Keep the 5 September APK, exact filter values and previous calibration as the reproducible baseline.",
    )
    set_single_run(slide.shapes[8], "FIX MARKER AGREEMENT")
    set_single_run(
        slide.shapes[9],
        "Detect disagreeing common-pose estimates before fusion; do not blindly mean-average a bad marker.",
    )
    set_single_run(slide.shapes[12], "RE-CHECK CALIBRATION")
    set_single_run(
        slide.shapes[13],
        "Use tape-consistent marker geometry and test that changing headset viewpoint does not move the mannequin.",
    )
    set_single_run(slide.shapes[16], "VALIDATE FULL CPR")
    set_single_run(
        slide.shapes[17],
        "Repeat hiding, compression and complete BLS scenarios after fusion is corrected.",
    )
    set_single_run(
        slide.shapes[18],
        "The installed filter is the baseline; marker agreement is now the highest-priority tracking problem",
    )

    prs.save(OUTPUT)
    # A successful reload catches broken package relationships immediately.
    checked = Presentation(OUTPUT)
    if len(checked.slides) != 16:
        raise RuntimeError(f"Expected 16 slides, found {len(checked.slides)}")
    print(OUTPUT)


if __name__ == "__main__":
    main()
