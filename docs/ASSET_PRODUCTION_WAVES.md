# Asset Production Waves and Cost Checkpoints

> Wave 0 revision 2 completed on 2026-08-01 in Painterly Tactical Realism. Actual v2 usage:
> 13 new-image calls, 0 edit calls, and 20 deterministic catalog outputs. Revision 1 used 6
> additional new-image calls and is archived as a rejected cost record. Wave 1 remains gated on
> visual approval of the v2 contact sheet and gameplay proof. Wave 1 static art was generated on
> 2026-08-02 with 8 approved new-image calls and 75 deterministic catalog outputs; ocean/beach
> upgrades and Batch 1F audio were intentionally excluded. The static-art review gate remains open.

This document turns [ASSETS.md](ASSETS.md) into a production schedule that can be run
over multiple occasions. Each batch is deliberately small enough to stop, inspect the
result, check actual cost, and decide whether to continue.

The goal is not to generate every sprite independently. Important objects have one
canonical source of truth, and most variants are deterministic exports or overlays.
This is what keeps a sloop, character, structure, or icon visually identical across
states.

## 1. Production rules

1. **One canonical master per identity.** A ship hull, character direction, structure,
   or UI component is approved once. Variants must derive from that master.
2. **Generated concepts are not automatically production assets.** Concepts establish
   silhouettes and style. Approved concepts are reconstructed or cleaned as layered
   SVGs, rigs, masks, or seamless textures.
3. **Never generate animation frames independently.** Pose or transform the same
   layered source, or edit one locked source while preserving its geometry.
4. **One batch per working occasion by default.** A batch ends at its cost checkpoint.
   Starting the next batch is a separate decision.
5. **Do not pack atlases until loose assets pass review.** Repacking during exploration
   creates noise and makes comparison harder.
6. **Review at gameplay scale.** Every batch must be checked at nominal size and at
   approximately 40 px on a 1280 x 720 phone-scale gameplay capture.
7. **Keep rejected generations.** Store them outside the shipping asset tree until the
   wave is approved. They are useful evidence when judging iteration cost.

## 2. Cost accounting

Prices vary by model, quality, image size, audio duration, and provider. This plan tracks
work units rather than embedding a price that will become stale.

| Code | Cost unit | What counts |
|---|---|---|
| `G` | New generation | A new concept, texture, portrait, VFX source, or key-art generation call |
| `E` | Edit/variation | A targeted edit using an approved image as the locked input |
| `V` | Vector construction | Creating or cleaning a canonical SVG; primarily time cost |
| `R` | Deterministic render | Exporting PNGs, masks, frames, or sizes from an approved source |
| `P` | Post-processing | Chroma removal, seam fixing, palette cleanup, downsampling, or alpha cleanup |
| `A` | Audio generation | One generated SFX variation, stem, loop, or musical cue |
| `H` | Human review | An approval checkpoint; no production work continues without it |

Record actual cost after every batch. If the service reports only a combined amount,
record that amount under `actual service cost` and leave the unit prices blank.

```text
estimated image cost = (G x current generation price) + (E x current edit price)
estimated audio cost = A x current per-file or per-second price
total batch cost = service cost + paid tooling/licensing + external artist cost
```

### Batch cost record

Copy this block into the cost log for each completed batch:

```yaml
batch: 0A
date:
operator:
model_or_tool:
quality_and_size:
new_generations_G: 0
edits_E: 0
vector_hours_V: 0
deterministic_renders_R: 0
postprocess_hours_P: 0
audio_outputs_A: 0
approved_assets: 0
rejected_outputs: 0
actual_service_cost:
other_cost:
notes:
decision: continue | revise | pause | cancel
```

Maintain the running log at `docs/ASSET_COST_LOG.md` once production begins. Do not
estimate later waves from the number of final PNG files: a character sheet may contain
dozens of frames but should derive from only three directional masters.

## 3. Cost controls and stop conditions

Before starting a batch, set two limits:

- **Call cap:** maximum `G + E` calls for that occasion.
- **Money cap:** maximum actual service spend for that occasion.

Stop the batch when either limit is reached. Also stop when any of these happens:

- Two consecutive edits make the approved identity less consistent.
- The silhouette does not read at gameplay scale.
- The output cannot be cleanly separated into the required layers or masks.
- More than half the generated candidates are rejected for the same reason.
- A requested variant would require redrawing rather than deriving from its master.

At a stop, record the result and change the source specification or prompt before buying
more generations.

## 4. Source-of-truth hierarchy

Use this order of authority:

1. `docs/ART_BIBLE.md` — global style, palette, line, shading, camera, and materials.
2. `assets_src/catalog.json` — size, pivot, orientation, source path, and dependencies.
3. Canonical master — high-resolution raster, SVG, layered rig, grayscale mask, or seamless
   source texture.
4. Derived loose PNGs — deterministic exports used for inspection.
5. Atlases — packed shipping artifacts generated from approved loose PNGs.

An atlas is never a source file. A derived PNG is never edited directly unless the
change is transferred back to its canonical master.

## 5. Overview

| Wave | Purpose | Approximate final scope | Primary approval question |
|---|---|---:|---|
| 0 | Prove the visual language and pipeline | 12 reference assets + tooling | Is this unmistakably our game, and can it be reproduced? |
| 1 | Build the playable vertical slice | About 45 art assets plus a small audio set | Is one complete fight readable and attractive on a phone? |
| 2 | Complete the normal island loop | Remaining ships, landing party, port, economy, icons | Can the full approach-fight-land-dig-loot-port loop ship? |
| 3 | Add boss content and polish | Castle, special enemies, remaining VFX, biomes, music | Does the game sustain variety without breaking coherence? |
| 4 | Prepare release presentation | Store art, final variations, audio polish, screenshots | Is every player-facing surface release quality? |

The call ranges below are planning ceilings, not targets. Reusing approved sources should
often bring the actual count below the range.

### Initial call forecast

This roll-up lets a current price sheet be applied before starting a wave. It excludes
the playtest-driven Batch 4A and the still-unknown number of remaining SFX in Batch 3F.

| Wave | New image calls `G` | Image edit calls `E` | Explicit audio outputs `A` |
|---|---:|---:|---:|
| 0 | 9-17 | 4-11 | 0 |
| 1 | 12-29 | 11-31 | 18-22 |
| 2 | 23-47 | 18-45 | 25-35 |
| 3 | 33-59 | 30-62 | Remaining SFX + 8 music deliverables |
| 4, excluding 4A | 4-11 | 6-16 | As discovered in playtesting |
| **Image subtotal** | **81-163** | **69-165** | — |

The upper end assumes several rejected candidates and targeted revisions. The lower end
assumes the approved style transfers cleanly between families. Calculate a provisional
budget with both ends before every wave, but authorize only one batch at a time.

`V` and `P` ranges later in this document are expected work-hours. `R` is a count of
local deterministic render/export jobs and normally has no per-call generation charge.

---

## Wave 0 — Style and pipeline proof

Wave 0 prevents the expensive mistake of producing hundreds of assets before the game
has an approved visual identity.

### Batch 0A — Art-direction candidates

**Deliverables**

- Three compact style boards, each showing the same subjects: sloop, skiff, palm, rock,
  sand/shore, cannonball impact, parchment panel, and cannon icon.
- All boards use top-down orthographic composition, plausible construction, natural materials,
  selective dark edges, restrained painterly texture, and the sea palette from `ASSETS.md`.
- A comparison sheet at nominal size and at 40 px reading size.

**Method**

- Generate whole style boards for comparison, not isolated production sprites.
- Do not mix features from different boards during the first review.
- Choose one board or explicitly describe a controlled combination for one revision.

**Planning ceiling:** `3-5 G`, `0-2 E`, `1 H`. **Actual v2:** `3 G`, `0 E`.

**Checkpoint 0A:** Pick one visual language. If none is strong enough, revise the art
brief once before generating more candidates.

### Batch 0B — Canonical sloop proof

**Deliverables**

- `hull_sloop` canonical layered source.
- `sail_med`, one `cannon_mount`, and `flag_wave` attachment proof.
- Grayscale hull, sail, and accent masks.
- Three shader recolors made from the same source.
- Bow-up orientation, center-of-mass pivot, and attachment metadata.
- A rotation/contact sheet showing the exact same ship at 0, 45, 90, 135, and 180
  degrees; these are engine rotations, not regenerated views.

