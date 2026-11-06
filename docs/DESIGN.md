# Design: the carify page (docs/) and README cluster

## Concept

carify's whole job is fitting a video under a line: the head unit plays 8-bit H.264 at 720p or smaller with AAC stereo, and anything over that is re-encoded down to it. So the page is a car's instrument cluster, and the head unit's limits are the redlines. Two dials, frame height and audio channels, flank a centre screen, the way a speedometer and a rev counter flank a cluster's info display. A file's real stream values sit on the dials; carify's run brings each needle back under its redline, or leaves it where it is when it already fits. A visitor should leave knowing which two numbers matter, that carify copies whatever is already under the line, and that the file ends up on the stick.

## Audience and primary action

People with a Chrysler, Jeep, Dodge or Ram whose head unit says "unsupported file", or plays a movie with no sound. They need to see what carify does to a file, believe it on real output, and copy the install line for their system.

## Type

- Saira, one variable file (`fonts/saira-latin-var.woff2`, weight 100 to 900, width 50 to 125%), in three widths:
  - 125% at 800 for the wordmark, the way model names are badged on a tailgate;
  - 100% at 700 to 720 for the headline, section heads and the dial readouts, and at 400 to 500 for text;
  - 75% at 600 to 700, in capitals with 0.14 to 0.18em tracking, for every instrument legend: dial titles, Fits and Over, the USB lamp, table heads, tabs.
  Saira's squared curves are the shape of dashboard type, and one family at three widths keeps the page to one voice.
- JetBrains Mono 400 to 500 for carify's output, commands, file names and codec words. It's the terminal in the centre screen.
- Scale: `scale.mjs`, 16px to 18px, ratio 1.2 to 1.333. The headline is `clamp(2.2rem, 1.15rem + 4.3vw, 5rem)`; dial readouts are 17.5% of the dial's width (container query units), so they scale with the dial.
- Both fonts are self-hosted with their OFL licences, latin subset from Google Fonts.

## Color

The RFS Nightshift and Dayshift values and nothing else. The OS setting decides the theme, the Night/Day switch overrides it (with a sweep from the click point), and the choice is saved as `rfs-theme` like the other RFS pages.

| Role | Night | Day | Use |
|---|---|---|---|
| bg / surface / raised | `#0C0D10` / `#13151A` / `#1A1D24` | `#F6F5F2` / `#FFFFFF` / `#ECEAE4` | Page; the binnacle plate (raised at night, surface by day) |
| dial faces | `#13151A` to `#070809` | `#FFFFFF` to `#ECEAE4` | A radial fade from surface to code-bg (night) or raised (day): black faces at night, white faces by day |
| line / line-strong | `#262A33` / `#636872` | `#D6D3CB` / `#89867F` | Rules, rims, minor ticks |
| ink / mute | `#E8E6E1` / `#8A8F99` | `#1A1B1E` / `#666A73` | Text, major ticks and numerals |
| Ember | `#FF6A3D` | `#C03B0A` | carify itself: the needles, the progress bar, the copy button, focus, and the status labels carify's `say()` colours (probe, re-encode, copying) |
| Mint | `#3DDC97` | `#15794D` | Under the line: Fits, and the labels carify's `ok()` colours (copy, wrote, done) |
| Raspberry | `#F06292` | `#B0306A` | The redlines, Over, and the ghost needle left where the input was |
| Amber | `#FFC247` | `#925F00` | carify's `warn()` lines (HDR, no audio). None of the four recorded runs prints one |

Every colour state carries a word: Over and Fits under each readout, Copying and Safe to remove on the USB lamp, Won't play, Plays without sound, Too tall and Already fine on the file buttons, and carify's own labels in the terminal. Only Night glows (the needles).

## Layout

A 1240px wrap. The headline runs across the top in two lines on desktop; under it the explanation on the left and the install box on the right; then the binnacle, full width: dial, screen, dial. On a phone the two dials sit side by side and the screen goes under them. Below the hero each section takes the form its content needs: one large statement for why it exists, a limits table whose "copied if it's" column ends on a Raspberry redline, the four recorded runs as a table, two command sheets, the settings table, and tested-on and known issues side by side.

