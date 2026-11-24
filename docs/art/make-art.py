"""Draw the cluster from docs/art/runs.json: the README's animated SVGs and the project page's data.

Writes:
  docs/assets/cluster-dark.svg, cluster-light.svg   the README picture: road-trip.mkv, then cartoons.mkv
  docs/runs.js                                      the four recorded runs, for the page's replay
  docs/index.html, between the art:* markers         the cluster in its finished road-trip state
                                                    (what the page shows without JS), the runs table
                                                    and the timings quoted in the text
  README.md, between the art:* markers               road-trip.mkv's output and the runs table

The dials are carify's limits drawn as Signal Crimson redlines: frame height (720, the --max-height
default) and audio channels (2). Both the animated README SVG and the project page use a 2-bay
horizontal wide-dash telemetry layout with a full-width progress and output strip underneath (never
sandwiching a terminal box between the dials). Text in the SVGs is converted to paths from
docs/fonts/, because an SVG shown through <img> can't load fonts. The SVG's base styles are the
finished road-trip state, which is what a viewer that skips the animation shows.

Run from the repo root:

    python -m pip install -r docs/art/requirements.txt
    python docs/art/make-art.py
"""
import html
import json
import math
import os
import re
import sys

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.normpath(os.path.join(HERE, ".."))
FONTS = os.path.join(DOCS, "fonts")
NL = "\n"

# Cyclorama Dawn v2.1.0 (Steel & Beacon Orange + Signal Crimson Fault)
THEMES = {
    "dark": dict(
        plate="#0C0C10",
        face="#050507",
        hub="#14141A",
        line="#2A2C35",
        strong="#676B78",
        ink="#F4F5F8",
        mute="#B3B5C0",
        steel="#74B8E8",
        steel_fill="#1F547A",
        ember="#F06E2B",
        beacon_ink="#FF9254",
        ember_tint="#26140C",
        amber="#FFC247",
        mint="#3DDC97",
        mint_tint="#0C241B",
        rasp="#FF5C6C",
        rasp_tint="#260E14",
    ),
    "light": dict(
        plate="#FFFFFF",
        face="#F5F7F9",
        hub="#E9EEF3",
        line="#D2DAE2",
        strong="#6E7784",
        ink="#0D1016",
        mute="#525B69",
        steel="#164669",
        steel_fill="#164669",
        ember="#BD4811",
        beacon_ink="#AD3D0A",
        ember_tint="#FDF0E9",
        amber="#885800",
        mint="#127247",
        mint_tint="#E7F6EE",
        rasp="#B91C2E",
        rasp_tint="#FCEBEF",
    ),
}

# --- the dials --------------------------------------------------------------------------------
# A 240-degree sweep, 0 at the bottom left, the top of the scale at the bottom right.
SWEEP = 120.0
DIALS = {
    "v": dict(title="Frame height", unit="HEIGHT", limit_label="REDLINE > 720PX · H.264 8-BIT", max=2160, limit=720, major=360, minor=120),
    "a": dict(title="Audio channels", unit="CHANNELS", limit_label="REDLINE > 2CH · AAC STEREO", max=8, limit=2, major=1, minor=0.5),
}


def angle(dial, value):
    d = DIALS[dial]
    return -SWEEP + 2 * SWEEP * min(max(value, 0), d["max"]) / d["max"]


def polar(cx, cy, r, deg):
    t = math.radians(deg)
    return cx + r * math.sin(t), cy - r * math.cos(t)


def arc(cx, cy, r, a0, a1):
    x0, y0 = polar(cx, cy, r, a0)
    x1, y1 = polar(cx, cy, r, a1)
    big = 1 if a1 - a0 > 180 else 0
    return f"M{x0:.2f} {y0:.2f}A{r} {r} 0 {big} 1 {x1:.2f} {y1:.2f}"


def fmt(v):
    return str(int(v)) if float(v).is_integer() else f"{v:g}"


# Tapered pointer bar across the tick ring, pointing up; rotated about the dial's centre.
def needle_points(cx, cy, r0=110.0, r1=151.0, w0=4.6, w1=1.6):
    return f"{cx - w0:.2f},{cy - r0:.2f} {cx - w1:.2f},{cy - r1:.2f} {cx + w1:.2f},{cy - r1:.2f} {cx + w0:.2f},{cy - r0:.2f}"


# --- what a run shows -------------------------------------------------------------------------
def video_words(v):
    depth = "10-bit" if "10" in v.get("pix_fmt", "") else "8-bit"
    if v.get("pix_fmt", "").startswith(("yuv422", "yuv444")):
        depth += " " + v["pix_fmt"][3:6]
    return f"{v['codec_name']} {depth}"


def video_spec(v):
    prof = v.get("profile", "")
    lvl = v.get("level", 0)
    depth = "10-bit" if "10" in v.get("pix_fmt", "") else "8-bit"
    if prof and lvl and v["codec_name"] == "h264":
        return f"{v['codec_name']} · {depth} · {prof} {lvl / 10:g}"
    if prof:
        return f"{v['codec_name']} · {depth} · {prof}"
    return f"{v['codec_name']} · {depth}"


def audio_words(a):
    layout = a.get("channel_layout", "")
    layout = {"5.1(side)": "5.1", "stereo": "stereo", "mono": "mono"}.get(layout, layout or f"{a['channels']}ch")
    return f"{a['codec_name']} {layout}"


def audio_spec(a, encoded=False):
    layout = a.get("channel_layout", "")
    layout = {"5.1(side)": "5.1 surround", "stereo": "stereo", "mono": "mono"}.get(layout, layout or f"{a['channels']}ch")
    if encoded:
        return f"{a['codec_name']} · {layout} · 160k"
    return f"{a['codec_name']} · {layout}"