**Method**

- Generate a small number of sloop silhouette candidates using the selected style board
  as reference.
- Approve one candidate and construct one layered canonical master.
- Render every proof from the same master.

**Planning ceiling:** `2-4 G`, `2-4 E`, `1 V`, `8-12 R`, `1 H`. **Actual v2:** `4 G`,
`0 E`; hull, sail, skiff, and cannon were approved as high-resolution canonical masters.

**Checkpoint 0B:** The sloop must remain pixel-identical except for approved overlays,
recoloring, and rotation. Do not continue if a variant required a newly generated hull.

### Batch 0C — Cross-family consistency proof

**Deliverables**

- `hull_skiff` canonical source.
- One palm, one rock, one parchment panel, and one cannon icon.
- `fill_sand` and a temporary shore edge.
- `fx_muzzleflash` four-frame proof.
- A simple composed battle mockup containing both ships and all supporting assets.

**Planning ceiling:** `4-8 G`, `2-5 E`, `4-6 V`, `15-25 R`, `1 H`. **Actual v2:** `6 G`,
`0 E`; palm, rock, parchment, sand, shore, and muzzle source were approved.

**Checkpoint 0C — style lock:** Approve the art bible before Wave 1. Changes after this
point must be corrections, not a new visual direction.

### Batch 0D — Asset tooling

**Deliverables**

- `assets_src/catalog.json` schema and initial entries.
- Deterministic raster/SVG-to-PNG renderer at 2x nominal resolution.
- Alpha, padding, dimensions, filename, and pivot validator.
- Contact-sheet generator.
- Loose-output directories for `ships`, `vfx`, `terrain`, `props`, `chars`, `ui`,
  `icons`, and `map`.
- Initial Godot import presets for lossless straight-alpha textures.

**Planning ceiling:** `0 G`, `0 E`; engineering time only.

**Checkpoint 0D:** Rebuild all Wave 0 PNGs from clean sources. A second build should be
byte-identical unless tool metadata prevents it, in which case pixel output must be
identical.

### Wave 0 gate

Proceed only when:

- The art bible is approved.
- Sloop recolors and attachments use one unchanged hull.
- Assets read at 40 px.
- The clean build and validator pass.
- Actual cost per approved canonical asset is understood.

Use the measured Wave 0 cost to revise the call caps for later waves.

---

## Wave 1 — Playable vertical slice

Wave 1 produces one representative encounter: sloop versus skiffs near a capturable
island, with cannon combat, treasure, map feedback, and basic HUD.

### Batch 1A — Core ship composition

**Assets**

- Final `hull_sloop` and `hull_skiff`.
- `sail_med`, sails-up state.
- `flag_wave`, two frames.
- Short or medium `cannon_mount` selected for the slice.
- `wake_strip` and four-frame `wake_foam`.
- Ship shadow treatment if enabled at the target quality level.

**Method**

- Refine only the Wave 0 masters.
- Animate the flag by deforming its fixed outline around a locked mast attachment.
- Derive wakes from one approved wake language; do not attach baked wakes to hulls.

**Planning ceiling:** `0-3 G`, `1-4 E`, `2-4 V`, `15-25 R`, `1 H`.

**Checkpoint 1A:** Test two recolored sloops and eight skiffs simultaneously. Confirm
silhouettes, faction readability, pivots, sorting, and rotation.

### Batch 1B — Ocean and island foundation

**Assets**

- `water_flow_tile`
- `water_detail_tile`
- `water_caustic_tile`
- `ramp_water_depth`
- `ramp_foam`
- `shore_foam_strip`
- `fill_sand`
- `fill_grass`
- `edge_shore`
- Two palms and two rocks

**Method**

- Generate or author textures at source resolution, then make seams deterministic.
- Ramps are authored numerically, not generated.
- Palm and rock variants derive from approved family rules but may have separate
  silhouettes.

**Planning ceiling:** `4-8 G`, `2-6 E`, `4-8 V/P`, `10-18 R`, `1 H`.

**Checkpoint 1B:** Run a tiling stress test at 4x4 repetitions, inspect visible seams,
and verify that ships remain more visually important than terrain.

