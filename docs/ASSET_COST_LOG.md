# Asset Cost Log

The built-in image generator did not expose a monetary amount. Call counts are therefore the
auditable cost measure; local rendering and post-processing add no generation calls.

| Batch | Date | Tool/mode | G | E | A | Approved result | Reported service cost | Decision |
|---|---|---|---:|---:|---:|---|---:|---|
| 0A-v1 | 2026-08-01 | Built-in image generation | 3 | 0 | 0 | 1 direction | Not exposed | Later rejected |
| 0B-v1 | 2026-08-01 | Built-in + deterministic SVG | 2 | 0 | 0 | 1 sloop system | Not exposed | Later rejected |
| 0C-v1 | 2026-08-01 | Built-in + deterministic SVG | 1 | 0 | 0 | Family proof | Not exposed | Later rejected |
| 0D-v1 | 2026-08-01 | Local Godot tooling | 0 | 0 | 0 | Renderer/validator | 0 calls | Archived |
| 0A-v2 | 2026-08-01 | Built-in image generation | 3 | 0 | 0 | Painterly Tactical Realism | Not exposed | Approved for production |
| 0B-v2 | 2026-08-01 | Built-in + local alpha cleanup | 4 | 0 | 0 | Hull, sail, skiff, cannon | Not exposed | Complete |
| 0C-v2 | 2026-08-01 | Built-in + local alpha/tiling | 6 | 0 | 0 | Palm, rock, UI, terrain, VFX | Not exposed | Complete |
| 0D-v2 | 2026-08-01 | Local Godot tooling | 0 | 0 | 0 | 20 deterministic outputs | 0 calls | Complete |
| **Cumulative Wave 0** |  |  | **19** | **0** | **0** | v2 active; v1 archived | **Not exposed** | Awaiting visual approval |

## Revision notes

- Revision 1 used 6 generations and was rejected as too rudimentary/cartoonish. Its rendered
  outputs, sources, art bible, and report are retained in `assets_archive/wave0_v1/`.
- Revision 2 used 13 new-image calls: 3 direction boards and 10 canonical family masters.
- No generated heading, faction color, or animation frame was purchased separately.
- Three faction hull proofs, five rotation views, four muzzle frames, masks, exact-size exports,
  terrain seam fixes, and proof sheets are deterministic local derivatives.
- No image-edit calls or audio generations were used.