def line_kind(line):
    """The colour carify gives a status line: say() is Beacon, ok() is Mint, warn() is Amber."""
    label, _, rest = line.partition(" ")
    rest = rest.strip()
    if re.match(r"(frame|size)=", line):
        return "progress"
    if label in ("video", "audio"):
        return "ok" if rest == "copy" else "tag"
    if label == "wrote" or (label == "usb" and rest.startswith("done")):
        return "ok"
    if label == "warn":
        return "warn"
    if label == "error":
        return "err"
    return "tag"


def where(recorded):
    """ffmpeg's version and the OS, short: ('6.1.1', 'Ubuntu 24.04')."""
    ff = re.search(r"version (\d+\.\d+(?:\.\d+)?)", recorded["ffmpeg"]).group(1)
    name, ver = recorded["os"].split()[:2]
    return ff, name + " " + ".".join(ver.split(".")[:2])


def summary(run):
    i, o = run["in"], run["out"]
    vact = "copy" if "video  copy" in run["screen"] else "re-encode"
    aact = "copy" if "audio  copy" in run["screen"] else "re-encode"
    prog = next(l for l in run["screen"] if line_kind(l) == "progress")
    spd = re.search(r"speed=\s*([\d.e+]+x)", prog).group(1)
    return {
        "name": run["name"],
        "file": run["file"],
        "why": run["why"],
        "cmd": run["cmd"],
        "seconds": run["seconds"],
        "speed": spd,
        "events": [[t, end == "\r", text] for t, end, text in run["events"]],
        "vin": i["video"]["height"],
        "vout": o["video"]["height"],
        "vdim_in": f'{i["video"]["width"]}×{i["video"]["height"]}',
        "vdim_out": f'{o["video"]["width"]}×{o["video"]["height"]}',
        "vspec_in": video_spec(i["video"]),
        "vspec_out": "copied unchanged" if vact == "copy" else video_spec(o["video"]),
        "vact": vact,
        "ain": i["audio"]["channels"],
        "aout": o["audio"]["channels"],
        "adim_in": f'{i["audio"]["channels"]} ch',
        "adim_out": f'{o["audio"]["channels"]} ch',
        "aspec_in": audio_spec(i["audio"], False),
        "aspec_out": "copied unchanged" if aact == "copy" else audio_spec(o["audio"], True),
        "aact": aact,
        "vwin": video_words(i["video"]),
        "vwout": video_words(o["video"]),
        "awin": audio_words(i["audio"]),
        "awout": audio_words(o["audio"]),
        "out": os.path.basename(next(l for l in run["screen"] if l.startswith("wrote")).split()[1]),
        "size": re.search(r"\((\d+ [KM]B)\)", next(l for l in run["screen"] if l.startswith("wrote"))).group(1),
        "duration": i["duration"],
        "screen": run["screen"],
    }


# --- text as paths ----------------------------------------------------------------------------
_fonts, _glyphs = {}, {}
FACES = {
    "cond": ("albert-sans-latin.woff2", {"wght": 600}),
    "condb": ("big-shoulders-stencil-latin.woff2", {"wght": 700}),
    "num": ("big-shoulders-stencil-latin.woff2", {"wght": 800}),
    "mono": ("azeret-mono-latin.woff2", {"wght": 400}),
    "monob": ("azeret-mono-latin.woff2", {"wght": 600}),
}


def font(face):
    if face not in _fonts:
        fname, loc = FACES[face]
        _fonts[face] = instancer.instantiateVariableFont(TTFont(os.path.join(FONTS, fname)), loc)
    return _fonts[face]


def advance(s, size, face, ls=0.0):
    f = font(face)
    gs, cmap = f.getGlyphSet(), f.getBestCmap()
    return sum(gs[cmap[ord(ch)]].width for ch in s) * size / f["head"].unitsPerEm + ls * size * (len(s) - 1)


def text(s, x, y, size, face, fill, ls=0.0, anchor="start", cls=None):
    """Paths for s with its baseline at y. ls is letter spacing in em."""
    f = font(face)
    gs, cmap, upm = f.getGlyphSet(), f.getBestCmap(), f["head"].unitsPerEm
    k = size / upm
    names = []
    for ch in s:
        if ord(ch) not in cmap:
            sys.exit(f"{FACES[face][0]} has no glyph for {ch!r}")
        names.append(cmap[ord(ch)])
    width = sum(gs[n].width * k for n in names) + ls * size * (len(names) - 1)
    pen_x = {"start": x, "middle": x - width / 2, "end": x - width}[anchor]
    uses = []
    for n in names:
        key = (face, n)
        if key not in _glyphs:
            pen = SVGPathPen(gs, ntos=lambda v: "%g" % round(v, 1))
            gs[n].draw(pen)
            _glyphs[key] = (f"g{len(_glyphs)}", pen.getCommands())
        gid, d = _glyphs[key]
        if d:
            uses.append(f'<use href="#{gid}" transform="matrix({k:.5f} 0 0 {-k:.5f} {pen_x:.2f} {y:.2f})"/>')
        pen_x += gs[n].width * k + ls * size
    c = f' class="{cls}"' if cls else ""
    return f'<g{c} fill="{fill}">{"".join(uses)}</g>'


# --- the README SVG (Wide-Dash 2-Bay Telemetry Cluster) ---------------------------------------
W, H = 1000, 456
CX = {"v": 134, "a": 634}
CY = 202
DIAL_R = 102


def pct(t, cycle):
    return f"{max(0.0, min(t, cycle)) / cycle * 100:.3f}%"