### Batch 1C — Cannon combat and VFX

**Assets**

- `ball_round`
- `ball_shadow`
- `fx_muzzleflash`, four frames, firing along +X
- `fx_splash_small`, six frames
- `fx_impact_wood`, five frames
- `fx_explosion`, eight frames

**Method**

- Generate one motion concept per effect when useful.
- Build each sequence from one approved effect identity using scaling, masks, particle
  pieces, and controlled edits.
- Validate frame-to-frame centroid and alpha bounds to prevent visible jumping.

**Planning ceiling:** `4-8 G`, `4-10 E`, `20-30 R/P`, `1 H`.

**Checkpoint 1C:** Inspect every effect in motion over light sand, dark water, and a ship.
The effect must read without obscuring the target for longer than intended.

### Batch 1D — Treasure and interaction feedback

**Assets**

- `treasure_mound`
- `x_marks_spot`
- `chest_closed`
- `chest_open`
- `coin_spin`, six frames
- `reticle_target`, four frames
- `marker_waypoint`, four frames
- `ring_selection`, four frames

**Planning ceiling:** `3-6 G`, `3-8 E`, `6-10 V`, `20-30 R`, `1 H`.

**Checkpoint 1D:** Confirm that treasure, targeting, movement, and selection remain
distinct when viewed together and under faction recoloring.

### Batch 1E — HUD, map, and core icons

**Assets**

- `panel_parchment`
- One rectangular `button_brass` with up, down, and disabled states
- `bar_frame` and the four required `bar_fill` tints
- `map_parchment`
- `map_x`
- Player `map_ship_icon`
- Approximately twelve core icons: `gold`, `chest`, `hull`, `sail`, `cannon`, `anchor`,
  `wheel`, `shot_round`, `fire`, `repair`, `map`, and `settings`

**Method**

- Construct UI and icons as SVG using shared stroke, corner, highlight, and grid tokens.
- Button states derive from one component; icon families share a 64 px, 4 px grid.
- Do not use image generation for every icon.

**Planning ceiling:** `1-4 G` for family exploration only, `1-3 E`, `18-24 V`,
`25-40 R`, `1 H`.

**Checkpoint 1E:** Check icons at 64, 32, and 24 px. Check the HUD with long numbers,
empty bars, full bars, and disabled controls.

### Batch 1F — Core sound pack

**Suggested sounds**

- Cannon fire, four variations
- Wood impact, three variations
- Small splash, three variations
- Explosion, two variations
- Bow wake loop
- Ocean ambience loop
- UI tap, confirm, cancel
- Coin pickup, two variations
- Island captured sting or temporary cue

**Planning ceiling:** `18-22 A`, followed by normalization and loop validation.

**Checkpoint 1F:** Test repeated cannon volleys and pickups. Reject machine-gun
repetition, clipped transients, stereo spatial SFX, and audible loop seams.

### Wave 1 gate

Build and play one complete encounter on the target mobile renderer. Record:

- Total Wave 1 service cost.
- Cost per approved master and per approved effect sequence.
- Rejection rate by asset family.
- GPU texture memory, atlas count, and largest atlas dimensions.
- Readability and performance with approximately 30 ships/effects on screen.

Do not start Wave 2 until the vertical slice looks intentional rather than provisional.

---

## Wave 2 — Full island loop

Wave 2 supports the normal progression loop: approach, fight, capture, land, dig, loot,
and use the port.

### Batch 2A — Standard fleet masters

**Assets**

- `hull_dinghy`
- `hull_brig`
- `hull_galleon`
- `hull_longboat`
- `sail_small` and `sail_large`
- `sail_small_furled`, `sail_med_furled`, `sail_large_furled`
- Remaining short, medium, and long `cannon_mount` sizes
- `deck_wheel`, `deck_capstan`, `deck_hatch`, `deck_crates`, and `deck_barrels`

**Method**

- Approve ship silhouettes as a lineup before detailing any one hull.
- Reuse the same material library and attachment conventions as the sloop.
- Deck dressing must be modular and reused across multiple hulls.

**Planning ceiling:** `8-14 G`, `6-12 E`, `12-20 V`, `35-55 R`, `2 H`.

