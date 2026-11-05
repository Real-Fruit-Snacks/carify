"""Draw the cluster from docs/art/runs.json: the README's animated SVGs and the project page's data.

Writes:
  docs/assets/cluster-dark.svg, cluster-light.svg   the README picture: road-trip.mkv, then cartoons.mkv
  docs/runs.js                                      the four recorded runs, for the page's replay
  docs/index.html, between the art:* markers         the cluster in its finished road-trip state
                                                    (what the page shows without JS), the runs table
                                                    and the timings quoted in the text
  README.md, between the art:* markers               road-trip.mkv's output and the runs table

The dials are carify's limits drawn as redlines: frame height (720, the --max-height default) and
audio channels (2). Text in the SVGs is converted to paths from docs/fonts, because an SVG shown
through <img> can't load fonts. The SVG's base styles are the finished road-trip state, which is
what a viewer that skips the animation shows. Run from the repo root:

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

# RFS Nightshift and Dayshift, and nothing else
THEMES = {
    "dark": dict(plate="#1A1D24", face="#070809", hub="#13151A", line="#262A33", strong="#636872", ink="#E8E6E1", mute="#8A8F99",
                 ember="#FF6A3D", amber="#FFC247", mint="#3DDC97", rasp="#F06292", glow=True),
    "light": dict(plate="#FFFFFF", face="#ECEAE4", hub="#FFFFFF", line="#D6D3CB", strong="#89867F", ink="#1A1B1E", mute="#666A73",
                  ember="#C03B0A", amber="#925F00", mint="#15794D", rasp="#B0306A", glow=False),
}

# --- the dials --------------------------------------------------------------------------------
# A 240-degree sweep, 0 at the bottom left, the top of the scale at the bottom right.
SWEEP = 120.0
DIALS = {
    "v": dict(title="Frame height", max=2160, limit=720, major=360, minor=120),
    "a": dict(title="Audio channels", max=8, limit=2, major=1, minor=0.5),
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


# The needle: a tapered bar across the tick ring, pointing up; rotated about the dial's centre.
def needle_points(cx, cy, k=1.0):
    r0, r1, w0, w1 = 110 * k, 151 * k, 4.6 * k, 1.6 * k
    return f"{cx - w0:.2f},{cy - r0:.2f} {cx - w1:.2f},{cy - r1:.2f} {cx + w1:.2f},{cy - r1:.2f} {cx + w0:.2f},{cy - r0:.2f}"


# --- what a run shows -------------------------------------------------------------------------
def video_words(v):
    depth = "10-bit" if "10" in v.get("pix_fmt", "") else "8-bit"
    if v.get("pix_fmt", "").startswith(("yuv422", "yuv444")):
        depth += " " + v["pix_fmt"][3:6]
    return f"{v['codec_name']} {depth}"


def audio_words(a):
    layout = a.get("channel_layout", "")
    layout = {"5.1(side)": "5.1", "stereo": "stereo", "mono": "mono"}.get(layout, layout or f"{a['channels']}ch")
    return f"{a['codec_name']} {layout}"


def line_kind(line):
    """The colour carify gives a status line: say() is Ember, ok() is Mint, warn() is Amber."""
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
    s = {"name": run["name"], "file": run["file"], "why": run["why"], "cmd": run["cmd"], "seconds": run["seconds"],
         "events": [[t, end == "\r", text] for t, end, text in run["events"]],
         "vin": i["video"]["height"], "vout": o["video"]["height"],
         "ain": i["audio"]["channels"], "aout": o["audio"]["channels"],
         "vwin": video_words(i["video"]), "vwout": video_words(o["video"]),
         "awin": audio_words(i["audio"]), "awout": audio_words(o["audio"]),
         "out": os.path.basename(next(l for l in run["screen"] if l.startswith("wrote")).split()[1]),
         "size": re.search(r"\((\d+ [KM]B)\)", next(l for l in run["screen"] if l.startswith("wrote"))).group(1),
         "duration": i["duration"], "screen": run["screen"]}
    return s


# --- text as paths ----------------------------------------------------------------------------
_fonts, _glyphs = {}, {}
FACES = {
    "cond": ("saira-latin-var.woff2", {"wght": 600, "wdth": 75}),
    "condb": ("saira-latin-var.woff2", {"wght": 700, "wdth": 75}),
    "num": ("saira-latin-var.woff2", {"wght": 700, "wdth": 100}),
    "mono": ("jetbrains-mono-latin-var.woff2", {"wght": 400}),
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


# --- the README SVG ---------------------------------------------------------------------------
W, H = 1000, 470
CX = {"v": 180, "a": 820}
CY = 262
SX, SW = 352, 296        # the centre screen


def pct(t, cycle):
    return f"{max(0.0, min(t, cycle)) / cycle * 100:.3f}%"


def build_svg(theme, runs, recorded):
    c = THEMES[theme]
    a, b = runs["road-trip"], runs["cartoons"]
    # ---- the timeline (seconds) ----
    SWEEP_UP, SWEEP_DOWN = 0.7, 0.7
    A0 = SWEEP_UP + SWEEP_DOWN                        # road-trip's run starts once the needles settle
    a_probe = A0 + a["events"][0][0]
    a_wrote = A0 + next(t for t, _, x in a["events"] if x.startswith("wrote"))
    a_done = A0 + a["events"][-1][0]
    B0 = a_done + 3.4                                 # cartoons.mkv: the audio needle rises to 6
    B_RISE = 0.6
    B1 = B0 + B_RISE
    b_probe = B1 + b["events"][0][0]
    b_wrote = B1 + next(t for t, _, x in b["events"] if x.startswith("wrote"))
    b_done = B1 + b["events"][-1][0]
    OFF = b_done + 3.6                                # needles fall back before the loop starts again
    CYCLE = OFF + 0.5
    DROP = 0.6

    # ---- needle keyframes: (time, angle, easing to the next keyframe) ----
    ease_io, ease_out, ease_in = "cubic-bezier(.45,0,.55,1)", "cubic-bezier(.2,.7,.2,1)", "cubic-bezier(.5,0,.75,0)"
    lo, hi = -SWEEP, SWEEP
    needle = {
        "v": [(0, lo, ease_io), (SWEEP_UP, hi, ease_out), (A0, angle("v", a["vin"]), "linear"),
              (a_wrote, angle("v", a["vin"]), ease_out), (a_wrote + DROP, angle("v", a["vout"]), "linear"),
              (B0, angle("v", a["vout"]), ease_io), (B1, angle("v", b["vin"]), "linear"),
              (b_wrote, angle("v", b["vin"]), ease_out), (b_wrote + DROP, angle("v", b["vout"]), "linear"),
              (OFF, angle("v", b["vout"]), ease_in), (CYCLE, lo, "linear")],
        "a": [(0, lo, ease_io), (SWEEP_UP, hi, ease_out), (A0, angle("a", a["ain"]), "linear"),
              (a_wrote, angle("a", a["ain"]), ease_out), (a_wrote + DROP, angle("a", a["aout"]), "linear"),
              (B0, angle("a", a["aout"]), ease_io), (B1, angle("a", b["ain"]), "linear"),
              (b_wrote, angle("a", b["ain"]), ease_out), (b_wrote + DROP, angle("a", b["aout"]), "linear"),
              (OFF, angle("a", b["aout"]), ease_in), (CYCLE, lo, "linear")],
    }

    def rot_keys(name, keys):
        body = "".join(f"{pct(t, CYCLE)}{{transform:rotate({deg:.2f}deg);animation-timing-function:{ez}}}" for t, deg, ez in keys)
        return f"@keyframes {name}{{{body}}}"

    # ---- what shows when: (start, end) windows ----
    win = {
        # road-trip
        "a-cmd": [(0, B0)], "a-out": [(a_wrote, B0)],
        "a-vin": [(a_probe, a_wrote)], "a-vout": [(a_wrote, B0)],
        "a-ain": [(a_probe, a_wrote)], "a-aout": [(a_wrote, B0)],
        "a-vlamp": [(a_probe, B0)], "a-alamp": [(a_probe, B0)],
        "a-busy": [(a_probe, a_wrote)], "a-took": [(a_wrote, B0)],
        "ghost-v": [(a_wrote, B0)], "a-ghost-a": [(a_wrote, B0)],
        # cartoons
        "b-cmd": [(B0, OFF)], "b-out": [(b_wrote, OFF)],
        "b-vin": [(b_probe, OFF)],
        "b-ain": [(b_probe, b_wrote)], "b-aout": [(b_wrote, OFF)],
        "b-vlamp": [(b_probe, OFF)], "b-alamp": [(b_probe, OFF)],
        "b-busy": [(b_probe, b_wrote)], "b-took": [(b_wrote, OFF)],
        "b-ghost-a": [(b_wrote, OFF)],
        # the stick, both runs
        "usb-copy": [(a_wrote, a_done), (b_wrote, b_done)], "usb-done": [(a_done, B0), (b_done, OFF)],
    }

    def toggle(name, windows):
        shown = lambda t: int(any(s <= t < e for s, e in windows))
        points = sorted({0.0} | {t for w in windows for t in w if 0 < t < CYCLE})
        body = "".join(f"{pct(t, CYCLE)}{{opacity:{shown(t)}}}" for t in points)
        return f"@keyframes {name}{{{body}100%{{opacity:{shown(0.0)}}}}}"

    # The finished road-trip state is the still frame.
    still = {k: int(any(s <= a_done + 1 < e for s, e in v)) for k, v in win.items()}

    # progress bars: the share of the clip ffmpeg had written at each redraw
    def progress_keys(name, run, start, end_hold):
        pts = [(0.0, 0.0), (start, 0.0)]
        for t, _, x in run["events"]:
            m = re.search(r"time=(-?)(\d+):(\d+):([\d.]+)", x)
            if m and not m.group(1):
                sec = int(m.group(2)) * 3600 + int(m.group(3)) * 60 + float(m.group(4))
                pts.append((start + t, min(sec / run["duration"], 1.0)))
        pts.append((end_hold, pts[-1][1]))
        pts.append((min(end_hold + 0.001, CYCLE), 0.0))
        body = "".join(f"{pct(t, CYCLE)}{{transform:scaleX({v:.3f})}}" for t, v in pts)
        return f"@keyframes {name}{{{body}100%{{transform:scaleX(0)}}}}"

    css = [toggle(k, v) for k, v in win.items()]
    css += [rot_keys("nv", needle["v"]), rot_keys("na", needle["a"])]
    css += [progress_keys("pa", a, A0, B0), progress_keys("pb", b, B1, OFF)]
    anim = "".join(f".{k}{{animation:{k} {CYCLE:.2f}s step-end infinite}}" for k in win)
    anim += f".nv{{animation:nv {CYCLE:.2f}s infinite}}.na{{animation:na {CYCLE:.2f}s infinite}}"
    anim += f".pa{{animation:pa {CYCLE:.2f}s linear infinite}}.pb{{animation:pb {CYCLE:.2f}s linear infinite}}"
    base = "".join(f".{k}{{opacity:{v}}}" for k, v in still.items())
    base += (f".nv{{transform:rotate({angle('v', a['vout']):.2f}deg)}}.na{{transform:rotate({angle('a', a['aout']):.2f}deg)}}"
             f".nv,.na,.pa,.pb{{transform-box:view-box}}.nv{{transform-origin:{CX['v']}px {CY}px}}"
             f".na{{transform-origin:{CX['a']}px {CY}px}}.pa,.pb{{transform-origin:{SX + 14}px 0}}.pb{{transform:scaleX(0)}}")

    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img">']
    o.append(f"<style>{base}@media (prefers-reduced-motion:no-preference){{{''.join(css)}{anim}}}</style>")
    o.append(f'<defs><radialGradient id="face"><stop offset="0" stop-color="{c["hub"]}"/><stop offset="1" stop-color="{c["face"]}"/></radialGradient></defs>')
    if c["glow"]:
        o.append('<defs><filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4" result="b"/>'
                 '<feComponentTransfer in="b" result="g"><feFuncA type="linear" slope=".8"/></feComponentTransfer>'
                 '<feMerge><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>')
    glow = ' filter="url(#glow)"' if c["glow"] else ""

    # the plate and its legends
    o.append(f'<rect x="0.5" y="0.5" width="{W - 1}" height="{H - 1}" rx="26" fill="{c["plate"]}" stroke="{c["line"]}"/>')
    ver = recorded["carify"].upper()
    ff, osv = where(recorded)
    o.append(text(ver, 40, 50, 15, "condb", c["mute"], ls=0.2))
    o.append(text(f"RECORDED RUN · {osv.upper()} · FFMPEG {ff}", W - 40, 50, 15, "cond", c["mute"], ls=0.14, anchor="end"))

    # the dials
    for key in ("v", "a"):
        d, cx = DIALS[key], CX[key]
        o.append(f'<circle cx="{cx}" cy="{CY}" r="152" fill="url(#face)" stroke="{c["line"]}" stroke-width="2"/>')
        o.append(f'<path d="{arc(cx, CY, 145, angle(key, d["limit"]), SWEEP)}" fill="none" stroke="{c["rasp"]}" stroke-width="5"/>')
        ticks = []
        v = 0.0
        while v <= d["max"] + 1e-9:
            major = abs(v / d["major"] - round(v / d["major"])) < 1e-9
            r0 = 124 if major else 131
            x0, y0 = polar(cx, CY, r0, angle(key, v))
            x1, y1 = polar(cx, CY, 138, angle(key, v))
            col = c["ink"] if major else c["strong"]
            ticks.append(f'<line x1="{x0:.2f}" y1="{y0:.2f}" x2="{x1:.2f}" y2="{y1:.2f}" stroke="{col}" stroke-width="{3 if major else 1.6}"/>')
            if major:
                tx, ty = polar(cx, CY, 100, angle(key, v))
                o.append(text(fmt(v), tx, ty + 6, 17, "cond", c["ink"] if v != d["limit"] else c["rasp"], anchor="middle"))
            v += d["minor"]
        o.append(f'<g stroke-linecap="round">{"".join(ticks)}</g>')
        o.append(text(d["title"].upper(), cx, CY - 46, 14, "condb", c["mute"], ls=0.16, anchor="middle"))

    # ghost needles where the input was, then the live needles
    o.append(f'<polygon class="ghost-v" points="{needle_points(CX["v"], CY)}" fill="{c["rasp"]}" fill-opacity=".5" '
             f'transform="rotate({angle("v", a["vin"]):.2f} {CX["v"]} {CY})"/>')
    for cls, run in (("a-ghost-a", a), ("b-ghost-a", b)):
        o.append(f'<polygon class="{cls}" points="{needle_points(CX["a"], CY)}" fill="{c["rasp"]}" fill-opacity=".5" '
                 f'transform="rotate({angle("a", run["ain"]):.2f} {CX["a"]} {CY})"/>')
    o.append(f'<g{glow}><polygon class="nv" points="{needle_points(CX["v"], CY)}" fill="{c["ember"]}"/>'
             f'<polygon class="na" points="{needle_points(CX["a"], CY)}" fill="{c["ember"]}"/></g>')
    for key in ("v", "a"):
        o.append(f'<circle cx="{CX[key]}" cy="{CY}" r="2" fill="none"/>')

    # hub readouts: the value, OVER or FITS, the codec
    def hub(cls, key, value, words, state, frm=None):
        cx = CX[key]
        col = c["mint"] if state == "FITS" else c["rasp"]
        parts = [text(fmt(value), cx, CY + 20, 58, "num", col, anchor="middle"),
                 text(state, cx, CY + 96, 18, "condb", col, ls=0.18, anchor="middle"),
                 text(words, cx, CY + 124, 16, "mono", c["ink"], anchor="middle")]
        if frm is not None:
            parts.append(text(f"from {fmt(frm)}", cx, CY + 48, 15, "mono", c["mute"], anchor="middle"))
        return f'<g class="{cls}">{"".join(parts)}</g>'

    over = lambda key, v: "FITS" if v <= DIALS[key]["limit"] else "OVER"
    o.append(hub("a-vin", "v", a["vin"], a["vwin"], over("v", a["vin"])))
    o.append(hub("a-vout", "v", a["vout"], a["vwout"], over("v", a["vout"]), a["vin"]))
    o.append(hub("a-ain", "a", a["ain"], a["awin"], over("a", a["ain"])))
    o.append(hub("a-aout", "a", a["aout"], a["awout"], over("a", a["aout"]), a["ain"]))
    o.append(hub("b-vin", "v", b["vin"], b["vwin"], over("v", b["vin"])))
    o.append(hub("b-ain", "a", b["ain"], b["awin"], over("a", b["ain"])))
    o.append(hub("b-aout", "a", b["aout"], b["awout"], over("a", b["aout"]), b["ain"]))

    # the centre screen
    sx, sw = SX, SW
    o.append(f'<rect x="{sx}" y="98" width="{sw}" height="320" rx="16" fill="{c["face"]}" stroke="{c["line"]}" stroke-width="2"/>')
    mid = sx + sw / 2
    for cls, run in (("a-cmd", a), ("b-cmd", b)):
        w = advance("$ " + run["cmd"], 17, "mono")
        x0 = mid - w / 2
        o.append(f'<g class="{cls}">{text("$", x0, 138, 17, "mono", c["mute"])}'
                 f'{text(run["cmd"], x0 + advance("$ ", 17, "mono"), 138, 17, "mono", c["ink"])}</g>')
    o.append(f'<rect x="{sx + 14}" y="156" width="{sw - 28}" height="6" rx="3" fill="{c["line"]}"/>')
    o.append(f'<rect class="pa" x="{sx + 14}" y="156" width="{sw - 28}" height="6" rx="3" fill="{c["ember"]}"/>')
    o.append(f'<rect class="pb" x="{sx + 14}" y="156" width="{sw - 28}" height="6" rx="3" fill="{c["ember"]}"/>')
    for cls, msg, col in (("a-busy", "ffmpeg encoding", c["ember"]), ("b-busy", "ffmpeg encoding", c["ember"]),
                          ("a-took", f"done in {a['seconds']:g} s", c["mute"]), ("b-took", f"done in {b['seconds']:g} s", c["mute"])):
        o.append(text(msg, mid, 188, 15, "mono", col, anchor="middle", cls=cls))

    def lamp(y, label, states):
        parts = [f'<rect x="{sx + 14}" y="{y}" width="{sw - 28}" height="38" rx="9" fill="none" stroke="{c["line"]}" stroke-width="2"/>',
                 text(label, sx + 30, y + 25, 16, "condb", c["mute"], ls=0.16)]
        for cls, word, col in states:
            parts.append(text(word, sx + sw - 30, y + 25, 16, "condb", col, ls=0.12, anchor="end", cls=cls))
        return "".join(parts)

    rtag = lambda run, kind: "COPY" if f"{kind}  copy" in run["screen"] else "RE-ENCODE"
    col = lambda word: c["mint"] if word == "COPY" else c["ember"]
    o.append(lamp(208, "VIDEO", [("a-vlamp", rtag(a, "video"), col(rtag(a, "video"))), ("b-vlamp", rtag(b, "video"), col(rtag(b, "video")))]))
    o.append(lamp(256, "AUDIO", [("a-alamp", rtag(a, "audio"), col(rtag(a, "audio"))), ("b-alamp", rtag(b, "audio"), col(rtag(b, "audio")))]))
    o.append(lamp(304, "USB", [("usb-copy", "COPYING", c["ember"]), ("usb-done", "SAFE TO REMOVE", c["mint"])]))
    for cls, run in (("a-out", a), ("b-out", b)):
        o.append(f'<g class="{cls}">{text(run["out"], mid, 374, 17, "mono", c["mint"], anchor="middle")}'
                 f'{text(run["size"] + " on the stick", mid, 398, 15, "mono", c["mute"], anchor="middle")}</g>')

    defs = "".join(f'<path id="{gid}" d="{d}"/>' for gid, d in _glyphs.values() if d)
    o.insert(1, f"<defs>{defs}</defs>")
    o.append("</svg>")
    return "".join(o)


# --- the page ---------------------------------------------------------------------------------
def dial_markup(key):
    """The dial face for the page: real <text>, so it uses the page's fonts."""
    d, cx, cy = DIALS[key], 160, 160
    o = [f'<svg class="face" viewBox="0 0 320 320" aria-hidden="true">',
         f'<circle class="rim" cx="{cx}" cy="{cy}" r="152"/>',
         f'<path class="red" d="{arc(cx, cy, 143, angle(key, d["limit"]), SWEEP)}"/>']
    ticks, nums = [], []
    v = 0.0
    while v <= d["max"] + 1e-9:
        major = abs(v / d["major"] - round(v / d["major"])) < 1e-9
        x0, y0 = polar(cx, cy, 124 if major else 131, angle(key, v))
        x1, y1 = polar(cx, cy, 138, angle(key, v))
        ticks.append(f'<line class="{"mj" if major else "mn"}" x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}"/>')
        if major:
            tx, ty = polar(cx, cy, 100, angle(key, v))
            lim = ' class="lim"' if v == d["limit"] else ""
            nums.append(f'<text{lim} x="{tx:.1f}" y="{ty + 6:.1f}">{fmt(v)}</text>')
        v += d["minor"]
    o.append(f'<g class="ticks">{"".join(ticks)}</g><g class="nums">{"".join(nums)}</g>')
    o.append(f'<polygon class="ghost" points="{needle_points(cx, cy)}"/>')
    o.append(f'<polygon class="needle" points="{needle_points(cx, cy)}"/>')
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
    ff, osv = where(recorded)

    def gauge(key, vin, vout, wout):
        state = "fits" if vout <= DIALS[key]["limit"] else "over"
        frm = f'from {fmt(vin)}' if vin != vout else ""
        return (f'<div class="gauge" id="gauge-{key}"><p class="legend">{DIALS[key]["title"]}</p>'
                f'<div class="dial" id="dial-{key}" style="--a:{angle(key, vout):.2f}deg;--g:{angle(key, vin):.2f}deg"'
                f'{" data-ghost" if vin != vout else ""}>'
                f'{dial_markup(key)}'
                f'<p class="hub"><b class="hub-val" data-s="{state}">{fmt(vout)}</b>'
                f'<span class="hub-from">{frm}</span>'
                f'<span class="hub-state" data-s="{state}">{"Fits" if state == "fits" else "Over"}</span>'
                f'<code class="hub-codec">{html.escape(wout)}</code></p></div></div>')

    r = runs["road-trip"]
    grad = ('<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs><radialGradient id="face-grad">'
            '<stop class="g0" offset="0"/><stop class="g1" offset="1"/></radialGradient></defs></svg>')
    return (f'<div class="binnacle">{grad}'
            f'{gauge("v", a["vin"], a["vout"], a["vwout"])}'
            f'<div class="console"><p class="legend"><span>{html.escape(recorded["carify"])}</span>'
            f'<span>Recorded run · {html.escape(osv)} · ffmpeg {ff}</span></p>'
            f'<div class="screen"><pre class="term" id="term"><code>{term_lines(r)}</code></pre>'
            f'<div class="bar" aria-hidden="true"><i id="bar" style="--p:1"></i></div>'
            f'<p class="usb" id="usb" data-s="done"><b>USB</b> <span class="w-none">waiting</span>'
            f'<span class="w-copy">copying</span><span class="w-done">safe to remove</span></p></div></div>'
            f'{gauge("a", a["ain"], a["aout"], a["awout"])}'
            f'</div>')