def build_svg(theme, runs, recorded):
    c = THEMES[theme]
    a, b = runs["road-trip"], runs["cartoons"]

    # ---- timeline (seconds): starts immediately in road-trip's probed state so frame 0 is never blank ----
    A0 = 0.0
    a_wrote = max(0.8, next(t for t, _, x in a["events"] if x.startswith("wrote")))
    a_done = max(a_wrote + 0.35, a["events"][-1][0] + 0.35)
    B0 = a_done + 3.2
    B_SHIFT = 0.55
    B1 = B0 + B_SHIFT
    b_wrote = B1 + max(0.8, next(t for t, _, x in b["events"] if x.startswith("wrote")))
    b_done = B1 + max(b_wrote - B1 + 0.35, b["events"][-1][0] + 0.35)
    RESET = b_done + 3.2
    CYCLE = RESET + 0.6
    DROP = 0.55

    ease_io, ease_out = "cubic-bezier(.45,0,.55,1)", "cubic-bezier(.2,.7,.2,1)"
    needle = {
        "v": [
            (0.0, angle("v", a["vin"]), "linear"),
            (a_wrote, angle("v", a["vin"]), ease_out),
            (a_wrote + DROP, angle("v", a["vout"]), "linear"),
            (B0, angle("v", a["vout"]), ease_io),
            (B1, angle("v", b["vin"]), "linear"),
            (b_wrote, angle("v", b["vin"]), ease_out),
            (b_wrote + DROP, angle("v", b["vout"]), "linear"),
            (RESET, angle("v", b["vout"]), ease_io),
            (CYCLE, angle("v", a["vin"]), "linear"),
        ],
        "a": [
            (0.0, angle("a", a["ain"]), "linear"),
            (a_wrote, angle("a", a["ain"]), ease_out),
            (a_wrote + DROP, angle("a", a["aout"]), "linear"),
            (B0, angle("a", a["aout"]), ease_io),
            (B1, angle("a", b["ain"]), "linear"),
            (b_wrote, angle("a", b["ain"]), ease_out),
            (b_wrote + DROP, angle("a", b["aout"]), "linear"),
            (RESET, angle("a", b["aout"]), ease_io),
            (CYCLE, angle("a", a["ain"]), "linear"),
        ],
    }

    def rot_keys(name, keys):
        body = "".join(f"{pct(t, CYCLE)}{{transform:rotate({deg:.2f}deg);animation-timing-function:{ez}}}" for t, deg, ez in keys)
        return f"@keyframes {name}{{{body}}}"

    win = {
        # Run A: road-trip.mkv
        "a-run": [(0.0, B0)],
        "a-busy": [(0.0, a_wrote)],
        "a-out": [(a_wrote, B0)],
        "a-vin": [(0.0, a_wrote)],
        "a-vout": [(a_wrote, B0)],
        "a-ain": [(0.0, a_wrote)],
        "a-aout": [(a_wrote, B0)],
        "ghost-v": [(a_wrote, B0)],
        "a-ghost-a": [(a_wrote, B0)],
        # Run B: cartoons.mkv
        "b-run": [(B0, CYCLE)],
        "b-busy": [(B0, b_wrote)],
        "b-out": [(b_wrote, CYCLE)],
        "b-ain": [(B0, b_wrote)],
        "b-aout": [(b_wrote, CYCLE)],
        "b-ghost-a": [(b_wrote, CYCLE)],
        # USB indicator across both runs
        "usb-wait": [(0.0, a_wrote), (B0, b_wrote)],
        "usb-copy": [(a_wrote, a_done), (b_wrote, b_done)],
        "usb-done": [(a_done, B0), (b_done, CYCLE)],
    }

    def toggle(name, windows):
        shown = lambda t: int(any(s <= t < e for s, e in windows))
        points = sorted({0.0} | {t for w in windows for t in w if 0 < t < CYCLE})
        body = "".join(f"{pct(t, CYCLE)}{{opacity:{shown(t)}}}" for t in points)
        return f"@keyframes {name}{{{body}100%{{opacity:{shown(0.0)}}}}}"

    # Static fallback (prefers-reduced-motion: reduce or static image viewers) = finished road-trip state
    still_t = a_done + 1.0
    still = {k: int(any(s <= still_t < e for s, e in v)) for k, v in win.items()}

    def progress_keys(name, run, start, end_hold):
        pts = [(0.0, 0.0), (start, 0.0)]
        for t, _, x in run["events"]:
            m = re.search(r"time=(-?)(\d+):(\d+):([\d.]+)", x)
            if m and not m.group(1):
                sec = int(m.group(2)) * 3600 + int(m.group(3)) * 60 + float(m.group(4))
                pts.append((start + t, min(sec / run["duration"], 1.0)))
        pts.append((end_hold, 1.0))
        pts.append((min(end_hold + 0.01, CYCLE), 0.0))
        body = "".join(f"{pct(t, CYCLE)}{{transform:scaleX({v:.3f})}}" for t, v in pts)
        return f"@keyframes {name}{{{body}100%{{transform:scaleX(0)}}}}"

    css = [toggle(k, v) for k, v in win.items()]
    css += [rot_keys("nv", needle["v"]), rot_keys("na", needle["a"])]
    css += [progress_keys("pa", a, A0, B0), progress_keys("pb", b, B1, CYCLE)]
    anim = "".join(f".{k}{{animation:{k} {CYCLE:.2f}s step-end infinite}}" for k in win)
    anim += f".nv{{animation:nv {CYCLE:.2f}s infinite}}.na{{animation:na {CYCLE:.2f}s infinite}}"
    anim += f".pa{{animation:pa {CYCLE:.2f}s linear infinite}}.pb{{animation:pb {CYCLE:.2f}s linear infinite}}"

    base = "".join(f".{k}{{opacity:{v}}}" for k, v in still.items())
    base += (
        f".nv{{transform:rotate({angle('v', a['vout']):.2f}deg)}}"
        f".na{{transform:rotate({angle('a', a['aout']):.2f}deg)}}"
        f".nv,.na,.pa,.pb{{transform-box:view-box}}"
        f".nv{{transform-origin:{CX['v']}px {CY}px}}"
        f".na{{transform-origin:{CX['a']}px {CY}px}}"
        f".pa,.pb{{transform-origin:24px 0}}.pb{{transform:scaleX(0)}}"
    )

    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img">']
    o.append(f"<style>{base}@media (prefers-reduced-motion:no-preference){{{''.join(css)}{anim}}}</style>")
    o.append(
        f'<defs>'
        f'<clipPath id="card-clip"><rect x="1" y="1" width="{W - 2}" height="{H - 2}" rx="9.5"/></clipPath>'
        f'<radialGradient id="face"><stop offset="0" stop-color="{c["hub"]}"/><stop offset="1" stop-color="{c["face"]}"/></radialGradient>'
        f'<linearGradient id="horizon" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{c["steel"]}"/><stop offset="1" stop-color="{c["ember"]}"/></linearGradient>'
        f'</defs>'
    )

    # Outer plate & clipped header/footer recessed bands + top 3px horizon bar
    o.append(f'<rect x="0.5" y="0.5" width="{W - 1}" height="{H - 1}" rx="10" fill="{c["plate"]}" stroke="{c["line"]}"/>')
    o.append('<g clip-path="url(#card-clip)">')
    o.append(f'<rect x="0" y="0" width="{W}" height="58" fill="{c["face"]}"/>')
    o.append(f'<rect x="0" y="342" width="{W}" height="{H - 342}" fill="{c["face"]}"/>')
    o.append(f'<rect x="0" y="0" width="{W}" height="3" fill="url(#horizon)"/>')
    o.append('</g>')
    o.append(f'<line x1="1" y1="58" x2="{W - 1}" y2="58" stroke="{c["line"]}"/>')
    o.append(f'<line x1="500" y1="58" x2="500" y2="342" stroke="{c["line"]}"/>')
    o.append(f'<line x1="1" y1="342" x2="{W - 1}" y2="342" stroke="{c["line"]}"/>')

    # --- Top Telemetry Header Bar ---
    ver = recorded["carify"].upper()
    ver_w = advance(ver, 11.5, "monob", ls=0.04) + 20
    o.append(f'<rect x="24" y="18" width="{ver_w:.1f}" height="24" rx="4" fill="{c["hub"]}" stroke="{c["line"]}"/>')
    o.append(text(ver, 24 + ver_w / 2, 34.2, 11.5, "monob", c["steel"], ls=0.04, anchor="middle"))

    cmd_x = 24 + ver_w + 16
    for cls, run in (("a-run", a), ("b-run", b)):
        o.append(
            f'<g class="{cls}">'
            f'{text("$", cmd_x, 34.5, 13.5, "monob", c["beacon_ink"])}'
            f'{text(run["cmd"], cmd_x + advance("$ ", 13.5, "monob"), 34.5, 13.5, "mono", c["ink"])}'
            f'</g>'
        )

    ff, osv = where(recorded)
    o.append(text(f"{osv.upper()} · FFMPEG {ff}", 748, 34.2, 10.5, "mono", c["mute"], ls=0.04, anchor="end"))

    # USB status token (fixed right slot x=764..976, w=212)
    def usb_badge(cls, label, stroke_col, bg_col, tag_col, txt_col):
        return (
            f'<g class="{cls}">'
            f'<rect x="764" y="18" width="212" height="24" rx="4" fill="{bg_col}" stroke="{stroke_col}"/>'
            f'{text("[USB]", 774, 34.0, 10.5, "monob", tag_col, ls=0.04)}'
            f'{text(label, 966, 34.0, 10.5, "monob", txt_col, ls=0.05, anchor="end")}'
            f'</g>'
        )

    o.append(usb_badge("usb-wait", "STANDBY", c["line"], c["hub"], c["steel"], c["mute"]))
    o.append(usb_badge("usb-copy", "COPYING", c["ember"], c["ember_tint"], c["beacon_ink"], c["beacon_ink"]))
    o.append(usb_badge("usb-done", "SAFE TO REMOVE", c["mint"], c["mint_tint"], c["mint"], c["mint"]))

    # --- 2-Bay Instrument Deck: Left = VIDEO STREAM, Right = AUDIO STREAM ---
    for key in ("v", "a"):
        d, cx = DIALS[key], CX[key]
        o.append(f'<circle cx="{cx}" cy="{CY}" r="{DIAL_R}" fill="url(#face)" stroke="{c["line"]}" stroke-width="1.75"/>')
        o.append(f'<path d="{arc(cx, CY, 95, angle(key, d["limit"]), SWEEP)}" fill="none" stroke="{c["rasp"]}" stroke-width="4.5"/>')
        ticks = []
        v = 0.0
        while v <= d["max"] + 1e-9:
            major = abs(v / d["major"] - round(v / d["major"])) < 1e-9
            r0 = 81 if major else 86
            x0, y0 = polar(cx, CY, r0, angle(key, v))
            x1, y1 = polar(cx, CY, 91, angle(key, v))
            col = c["ink"] if major else c["strong"]
            ticks.append(f'<line x1="{x0:.2f}" y1="{y0:.2f}" x2="{x1:.2f}" y2="{y1:.2f}" stroke="{col}" stroke-width="{2.5 if major else 1.3}"/>')
            if major:
                tx, ty = polar(cx, CY, 62, angle(key, v))
                o.append(text(fmt(v), tx, ty + 3.8, 10.5, "cond", c["rasp"] if v == d["limit"] else c["ink"], anchor="middle"))
            v += d["minor"]
        o.append(f'<g stroke-linecap="square">{"".join(ticks)}</g>')
        o.append(text(d["unit"], cx, CY - 32, 9.5, "monob", c["mute"], ls=0.14, anchor="middle"))

    # Ghost needles (where input started) + live Beacon Orange needles (outer track 75..100.5 clears scale labels)
    n_v = needle_points(CX["v"], CY, r0=75.0, r1=100.5, w0=3.4, w1=1.3)
    n_a = needle_points(CX["a"], CY, r0=75.0, r1=100.5, w0=3.4, w1=1.3)
    o.append(f'<polygon class="ghost-v" points="{n_v}" fill="{c["rasp"]}" fill-opacity="0.65" transform="rotate({angle("v", a["vin"]):.2f} {CX["v"]} {CY})"/>')
    for cls, run in (("a-ghost-a", a), ("b-ghost-a", b)):
        o.append(f'<polygon class="{cls}" points="{n_a}" fill="{c["rasp"]}" fill-opacity="0.65" transform="rotate({angle("a", run["ain"]):.2f} {CX["a"]} {CY})"/>')
    o.append(f'<polygon class="nv" points="{n_v}" fill="{c["ember"]}"/>')
    o.append(f'<polygon class="na" points="{n_a}" fill="{c["ember"]}"/>')

    # Clean dial hub values (no cramped codec lines inside the dial)
    def dial_hub(cls, key, value, state, frm=None):
        cx = CX[key]
        col = c["mint"] if state == "FITS" else c["rasp"]
        parts = [
            text(fmt(value), cx, CY + 12, 44, "num", col, ls=0.04, anchor="middle"),
            text(state, cx, CY + 34, 11, "monob", col, ls=0.16, anchor="middle"),
        ]
        if frm is not None:
            parts.append(text(f"from {fmt(frm)}", cx, CY + 54, 10, "mono", c["mute"], anchor="middle"))
        return f'<g class="{cls}">{"".join(parts)}</g>'

    over = lambda key, v: "FITS" if v <= DIALS[key]["limit"] else "OVER"
    o.append(dial_hub("a-vin", "v", a["vin"], over("v", a["vin"])))
    o.append(dial_hub("a-vout", "v", a["vout"], over("v", a["vout"]), a["vin"]))
    o.append(dial_hub("b-run", "v", b["vin"], over("v", b["vin"])))
    o.append(dial_hub("a-ain", "a", a["ain"], over("a", a["ain"])))
    o.append(dial_hub("a-aout", "a", a["aout"], over("a", a["aout"]), a["ain"]))
    o.append(dial_hub("b-ain", "a", b["ain"], over("a", b["ain"])))
    o.append(dial_hub("b-aout", "a", b["aout"], over("a", b["aout"]), b["ain"]))

    # Right-side structured telemetry spec panel inside each bay
    def action_badge(cls, x_right, y, act):
        label = "COPY" if act == "copy" else "RE-ENCODE"
        w = 58 if act == "copy" else 94
        x0 = x_right - w
        sc = c["mint"] if act == "copy" else c["ember"]
        bg = c["mint_tint"] if act == "copy" else c["ember_tint"]
        tc = c["mint"] if act == "copy" else c["beacon_ink"]
        return (
            f'<g class="{cls}">'
            f'<rect x="{x0}" y="{y}" width="{w}" height="22" rx="4" fill="{bg}" stroke="{sc}"/>'
            f'{text(label, x0 + w / 2, y + 14.8, 10, "monob", tc, ls=0.06, anchor="middle")}'
            f'</g>'
        )

    def spec_bay(key, x0, title, limit_text):
        x1 = x0 + 222
        parts = [
            text(title, x0, 110, 19, "condb", c["ink"], ls=0.08),
            f'<line x1="{x0}" y1="122" x2="{x1}" y2="122" stroke="{c["line"]}"/>',
            f'<rect x="{x0}" y="134" width="3" height="12" rx="1" fill="{c["rasp"]}"/>',
            text(limit_text, x0 + 10, 144, 9.8, "monob", c["mute"], ls=0.04),
            # IN card shell
            f'<rect x="{x0}" y="158" width="222" height="62" rx="6" fill="{c["face"]}" stroke="{c["line"]}"/>',
            text("IN", x0 + 12, 179, 10, "monob", c["steel"], ls=0.08),
            # Connector arrow
            f'<path d="M{x0 + 111} 224v16m-4-4 4 4 4-4" fill="none" stroke="{c["strong"]}" stroke-width="1.6" stroke-linecap="square"/>',
            # OUT card shell (base border)
            f'<rect x="{x0}" y="246" width="222" height="62" rx="6" fill="{c["face"]}" stroke="{c["line"]}"/>',
            text("OUT", x0 + 12, 267, 10, "monob", c["mint"], ls=0.08),
        ]
        # Per-run badges & IN/OUT values
        if key == "v":
            parts.append(action_badge("a-run", x1, 91, a["vact"]))
            parts.append(action_badge("b-run", x1, 91, b["vact"]))
            # IN content
            for cls, run in (("a-run", a), ("b-run", b)):
                parts.append(
                    f'<g class="{cls}">'
                    f'{text(run["vdim_in"], x1 - 12, 179, 11, "monob", c["ink"], anchor="end")}'
                    f'{text(run["vspec_in"], x0 + 12, 204, 11, "mono", c["mute"])}'
                    f'</g>'
                )
            # OUT content: road-trip encoding -> written; cartoons already copied
            parts.append(
                f'<g class="a-busy">'
                f'{text("target 720p", x1 - 12, 267, 10.5, "mono", c["beacon_ink"], anchor="end")}'
                f'{text("re-encoding h264 8-bit...", x0 + 12, 292, 10.5, "mono", c["beacon_ink"])}'
                f'</g>'
            )
            parts.append(
                f'<g class="a-vout">'
                f'<rect x="{x0}" y="246" width="222" height="62" rx="6" fill="none" stroke="{c["mint"]}"/>'
                f'{text(a["vdim_out"], x1 - 12, 267, 11, "monob", c["ink"], anchor="end")}'
                f'{text(a["vspec_out"], x0 + 12, 292, 11, "mono", c["ink"])}'
                f'</g>'
            )
            parts.append(
                f'<g class="b-run">'
                f'<rect x="{x0}" y="246" width="222" height="62" rx="6" fill="none" stroke="{c["mint"]}"/>'
                f'{text(b["vdim_out"], x1 - 12, 267, 11, "monob", c["ink"], anchor="end")}'
                f'{text(b["vspec_out"], x0 + 12, 292, 11, "mono", c["mint"])}'
                f'</g>'
            )
        else:
            parts.append(action_badge("a-run", x1, 91, a["aact"]))
            parts.append(action_badge("b-run", x1, 91, b["aact"]))
            for cls, run in (("a-run", a), ("b-run", b)):
                parts.append(
                    f'<g class="{cls}">'
                    f'{text(run["adim_in"], x1 - 12, 179, 11, "monob", c["ink"], anchor="end")}'
                    f'{text(run["aspec_in"], x0 + 12, 204, 11, "mono", c["mute"])}'
                    f'</g>'
                )
            for busy_cls, out_cls, run in (("a-busy", "a-aout", a), ("b-busy", "b-aout", b)):
                parts.append(
                    f'<g class="{busy_cls}">'
                    f'{text("target 2 ch", x1 - 12, 267, 10.5, "mono", c["beacon_ink"], anchor="end")}'
                    f'{text("re-encoding aac 160k...", x0 + 12, 292, 10.5, "mono", c["beacon_ink"])}'
                    f'</g>'
                )
                parts.append(
                    f'<g class="{out_cls}">'
                    f'<rect x="{x0}" y="246" width="222" height="62" rx="6" fill="none" stroke="{c["mint"]}"/>'
                    f'{text(run["adim_out"], x1 - 12, 267, 11, "monob", c["ink"], anchor="end")}'
                    f'{text(run["aspec_out"], x0 + 12, 292, 11, "mono", c["ink"])}'
                    f'</g>'
                )
        return "".join(parts)

    o.append(spec_bay("v", 254, "VIDEO STREAM", DIALS["v"]["limit_label"]))
    o.append(spec_bay("a", 754, "AUDIO STREAM", DIALS["a"]["limit_label"]))

    # --- Bottom Full-Width Pipeline Progress & Output Footer Strip ---
    # Row 1: stage status + timing
    def stage_line(cls, tag, tag_col, msg, right_txt, right_col):
        tx = 24 + advance(tag + "  ", 12, "monob")
        return (
            f'<g class="{cls}">'
            f'{text(tag, 24, 372, 12, "monob", tag_col)}'
            f'{text(msg, tx, 372, 12, "mono", c["ink"])}'
            f'{text(right_txt, 976, 372, 12, "monob", right_col, anchor="end")}'
            f'</g>'
        )

    o.append(stage_line("a-busy", "[run]", c["beacon_ink"], "ffmpeg re-encoding video (libx264 crf 20) + audio (aac stereo 160k)...", "encoding...", c["beacon_ink"]))
    o.append(stage_line("a-out", "[ok]", c["mint"], f'wrote ./{a["out"]} ({a["size"]})  ·  copied to /media/runner/MOVIES', f'{a["seconds"]:g} s · {a["speed"]}', c["mint"]))
    o.append(stage_line("b-busy", "[run]", c["beacon_ink"], "ffmpeg copying h264 video stream + re-encoding audio (aac stereo 160k)...", "encoding...", c["beacon_ink"]))
    o.append(stage_line("b-out", "[ok]", c["mint"], f'wrote ./{b["out"]} ({b["size"]})  ·  copied to /media/runner/MOVIES', f'{b["seconds"]:g} s · {b["speed"]}', c["mint"]))

    # Row 2: Full-width Steel -> Beacon progress rail
    o.append(f'<rect x="24" y="388" width="952" height="7" rx="3.5" fill="{c["line"]}"/>')
    o.append('<rect class="pa" x="24" y="388" width="952" height="7" rx="3.5" fill="url(#horizon)"/>')
    o.append('<rect class="pb" x="24" y="388" width="952" height="7" rx="3.5" fill="url(#horizon)"/>')

    # Row 3: Recorded clip tabs + legend
    def clip_chip(x, w, num, fname, active_cls):
        return (
            f'<rect x="{x}" y="412" width="{w}" height="24" rx="4" fill="{c["plate"]}" stroke="{c["line"]}"/>'
            f'{text(num, x + 10, 428, 10, "monob", c["mute"])}'
            f'{text(fname, x + 32, 428, 10.5, "mono", c["mute"])}'
            f'<g class="{active_cls}">'
            f'<rect x="{x}" y="412" width="{w}" height="24" rx="4" fill="{c["ember_tint"]}" stroke="{c["ember"]}"/>'
            f'{text(num, x + 10, 428, 10, "monob", c["beacon_ink"])}'
            f'{text(fname, x + 32, 428, 10.5, "monob", c["ink"])}'
            f'</g>'
        )

    o.append(clip_chip(24, 168, "01", a["file"], "a-run"))
    o.append(clip_chip(202, 162, "02", b["file"], "b-run"))
    o.append(text("REPLAYED AT RECORDED CI SPEED · LIMITS 720PX / 2CH", 976, 428, 10, "mono", c["mute"], ls=0.05, anchor="end"))

    defs = "".join(f'<path id="{gid}" d="{d}"/>' for gid, d in _glyphs.values() if d)
    o.insert(1, f"<defs>{defs}</defs>")
    o.append("</svg>")
    return "".join(o)


