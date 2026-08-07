# Demo recording

Regenerates the GIFs and the App Store preview in `marketing/demo/`. Everything is captured from the
real app driven through the accessibility API — nothing is mocked, and nothing the app doesn't do is
edited in.

```bash
# 1. build the app the recording runs against
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild build -project Jobhunt.xcodeproj -scheme Jobhunt-DMG -configuration Debug-DMG \
  -destination 'platform=macOS' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Jobhunt-local CODE_SIGNING_ALLOWED=NO

# 2. dry-run FIRST — it asserts every scene actually fired
./scripts/demo/reset.sh
./scripts/demo/configure.sh OpenRouter mistralai/ministral-14b-2512
SCENE_LOG=/tmp/scenes.txt ./scripts/demo/drive.sh

# 3. record (single shell invocation — see "dead air" below)
./scripts/demo/reset.sh
{ ( sleep 1.5; SCENE_LOG=/tmp/scenes.txt ./scripts/demo/drive.sh ) & } \
  && screencapture -v -V 46 -R 55,100,1600,900 /tmp/master.mov

# 4. cut out the real extraction wait, caption, and encode
./scripts/demo/cut.sh /tmp/master.mov marketing/demo
```

## Privacy

The recording runs a **second app instance** with `--ui-test-store --seed-demo-data`, which opens an
isolated temp store. `ModelContainerFactory.freshTestStore()` deletes that store on every launch, so
each run starts from clean demo data and any correction made during a previous take is gone. The
user's real job search is never opened and never appears on screen. The capture region starts at
y=100, below the menu bar, so the menu bar is out of frame too.

## Geometry

Window is sized to **1600x900 points at (55,100)**. `screencapture -R` records that region at 2x on
Retina, giving **3200x1800** — exactly 16:9, so it scales to 1920x1080 with no crop and no
letterboxing. Verify with a 4-second test capture and extract a frame before recording anything real.

## Pitfalls hit while building this

Every one of these produced footage where **nothing happened**, with no error.

**AppleScript / accessibility**

- **`click at {x,y}` does nothing in SwiftUI.** Select via the accessibility tree instead: find the
  row and `set selected of r to true`.
- **Iterate by index, not by reference.** `repeat with e in (UI elements of sa)` yields loop
  references, and geometry lookups on a reference raise `-1700` ("can't make … into type
  specifier"). `repeat with i from 1 to (count …)` + `UI element i of sa` works. This bit twice —
  once on the flag buttons, once on the sheet's buttons.
- **Read geometry as `value of attribute "AXPosition"`, and assign it before subscripting.**
  `position of x` intermittently throws for elements whose `help` reads fine on the same pass, and
  `item 1 of (value of attribute "AXPosition" of x)` as a single expression is rejected — the
  two-statement form is the only reliable one. Both failures land inside a `try` and silently
  produce "found nothing".
- **Poll, don't sleep-and-hope.** After a tab switch the flag buttons exist for a moment with no
  `AXHelp`, so one matcher pass behind a fixed delay finds nothing. The flag lookup retries for ~10s.
- **Re-resolve container references each pass** — a reference captured around app activation goes
  stale and every subsequent access throws.
- **`AXFocused` is not settable on these rows** (`-10006`); set it on the outline, or rely on
  selection.
- **The detail tabs expose neither name nor child text**, so they can only be addressed by index
  (1=Overview, 2=Fit, 3=Timeline, 4=Description, 5=Raw). That order is defined in code, not by data,
  so unlike list rows it can't shift underneath you. **List rows are addressed by their text.**
- **The sheet's buttons have no name either** — Save is simply the right-most one.
- **Re-activate the app before each block**, and give it ~0.6s: activation makes SwiftUI rebuild the
  pane.

**Tooling**

- **This Homebrew ffmpeg has no `drawtext` and no `subtitles`** (no libfreetype/libass). Check with
  `ffmpeg -filters | grep drawtext`. Captions are rendered to PNGs with ImageMagick and composited
  via `overlay=…:enable='between(t,a,b)'`.
- **ImageMagick's default font is unresolved here** ("unable to read font ''"), so `-font` is always
  passed explicitly. Do **not** pass `-interword-spacing` to `label:` — it collapses word spacing.
- **`-t` must come before `-i`.** As an output option it caps output duration, which the sped-up
  stream is already under, so the trim silently does nothing — the first preview came out at 30.6s
  and was rejected by the duration guard in `encode.sh`.
- **Dead air:** the capture and the driver must start from a *single* shell invocation. The gap
  between two tool calls becomes dead footage at the front and a truncated ending.
- **Caption timings come from `SCENE_LOG`**, not from reading the script — AppleScript step durations
  drift between runs. Video time = scene time + the 1.5s capture head start.

## The wait is real, and cut

Extraction and scoring against a real provider take about a minute. `cut.sh` removes that wait and
labels the jump *"about a minute later…"* rather than hiding it — how long it takes depends on the
model the viewer picks, so implying it's instant would misrepresent the product.

## Pick a model that answers the same way twice

Record with a model measured as consistent. At `temperature: 0`, hosted inference still varies:
`deepseek-v4-flash` changed 7 of 15 requirement verdicts between byte-identical calls and moved the
score 10–16 points, which made takes unreproducible. `ministral-14b` changed 2 and moves ~1.5 points.
See `marketing/help/which-model.html`.

## Known limitation filmed as-is

After saving a correction the requirement row moves from **Gaps** to **Requirements met**, but the
headline score ring keeps its old value until the job is reselected. The walkthrough shows the
reselect rather than faking an in-place update. Tracked as a UI-refresh bug.

## App Store preview constraints

1920x1080, **15–30 seconds**, real app footage. `encode.sh` asserts the duration and fails the build
rather than letting App Store Connect reject it. The master runs ~46s and is trimmed to 44.2s then
sped to 1.5x → 29.6s.
