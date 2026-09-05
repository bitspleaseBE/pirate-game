# Pirates: Treasure Hunt

A one-thumb naval action game. Sail, fight broadsides, capture islands, take the gold off
their quays.
Godot 4.7, targeting mobile web first.

**Play:** https://bitspleasebe.github.io/pirate-game/ (deployed from `main`)

## Docs

| | |
|---|---|
| [GAME_DESIGN.md](docs/GAME_DESIGN.md) | What the game is — loop, combat, progression |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | How it holds 60 fps in a phone browser |
| [ASSETS.md](docs/ASSETS.md) | Every asset needed, with specs |
| [ART_BIBLE.md](docs/ART_BIBLE.md) | Visual language for generated art |
| [ASSET_PRODUCTION_WAVES.md](docs/ASSET_PRODUCTION_WAVES.md) | Asset production plan |

## Running it

Needs Godot **4.7.1**. Open the project, or:

```bash
godot src/scenes/voyage.tscn
```

Controls: tap an enemy to **mark** it — your guns then fire on their own the instant she
enters a broadside arc. Tap water to **steer**; that keeps the target marked, so sailing
and shooting are the same activity and working the ship onto a good angle is the whole
skill. Tap the marked enemy again to break off. Pinch to zoom, drag to look around, `F3`
for the debug overlay, `Esc` for the menu. Bottom right: **Hideout** sets a course home
and opens the port when you get there, the **fleet badge** opens the roster, the **shot
rack** is one button per shot type with the loaded one lit and the rest showing what you
have left, and a **BOARD** prompt appears above it whenever you are alongside a hull whose
crew can no longer hold her. Running a hull down damages you both,
scaled by tonnage — worth doing in a Galleon, suicide in a Dinghy.

Two things reward sailing well rather than shooting often: shot loses weight at long
range, so close; and a ball that arrives along a hull's bow-to-stern axis **rakes** her
for over double damage, so crossing an enemy's stern is worth the manoeuvre. The gauges
on either beam of your ship fill as that battery reloads and light up when it bears.

## Development commands

Play a full island loop headless and assert the game actually works. This is what CI
gates on:

```bash
godot --headless src/scenes/voyage.tscn -- --smoke
```

Measure how *busy* a fight is, which is the thing no other harness could see. `--smoke`
sails at the deliberately gentle opening island and asserts that combat happened; for a
long time what happened was three shots in eighty seconds, and it passed every time. This
puts a mid-game hull in front of a mid-game island and counts shots, hits, rakes, kills
and damage taken per minute, with a floor under the shot rate:

```bash
godot --headless src/scenes/voyage.tscn -- --arena
```

Assert the objective of a voyage is actually the hardest thing in it — four batteries, an
armoured keep, and a keep that cannot be hurt while a battery still stands. The castle
shipped for months as the *least* defended island on the map and nothing noticed, because
nothing ever asked what was on it. (Run with a display and it also frames the keep.)

```bash
godot --headless src/scenes/voyage.tscn -- --castle
```

Play the opening of the game the way a new player does — the starting Dinghy, islands one
to five in order, spending only what the run actually earns — and report whether it can be
survived. Every other harness asks "does this work"; this one asks "is the start of the
game fair", which is a different question and the one that was going unasked. `--smoke`
stops after the gentle first island and `--arena` starts from a mid-game Brig with gold in
the bank, so nothing had ever played the ramp itself. It had a wall in it: the opening
chest paid 154 gold against a 260-gold hull, so island two — a Navy Sloop against a Dinghy
— was a fight the arithmetic said you lose:

```bash
godot --headless src/scenes/voyage.tscn -- --ladder
godot --headless src/scenes/voyage.tscn -- --ladder --seed=22   # sweep other worlds
```

It pins its own seed, because the swing between two archipelagos is wider than most
changes worth measuring — the same build finished island two on 74% of its hull and was
wiped on it, on consecutive runs. Deliberately **not** a CI gate, for the same reason
`--arena` is not: the tier-3 islands still sink it on some seeds, and a gate that fails a
third of the time gets ignored rather than fixed.

Assert ships actually carry canvas and that it answers the wind — yards braced sharp when
pointing, squared before the wind, and the cloth bellying downwind of its own yard on every
point of sail. That last one is the assertion no screenshot could replace: a sail bellied
into the wind renders perfectly happily and still looks like a sail:

```bash
godot --headless src/scenes/voyage.tscn -- --rig
```

Assert a ship under canvas sails rather than drives — that her track lies to *leeward* of
her heading, that the crab vanishes running dead before the wind and flips when she comes
about, and that an oared hull makes none of it. Same reasoning as the rig check, one layer
down: a hull crabbing the wrong way is still visibly not going where it points, the wake
still streams off a quarter, and every screenshot of it is convincing. It is only wrong if
you know where the wind is:

```bash
godot --headless src/scenes/voyage.tscn -- --sailing
```

Measure what tapping the water actually gets you: how far past the mark she coasts, how
long from a course order to being on it, how long the player's order survives before the
engagement assist takes the helm back, and whether a course to an island's harbour gets
there. Every other gate asks whether a system *works* — `--smoke` proves a ship reaches an
island and `--touch` proves the tap reaches the router, and between them the helm could be
arriving three ship-lengths past your finger and both would pass:

```bash
godot --headless src/scenes/voyage.tscn -- --helm
```

Assert that a captured island can be taken back. Three design rules rather than three
correctness ones: an ignored reprisal costs the island, a fought one saves it, and the
jungle tribes never campaign — which is what keeps the opening islands safe to leave. The
middle one is the one that would rot quietly, because a raid that *cannot* be beaten looks
exactly like one that has not been beaten yet:

```bash
godot --headless src/scenes/voyage.tscn -- --reprisal
```

Assert every sound cue has a file behind it and the music actually reacts to the game.
Audio is the one subsystem whose entire failure mode is silence — a missing file is
skipped at boot with one warning and then plays nothing, forever, with no error at any
call site — so a cue with a wrong path is indistinguishable from one nobody has triggered:

```bash
godot --headless src/scenes/voyage.tscn -- --audio
```

Assert a beaten ship that gets clear stops counting as a defender. Two full arena runs
produced zero routs — a competent hull kills a runner long before it reaches open water —
so this path never executes in ordinary play and would sit there rotting. If it broke, the
symptom would be an island that refuses to be captured while a ship the player cannot see
sails away from it forever:

```bash
godot --headless src/scenes/voyage.tscn -- --rout
```

Check that ramming costs both hulls, and costs the smaller one more. The risk is not that
it breaks but that it quietly does nothing, which is the state hull collisions shipped in
for months:

```bash
godot --headless src/scenes/voyage.tscn -- --ram
```

Prove the two enemies that are not gun duels still do their one thing — a fireship has to
close and detonate, a bomb ketch has to telegraph *before* it fires. Both fail silently:
the ships still spawn and still get shot at, so nothing else here would notice:

```bash
godot --headless src/scenes/voyage.tscn -- --doctrine
```

Drive a boarding end to end in both the outcomes it has — kept when a berth is free,
stripped for cargo when not — through the same prompt the player presses:

```bash
godot --headless src/scenes/voyage.tscn -- --board
```

Tap the sea with a synthesised finger and assert the helm answers. Tap-to-sail is the only
control the game has and it was **dead on every touchscreen** while working perfectly under
a mouse: Godot's `emulate_mouse_from_touch` delivers an emulated click alongside every real
touch, two pointers at once is this router's definition of a pinch, and so every tap on a
phone was filed as a two-finger zoom of zero magnitude. Nothing in the harness could see
it, because every other run drives `EventBus` directly — downstream of the entire pointer
path — and a screenshot of a ship that was never ordered anywhere looks exactly like a
screenshot of one that was. This drives a tap, a click, a drag and a pinch in through
`Input.parse_input_event`, so the engine's own emulation is part of what is under test:

```bash
godot --headless src/scenes/voyage.tscn -- --touch
godot --resolution 390x844 src/scenes/voyage.tscn -- --touch   # and on a phone-shaped one
```

Capture gameplay frames to `user://shots/` — the only reliable way to check art, scale
and z-order:

```bash
godot src/scenes/voyage.tscn -- --shot
```

Frame an actual engagement instead. The plain `--shot` run mostly photographs open water,
so none of its frames reliably contains a marked target — which means none of them shows
the firing arcs, the reload gauges inside them, a mortar's telegraph ring or a boarding.
Those are unreadable-or-fine rather than working-or-broken, and only a rendered frame can
tell the difference:

```bash
godot src/scenes/voyage.tscn -- --shot-combat
```

Frame each island's harbour instead — hostile, held, and unloading — which is the only way
to tell whether the port reads as a port at gameplay zoom:

```bash
godot src/scenes/voyage.tscn -- --shot-harbour
```

Frame the title screen in both the states it ships in — no save to continue, and one
waiting — which is the only way to check the three buttons are still told apart at a
glance:

```bash
godot src/scenes/main_menu.tscn -- --shot-menu
```

Add `--sail` to either flag to start in a Sloop instead of the oared Dinghy, which is the
only way to exercise the wind, the wake and the compass ring without first playing through
the opening islands:

```bash
godot src/scenes/voyage.tscn -- --shot --sail
```

Frame the fleet roster with all three card states in it — a knocked-about flagship, a
healthy escort, and a berth whose hull is still at the yard. Reaching a three-ship fleet in
play costs a diamond and most of a voyage, so the harness builds one:

```bash
godot src/scenes/voyage.tscn -- --shot-fleet
```

Frame the HUD and every modal at real phone viewports, in both orientations and on a
tablet. The game is played on a phone and developed in a 1280x720 desktop window, and every
other capture runs at the latter — so the layout that most needed looking at was the one
nothing had ever photographed. The window is resized between passes, because the point is
to compare the same four screens across three shapes:

```bash
godot src/scenes/voyage.tscn -- --shot-mobile
```

The sizes are CSS pixels, which is what the interface is laid out in — a phone reporting a
3x device pixel ratio has three times as many real ones, and the UI scale cancels that out,
so `390x844` here is a 1170x2532 iPhone. Any screen can be framed directly with Godot's own
flag, which is how the title screen gets the same treatment:

```bash
godot --resolution 390x844 src/scenes/main_menu.tscn -- --shot-menu
```

Sail the fleet home from offshore and assert the hideout actually opens when it arrives.
The Hideout button only sets a course; everything that makes going home worth doing happens
on arrival, so a course that quietly fails looks exactly like a dead button:

```bash
godot --headless src/scenes/voyage.tscn -- --hideout
```

Regenerate the placeholder sound effects (deterministic; safe to re-run — each cue is
seeded from its own name, so adding one cannot change any of the others):

```bash
python3 tools/audio/make_placeholder_sfx.py
```

Regenerate the placeholder music stems and the sea ambience. The three stems are one piece
of music in one key and tempo, the same length to the sample, and the script refuses to
finish if they ever differ — drift would not error, it would slowly turn a chord into a
cluster over the course of a voyage:

```bash
python3 tools/audio/make_placeholder_music.py
```

Recut the sailcloth swatch the drawn rig wears. The sail is a shape drawn in code, but a
flat polygon on a hull that is a rendered, weathered 3D asset reads as a placeholder on
finished art — so it wears a patch of real canvas lifted out of the sail master, which is
useless as a sprite here but whose cloth is as good from above as from abeam:

```bash
python3 tools/assets/make_sail_linen.py
```

Rebuild the Wave 0 art from its masters:

```bash
godot --headless --path tools/assets --script render_assets.gd
```

Export a web build locally:

```bash
godot --headless --export-release "Web" dist/web/index.html
```

## Layout

```
assets/          imported art, audio, fonts (wave0/ is current, placeholder/ is Kenney)
assets_src/      art masters and sources — never exported
docs/
src/
  autoload/      EventBus, Quality, Pools, Grid, Cull, Audio, GameState, Save, Router
  core/          spatial grid, object pool, input router, debug overlay
  data/          Resource definitions and their libraries
  entities/      ships, projectiles, effects
  world/         ocean, islands, archipelago generator, spawn director, camera
  ui/            HUD, minimap, world overlay
  scenes/        boot, main menu, voyage
tools/           asset and audio generation
inspiration/     Kenney CC0 reference packs (.gdignore'd — not imported or shipped)
```

## Things worth knowing before you change something

- **The renderer is `gl_compatibility` everywhere**, including native mobile. Vulkan
  cannot ship to web, and one rendering path beats two.
- **The web export must stay single-threaded.** GitHub Pages cannot send the COOP/COEP
  headers `SharedArrayBuffer` needs. CI fails the build if that flips.
- **Nothing in gameplay calls `instantiate()` or `queue_free()` per frame.** Use `Pools`.
- **Projectiles are not physics bodies.** One system integrates them all; hits resolve
  through the spatial grid.
- **Balance lives in `src/data/*_library.gd` fallbacks** until the `.tres` files land.
