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
and opens the port when you get there, the **fleet badge** opens the roster, the brass
button cycles your shot, and a **BOARD** prompt appears above it whenever you are
alongside a hull whose crew can no longer hold her. Running a hull down damages you both,
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

Assert ships actually carry canvas and that it answers the wind — yards braced sharp when
pointing, squared before the wind, and the cloth bellying downwind of its own yard on every
point of sail. That last one is the assertion no screenshot could replace: a sail bellied
into the wind renders perfectly happily and still looks like a sail:

```bash
godot --headless src/scenes/voyage.tscn -- --rig
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