**Checkpoint 2A:** Review the full ship lineup as black silhouettes, grayscale values,
and faction-colored gameplay sprites. Each tier must read instantly.

### Batch 2B — Island structures and defenses

**Assets**

- Three neutral huts
- Tent, four-frame campfire, and cookpot
- Barrel, crate, sack, and net
- Dock straight, corner, end, post, and ladder
- `cannon_emplacement` with separate rotating barrel
- `watchtower`
- `shipyard` with two damage states
- `flagpole` and two-frame `flag_island`

**Planning ceiling:** `7-12 G`, `5-10 E`, `18-28 V`, `35-55 R`, `2 H`.

**Checkpoint 2B:** Assemble at least three islands from the same components. Structures
must share scale and material language without looking duplicated.

### Batch 2C — Landing-party character rig

**Assets**

- Pirate walk: down, up, and side, four frames each
- Pirate idle: three directions, two frames each
- Pirate dig: four side-view frames
- Pirate carry-walk: three directions, four frames each
- Pirate row: four frames

**Method**

- Create three canonical directional rigs from one approved character identity.
- Mirror the side direction at runtime.
- Pose fixed body parts; never redraw clothing or face per frame.
- Perform a final silhouette cleanup at 32 x 40 px.

**Planning ceiling:** `3-6 G`, `3-8 E`, `3 rig masters`, `38 R`, `1-2 H`.

**Checkpoint 2C:** Play every animation consecutively and verify constant hat, coat,
body proportions, equipment, baseline, and foot placement.

### Batch 2D — Loot, pickups, and progression

**Assets**

- `doubloon_spin`
- Four gem variants
- Five `crate_ammo` variants using one crate master and stencil overlays
- `kit_repair`
- `pickup_life`
- Four `bottle_boost` variants
- `scroll_blueprint`
- `map_fragment`
- Four `floating_debris` variants
- `treasure_hole`

**Planning ceiling:** `4-8 G`, `3-8 E`, `12-18 V`, `35-50 R`, `1 H`.

**Checkpoint 2D:** Verify silhouette and color accessibility. Ammo variants cannot rely
on color alone; their lid stencils must remain readable at gameplay size.

### Batch 2E — Port UI and complete icon family

**Assets**

- Remaining parchment panel sizes
- Wood panel and rope frame
- Remaining brass button shapes and states
- Ghost button states
- Toggle, slider, tabs, bars, card, ribbons, tooltip, reward burst
- Compass rose, wind indicator, joystick, and fleet badges
- All remaining icons listed in `ASSETS.md`

**Method**

- Expand the Wave 1 component system; do not design screens as isolated paintings.
- Build every icon from the same grid, stroke, and two-tone palette.
- Generate family concepts only if the established icon grammar fails for a category.

**Planning ceiling:** `0-4 G`, `0-4 E`, `60-85 V`, `80-120 R`, `2 H`.

**Checkpoint 2E:** Review a complete port screen, upgrade cards, settings screen, and
combat HUD. Check 9-slice stretching and all control states.

### Batch 2F — Treasure-map completion

**Assets**

- Torn-edge mask and map compass
- Ally and captured map ship icons
- Map skull, port pin, fog tile, route dash, and island-stroke brush

**Planning ceiling:** `1-3 G`, `1-3 E`, `8-12 V`, `12-20 R`, `1 H`.

**Checkpoint 2F:** Compare world geometry and map geometry. The map may be stylized but
must not imply different island shapes or navigable routes.

### Batch 2G — Island-loop audio

**Suggested sounds**

- Mortar launch and whistle placeholders if needed for testing
- Sail unfurl, anchor drop/raise, and hull creaks
- Shore ambience and gull variations
- Row loop, digging variations, chest open
- Crew shouts and cheers
- Purchase, upgrade, large loot, map open/close, and error feedback
- Warm port music loop or a temporary approved stem

**Planning ceiling:** `25-35 A`.

**Checkpoint 2G:** Play the entire island loop without music first, then with music.
Verify hierarchy: combat and warnings must remain audible over ambience and reward cues.

### Wave 2 gate

The full approach-fight-land-dig-loot-port loop must be playable using approved art and
audio. Update the forecast for Waves 3 and 4 using actual per-family costs.

---

## Wave 3 — Bosses, special enemies, and polish

