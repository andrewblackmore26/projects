"""Measures docs/ship-design-reference.png into docs/ship-design-reference.json.

The ship design spec says of its reference image "read it precisely, because every rule here comes
from it". This is that reading, as numbers: every circle's centre, rim radius and colour, the two
dashed rails, and the scale that maps the image onto the spec's radius ladder (core_1 = 34).

Method: bright rim pixels vote for circle centres (a Hough transform over integer radii), each peak is
refined by a least-squares fit to the rim pixels it explains, and its colour is read from those same
pixels. Rails are too faint and too sparse (2 on / 4 off) to vote, so they are read as peaks in the
radial histogram of faint pixels about the fitted core centre.

Run: python tools/measure_reference.py [--debug artifacts/reference_census.png]
Needs Pillow and numpy only.
"""
import argparse
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "docs", "ship-design-reference.png")
TARGET = os.path.join(ROOT, "docs", "ship-design-reference.json")

LADDER = {"core_1": 34, "core_2": 22, "core_3": 13, "core_dot": 5, "hub": 15, "pod": 7, "micro": 4}
RAILS = [52, 96, 140, 184]

BRIGHT = 110        # max channel above this is a rim, a line or a running light
FAINT_LOW = 14      # max channel this far above the background is a rail dash ...
MIN_RADIUS = 3
MAX_RADIUS = 60
# Hough peak threshold. Measured on this image: every real circle peaks at 0.44-0.52 (votes smear
# over neighbouring centre cells, so a perfect rim never reaches 1.0), while the noise floor from
# lines and neighbouring rims is <= 0.31 for radius >= 10. 0.40 sits between the two. Small radii are
# noisier, which is what MIN_ARC below is for.
MIN_COVERAGE = 0.40
MIN_ARC = 0.75      # fraction of 10-degree sectors of the FITTED rim that must contain a lit pixel


def classify(rgb):
    """Names a pixel colour by channel ratios. Running lights are near-white and named 'light'."""
    r, g, b = [float(v) for v in rgb]
    top = max(r, g, b, 1.0)
    if b / top > 0.62 and g / top > 0.8:
        return "light"
    if g / top < 0.55:
        return "red"
    return "amber"


def hough(mask):
    """Returns {radius: accumulator} with votes normalised to the fraction of circumference lit."""
    height, width = mask.shape
    ys, xs = np.nonzero(mask)
    result = {}
    for radius in range(MIN_RADIUS, MAX_RADIUS + 1):
        steps = max(24, int(round(2.0 * math.pi * radius)))
        angles = np.linspace(0.0, 2.0 * math.pi, steps, endpoint=False)
        cx = np.rint(xs[:, None] - radius * np.cos(angles)[None, :]).astype(int)
        cy = np.rint(ys[:, None] - radius * np.sin(angles)[None, :]).astype(int)
        inside = (cx >= 0) & (cx < width) & (cy >= 0) & (cy < height)
        acc = np.zeros((height, width), dtype=np.float32)
        np.add.at(acc, (cy[inside], cx[inside]), 1.0)
        # A rim is ~2 px wide, so one circumference collects about 2 * steps votes.
        result[radius] = acc / (2.0 * steps)
    return result


def peaks(accumulators):
    """Greedy non-maximum suppression across position and radius."""
    candidates = []
    for radius, acc in accumulators.items():
        ys, xs = np.nonzero(acc >= MIN_COVERAGE)
        for y, x in zip(ys, xs):
            candidates.append((float(acc[y, x]), int(x), int(y), radius))
    candidates.sort(reverse=True)
    kept = []
    for score, x, y, radius in candidates:
        clash = False
        for _, kx, ky, kr in kept:
            # Same circle seen again at a neighbouring radius or centre. Concentric circles of
            # clearly different radius (the core stack) are NOT a clash.
            if math.hypot(x - kx, y - ky) < 4.0 and abs(radius - kr) < 4:
                clash = True
                break
        if not clash:
            kept.append((score, x, y, radius))
    return kept


