"""Draws the analysis PNGs.

Nothing here affects a single number. It exists only because matplotlib is not
installed, so the plots are drawn with Pillow instead. The analysis scripts
call one of two functions:

    save_panels(path, "Title", panels, columns=2)

where each panel is (title, x values, {label: y values}, unit) - for anything
measured sample by sample, and

    save_scatter(path, "Title", series, "x label", "y label")

where series is {name: [(x, y, point label), ...]} - for a handful of points
that each stand for a whole condition rather than a moment, such as one point
per viewpoint. It fits a line through each series and prints the slope, because
with six points the question is never "what is the shape" but "is there a
trend, and how steep".
"""

import numpy as np
from PIL import Image, ImageDraw, ImageFont


COLORS = ["#2274a5", "#f28e2b", "#59a14f", "#e15759"]

MARGIN = 40
HEADER = 70
GAP = 30


def font(size, bold=False):
    try:
        return ImageFont.truetype("arialbd.ttf" if bold else "arial.ttf", size)
    except OSError:
        return ImageFont.load_default()


def _draw_panel(draw, box, title, times, lines, unit):
    x, y, width, height = box
    left, top, right, bottom = 55, 50, 20, 35
    x0, y0 = x + left, y + top
    x1, y1 = x + width - right, y + height - bottom

    draw.rectangle((x, y, x + width, y + height), "white", "#b8c1ca")
    draw.text((x + 10, y + 8), title, "#183b56", font=font(17, True))
    draw.text((x + 5, y0 - 17), unit, "#5c6770", font=font(10))

    values = np.concatenate(list(lines.values()))
    maximum = max(float(np.max(values)) * 1.08, 0.001)
    first_time, last_time = float(times[0]), float(times[-1])
    if first_time == last_time:
        last_time += 1

    # Horizontal grid.
    for step in range(5):
        fraction = step / 4
        py = y1 - fraction * (y1 - y0)
        draw.line((x0, py, x1, py), fill="#e5e9ed")
        draw.text(
            (x + 3, py - 6),
            f"{fraction * maximum:.1f}",
            "#5c6770",
            font=font(10),
        )

    # Data lines.
    for color, (label, data) in zip(COLORS, lines.items()):
        points = []
        for time, value in zip(times, data):
            px = x0 + (time - first_time) / (last_time - first_time) * (x1 - x0)
            py = y1 - value / maximum * (y1 - y0)
            points.append((px, py))
        if len(points) > 1:
            draw.line(points, fill=color, width=2)

    # Legend.
    legend_x = x0 + 5
    for color, label in zip(COLORS, lines):
        draw.rectangle((legend_x, y0 + 4, legend_x + 10, y0 + 14), fill=color)
        draw.text((legend_x + 14, y0 + 2), label, "#303840", font=font(10))
        legend_x += 90 + len(label) * 3


def _wrap(draw, text, chosen_font, width):
    """Break text into lines that fit within width pixels."""
    lines, line = [], ""
    for word in text.split():
        candidate = f"{line} {word}".strip()
        if line and draw.textlength(candidate, font=chosen_font) > width:
            lines.append(line)
            line = word
        else:
            line = candidate
    return lines + [line] if line else lines


def _ticks(low, high, count=6):
    """Round tick values covering [low, high], so axes read 0.2 rather than 0.1873."""
    if high - low < 1e-9:
        low, high = low - 0.5, high + 0.5
    rough = (high - low) / (count - 1)
    magnitude = 10.0 ** np.floor(np.log10(rough))
    step = next(m * magnitude for m in (1, 2, 2.5, 5, 10) if rough <= m * magnitude)
    start = np.floor(low / step) * step
    return [start + i * step for i in range(int((high - start) / step) + 2)]


def _fit(points):
    """Least-squares line and correlation, or None when there are too few points."""
    if len(points) < 3:
        return None
    x = np.array([p[0] for p in points], dtype=float)
    y = np.array([p[1] for p in points], dtype=float)
    if np.ptp(x) < 1e-9:
        return None
    slope, intercept = np.polyfit(x, y, 1)
    return float(slope), float(intercept), float(np.corrcoef(x, y)[0, 1])