### Batch 3A — Special enemy ships

**Assets**

- `hull_bombketch` and `mortar_pit`
- `hull_fireship`
- Torn sail overlays for small, medium, and large sails
- Three hull-damage overlay intensities adapted through masks to every required hull
- Six-frame hull-agnostic wreck sequence

**Planning ceiling:** `5-9 G`, `5-10 E`, `10-16 V`, `35-60 R`, `2 H`.

**Checkpoint 3A:** Special enemies must be recognizable from silhouette before color or
effects. Damage overlays may add damage but cannot move existing ship features.

### Batch 3B — Castle boss set

**Assets**

- Castle wall straight, corner, and gate
- Castle tower
- Castle keep with three damage states
- Castle battery with separate barrel
- Supporting cliff edge if required by the boss island

**Planning ceiling:** `5-9 G`, `4-8 E`, `12-20 V`, `25-40 R`, `2 H`.

**Checkpoint 3B:** Assemble the boss at several island shapes. Damage states must preserve
the original footprint, collision expectations, and battery sockets.

### Batch 3C — Remaining terrain, props, and landmarks

**Assets**

- Jungle, rock, and snow fills
- Cliff and grass-to-sand edges
- Dirt path
- Remaining palms, bushes, ferns, grass tufts, and rocks
- Driftwood, bones, skull, signpost, two beach wrecks, and reusable shadow blob

**Planning ceiling:** `8-14 G`, `5-10 E`, `18-28 V/P`, `35-55 R`, `2 H`.

**Checkpoint 3C:** Review every biome with the same ships and UI overlay. Biomes should
change mood without looking like different games.

### Batch 3D — Remaining projectiles and combat VFX

**Assets**

- Fire, explosive, chain, grape, and mortar ordnance
- Trail-puff frames
- Large splash, fire loop, smoke plume, sink whirl, ripple ring, boarding clash,
  sparkle, flag raise, and digging dust
- Droplet, foam, ember, soft smoke, spark, and splinter particle textures

**Planning ceiling:** `10-18 G`, `12-24 E`, `55-85 R/P`, `2 H`.

**Checkpoint 3D:** Run a visual-noise test with overlapping effects. Gameplay telegraphs,
targets, and health states must remain readable.

### Batch 3E — Soldier and captain characters

**Assets**

- Soldier walk, three directions, four frames each
- Soldier fire, two frames
- Four captain portraits, one per ship tier

**Method**

- Soldier uses the same rig rules and scale as the pirate.
- Portraits may use image generation, but approve one facial/style language first and use
  locked references for the remaining tiers.

**Planning ceiling:** `5-9 G`, `4-10 E`, `3 rig masters`, `14 character R`, `1-2 H`.

**Checkpoint 3E:** Compare all portraits together and all world characters together.
They may differ in identity, not in rendering style or anatomy rules.

### Batch 3F — Full audio and adaptive music

**Assets**

- Complete missing SFX and required 3-4 variation sets from `ASSETS.md`
- Menu, calm, tense, combat, boss, and port music
- Victory and defeat stings
- Calm, tense, and combat authored as compatible stems in one key and tempo

**Planning ceiling:** remaining SFX count plus `8 A` musical deliverables. Track musical
duration separately because its cost is not comparable to a one-shot SFX.

**Checkpoint 3F:** Test musical transitions during approach, combat, and victory. Reject
stems that click, drift, change tempo, or cannot crossfade without a noticeable seam.

### Wave 3 gate

Complete a boss run on low, medium, and high quality settings. Review asset memory,
effect density, audio mixing, and whether damage and enemy identities remain readable.

---

## Wave 4 — Release assets and final variation

### Batch 4A — Final variation pass

**Assets**

- Remaining prop silhouette variants justified by visible repetition
- Missing audio variations identified during playtesting
- Final accessibility adjustments
- Corrections to animations, seams, outlines, masks, and pivots

**Planning ceiling:** Set only after playtesting. Every item must reference a logged
problem; do not add assets solely to exhaust the list.

**Checkpoint 4A:** Compare before/after captures. Keep only changes that improve a
measured readability, repetition, or quality issue.

### Batch 4B — Brand and store foundation

**Assets**

