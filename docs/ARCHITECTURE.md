# Architecture & Performance

The budget: **60 fps on a 2019 mid-range Android phone, inside a browser tab.** That is
roughly a Snapdragon 660 running WebGL2 through Godot's GL Compatibility renderer, with no
threads. Everything below exists to hold that number while 40 ships, 100 cannonballs and a
dozen islands are live.

## 1. Renderer choice

`gl_compatibility` for **every** platform, including native mobile.

Godot's Mobile and Forward+ renderers are Vulkan-only, so they cannot ship to web at all.
Rather than maintain two rendering paths with different shader behaviour and different
bugs, we target WebGL2 / GLES3 everywhere. For a 2D game the Vulkan renderers buy us
nothing we need.

Consequences we accept and design around:
- No `SCREEN_TEXTURE` mip chain, no compute shaders.
- 2D MSAA off; we rely on linear filtering and slightly oversized art instead.
- Maximum texture size assumed 2048 (WebGL2's guaranteed floor is 2048; many devices go
  higher, we do not rely on it).

## 2. Frame budget

| System | Budget @60fps | How it is held |
|---|---|---|
| Ocean | 1 draw call, < 1 ms | One camera-locked shader quad |
| Islands | 1–2 draw calls each | `Polygon2D` with a tiling texture, never a tilemap |
| Ships | ≤ 40 alive, ≤ 25 visible | Culling manager disables off-screen ships entirely |
| Projectiles | ≤ 150 alive | Pooled, no physics bodies, single-loop integration |
| Particles | scales with device tier | `QualityManager` multiplies every emitter's amount |
| UI | < 1 ms | Minimap draws from island polygons via `_draw()` |

## 3. Culling & activation

This is the core of the "don't die on slow devices" story. Three layers:

### 3.1 SpatialGrid (`src/core/spatial_grid.gd`)

A uniform hash grid over world space, cell size 512 px. Every gameplay entity registers
itself. It answers two questions cheaply:

- `query_rect(rect)` — what is in / near the camera? Used by the culling manager.
- `query_radius(pos, r)` — what did this cannonball hit? Used instead of physics queries.

One data structure serves both, so the cost is paid once.

### 3.2 CullingManager (`src/autoload/culling_manager.gd`)

Runs on a **staggered timer, not every frame** (default 6 Hz — culling state does not need
frame accuracy). Each tick it:

1. Computes the camera's world rect, inflated by a margin (default 30% of the viewport).
2. Queries the grid for entities inside it.
3. For entities that left the rect: `visible = false` and
   `process_mode = PROCESS_MODE_DISABLED`.
4. For entities that entered: re-enable, and give them a `_on_activated()` call so they can
   catch up on however much simulated time they missed.

Point 4 is the part that is usually done wrong. A disabled ship must not teleport when it
comes back on screen, so off-screen entities are still advanced — by a cheap
**low-frequency simulation** (see 3.4), not by their full `_process`.

`VisibleOnScreenEnabler2D` is used only for pure decoration (props, palm sway) where being
frame-exact and simulation-free is fine. It is not used for anything with gameplay state,
because its rect test does not respect our margin or our LOD tiers.

### 3.3 LOD tiers

Every cullable entity resolves to one of four tiers each culling tick, based on distance
from the camera centre and on the current quality level:

| Tier | Condition | Behaviour |
|---|---|---|
| `FULL` | On screen, near | Full `_process`, particles, wake, animated flag, health pips |
| `REDUCED` | On screen, far / off-screen but close | No particles, no wake, no per-frame animation; physics at half rate |
| `SIMULATED` | Off screen | Node disabled; position advanced by the low-frequency simulator |
| `DORMANT` | Off screen and far, or in an un-alerted island group | Nothing runs at all |

The tier is exposed as a signal so entities opt into their own degradation rather than the
manager reaching into their internals.

### 3.4 Low-frequency simulation

