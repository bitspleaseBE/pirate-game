# Wave 1 Static-Art Completion Report

Date: 2026-08-02  
Status: generated and validated; ready for visual approval and gameplay integration.

## Scope

Wave 1 static art for batches 1A through 1E is complete. Wave 0 ship, sail, flag,
cannon, parchment, and muzzle-flash masters remain the source of truth and were not
regenerated.

Per production direction, these ocean and beach inputs were deliberately excluded:

- `water_flow_tile`, `water_detail_tile`, `water_caustic_tile`
- `ramp_water_depth`, `ramp_foam`, `shore_foam_strip`
- Wave 1 replacements for `fill_sand` and `edge_shore`

They are intended to be produced procedurally rather than consumed as new static art.
The ship wake and cannon-miss splash remain static VFX because they are animated combat
feedback, not ocean-surface or shoreline rendering.

Wave 1 audio (Batch 1F) was also outside this image-production occasion.

## Deliverables

- Core ship presentation: wake strip, four bow-foam frames, and optional ship shadow.
- Island support: a deterministic seamless grass tile plus second approved palm and rock
  silhouettes.
- Combat: round shot and shadow, six splash frames, five wood-impact frames, and eight
  explosion frames. The approved four-frame Wave 0 muzzle flash is reused unchanged.
- Treasure and interaction: mound, X mark, closed/open chest, six coin frames, four-frame
  target reticle, waypoint marker, and selection ring.
- HUD and map: three brass-button states, bar frame and four fills, map parchment, map X,
  map ship marker, and twelve core icons. The Wave 0 parchment panel is reused unchanged.
- Proofs: contact sheet, 40 px comparison, and composed encounter proof.

The catalog contains 75 Wave 1 outputs. With the existing 20 Wave 0 outputs, the renderer
and validator check 95 catalog entries. Three Wave 1 proof PNGs are additional non-catalog
review artifacts.

## Generation usage

Eight built-in new-image calls returned approved canonical masters:

1. `wake_strip`
2. `wake_foam`
3. `palm_1`
4. `rock_1`
5. `fx_splash_small`
6. `fx_impact_wood`
7. `fx_explosion`
8. `treasure_mound`

No image-edit calls were used. Several grass/chest calls did not return from the image
service and were stopped; they produced no artifact and are recorded separately from the
eight successful generations. Grass, chest states, UI, icons, projectiles, and animation
variants were completed deterministically in the local pipeline.

## Pipeline changes

- Catalog schema 3 supports included wave catalogs and compact sequence definitions.
- `assets_src/catalog_wave1.json` records every Wave 1 shipping PNG and the procedural
  exclusions.
- Generated VFX families derive all frames from one locked master using centered scale,
  reflection, and alpha changes.
- The grass tile is generated from deterministic periodic color fields and wrapped blade
  strokes, so its borders repeat without a seam.
- UI and icons share SVG geometry, palette, highlight, stroke, and safe-area tokens.

## Validation

- 95/95 catalog entries pass unique ID, file, exact dimensions, 2048 px limit, and
  transparent-border checks.
- Generated masters were alpha-cleaned with the built-in image-generation skill's local
  chroma-removal workflow and inspected on dark and light grounds.
- Icons were checked at 64, 54, and 40 px in the proof sheet.
- Animation frame families remain centered because all frames derive from one source image.
- Visual proofing caught and corrected an unsupported SVG filter and two icon safe-area
  violations before the final validation run.
- A clean second render produced byte-identical checksums for all 78 Wave 1 PNGs, including
  the three proof images that remained unchanged during the catalog rebuild.

## Rebuild commands

```sh
godot --headless --path tools/assets --script render_assets.gd
godot --headless --path tools/assets --script validate_assets.gd
godot --headless --path tools/assets --script make_wave1_proofs.gd
```

## Review gate

The static-art wave is ready for review. Gameplay integration, live animation timing,
30-object stress testing, atlas packing, and Batch 1F audio remain separate tasks before the
full Wave 1 gameplay gate can be closed.
