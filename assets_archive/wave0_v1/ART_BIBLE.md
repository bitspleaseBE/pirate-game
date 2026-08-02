# Pirates: Treasure Hunt — Art Bible

Status: Wave 0 style lock, revision 1.

## Selected direction

The primary direction is **Bold Cartographic Toybox** (`direction_b_cartographic_toybox.png`).
It provides the best silhouette clarity at mobile scale and the most reproducible flat-vector
construction. The slightly angular silhouette discipline from Graphic Sea-Adventure Print may
be used, but its surface flecks and print noise are not part of the production style.

The generated boards and gameplay mockup are visual references. They are not shipping assets
and must not be cropped into production sprites.

## Camera and geometry

- Strict top-down orthographic world art; no horizon and no isometric elevation.
- Ships point bow-up toward negative Y at rotation zero.
- Ship pivot is the center of mass.
- Prop pivot is base center.
- Forms favor broad, readable masses over historical micro-detail.
- Structural geometry is nearly bilateral where the real object is bilateral.
- Small irregularities may appear in leaves, rocks, parchment, and damage, never in sockets,
  pivots, masks, or gameplay silhouettes.

## Line language

| Nominal asset size | Outer outline | Interior line |
|---|---:|---:|
| 24–48 px | 2–2.5 px | 1–1.5 px |
| 64–128 px | 3–4 px | 1.5–2 px |
| 160–320 px | 4–6 px | 2–3 px |

- Primary outline: `#082638`.
- Secondary dark structure: `#163D4C`.
- Round joins and caps by default.
- Interior lines use lower contrast than the silhouette.
- At least one continuous dark boundary must survive at a 40 px reading size.

## Palette

| Role | Base | Light | Dark |
|---|---|---|---|
| Ink/navy | `#082638` | `#163D4C` | `#041820` |
| Wood | `#A65E2E` | `#D28A3D` | `#6E3E1F` |
| Deck | `#955126` | `#B96C32` | `#5E351E` |
| Canvas | `#F3E3B5` | `#FFF2CF` | `#D8C487` |
| Brass | `#E5A62F` | `#F4C759` | `#A86C1A` |
| Iron | `#526974` | `#82959D` | `#2F4652` |
| Water | `#2DAEB6` | `#62D1CD` | `#178D9C` |
| Sand | `#EACB83` | `#F4DDA2` | `#D8B66B` |
| Foliage | `#4F8D3A` | `#7FAD45` | `#28582E` |
| Rock | `#687781` | `#A6B0B4` | `#3C4B56` |
| Player accent | `#D9573F` | `#EE7659` | `#A9342D` |

Additional faction colors replace only the player-accent mask. They do not alter hull,
deck, metal, canvas, or outline colors.

## Shading and material rules

- One base value plus one light or dark value per material.
- Ambient highlight comes from upper left.
- No cast shadows in source sprites. Reusable blob shadows are separate game objects.
- No airbrushed gradients, glossy 3D speculars, or procedural noise in world sprites.
- Wood uses a small number of broad plank separations, not dense grain.
- Canvas uses edge tension and at most two fold cues.
- Metal reads through value grouping and a single highlight strip.
- Texture fills may use sparse low-contrast marks, with no unique focal mark that reveals tiling.

## Identity preservation

- One canonical SVG per hull silhouette.
- Sails, cannons, flags, wakes, damage, and fire are separate overlays.
- Faction variants are deterministic color replacements or shader masks.
- Animation frames derive from one master and may not introduce new structural details.
- A revision that changes silhouette, pivot, or attachment sockets increments the master revision.
- Marketing art must reuse the same canonical game identities.

## Readability tests

Every approved family is checked:

1. At 2× export size for edge and alpha quality.
2. At nominal size for the intended import scale.
3. With the longest dimension reduced to about 40 px.
4. Over both dark water and light sand.
5. In grayscale and in at least three faction recolors where applicable.

## Prohibited production traits

- Independently generated ship or animation variants.
- Isometric or three-quarter world sprites.
- Thin gray outlines.
- Unbounded texture noise.
- Baked water, wakes, shadows, or faction colors in a hull master.
- Skull motifs as generic decoration; reserve them for explicit pirate-status assets.
- Text, watermarks, copied logos, or exact motifs from reference packs.