Off-screen ships are stepped at 4 Hz by `CullingManager` with a reduced model: move toward
their nav target, no steering behaviours, no collision, no shooting. That keeps the world
coherent (a fleeing enemy actually gets away) at roughly 1/200th the cost of running it
properly.

## 4. Projectiles without physics

Cannonballs are the highest-count entity in the game and the easiest to get wrong.

- No `RigidBody2D`, no `Area2D`, no `PhysicsBody2D`. Zero physics-server involvement.
- All live projectiles are owned by one `ProjectileSystem` node and integrated in a single
  `_physics_process` loop — one function call per frame instead of 150.
- Ballistic arc is analytic: launch position, target position, flight time, and a parabolic
  height offset. Altitude drives the sprite's `offset` and its shadow's scale. No gravity
  integration, no drift, and the impact point is known at launch — which also means the AI
  can lead a target correctly and telegraphs can be drawn accurately.
- Hit detection is a `SpatialGrid.query_radius` at the impact point on the frame the
  projectile lands, plus an optional mid-flight proximity check for ram/fireship cases.
- Sprites come from `PoolManager`; the arrays are reused, never reallocated.

## 5. Object pooling

`src/core/object_pool.gd` + the `Pools` autoload.

Pooled: cannonballs, splashes, impacts, explosions, smoke, muzzle flashes, floating damage
numbers, loot pickups, wake segments.

Rules:
- Pools pre-warm at scene load, sized from the current quality tier.
- Pooled scenes implement `_pool_reset()` and `_pool_release()`; the pool never assumes it
  can just `queue_free()`.
- Pools grow past their initial size but log a warning, so an undersized pool shows up in
  development instead of silently allocating during a fight.
- Nothing in gameplay calls `instantiate()` or `queue_free()` per-frame. That is the rule
  that keeps the web build off the GC.

## 6. QualityManager

Two jobs: pick a starting tier, then adapt.

**Detection** — platform (`OS.has_feature("web")`, `OS.get_name()`), renderer name, screen
DPI and resolution, and `OS.get_processor_count()` produce an initial guess of `LOW`,
`MEDIUM` or `HIGH`.

**Adaptation** — a rolling 2-second average of frame time. Two consecutive seconds under
the floor drops a tier; thirty seconds comfortably above it may raise one (with hysteresis,
so it cannot oscillate). Manual override in settings always wins.

What a tier controls:

| Knob | LOW | MEDIUM | HIGH |
|---|---|---|---|
| Render scale | 0.7 | 0.85 | 1.0 |
| Particle multiplier | 0.25 | 0.6 | 1.0 |
| Max visible ships | 12 | 20 | 32 |
| Max live projectiles | 60 | 100 | 160 |
| Ocean shader | 2 wave octaves, no caustics | 3 octaves | 4 octaves + caustics + shore foam |
| Wake trails | off | selected ship only | all ships |
| Shadows (blob sprites) | off | ships only | everything |
| Cull margin | 10% | 20% | 35% |
| Damage numbers | off | on | on |

Render scale is applied via `get_viewport().scaling_3d_scale`'s 2D equivalent — for 2D we
resize the root `SubViewport` and let the stretch mode upscale, which is the only way to
get real fill-rate savings in GL Compatibility.

## 7. Ocean

One `ColorRect` parented to the camera, sized to the viewport plus a margin, with a shader
that reconstructs **world-space UVs** from the camera's world offset (passed as a uniform).

The result: the entire ocean, at any world size, is a single draw call whose cost is
exactly one screen of fragments. A tilemap ocean would have been thousands of quads and a
streaming problem for nothing.

Wave motion, depth colouring near shore, caustics and shore foam are all in that one
shader, gated by a quality uniform.

## 8. Islands

Islands are **polygons, not tilemaps**:

- `Polygon2D` with a seamless fill texture and UV scaling → 1 draw call per biome band.
- `Line2D` along the same points for the shore-foam edge.
- `StaticBody2D` + `CollisionPolygon2D` from the same points for collision.
- The **same point array** feeds the minimap, so the treasure map is guaranteed to match
  the world and costs one `_draw()` call.