# --- the project page -------------------------------------------------------------------------
def dial_markup(key):
    """The dial face for the page: real <text>, so it uses the page's self-hosted fonts."""
    d, cx, cy = DIALS[key], 160, 160
    o = [
        f'<svg class="face" viewBox="0 0 320 320" aria-hidden="true">',
        f'<circle class="rim" cx="{cx}" cy="{cy}" r="152"/>',
        f'<path class="red" d="{arc(cx, cy, 142, angle(key, d["limit"]), SWEEP)}"/>',
    ]
    ticks, nums = [], []
    v = 0.0
    while v <= d["max"] + 1e-9:
        major = abs(v / d["major"] - round(v / d["major"])) < 1e-9
        x0, y0 = polar(cx, cy, 121 if major else 129, angle(key, v))
        x1, y1 = polar(cx, cy, 137, angle(key, v))
        ticks.append(f'<line class="{"mj" if major else "mn"}" x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}"/>')
        if major:
            tx, ty = polar(cx, cy, 92, angle(key, v))
            lim = ' class="lim"' if v == d["limit"] else ""
            nums.append(f'<text{lim} x="{tx:.1f}" y="{ty + 5.5:.1f}">{fmt(v)}</text>')
        v += d["minor"]
    o.append(f'<g class="ticks">{"".join(ticks)}</g><g class="nums">{"".join(nums)}</g>')
    o.append(f'<polygon class="ghost" points="{needle_points(cx, cy, r0=116.0, r1=151.0, w0=4.4, w1=1.6)}"/>')
    o.append(f'<polygon class="needle" points="{needle_points(cx, cy, r0=116.0, r1=151.0, w0=4.4, w1=1.6)}"/>')
    o.append("</svg>")
    return "".join(o)