def refine(pixels_xy, x, y, radius):
    """Least-squares (Kasa) circle fit to the rim pixels within 2.5 px of the Hough estimate."""
    distance = np.hypot(pixels_xy[:, 0] - x, pixels_xy[:, 1] - y)
    near = pixels_xy[np.abs(distance - radius) < 2.5]
    if len(near) < 8:
        return None
    a = np.column_stack([near[:, 0], near[:, 1], np.ones(len(near))])
    b = -(near[:, 0] ** 2 + near[:, 1] ** 2)
    solution, *_ = np.linalg.lstsq(a, b, rcond=None)
    cx, cy = -solution[0] / 2.0, -solution[1] / 2.0
    fitted = math.sqrt(max(cx * cx + cy * cy - solution[2], 0.0))
    residual = float(np.sqrt(np.mean((np.hypot(near[:, 0] - cx, near[:, 1] - cy) - fitted) ** 2)))
    # A line grazing the estimate can vote like an arc; a real rim is lit all the way round.
    sectors = np.floor(np.degrees(np.arctan2(near[:, 1] - cy, near[:, 0] - cx)) % 360.0 / 10.0).astype(int)
    arc = len(set(sectors.tolist())) / 36.0
    return cx, cy, fitted, residual, near, arc


def nearest_ladder(units):
    name = min(LADDER, key=lambda key: abs(LADDER[key] - units))
    return name, LADDER[name]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", default="")
    arguments = parser.parse_args()

    image = Image.open(SOURCE).convert("RGB")
    pixels = np.asarray(image).astype(np.float32)
    height, width = pixels.shape[:2]
    top = pixels.max(axis=2)
    background = np.median(pixels.reshape(-1, 3), axis=0)
    bright = top > BRIGHT

    ys, xs = np.nonzero(bright)
    bright_xy = np.column_stack([xs, ys]).astype(np.float64)
    found = []
    for score, x, y, radius in peaks(hough(bright)):
        fit = refine(bright_xy, x, y, radius)
        if fit is None:
            continue
        cx, cy, fitted, residual, near, arc = fit
        if residual > 1.2 or arc < MIN_ARC:
            continue
        names = [classify(pixels[int(py), int(px)]) for px, py in near]
        coloured = [name for name in names if name != "light"]
        colour = max(set(coloured), key=coloured.count) if coloured else "light"
        inner = pixels[int(round(cy)), int(round(cx))]
        found.append({
            "x": round(cx, 2), "y": round(cy, 2), "radius_px": round(fitted, 2),
            "coverage": round(score, 3), "arc": round(arc, 3), "fit_rms_px": round(residual, 3), "colour": colour,
            "centre_rgb": [int(v) for v in inner],
            "light_fraction": round(names.count("light") / float(len(names)), 3),
        })

    # Drop duplicates the fit converged onto the same circle.
    unique = []
    for circle in sorted(found, key=lambda item: -item["coverage"]):
        if any(math.hypot(circle["x"] - other["x"], circle["y"] - other["y"]) < 3.0
               and abs(circle["radius_px"] - other["radius_px"]) < 3.0 for other in unique):
            continue
        unique.append(circle)

    # Two structural rejections. No single fit statistic separates line clutter from a real pod that
    # is partly hidden behind a set piece (both measured coverage ~0.41, rms ~1.0), so:
    #  - "inside": a circle whose CENTRE lies inside a larger one without sharing its centre. The
    #    reference only nests circles concentrically (the core stack); what was found here is the two
    #    V lines and the hub rim closing a loop. Testing the centre, not the whole circle: the first
    #    version asked for full containment and one of the four loops poked 0.1 px past the hub rim.
    #  - "hollow": a weak peak whose centre pixel is background. Only occlusion excuses a weak peak,
    #    and an unfilled ring with nothing over it scores like the clean circles (>= 0.47). What was
    #    found here is an arm and a node spoke running 3 px apart.
    rejected = []
    kept = []
    for circle in unique:
        reason = ""
        for other in unique:
            if other is circle or other["radius_px"] <= circle["radius_px"]:
                continue
            gap = math.hypot(circle["x"] - other["x"], circle["y"] - other["y"])
            if gap > 2.0 and gap < other["radius_px"]:
                reason = "inside"
        is_background = max(abs(circle["centre_rgb"][i] - background[i]) for i in range(3)) < 6
        if not reason and is_background and circle["coverage"] < 0.45:
            reason = "hollow"
        if reason:
            circle["rejected"] = reason
            rejected.append(circle)
        else:
            kept.append(circle)
    unique = kept

    core = max(unique, key=lambda item: item["radius_px"])
    scale = core["radius_px"] / float(LADDER["core_1"])
    for circle in unique:
        dx, dy = circle["x"] - core["x"], circle["y"] - core["y"]
        circle["radius_units"] = round(circle["radius_px"] / scale, 2)
        circle["ladder"], ladder_value = nearest_ladder(circle["radius_units"])
        circle["ladder_error_units"] = round(circle["radius_units"] - ladder_value, 2)
        circle["polar_radius_units"] = round(math.hypot(dx, dy) / scale, 2)
        # Screen angle, 0 = up (the ship's forward), clockwise positive.
        circle["polar_angle_deg"] = round(math.degrees(math.atan2(dx, -dy)) % 360.0, 1)
    unique.sort(key=lambda item: (item["polar_radius_units"], item["polar_angle_deg"]))

    # Rails: faint amber dashes, read as peaks in the radial histogram about the core centre.
    faint = (top > background.max() + FAINT_LOW) & (top <= BRIGHT)
    fy, fx = np.nonzero(faint)
    radial = np.hypot(fx - core["x"], fy - core["y"])
    histogram, edges = np.histogram(radial, bins=np.arange(0.0, max(width, height), 1.0))
    # Normalise by circumference so an outer ring does not win on length alone.
    density = histogram / np.maximum(2.0 * math.pi * (edges[:-1] + 0.5), 1.0)
    rails = []
    for index in np.argsort(density)[::-1]:
        radius_px = float(edges[index] + 0.5)
        if radius_px < core["radius_px"] + 6.0:
            continue
        if any(abs(radius_px - rail["radius_px"]) < 8.0 for rail in rails):
            continue
        # Measured: the two real rails are lit 0.39 and 0.43 of their circumference (a 2-on/4-off
        # dash is 0.33 plus anti-aliasing); the next strongest ring, the soft edges of the outer
        # pods, is 0.15. 0.25 sits between.
        if density[index] < 0.25:
            break
        units = radius_px / scale
        nearest = min(RAILS, key=lambda value: abs(value - units))
        rails.append({"radius_px": round(radius_px, 1), "radius_units": round(units, 1),
                      "nearest_rail": nearest, "rail_error_units": round(units - nearest, 1),
                      "lit_fraction": round(float(density[index]), 3)})
    rails.sort(key=lambda item: item["radius_px"])

    # Structure, in the grammar's own terms. Angles are measured from the ship's forward (up).
    stack = sorted([c for c in unique if c["polar_radius_units"] < 2.0], key=lambda c: -c["radius_units"])
    structure = {"core_stack": [{"radius_units": c["radius_units"], "colour": c["colour"]} for c in stack], "rails": [], "clusters": []}
    for rail in rails:
        members = sorted([c for c in unique if abs(c["polar_radius_units"] - rail["radius_units"]) < 6.0 and c["radius_units"] >= 6.0],
                         key=lambda c: c["polar_angle_deg"])
        angles = [c["polar_angle_deg"] for c in members]
        order = len(members)
        step = 360.0 / order if order else 0.0
        phase = angles[0] % step if order else 0.0
        worst = max([abs(((a - phase + step / 2.0) % step) - step / 2.0) for a in angles]) if order else 0.0
        structure["rails"].append({
            "rail": rail["nearest_rail"], "order": order, "phase_deg": round(phase, 1),
            "member_ladder": sorted(set(c["ladder"] for c in members)),
            "member_orbit_units": round(float(np.mean([c["polar_radius_units"] for c in members])), 2) if order else 0.0,
            "worst_spacing_error_deg": round(worst, 1)})
    for hub in [c for c in unique if c["ladder"] == "hub" and c["polar_radius_units"] > 2.0]:
        outward = math.radians(hub["polar_angle_deg"])
        children = []
        for c in unique:
            if c is hub:
                continue
            dx, dy = (c["x"] - hub["x"]) / scale, (c["y"] - hub["y"]) / scale
            distance = math.hypot(dx, dy)
            if distance > 40.0:
                continue
            bearing = (math.degrees(math.atan2(dx, -dy) - outward) + 180.0) % 360.0 - 180.0
            children.append({"ladder": c["ladder"], "colour": c["colour"], "radius_units": c["radius_units"],
                             "distance_units": round(distance, 2), "bearing_from_outward_deg": round(bearing, 1)})
        children.sort(key=lambda item: (item["colour"], item["bearing_from_outward_deg"]))
        structure["clusters"].append({"hub_angle_deg": hub["polar_angle_deg"], "hub_orbit_units": hub["polar_radius_units"], "children": children})

    census = {
        "source": "docs/ship-design-reference.png",
        "image_size": [width, height],
        "background_rgb": [int(v) for v in background],
        "center": [core["x"], core["y"]],
        "px_per_unit": round(scale, 4),
        "scale_basis": "largest fitted circle is core_1 = 34 units",
        "threshold": {"bright": BRIGHT, "faint_above_background": FAINT_LOW, "min_coverage": MIN_COVERAGE},
        "rails": rails,
        "structure": structure,
        "circles": unique,
        "rejected": rejected,
    }
    with open(TARGET, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(census, handle, indent=2)
        handle.write("\n")

    print("scale px/unit: %.4f   centre: (%.1f, %.1f)   circles: %d   rails: %d"
          % (scale, core["x"], core["y"], len(unique), len(rails)))
    for rail in rails:
        print("  rail  r=%6.1f px = %5.1f u  (nearest %3d, error %+.1f)  lit %.2f"
              % (rail["radius_px"], rail["radius_units"], rail["nearest_rail"], rail["rail_error_units"], rail["lit_fraction"]))
    for circle in unique:
        print("  %-6s r=%5.2f u (%-8s %+5.2f)  at %6.2f u  %6.1f deg  cov %.2f  light %.2f"
              % (circle["colour"], circle["radius_units"], circle["ladder"], circle["ladder_error_units"],
                 circle["polar_radius_units"], circle["polar_angle_deg"], circle["coverage"], circle["light_fraction"]))

    print("rejected: %s" % ", ".join("%s r=%.1f u at %.1f u (%s)" % (c["colour"], c["radius_px"] / scale, math.hypot(c["x"] - core["x"], c["y"] - core["y"]) / scale, c["rejected"]) for c in rejected))
    print("core stack:", [(c["radius_units"], c["colour"]) for c in structure["core_stack"]])
    for rail in structure["rails"]:
        print("rail %d: order %d, phase %.1f deg, members %s at %.2f u, worst spacing error %.1f deg"
              % (rail["rail"], rail["order"], rail["phase_deg"], rail["member_ladder"], rail["member_orbit_units"], rail["worst_spacing_error_deg"]))
    for cluster in structure["clusters"]:
        print("hub at %.1f deg:" % cluster["hub_angle_deg"], ["%s %s %.1f u @ %+.1f" % (k["colour"], k["ladder"], k["distance_units"], k["bearing_from_outward_deg"]) for k in cluster["children"]])

    if arguments.debug:
        overlay = image.copy()
        draw = ImageDraw.Draw(overlay)
        for circle in unique:
            r = circle["radius_px"]
            draw.ellipse([circle["x"] - r, circle["y"] - r, circle["x"] + r, circle["y"] + r], outline=(0, 255, 255))
        for rail in rails:
            r = rail["radius_px"]
            draw.ellipse([core["x"] - r, core["y"] - r, core["x"] + r, core["y"] + r], outline=(255, 0, 255))
        os.makedirs(os.path.dirname(os.path.abspath(arguments.debug)), exist_ok=True)
        overlay.save(arguments.debug)
        print("debug overlay:", arguments.debug)


if __name__ == "__main__":
    main()
