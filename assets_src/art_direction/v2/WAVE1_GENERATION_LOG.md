# Wave 1 Static-Art Generation Log

Mode: built-in image generation plus deterministic Godot/SVG construction.  
Successful new-image calls: 8. Image-edit calls: 0.

All raster prompts used the locked Painterly Tactical Realism direction at
`direction_b_painterly_tactical_selected.png`. Existing Wave 0 masters were supplied as
family or material references where useful. Each isolated subject used a flat magenta or
green chroma field and was alpha-cleaned locally before entering the catalog.

| Call | Saved canonical source | Role |
|---|---|---|
| G1 | `../../ships/wake/v1/wake_strip_master.png` | Long ship-wake identity |
| G2 | `../../ships/wake/v1/wake_foam_master.png` | Four-frame bow-foam source |
| G3 | `../../props/palm/v2/palm_1_master.png` | Second palm silhouette |
| G4 | `../../props/rock/v2/rock_1_master.png` | Second limestone silhouette |
| G5 | `../../vfx/v1/fx_splash_small_master.png` | Six-frame cannon-miss source |
| G6 | `../../vfx/v1/fx_impact_wood_master.png` | Five-frame splinter source |
| G7 | `../../vfx/v1/fx_explosion_master.png` | Eight-frame black-powder source |
| G8 | `../../props/treasure/v1/treasure_mound_master.png` | Diggable treasure mound |

## Prompt set

The shared production prompt was:

```text
Use case: stylized-concept
Asset type: high-resolution canonical game asset master
Input images: the selected Painterly Tactical Realism board is the locked art-direction
reference; any additional approved master is a family/material reference only.
Primary request: create one isolated subject in strict top-down orthographic view with
believable construction or natural motion, restrained color, selective edges, diffuse
upper-left lighting, grouped values, and clear mobile-scale silhouette.
Background: one perfectly flat removable chroma field with no floor, shadow, gradient,
texture, reflection, or lighting variation.
Constraints: no scenery, text, logo, watermark, duplicate subject, horizon, perspective,
isometric camera, toy/chibi geometry, thick uniform outline, plastic gloss, neon color, or
the chosen key color in the subject.
```

Subject clauses specified: vertical tapering wake; V-shaped bow foam; shorter right-leaning
coconut palm; low broad limestone outcrop; radial cannon splash; +X wood-splinter impact;
compact naval black-powder explosion; and a subtle diggable soil mound.

## Non-generated families

- Wave 0 ship, sail, flag, cannon, parchment, and muzzle masters are reused unchanged.
- Chest states, brass buttons, bars, map, feedback widgets, projectiles, coins, and core icons
  are shared-token SVG constructions.
- All animation frames are deterministic derivatives of one approved master or SVG identity.
- Grass is a deterministic periodic/wrapped renderer output after repeated material-swatch
  generation attempts did not return from the service.
- Ocean and beach shader/shoreline assets are intentionally omitted from the Wave 1 catalog.
