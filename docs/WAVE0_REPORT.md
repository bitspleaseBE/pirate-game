# Wave 0 Completion Report — Revision 2

Date: 2026-08-01  
Status: complete; ready for visual approval.

## Outcome

Wave 0 was rebuilt in **Painterly Tactical Realism** after revision 1 was rejected as too
rudimentary and cartoonish. Revision 1 remains available under `assets_archive/wave0_v1/` for
cost and decision auditing; it is no longer referenced by the production catalog.

- One construction-plausible sloop master drives the base hull, three faction proofs, the
  accent mask, and every rotation view.
- The sail, cannon, skiff, palm, rock, parchment, terrain, and muzzle flash use new high-detail
  masters made for the selected v2 direction.
- Palm anatomy, wood construction, canvas folds, metal treatment, and material texture are
  substantially more natural and restrained.
- All shipping files are local deterministic 2x exports; generated boards are not cropped into
  gameplay assets.

## Revision 2 generation usage

| Batch | New generations | Edit calls | Result |
|---|---:|---:|---|
| 0A-v2 — direction boards | 3 | 0 | Painterly Tactical Realism selected |
| 0B-v2 — sloop system | 4 | 0 | Hull, sail, skiff, cannon masters |
| 0C-v2 — supporting families | 6 | 0 | Palm, rock, parchment, sand, shore, muzzle master |
| 0D-v2 — local conversion/tooling | 0 | 0 | Raster/SVG renderer, recolor, masks, proofs |
| **Revision 2 total** | **13** | **0** | **20 catalog assets rebuilt** |

Revision 1 used 6 new generations, so the cumulative Wave 0 exploration total is 19 new-image
calls and 0 edit calls. The built-in generator exposed no monetary amount; call counts are the
authoritative cost record.

## Canonical revision 2 masters

- `assets_src/ships/sloop/v2/hull_sloop_master.png`
- `assets_src/ships/sloop/v2/sail_med_master.png`
- `assets_src/ships/sloop/v2/cannon_mount_master.png`
- `assets_src/ships/skiff/v2/hull_skiff_master.png`
- `assets_src/props/palm/v2/palm_0_master.png`
- `assets_src/props/rock/v2/rock_0_master.png`
- `assets_src/ui/v2/panel_parchment_master.png`
- `assets_src/terrain/v2/fill_sand_source.png`
- `assets_src/terrain/v2/edge_shore_source.png`
- `assets_src/vfx/v2/fx_muzzleflash_master.png`
- `assets_src/ships/sloop/flag_wave_0.svg` and `flag_wave_1.svg`

The magenta-backed inputs are retained beside their alpha-cleaned masters. The contact sheet,
40 px proof, production composition, and rotation sheet are generated only from final catalog
outputs.

## Validation

- 20/20 catalog entries pass ID, file, dimensions, maximum-size, and alpha-border checks.
- All outputs match their exact 2x nominal dimensions.
- The same hull pixels are used for all faction and rotation proofs.
- Sand is mirrored into a seamless XY tile; the shore source is mirrored into an X-tileable strip.
- Palm and muzzle masters received local chroma removal, despill, and a two-pixel edge contraction.
- Gameplay-scale proofs were visually inspected on dark water and light sand.
- A clean second build produced byte-identical checksums for all 24 production/proof PNGs.
- Terrain edge tests measured zero pixel delta on both sand axes and on the shore strip's X axis.

## Rebuild commands

```sh
godot --headless --path tools/assets --script render_assets.gd
godot --headless --path tools/assets --script validate_assets.gd
godot --headless --path tools/assets --script make_wave0_proofs.gd
```

## Wave 1 gate

Approve the v2 contact sheet and gameplay proof before Wave 1. Later ship classes should inherit
the sloop’s construction logic, palette, edge treatment, and material density—not regenerate a
new visual language.