def term_lines(run):
    out = [f'<span class="l-cmd"><span class="ps">$</span> {html.escape(run["cmd"])}</span>']
    for line in run["screen"]:
        kind = line_kind(line)
        if kind == "progress":
            out.append(f'<span class="l-progress">{html.escape(line)}</span>')
        else:
            label, rest = line[:6], line[6:]
            out.append(f'<span class="l-{kind}"><b>{html.escape(label)}</b>{html.escape(rest)}</span>')
    return "".join(out)


def cluster_markup(runs, recorded):
    a = summary(runs["road-trip"])
    r = runs["road-trip"]
    ff, osv = where(recorded)

    def stream_bay(key, title, limit_label, vin, vout, dim_in, dim_out, spec_in, spec_out, act):
        state = "fits" if vout <= DIALS[key]["limit"] else "over"
        frm = f"from {fmt(vin)}" if vin != vout else ""
        act_label = "COPY" if act == "copy" else "RE-ENCODE"
        act_cls = "is-copy" if act == "copy" else "is-encode"
        return (
            f'<div class="bay" id="bay-{key}">'
            f'<div class="dial" id="dial-{key}" style="--a:{angle(key, vout):.2f}deg;--g:{angle(key, vin):.2f}deg"'
            f'{" data-ghost" if vin != vout else ""}>'
            f'{dial_markup(key)}'
            f'<p class="hub">'
            f'<span class="hub-unit">{DIALS[key]["unit"]}</span>'
            f'<b class="hub-val" data-s="{state}">{fmt(vout)}</b>'
            f'<span class="hub-state" data-s="{state}">{"Fits" if state == "fits" else "Over"}</span>'
            f'<span class="hub-from">{frm}</span>'
            f'</p></div>'
            f'<div class="spec">'
            f'<div class="spec-head">'
            f'<span class="spec-title">{title}</span>'
            f'<span class="spec-act {act_cls}" id="act-{key}">{act_label}</span>'
            f'</div>'
            f'<p class="spec-limit">{limit_label}</p>'
            f'<div class="spec-box" id="in-{key}">'
            f'<div class="spec-row"><span class="spec-k is-in">IN</span><span class="spec-dim" id="dim-in-{key}">{html.escape(dim_in)}</span></div>'
            f'<div class="spec-val" id="spec-in-{key}">{html.escape(spec_in)}</div>'
            f'</div>'
            f'<div class="spec-arrow" aria-hidden="true">↓</div>'
            f'<div class="spec-box is-out" id="out-{key}" data-ready="true">'
            f'<div class="spec-row"><span class="spec-k is-out">OUT</span><span class="spec-dim" id="dim-out-{key}">{html.escape(dim_out)}</span></div>'
            f'<div class="spec-val" id="spec-out-{key}">{html.escape(spec_out)}</div>'
            f'</div>'
            f'</div></div>'
        )

    grad = (
        '<svg width="0" height="0" style="position:absolute" aria-hidden="true">'
        '<defs><radialGradient id="face-grad"><stop class="g0" offset="0"/><stop class="g1" offset="1"/></radialGradient></defs>'
        '</svg>'
    )
    return (
        f'<div class="cluster-head">'
        f'<div class="cluster-cmd">'
        f'<span class="cluster-ver">{html.escape(recorded["carify"])}</span>'
        f'<code class="cluster-cmd-line" id="cmd-line"><span class="ps">$</span> <span id="cmd-typed">{html.escape(r["cmd"])}</span></code>'
        f'</div>'
        f'<div class="cluster-meta">'
        f'<p class="usb" id="usb" data-s="done"><b>[USB]</b> '
        f'<span class="w-none">standby</span><span class="w-copy">copying</span><span class="w-done">safe to remove</span></p>'
        f'<button type="button" class="cluster-ctrl" id="cluster-ctrl">Replay</button>'
        f'</div>'
        f'</div>'
        f'<div class="binnacle">{grad}'
        f'{stream_bay("v", "VIDEO STREAM", DIALS["v"]["limit_label"], a["vin"], a["vout"], a["vdim_in"], a["vdim_out"], a["vspec_in"], a["vspec_out"], a["vact"])}'
        f'{stream_bay("a", "AUDIO STREAM", DIALS["a"]["limit_label"], a["ain"], a["aout"], a["adim_in"], a["adim_out"], a["aspec_in"], a["aspec_out"], a["aact"])}'
        f'</div>'
        f'<div class="pipeline">'
        f'<div class="pipeline-row">'
        f'<p class="pipeline-msg" id="pipe-msg" data-s="ok"><b id="pipe-tag">[ok]</b> <span id="pipe-text">wrote ./{html.escape(a["out"])} ({html.escape(a["size"])}) · copied to /media/runner/MOVIES</span></p>'
        f'<span class="pipeline-stat" id="pipe-stat">{a["seconds"]:g} s · {html.escape(a["speed"])}</span>'
        f'</div>'
        f'<div class="bar" aria-hidden="true"><i id="bar" style="--p:1"></i></div>'
        f'</div>'
        f'<div class="log-strip">'
        f'<div class="log-bar"><span>Recorded terminal output</span><span>{html.escape(osv)} · ffmpeg {ff}</span></div>'
        f'<pre class="term" id="term"><code>{term_lines(r)}</code></pre>'
        f'</div>'
    )


