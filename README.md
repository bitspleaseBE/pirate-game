# Pirates: Treasure Hunt

A one-thumb naval action game. Sail, fight broadsides, capture islands, dig up gold.
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

Controls: tap water to set a course, tap an enemy to engage (your ship will manoeuvre
to bring a broadside to bear), pinch to zoom, drag to look around, `F3` for the debug
overlay, `Esc` for the menu.

## Development commands

Play a full island loop headless and assert the game actually works. This is what CI
gates on:

```bash
godot --headless src/scenes/voyage.tscn -- --smoke
```

Capture gameplay frames to `user://shots/` — the only reliable way to check art, scale
and z-order:

```bash
godot src/scenes/voyage.tscn -- --shot
```

Regenerate the placeholder sound effects (deterministic; safe to re-run):

```bash
python3 tools/audio/make_placeholder_sfx.py
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