def save_scatter(path, title, series, x_label, y_label, subtitle=None, caption=None,
                 zero_note=None, width=1000, height=660):
    """One labelled scatter, a fitted line per series, saved as a PNG.

    series maps a name to a list of (x, y, point label). Points are named on the chart, because
    with six of them WHICH one is the outlier is the whole finding and a bare dot cannot say
    "crouch". But each x is named ONCE, above the highest point there, rather than once per
    series: when two series share an x they are two measurements of one condition, so labelling
    both printed every name twice and the duplicates collided with the dots they belonged to.
    """
    image = Image.new("RGB", (width, height), "#eef2f5")
    draw = ImageDraw.Draw(image)
    draw.text((MARGIN, 16), title, "#12344d", font=font(26, True))

    x0 = MARGIN + 62
    x1 = width - MARGIN - 10
    cursor = 52
    if subtitle:
        small = font(13)
        for line in _wrap(draw, subtitle, small, x1 - MARGIN):
            draw.text((MARGIN, cursor), line, "#5c6770", font=small)
            cursor += 17
        cursor += 6

    # Above the axes, not rotated beside them: Pillow cannot rotate text in place, and putting it
    # to the left instead ran it straight through the tick numbers.
    draw.text((MARGIN, cursor), y_label, "#303840", font=font(12))
    y0 = cursor + 20

    # The caption is measured before the axes are drawn, so the plot shrinks to make room for it
    # rather than the caption running off the bottom of the image.
    caption_lines = _wrap(draw, caption, font(13), x1 - MARGIN) if caption else []
    y1 = height - MARGIN - 34 - len(caption_lines) * 18
    draw.rectangle((x0, y0, x1, y1), "white", "#b8c1ca")

    everything = [p for points in series.values() for p in points]
    x_ticks = _ticks(min(p[0] for p in everything), max(p[0] for p in everything))
    # Padded by a tenth of the span so labels near the top or bottom are not clipped.
    span = max(p[1] for p in everything) - min(p[1] for p in everything)
    y_ticks = _ticks(min(p[1] for p in everything) - span * 0.1,
                     max(p[1] for p in everything) + span * 0.1)
    x_lo, x_hi = x_ticks[0], x_ticks[-1]
    y_lo, y_hi = y_ticks[0], y_ticks[-1]

    def place(x, y):
        return (x0 + (x - x_lo) / (x_hi - x_lo) * (x1 - x0),
                y1 - (y - y_lo) / (y_hi - y_lo) * (y1 - y0))

    for tick in y_ticks:
        _, py = place(x_lo, tick)
        draw.line((x0, py, x1, py), fill="#e5e9ed")
        draw.text((x0 - 12, py - 6), f"{tick:g}", "#5c6770", font=font(11), anchor="ra")
    for tick in x_ticks:
        px, _ = place(tick, y_lo)
        draw.line((px, y0, px, y1), fill="#e5e9ed")
        draw.text((px, y1 + 8), f"{tick:g}", "#5c6770", font=font(11), anchor="ma")

    # Zero is the truth line wherever the y axis is an error: on it means the camera agreed with
    # the tape. Drawn darker than the grid so it is not mistaken for one, and named, because a
    # reader who does not already know the finding has no reason to read a grid line as "correct".
    if y_lo < 0 < y_hi:
        _, py = place(x_lo, 0)
        draw.line((x0, py, x1, py), fill="#8a97a2", width=2)
        if zero_note:
            draw.text((x1 - 8, py - 17), zero_note, "#6f7c87", font=font(11), anchor="ra")

    draw.text((x0, y1 + 26), x_label, "#303840", font=font(12))

    legend_y = y0 + 8
    for color, (name, points) in zip(COLORS, series.items()):
        # The trend line is drawn but its slope is NOT written here. A chart answers "is there a
        # trend and how big"; the exact figure belongs in the printed table, where it can carry
        # the caveats a legend has no room for.
        line = _fit(points)
        if line is not None:
            slope, intercept, _ = line
            draw.line((*place(x_lo, slope * x_lo + intercept),
                       *place(x_hi, slope * x_hi + intercept)), fill=color, width=2)
        for x, y, _ in points:
            px, py = place(x, y)
            draw.ellipse((px - 5, py - 5, px + 5, py + 5), fill=color, outline="white")
        draw.rectangle((x0 + 10, legend_y, x0 + 24, legend_y + 10), fill=color)
        draw.text((x0 + 30, legend_y - 2), name, "#303840", font=font(12))
        legend_y += 20

    # One name per x, above whichever series sits highest there. See the docstring.
    highest = {}
    for points in series.values():
        for x, y, label in points:
            if x not in highest or y > highest[x][0]:
                highest[x] = (y, label)
    for x, (y, label) in highest.items():
        px, py = place(x, y)
        draw.text((px, py - 12), label, "#303840", font=font(12), anchor="ms")

    for index, line in enumerate(caption_lines):
        draw.text((MARGIN, y1 + 46 + index * 18), line, "#5c6770", font=font(13))

    image.save(path)
    print(f"\nPlot saved: {path}")


def save_panels(path, title, panels, columns=2, width=750, height=420):
    """Draw the panels into a grid and save one PNG."""
    rows = -(-len(panels) // columns)  # Round up.
    image = Image.new(
        "RGB",
        (
            2 * MARGIN + columns * width + (columns - 1) * GAP,
            HEADER + rows * height + (rows - 1) * GAP + MARGIN,
        ),
        "#eef2f5",
    )
    draw = ImageDraw.Draw(image)
    draw.text((MARGIN + 5, 18), title, "#12344d", font=font(28, True))

    for index, panel in enumerate(panels):
        x = MARGIN + (index % columns) * (width + GAP)
        y = HEADER + (index // columns) * (height + GAP)
        _draw_panel(draw, (x, y, width, height), *panel)

    image.save(path)
    print(f"\nPlot saved: {path}")