def files_markup(runs):
    out = []
    for name, r in runs.items():
        pressed = "true" if name == "road-trip" else "false"
        out.append(
            f'<button type="button" class="file" data-run="{name}" aria-pressed="{pressed}">'
            f'<code>{html.escape(r["file"])}</code><span>{html.escape(r["why"].split(": ", 1)[1])}</span>'
            f'<em>{html.escape(r["why"].split(": ", 1)[0].capitalize())}</em></button>'
        )
    return "".join(out)


def run_rows(runs):
    """One row per run for the tables: clip, came in as, what carify did, time, speed, went out as."""
    rows = []
    for r in runs.values():
        iv, ia, ov, oa = r["in"]["video"], r["in"]["audio"], r["out"]["video"], r["out"]["audio"]
        did = [f"{kind} copied" if f"{kind}  copy" in r["screen"] else f"{kind} re-encoded" for kind in ("video", "audio")]
        prog = next(l for l in r["screen"] if line_kind(l) == "progress")
        rows.append({
            "file": r["file"],
            "in": f'{iv["codec_name"]} {iv.get("profile", "")}, {iv["width"]}×{iv["height"]}, {audio_words(ia)}',
            "did": ", ".join(did).capitalize(),
            "took": f'{r["seconds"]:g} s',
            "speed": re.search(r"speed=\s*([\d.e+]+x)", prog).group(1),
            "out": f'{ov["codec_name"]} {ov.get("profile", "")} {ov.get("level", 0) / 10:g}, {ov["width"]}×{ov["height"]}, '
                   f'{audio_words(oa)}, {summary(r)["size"]}',
        })
    return rows


