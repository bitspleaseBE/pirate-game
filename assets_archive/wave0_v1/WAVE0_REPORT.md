# Wave 0 Completion Report

Date: 2026-08-01  
Status: complete, awaiting visual approval before Wave 1.

## Outcome

Wave 0 established a reproducible, consistency-first art pipeline for the game.

- Selected direction: **Bold Cartographic Toybox**.
- Canonical sloop: one SVG master, one accent mask, and deterministic proof recolors.
- Cross-family proof: ship, sail, cannon, flags, skiff, prop, terrain, UI, icon, and VFX assets.
- Tooling: isolated Godot renderer, validator, contact-sheet generator, rotation proof, and
  production-scene compositor.
- Generated concept references are stored under `assets_src/` and excluded from the main
  Godot project by `.gdignore`.

## Actual generation usage

| Batch | New generations | Edit calls | Audio calls |
|---|---:|---:|---:|
| 0A — direction boards | 3 | 0 | 0 |
| 0B — sloop concepts | 2 | 0 | 0 |
| 0C — gameplay composition reference | 1 | 0 | 0 |
| 0D — local tooling | 0 | 0 | 0 |
| **Total** | **6** | **0** | **0** |

This is below the initial Wave 0 forecast of 9–17 new generations and 4–11 edits. The
built-in generator did not expose a monetary amount, so the measurable call count is the
authoritative cost record.

## Canonical source deliverables

- `docs/ART_BIBLE.md`
- `assets_src/catalog.json`
- `assets_src/ships/sloop/hull_sloop.svg`
- `assets_src/ships/sloop/hull_sloop_accent_mask.svg`
- `assets_src/ships/sloop/sail_med.svg`
- `assets_src/ships/sloop/cannon_mount.svg`
- `assets_src/ships/sloop/flag_wave_0.svg`
- `assets_src/ships/sloop/flag_wave_1.svg`
- `assets_src/ships/skiff/hull_skiff.svg`
- `assets_src/props/palm/palm_0.svg`
- `assets_src/props/rock/rock_0.svg`
- `assets_src/ui/panel_parchment.svg`
- `assets_src/icons/icon_cannon.svg`
- `assets_src/terrain/fill_sand.svg`
- `assets_src/terrain/edge_shore.svg`
- Four canonical muzzle-flash frame SVGs

## Proof deliverables

- `assets/wave0/wave0_contact_sheet.png`
- `assets/wave0/wave0_40px_proof.png`
- `assets/wave0/wave0_production_scene.png`
- `assets/wave0/ships/sloop_rotation_proof.png`
- Three art-direction boards
- Two sloop concepts
- One generated gameplay composition reference

The production scene and rotation proof are composed from the exact canonical PNGs. No ship
was regenerated for either proof.

## Validation

- 20 catalog entries rendered at 2× nominal resolution.
- 20/20 entries passed ID, file, dimensions, maximum-size, and alpha-border validation.
- The palm initially touched its outer border; its SVG was corrected and rebuilt.
- A second clean render produced identical checksums for all 24 PNG outputs and proofs.
- The asset tools run in a minimal isolated Godot project and do not load game autoloads.

## Rebuild commands

```sh
godot --headless --path tools/assets --script render_assets.gd
godot --headless --path tools/assets --script validate_assets.gd
godot --headless --path tools/assets --script make_wave0_proofs.gd
```

## Wave 1 gate

Before Wave 1 begins, inspect the contact sheet, 40 px proof, rotation proof, and production
scene. The required decision is one of:

- **Approve:** use the current art bible and canonical geometry for Wave 1.
- **Revise:** make targeted changes to palette, silhouette, detail density, or UI treatment.
- **Restart direction:** discard the style lock; this should happen only before additional
  asset families are produced.