- Final logo lockup, horizontal and stacked SVG
- 1024 px app icon
- Android adaptive foreground and background
- iOS icon exports
- Favicon exports
- 1920 x 1080 splash screen
- 1200 x 630 share image

**Method**

- Logo and app icon must derive from one approved brand mark.
- Platform sizes are deterministic exports, not separate generations.
- Avoid tiny ship details that disappear in small icons.

**Planning ceiling:** `4-8 G`, `3-8 E`, `2-4 V`, `15-25 R`, `2 H`.

**Checkpoint 4B:** Review at every required platform size, including 16 px favicon size.

### Batch 4C — Screenshots and trailer stills

**Assets**

- Six store screenshots for each required device class
- Phone and tablet crops/layouts
- Three trailer key-art frames

**Method**

- Capture real gameplay first. Use compositing only for layout, typography, and controlled
  presentation polish.
- Never depict mechanics, ships, enemies, or environments that are absent from the game.
- Reuse the real canonical game assets; do not regenerate ships for marketing art.

**Planning ceiling:** `0-3 G` for background/presentation elements, `3-8 E`, plus capture
and layout time.

**Checkpoint 4C:** Every promotional image must be truthful to the shipped game and
legible at storefront thumbnail size.

### Batch 4D — Final technical build

**Deliverables**

- Approved per-group atlases no larger than 2048 x 2048
- Straight-alpha, sRGB, lossless imports
- One-pixel sprite padding and two-pixel atlas padding
- PNG-8 where visually lossless; otherwise PNG-24
- Complete manifest and licenses
- No SVG source shipped in export presets
- Reproducible clean asset build

**Planning ceiling:** `0 G`, `0 E`; engineering and QA time only.

**Checkpoint 4D — release gate:** Build from a clean checkout, compare manifests and
pixel output, run the game on target web/mobile devices, and archive the final cost log.

---

## 6. Suggested occasion schedule

The safest default is one batch per occasion. Batches with no generation work may be
combined if time allows.

| Occasion | Batch | Decision before continuing |
|---:|---|---|
| 1 | 0A | Select or reject the visual language |
| 2 | 0B | Approve the canonical sloop system |
| 3 | 0C | Lock cross-family art direction |
| 4 | 0D | Verify reproducible asset builds |
| 5-10 | 1A-1F | Approve the vertical slice and measured unit costs |
| 11-17 | 2A-2G | Approve the complete normal island loop |
| 18-23 | 3A-3F | Approve boss content, polish, and complete audio |
| 24-27 | 4A-4D | Approve release presentation and final build |

This is a planning sequence, not a deadline. If a checkpoint fails, the next occasion
repeats or revises that batch rather than silently consuming the next batch's budget.

## 7. Status dashboard

Update this table when production begins:

| Batch | Status | Actual `G` | Actual `E` | Actual `A` | Approved outputs | Actual service cost | Decision |
|---|---|---:|---:|---:|---:|---:|---|
| 0A | Complete | 3 | 0 | 0 | 1 selected direction | Not exposed | Continue |
| 0B | Complete | 2 | 0 | 0 | 1 canonical sloop system | Not exposed | Continue |
| 0C | Complete | 1 | 0 | 0 | 1 cross-family proof set | Not exposed | Continue |
| 0D | Complete | 0 | 0 | 0 | Renderer + validator + proofs | 0 generation calls | Complete |
| 1A-1F | Not started | 0 | 0 | 0 | 0 | — | — |
| 2A-2G | Not started | 0 | 0 | 0 | 0 | — | — |
| 3A-3F | Not started | 0 | 0 | 0 | 0 | — | — |
| 4A-4D | Not started | 0 | 0 | 0 | 0 | — | — |

## 8. Definition of done for every visual asset

- Correct name, dimensions, pivot, orientation, and atlas group.
- Canonical source and catalog entry exist.
- Transparent border and straight alpha validate.
- Reads at nominal size and at expected gameplay size.
- Uses approved palette, outline, shading, and material rules.
- Variants preserve the canonical identity.
- Animation loops or completes without spatial jumping.
- Texture seams are not visible in a repetition test.
- No unapproved text, watermark, trademark, or generated artifact remains.
- Approved status and actual production cost are recorded.