def runs_table(runs):
    e = html.escape
    return "".join(
        f'<tr><th scope="row"><code>{e(x["file"])}</code></th><td>{e(x["in"])}</td><td>{e(x["did"])}</td>'
        f'<td class="num">{e(x["took"]).replace(" ", "&nbsp;")} <span>({e(x["speed"])})</span></td>'
        f'<td>{e(x["out"]).replace(" MB", "&nbsp;MB").replace(" KB", "&nbsp;KB")}</td></tr>'
        for x in run_rows(runs)
    )


def readme_table(runs):
    out = ["", "", "| Clip | Came in as | carify | Took | Went out as |", "|---|---|---|---|---|"]
    out += [f'| `{x["file"]}` | {x["in"]} | {x["did"]} | {x["took"]} ({x["speed"]}) | {x["out"]} |' for x in run_rows(runs)]
    return NL.join(out) + NL + NL


def readme_run(run):
    return NL + NL + "```text" + NL + "$ " + run["cmd"] + NL + NL.join(run["screen"]) + NL + "```" + NL + NL


def patch(path, marker, content):
    with open(path, encoding="utf-8") as fh:
        page = fh.read()
    pat = re.compile(rf"(<!-- art:{marker} -->).*?(<!-- /art:{marker} -->)", re.S)
    if not pat.search(page):
        sys.exit(f"{path} has no art:{marker} markers")
    page = pat.sub(lambda m: m.group(1) + content + m.group(2), page)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(page)


