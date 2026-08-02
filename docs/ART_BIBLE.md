# Pirates: Treasure Hunt — Art Bible

Status: Wave 0 style lock, revision 2 (2026-08-01).

## Selected direction

The production direction is **Painterly Tactical Realism**
(`assets_src/art_direction/v2/direction_b_painterly_tactical_selected.png`). It combines
believable maritime construction and natural tropical forms with the strong value grouping
needed for a top-down game. The result should feel illustrated and authored, not photographic,
toy-like, or Saturday-morning cartoonish.

The direction boards are references only. Shipping sprites are rendered from the canonical
masters recorded in `assets_src/catalog.json`.

## Camera and geometry

- Strict top-down orthographic world art; no horizon or isometric elevation.
- Ships point bow-up toward negative Y at rotation zero.
- Ship pivots use center of mass; props use base center.
- Naval architecture must remain plausible: a continuous gunwale, coherent plank direction,
  centered mast socket, usable hatches, and aligned gun positions.
- Structural forms stay nearly bilateral where the real object is bilateral.
- Organic asymmetry belongs in foliage, stone fracture, cloth, foam, smoke, and damage.

## Shape and edge language

- Silhouettes are clean and decisive, but the style does not use a uniform cartoon outline.
- Dark contact edges are strongest around hulls, ironwork, and major overlaps.
- Interior edges are thinner, lower contrast, and may dissolve into painted material detail.
- Foliage uses grouped fronds with believable leaflet rhythm, not radial green spikes.
- At about 40 px, the hull, skiff, palm crown/trunk, rock mass, cannon, and muzzle direction
  must remain identifiable even when fine texture disappears.

## Palette and lighting

| Material | Base range | Highlight | Shadow/accent |
|---|---|---|---|
| Aged timber | warm umber / weathered oak | dry honey wood | deep brown-black seams |
| Canvas | warm sailcloth cream | sun-bleached linen | muted taupe folds |
| Iron | charcoal / blue-black | restrained steel glint | near-black occlusion |
| Brass | aged ochre | small warm glint | brown tarnish |
| Water | desaturated tropical teal | soft cyan-green variation | blue-teal depth |
| Sand | muted warm ochre | dry beige | compacted brown |
| Foliage | olive and deep palm green | sunlit yellow-green | cool forest green |
| Player accent | weathered oxblood red | muted brick | dark burgundy |

- Lighting is diffuse from upper left, with restrained ambient occlusion.
- Values are grouped into readable large masses before surface detail is added.
- Highlights are material-specific and never glossy plastic.
- Saturation is selective: sails, wood, sand, and foliage remain natural and weathered.

## Material treatment

- Wood may show plank seams, grain, wear, pegs, and edge abrasion, but not random visual noise.
- Canvas shows weave, rope tension, seams, and a few broad folds.
- Metal reads through shape, dark mass, and small highlights rather than chrome reflections.
- Palms use a ringed, tapering trunk, a layered natural crown, coconuts where useful, and
  uneven frond lengths consistent with real growth.
- Rock planes follow coherent fracture and erosion patterns.
- Terrain texture is low contrast and seamless; it cannot compete with ships.
- Source sprites contain no baked water, wake, or global cast shadow.

## Canonical-source policy

- Hero ships, boats, foliage, rocks, painted UI surfaces, and complex VFX use one approved
  high-resolution transparent raster master per identity.
- Simple geometric UI, masks, and small cloth cycles may use deterministic SVG masters.
- Every game PNG is a deterministic 2x export defined in `assets_src/catalog.json`.
- Hull faction proofs recolor only detected accent paint on the same canonical pixels.
- Sail, cannon, and flag are separate overlays; engine rotation supplies headings.
- Animation frames derive from one source effect or layered rig and may not introduce new
  structure between frames.
- A silhouette, pivot, socket, or topology change increments `master_revision`.
- Marketing art must reuse the same canonical identities.

## Readability and QA

Every approved family is checked:

1. At 2x export size for alpha and edge quality.
2. At nominal import size.
3. With the longest dimension reduced to roughly 40 px.
4. Over dark water and light sand.
5. In a rotation proof where appropriate.
6. With a transparent outer border and exact catalog dimensions.

## Prohibited production traits

- Independently generated ship headings, color variants, or animation frames.
- Cute proportions, toy geometry, chibi forms, thick uniform black outlines, or flat clip art.
- Photorealism that breaks the illustrated game world.
- Isometric or three-quarter world sprites.
- Arbitrary rigging, impossible deck layouts, or structural drift between variants.
- Plastic highlights, neon tropical colors, excessive texture noise, or muddy silhouettes.
- Baked water, wakes, large cast shadows, text, watermarks, copied logos, or reference-pack motifs.