def files_markup(runs):
    out = []
    for name, r in runs.items():
        pressed = "true" if name == "road-trip" else "false"
        out.append(f'<button type="button" class="file" data-run="{name}" aria-pressed="{pressed}">'
                   f'<code>{html.escape(r["file"])}</code><span>{html.escape(r["why"].split(": ", 1)[1])}</span>'
                   f'<em>{html.escape(r["why"].split(": ", 1)[0].capitalize())}</em></button>')
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
        f'<td>{e(x["out"]).replace(" MB", "&nbsp;MB").replace(" KB", "&nbsp;KB")}</td></tr>' for x in run_rows(runs))


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
    patch(page, "recorded", f"{html.escape(data['recorded']['carify'])} on 30-second test clips, "
                            f"recorded on GitHub's {osv} runner with ffmpeg {ff}")
    for name in ("dashcam", "road-trip"):
        patch(page, f"t-{name}", f"{runs[name]['seconds']:g}&nbsp;s")
    print(f"patched {os.path.relpath(page)}")

    readme = os.path.normpath(os.path.join(DOCS, "..", "README.md"))
    patch(readme, "readme-run", readme_run(runs["road-trip"]))
    patch(readme, "readme-runs", readme_table(runs))
    print(f"patched {os.path.relpath(readme)}")


if __name__ == "__main__":
    main()
