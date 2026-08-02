# Asset tools

These scripts run in an isolated Godot project so they do not load gameplay autoloads.

From the repository root:

```sh
godot --headless --path tools/assets --script render_assets.gd
godot --headless --path tools/assets --script validate_assets.gd
godot --headless --path tools/assets --script make_wave0_proofs.gd
godot --headless --path tools/assets --script make_wave1_proofs.gd
```

`render_assets.gd` reads `assets_src/catalog.json`, renders SVG sources and converts approved
high-resolution raster masters at the configured 2× scale. It also applies deterministic accent
recolors, builds the hull mask and cannon icon, derives the muzzle sequence, and fixes terrain
seams before writing loose PNGs under `assets/wave0/`.

`validate_assets.gd` checks unique IDs, output existence, dimensions, the 2048 px safety
limit, and transparent outer borders for sprite entries.

`make_wave0_proofs.gd` generates the contact sheet, 40 px readability comparison, sloop
rotation proof, and a gameplay composition made only from the rendered canonical PNGs.

`make_wave1_proofs.gd` generates the Wave 1 contact sheet, 40 px readability comparison,
and composed vertical-slice proof. `catalog.json` schema 3 includes
`assets_src/catalog_wave1.json`; compact sequence definitions expand to loose deterministic
frames during rendering and validation.

The source directory contains `.gdignore`; canonical SVG/raster masters and generated concept
references must not be imported or shipped by the main game project.
