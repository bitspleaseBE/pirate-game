# Wave 0 Generation Log

Mode: built-in image generation. The Kenney images were used only as style/readability
references. All prompts required original designs and prohibited copied logos and motifs.

## Calls

| Call | Saved output | Result |
|---|---|---|
| G1 | `concepts/direction_a_carved_nautical.png` | Art-direction candidate A |
| G2 | `concepts/direction_b_cartographic_toybox.png` | Selected primary direction |
| G3 | `concepts/direction_c_graphic_print.png` | Secondary silhouette reference |
| G4 | `../ships/sloop/concept_sturdy.png` | Rejected as too broad and detailed |
| G5 | `../ships/sloop/concept_lean_selected.png` | Selected structural reference |
| G6 | `wave0_gameplay_concept.png` | Composition reference only |

Actual Wave 0 exploratory usage: **6 new generations, 0 edit calls**.

## Shared art-board prompt

```text
Use case: stylized-concept
Asset type: Wave 0 art-direction board for a production mobile pirate game
Input images: the supplied Kenney images are style/readability references only; do not copy
their exact ships, icons, island shapes, compositions, logos, or symbols.
Primary request: create one polished art-direction board showing a coherent original asset
family: top-down sloop, top-down skiff, palm tree, rock, sand-to-shore sample, cannonball wood
impact, parchment panel, and cannon icon.
Composition: clean 3:2 board, one subject per unlabeled cell; ships point up in strict top-down
orthographic projection.
Constraints: consistent outline and lighting; clear at 40 px; no text, captions, logos,
trademarks, watermark, perspective, cast shadows, or duplicate subjects.
```

Candidate A added carved nautical vector silhouettes and restrained crafted irregularity.
Candidate B added exceptionally clean chunky geometry and broad, uncluttered color fields.
Candidate C added angular screen-print silhouettes and a limited color-separation treatment.

## Shared sloop prompt

```text
Use case: stylized-concept
Asset type: canonical ship concept for a top-down mobile game
Input image: the selected Wave 0 board is the locked style reference.
Primary request: design one original medium sloop hull; hull and deck only, with no sail,
flag, water, wake, projectile, or scenery.
Subject: pointed bow, readable deck, central mast socket, compact hatch, reinforced gunwale,
and two aligned cannon attachment sockets per side.
Composition: one centered ship, bow up, strict top-down orthographic view, complete silhouette,
vertical 3:5 proportion.
Constraints: near-bilateral structural symmetry; readable at 40 px; no text, logo, watermark,
perspective, cast shadow, skull ornament, ornate micro-detail, 3D, or painterly texture.
```

The selected candidate requested a lean privateer silhouette and a softly squared transom.

## Gameplay composition prompt

```text
Use case: stylized-concept
Asset type: gameplay composition proof
Input image: the selected Wave 0 board is the locked style reference.
Primary request: one lean player sloop exchanging a broadside with three skiffs beside a
compact tropical island; include palm, rocks, shore, muzzle flash, wood impact, a parchment
minimap panel, and a cannon action icon.
Composition: 16:9 top-down orthographic gameplay view; ships rotate only in the 2D plane.
Constraints: consistent identities and phone-scale readability; no text, labels, logos,
watermark, device frame, isometric camera, 3D rendering, or copied reference motifs.
```

