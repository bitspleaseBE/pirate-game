# Wave 0 Revision 2 Generation Log

Mode: built-in image generation. New-image calls: 13. Edit calls: 0.

The selected style reference is `direction_b_painterly_tactical_selected.png`. Generated
direction boards are non-shipping references. Canonical subjects were generated separately at
high resolution, then alpha-cleaned or made seamless locally and rendered through the catalog.

## Call record

| Call | Output | Role |
|---|---|---|
| G1 | `direction_a_illustrated_realism.png` | Direction candidate |
| G2 | `direction_b_painterly_tactical_selected.png` | Selected direction |
| G3 | `direction_c_maritime_graphic.png` | Direction candidate |
| G4 | `../../ships/sloop/v2/hull_sloop_chroma.png` | Canonical sloop hull/deck |
| G5 | `../../ships/sloop/v2/sail_med_chroma.png` | Canonical medium sail assembly |
| G6 | `../../ships/skiff/v2/hull_skiff_chroma.png` | Canonical skiff |
| G7 | `../../props/palm/v2/palm_0_chroma.png` | Canonical natural palm |
| G8 | `../../props/rock/v2/rock_0_chroma.png` | Canonical limestone rock |
| G9 | `../../ships/sloop/v2/cannon_mount_chroma.png` | Canonical deck cannon |
| G10 | `../../ui/v2/panel_parchment_chroma.png` | Canonical parchment panel |
| G11 | `../../terrain/v2/fill_sand_source.png` | Sand texture source |
| G12 | `../../terrain/v2/edge_shore_source.png` | Shore strip source |
| G13 | `../../vfx/v2/fx_muzzleflash_chroma.png` | Canonical muzzle effect source |

## Shared direction-board prompt

```text
Use case: game asset art-direction board.
Create a premium, cohesive 3:2 visual-development board for a top-down pirate strategy/action
game. Show exactly one strict top-down medium sloop, skiff, natural Caribbean palm, limestone
rock, sand/shore sample, directional cannon muzzle/impact, blank parchment panel, and cannon
action icon. Favor believable maritime construction, natural botany, weathered wood and linen,
restrained painterly texture, selective dark contact edges, grouped values, and mobile-scale
silhouette clarity. Illustrated stylized realism—not photoreal and not cartoonish. No text,
labels, watermark, logo, horizon, isometric view, cute proportions, toy shapes, thick uniform
outlines, plastic 3D rendering, neon color, skull decoration, or copied motifs.
```

Candidate B additionally emphasized tactical readability, restrained saturation, subtle ambient
occlusion, and the clearest large value groups; it became the locked production direction.

## Shared canonical-object prompt

```text
Use case: high-resolution canonical game asset master.
Match the selected Painterly Tactical Realism board. Render one centered, complete subject in
strict top-down orthographic view with believable construction or anatomy, restrained natural
color, selective edges, subtle ambient occlusion, and premium hand-painted material detail.
Preserve a clean readable silhouette at small gameplay size. Place the isolated subject on one
perfectly flat, uniform #ff00ff chroma field with no ground plane, cast shadow, scenery, text,
logo, watermark, duplicated subject, perspective, toy/chibi geometry, thick cartoon outline,
plastic gloss, or decorative clutter. Leave generous clear space around the silhouette.
```

Subject clauses:

- **Sloop:** lean 3:5 hull and deck only, pointed bow toward negative Y, squared transom,
  continuous gunwale, coherent planks, centered mast socket, hatch/capstan/rope, and two aligned
  gun positions per side; no sail, mast assembly, flag, wake, or water.
- **Sail:** square medium cream linen sail, horizontal yard, centered vertical mast, plausible
  rope tension and seams; no hull, water, flag, or emblem.
- **Skiff:** narrow clinker-built open boat, bow up, coherent ribs and thwarts, centered socket;
  no occupants, oars, wake, or water.
- **Palm:** mature Caribbean coconut palm with a tapering ringed leaning trunk, coconuts, and a
  layered crown of natural fronds with believable leaflet rhythm; no island or soil base.
- **Rock:** compact pale tropical limestone cluster with coherent fracture, erosion, and a
  strong readable mass.
- **Cannon:** short iron naval cannon on a credible wooden carriage, strict top-down, barrel
  firing toward positive X; no muzzle flash.
- **Parchment:** blank horizontal 3:2 aged sheet, restrained irregular edge and stains, clear
  writable center; no symbols, map, text, ribbon, or wax seal.
- **Muzzle effect:** one directional black-powder cannon discharge firing toward positive X,
  with compact orange-white flame, hot sparks, and layered gray-brown smoke; no weapon.

## Terrain prompts

```text
Create a square seamless source texture of fine tropical beach sand in restrained warm ochre and
beige. Near-orthographic surface view, subtle grains, compacted variation, sparse tiny shell
flecks, low contrast, no focal objects, footprints, shadows, borders, text, or directional light.
```

```text
Create a wide 4:1 strict top-down tropical shoreline strip: clear teal water, a narrow irregular
white foam transition, and natural warm sand. Horizontally tileable, low contrast, mature
painterly realism, no rocks, plants, objects, horizon, labels, frame, or cast shadows.
```

## Post-processing

Chroma-backed masters use the bundled local remover with automatic border-key sampling,
soft matte, despill, and alpha cleanup. The palm and muzzle effect use a two-pixel edge
contraction. Terrain continuity is made deterministic in the renderer by mirror tiling.