def main():
    with open(os.path.join(HERE, "runs.json"), encoding="utf-8") as fh:
        data = json.load(fh)
    runs = {r["name"]: r for r in data["runs"]}
    sums = {k: summary(v) for k, v in runs.items()}

    for theme in THEMES:
        _glyphs.clear()
        path = os.path.join(DOCS, "assets", f"cluster-{theme}.svg")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(build_svg(theme, sums, data["recorded"]) + "\n")
        print(f"wrote {os.path.relpath(path)} ({os.path.getsize(path) // 1024} KB)")

    js = {"recorded": data["recorded"], "dials": DIALS, "sweep": SWEEP, "runs": list(sums.values())}
    path = os.path.join(DOCS, "runs.js")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("// Generated by docs/art/make-art.py from docs/art/runs.json. Don't edit by hand.\n")
        fh.write("window.CARIFY_RUNS = " + json.dumps(js, separators=(",", ":"), sort_keys=True, ensure_ascii=False) + ";\n")
    print(f"wrote {os.path.relpath(path)} ({os.path.getsize(path) // 1024} KB)")

    page = os.path.join(DOCS, "index.html")
    patch(page, "cluster", cluster_markup(runs, data["recorded"]))
    patch(page, "files", files_markup(runs))
    patch(page, "runs", runs_table(runs))
    ff, osv = where(data["recorded"])
    patch(
        page,
        "recorded",
        f"{html.escape(data['recorded']['carify'])} on 30-second test clips, "
        f"recorded on GitHub's {osv} runner with ffmpeg {ff}",
    )
    for name in ("dashcam", "road-trip"):
        patch(page, f"t-{name}", f"{runs[name]['seconds']:g}&nbsp;s")
    print(f"patched {os.path.relpath(page)}")

    readme = os.path.normpath(os.path.join(DOCS, "..", "README.md"))
    patch(readme, "readme-run", readme_run(runs["road-trip"]))
    patch(readme, "readme-runs", readme_table(runs))
    print(f"patched {os.path.relpath(readme)}")


if __name__ == "__main__":
    main()