Props on the island are children of a `VisibleOnScreenEnabler2D`-gated container and
Y-sorted only within that container.

This is why the asset list needs seamless fills and edge brushes rather than a 47-piece
autotile set — a large art saving that falls straight out of the rendering choice.

## 9. Scene & code layout

```
project.godot
export_presets.cfg
assets/            imported art, audio, fonts (placeholder/ holds Kenney stand-ins)
assets_src/        SVG / project sources, never exported
docs/
src/
  autoload/        EventBus, Quality, Pools, Grid, Cull, Audio, GameState, Save, Router
  core/            spatial_grid, object_pool, math helpers, debug overlay
  data/            Resource definitions: ShipStats, AmmoType, UpgradeDef, LootTable, IslandDef
  entities/
    ships/         ship base + player/enemy controllers + AI states
    projectiles/   projectile_system, projectile visuals
    structures/    fort cannon, shipyard, castle
    crew/          landing party
  world/           ocean, island, port, archipelago generator, spawn director
  ui/              hud, minimap, port, menus
  scenes/          boot, main_menu, voyage
tests/             GUT tests for grid, pool, quality, ballistics
tools/             asset packing + atlas scripts
.github/workflows/ CI + Pages deploy
```

## 10. Data-driven content

Ship stats, ammo types, upgrades, loot tables and island definitions are `Resource`
subclasses with `@export`ed fields, designed to be authored as `.tres` files under
`assets/data/`. Keeping tuning out of code keeps it out of the diff noise and makes a
future remote-config or A/B test trivial.

**Current state:** the `.tres` files are not written yet. `AmmoLibrary` and
`ShipStatsLibrary` load from disk if a resource exists and otherwise fall back to a code
table, and today every lookup takes the fallback — so **the code tables are the balance**,
and that is where to change a number.

The precedence is one-way on purpose (`.tres` always wins), so the migration is a matter
of authoring files one at a time rather than a flag day. Two live sources of truth would
be worse than one temporary one in the wrong place: the moment a `.tres` exists for a
type, edits to its code table stop having any effect, which is exactly the kind of silent
no-op that wastes an afternoon.

## 11. Input

`InputRouter` is the single place that turns pointer events into intents:

`InputEventScreenTouch` / `InputEventMouseButton` → hit test through `SpatialGrid` →
emit `intent_move(pos)`, `intent_target(entity)`, `intent_select(ship)`, `intent_open_port(island)`.

Nothing else in the game reads raw input. That is what makes it possible to add a virtual
joystick, gamepad support or a replay system later without touching gameplay code.

## 12. Web deployment

Deployed to GitHub Pages from `.github/workflows/deploy-pages.yml`.

**The critical constraint:** GitHub Pages cannot set the `Cross-Origin-Opener-Policy` and
`Cross-Origin-Embedder-Policy` response headers that `SharedArrayBuffer` requires. So the
web export **must** have thread support disabled (`variant/thread_support=false`). A
threaded Godot web build simply will not boot on Pages.

Also set for web:
- `gzip` precompression is skipped — Pages serves its own compression.
- `.nojekyll` at the site root, or Pages will eat files beginning with an underscore.
- Extensions filter kept tight, and `html/experimental_virtual_keyboard=false`.
- Audio uses `AudioStreamPlayer` with a low mix rate on web to avoid crackle in Safari.

Because the site lives at `/pirate-game/`, all paths in the shell stay relative — Godot's
default shell already does this; do not hardcode absolute paths in any custom HTML head.

## 13. Testing & profiling

- `tests/` uses GUT for the pure-logic pieces: grid queries, pool lifecycle, ballistic
  solver, loot roll distribution, save round-trip.
- `F3` toggles a debug overlay: fps, frame time, draw calls, live/visible entity counts per
  type, pool high-water marks, current quality tier and why it was chosen.
- `--headless` smoke test in CI loads every scene and asserts no script errors, so a broken
  scene cannot reach Pages.