## Signature

The dials. 240-degree sweeps with the head unit's limit drawn as a redline: 720 on a 0 to 2160 frame-height scale, 2 on a 0 to 8 channel scale. The needle is a short Ember pointer riding the tick ring, so the readout in the hub stays clear, and a Raspberry ghost needle stays where the input was. The wordmark has the same redline under it.

## Wow moment

On load the cluster does the gauge sweep a car does when you switch it on: both needles to full scale and back, settling on road-trip.mkv's values, 1080 and 6, both Over. The command types itself, and then carify's real output from `docs/art/runs.json` prints at the times it was recorded: the probe line, the two re-encode decisions, ffmpeg's progress line redrawing in place while the bar fills, then `wrote`. At that moment the needles drop to 720 and 2, the readouts turn Mint and say Fits, the ghost needles stay at 1080 and 6, and the USB lamp goes from Copying to Safe to remove. The four file buttons replay the other recorded runs; cartoons.mkv moves only the audio needle, dashcam.mp4 moves nothing and finishes in 0.2 s.

- **No JS:** the finished road-trip run, complete, rendered into the HTML by `make-art.py`.
- **Reduced motion:** nothing plays by itself; a file button shows that run finished, at once.
- **Phone:** the same cluster, dials side by side, screen underneath.

## README cluster

`docs/art/make-art.py` draws the same cluster as `assets/cluster-{dark,light}.svg`, with text converted to paths from `fonts/` (an `<img>` can't load fonts). It plays road-trip.mkv and then cartoons.mkv in a loop of about 16 s, using CSS keyframes timed from the recorded events; its base styles are the finished road-trip state, which is what readers with reduced motion see. `make-art.py` also writes `runs.js` for the page and fills the `art:*` markers in `index.html` and `README.md`, so every number on both comes from `runs.json`.

`docs/art/record.py` makes the four test clips with ffmpeg's `testsrc2` and `sine` sources and records carify on each. CI (`.github/workflows/test.yml`, job `art`) records them again on ubuntu-24.04 and fails if carify's output no longer matches (timings and sizes aside), then reruns `make-art.py` and fails if anything it writes differs. `card.html` puts the cluster's still frame under the name for the 1280 × 640 social preview (`assets/social.png`).

Don't wrap the README's `<picture>` in a link: GitHub then shows the light image in dark mode.

## Motion

Needles move on `cubic-bezier(.2,.7,.2,1)` in 0.6 s, the sweep in 0.7 s each way. Text switches at once, as a display would. The progress bar moves linearly between ffmpeg's redraws. Nothing on the page loops except the prompt's cursor; the README loop holds each finished state for over three seconds. Nothing flashes faster than once a second.

## Voice

Plain and exact, as in the README: real commands, carify's output quoted as it prints it, real numbers from the recorded runs, and the limits stated as limits carify works to, not as a published Uconnect spec.

## Files

- `index.html`, `styles.css`, `script.js`, `runs.js` (generated), `fonts/`, and the icons and manifest. The favicon is the dial reduced to one arc, its redline, and an Ember needle in the safe part.
- `art/record.py`, `art/runs.json`, `art/make-art.py`, `art/requirements.txt`.
- `assets/cover-*`, `assets/social-*.png` and `assets/cover.toml` are the RFS brand cover from rfs-brand's `make-cover.py`. The page doesn't use them, but the rfs-brand site's cover gallery loads `cover-{dark,light}.svg` from here, so they stay.

## Alternatives considered

- The head unit's file browser: the MOVIES stick's file list, with "Unsupported file" entries turning playable. More literal, but it would be a mock-up of a screen I can't show truthfully across Uconnect generations.
- A window sticker: each file's streams printed like a new car's spec label, before and after. Warm and readable, but static, and the two numbers that decide everything get lost in a list.
