# Asset List

Everything the game needs, with the specs a generator (or an artist) needs to produce it
consistently. Kenney's CC0 packs in `inspiration/` are the style reference and the
placeholder source; the goal is to replace all of them with our own coherent set.

## 0. Art direction & technical spec

**Style:** premium stylized realism in strict top-down orthographic view. Believable naval
construction, natural tropical foliage, weathered materials, selective dark contact edges,
and restrained painterly texture. The work is illustrated rather than photographic, but it
must not read as toy-like, chibi, flat clip art, or overly cartoonish. It remains clear at
about 40 px on a phone.

**Why:** high-resolution canonical masters preserve convincing material and structural detail,
while deterministic downsampling, overlays, masks, and engine rotation keep identities stable
and the screen readable when many ships are present.

**Pipeline:** approved high-resolution raster masters for ships, organic props, painted UI,
textures, and complex VFX; SVG masters for simple geometry, masks, and small cloth cycles. The
catalog renders both to PNG at 2× nominal, then packs per-group atlases for import. Never ship
canonical masters.

| Rule | Value |
|---|---|
| World scale | 1 world unit = 1 px at zoom 1.0 |
| Terrain grid | 64 px (matches the Kenney reference) |
| Ship pivot | Centre of mass; **bow points up (−Y)** at rotation 0 |
| Prop pivot | Base centre (feet), so props sort by Y correctly |
| Alpha | Straight (not premultiplied) |
| Padding | 1 px transparent border on the sprite, 2 px in the atlas |
| Max atlas | 2048 × 2048 (WebGL2 safety floor) |
| Export | PNG-8 where the palette allows, else PNG-24; lossless import in Godot |
| Colour | sRGB |

**Recolour strategy:** each ship has one neutral material master plus an accent mask. Faction
color changes only painted trim, sail markings, and flags through a palette shader; it never
changes hull geometry, deck construction, or material texture. Only real silhouette differences
receive separate masters.

**Atlas groups:** `ships`, `vfx`, `terrain`, `props`, `chars`, `ui`, `icons`, `map`.

---

## 1. Ships & ship parts — atlas `ships`

Modular: hull + sail overlay + flag, composed at runtime. Damage states are overlays, not
separate hulls.

| Asset | Count | Nominal size (px) | Notes |
|---|---|---|---|
| `hull_dinghy` | 1 | 64 × 96 | Player tier 1 |
| `hull_sloop` | 1 | 96 × 160 | Player tier 2 / standard enemy |
| `hull_brig` | 1 | 140 × 224 | Player tier 3 / heavy enemy |
| `hull_galleon` | 1 | 180 × 320 | Player tier 4 |
| `hull_skiff` | 1 | 48 × 72 | Swarm enemy |
| `hull_bombketch` | 1 | 110 × 150 | Wide, stubby, mortar pit visible on deck |
| `hull_fireship` | 1 | 90 × 150 | Charred, barrels lashed to deck |
| `hull_longboat` | 1 | 32 × 56 | Landing party |
| `hull_damage_overlay` | 3 | match hulls | Light / heavy / critical — scorch + hull breach |
| `sail_small` / `_med` / `_large` | 3 | 64/110/170 sq | Sails-up state |
| `sail_*_furled` | 3 | ″ | Anchored / becalmed |
| `sail_*_torn` | 3 | ″ | Chain-shot damage state |
| `flag_wave` | 2 frames | 24 × 32 | Recoloured per faction |
| `flag_jollyroger` | 2 frames | 24 × 32 | Skull motif |
| `cannon_mount` | 3 | 20 × 32 → 32 × 56 | Short / medium / long, side-mounted |
| `mortar_pit` | 1 | 40 × 40 | Bomb ketch |
| `deck_wheel`, `deck_capstan`, `deck_hatch`, `deck_crates`, `deck_barrels` | 5 | 24–48 sq | Deck dressing |
| `wreck_frames` | 6 frames | match hull | Sinking animation, hull-agnostic silhouette |
| `wake_strip` | 1 | 64 × 256 | Vertically tileable, alpha-faded tail |
| `wake_foam` | 4 frames | 48 × 48 | Bow foam |

**Subtotal: ~45 sprites + 3 sheets.**

## 2. Projectiles & ordnance — atlas `vfx`

| Asset | Count | Size (px) | Notes |
|---|---|---|---|
| `ball_round` | 1 | 12 sq | |
| `ball_shadow` | 1 | 16 sq | Soft dark ellipse, scaled by ball altitude |
| `ball_fire` | 4 frames | 16 sq | Flickering |
| `ball_explosive` | 1 | 14 sq | Fuse spark |
| `ball_chain` | 2 frames | 24 × 12 | Two balls + chain, spins |
| `shot_grape` | 1 | 20 sq | Cluster |
| `bomb_mortar` | 1 | 18 sq | Lobbed, larger shadow |
| `trail_puff` | 4 frames | 16 sq | Faint smoke behind a ball |

**Subtotal: 8 assets / 15 frames.**

## 3. VFX sheets & particle textures — atlas `vfx`

| Asset | Frames | Cell (px) | Notes |
|---|---|---|---|
| `fx_muzzleflash` | 4 | 64 | Directional, fires along +X |
| `fx_splash_small` | 6 | 48 | Missed shot |
| `fx_splash_large` | 6 | 96 | Mortar / sinking |
| `fx_impact_wood` | 5 | 64 | Splinters |
| `fx_explosion` | 8 | 128 | Explosive shot / fireship |
| `fx_fire_loop` | 6 | 64 | Burning ship, loops |
| `fx_smoke_plume` | 8 | 96 | Rises, loops |
| `fx_sink_whirl` | 8 | 128 | Ship going down |
| `fx_ripple_ring` | 6 | 96 | Expanding ring, used for AoE telegraphs too |
| `fx_boarding_clash` | 6 | 64 | Sword sparks |
| `fx_sparkle` | 6 | 48 | Treasure / reward |
| `fx_flag_raise` | 8 | 64 | Island capture flourish |
| `fx_dust_dig` | 5 | 48 | Landing party digging |
| **Particle textures** | | | Single frames for GPUParticles2D |
| `p_droplet`, `p_foam`, `p_ember`, `p_smoke_soft`, `p_spark`, `p_splinter` | 6 | 32 sq | |

**Subtotal: 13 sheets (~82 frames) + 6 particle textures.**

## 4. Ocean — shader inputs, not sprites

The ocean is one camera-locked shader quad (see ARCHITECTURE.md), so it needs data
textures rather than art.

| Asset | Size | Notes |
|---|---|---|
| `water_flow_tile` | 512 sq, seamless | RG flow / fake normal |
| `water_detail_tile` | 512 sq, seamless | Subtle value break-up |
| `water_caustic_tile` | 256 sq, seamless | Shallow-water sparkle |
| `ramp_water_depth` | 256 × 1 | Deep → shallow → shore colour ramp |
| `ramp_foam` | 128 × 1 | Foam alpha falloff |
| `shore_foam_strip` | 128 × 32, h-tileable | Animated band along island edges |

**Subtotal: 6 textures.**

## 5. Terrain fills & edges — atlas `terrain`

Islands are polygons filled with a tiling texture (not a tilemap), so we need fills and
edge brushes rather than a 47-piece autotile set. This is a large saving.

| Asset | Size | Notes |
|---|---|---|
| `fill_sand` | 256 sq, seamless | |
| `fill_grass` | 256 sq, seamless | |
| `fill_jungle` | 256 sq, seamless | Darker, denser |
| `fill_rock` | 256 sq, seamless | |
| `fill_snow` | 256 sq, seamless | Late-voyage biome |
| `edge_shore` | 128 × 48, h-tileable | Sand → water transition |
| `edge_cliff` | 128 × 64, h-tileable | Rock → water, with drop shadow |
| `edge_grass_sand` | 128 × 32, h-tileable | Inner biome boundary |
| `path_dirt` | 64 sq, seamless | Landing-party trail |

**Subtotal: 9 textures.** *(If we later want interior detail tiles, a 16-piece Wang set
per biome would be +64 — deferred.)*

## 6. Island props & structures — atlas `props`

| Asset | Count | Size (px) | Notes |
|---|---|---|---|
| `palm` | 4 | 64 × 96 | Variants, 2-frame sway optional |
| `bush`, `fern`, `grass_tuft` | 6 | 32–48 | |
| `rock` | 5 | 32–96 | |
| `driftwood`, `bones`, `skull_ground` | 3 | 32–48 | Set dressing |
| `hut` | 3 | 96 sq | Neutral village |
| `tent`, `campfire` (4f), `cookpot` | 3 | 48–64 | |
| `barrel`, `crate`, `sack`, `net` | 4 | 32–48 | |
| `dock_plank_straight` / `_corner` / `_end` | 3 | 64 sq | Assemble jetties |
| `dock_post`, `dock_ladder` | 2 | 24 × 40 | |
| `beach_wreck` | 2 | 128 × 96 | Landmark |
| `treasure_mound` | 1 | 64 sq | Before digging |
| `treasure_hole` | 1 | 64 sq | After |
| `x_marks_spot` | 1 | 48 sq | Painted on ground |
| `signpost` | 1 | 32 × 48 | |
| `cannon_emplacement` | 1 | 64 sq + 48 barrel | Rotating barrel is a separate sprite |
| `watchtower` | 1 | 64 × 112 | |
| `shipyard` | 1 | 160 × 128 | Destructible objective; 2 damage states |
| `castle_wall_straight` / `_corner` / `_gate` | 3 | 96 sq | 9-slice-ish assembly |
| `castle_tower` | 1 | 112 × 144 | |
| `castle_keep` | 1 | 224 × 224 | Boss; 3 damage states |
| `castle_battery` | 1 | 80 sq + barrel | Boss weak point |
| `flagpole` + `flag_island` (2f) | 2 | 24 × 80 | Flips on capture |
| `shadow_blob` | 1 | 64 sq | Reused + tinted for every prop |

**Subtotal: ~55 sprites + a few damage states.**

## 7. Characters — atlas `chars`

Top-down, 8 directions is too expensive; use 4 directions with a mirrored pair (so 3
authored sets: down, up, side).

| Asset | Frames | Cell (px) | Notes |
|---|---|---|---|
| `pirate_walk` | 3 dirs × 4 | 32 × 40 | Landing party |
| `pirate_idle` | 3 dirs × 2 | ″ | |
| `pirate_dig` | 4 | ″ | Side view only |
| `pirate_carry_walk` | 3 dirs × 4 | ″ | Hauling the chest |
| `pirate_row` | 4 | ″ | In the longboat |
| `soldier_walk` | 3 dirs × 4 | 32 × 40 | Fort garrison |
| `soldier_fire` | 2 | ″ | |
| `captain_portrait` | 4 | 128 sq | UI only; one per ship tier |

**Subtotal: ~70 frames + 4 portraits.**

## 8. Treasure & pickups — atlas `props`

| Asset | Frames | Size (px) | Notes |
|---|---|---|---|
| `chest_closed` / `_open` | 2 | 48 sq | |
| `coin_spin` | 6 | 24 sq | |
| `diamond_spin` | 6 | 28 sq | Distinct silhouette from coin |
| `gem` | 4 | 24 sq | Colour variants |
| `crate_ammo` | 5 | 40 sq | One per shot type, icon stencilled on the lid |
| `kit_repair` | 1 | 40 sq | |
| `pickup_life` | 1 | 32 sq | |
| `bottle_boost` | 4 | 32 sq | One per boost |
| `scroll_blueprint` | 1 | 40 sq | |
| `map_fragment` | 1 | 40 sq | |
| `floating_debris` | 4 | 32 sq | Post-sinking loot marker |

**Subtotal: ~30 assets / 40 frames.**

## 9. UI frames & widgets — atlas `ui`

| Asset | Count | Notes |
|---|---|---|
| `panel_parchment` | 3 | 9-slice; small / medium / full-screen |
| `panel_wood` | 1 | 9-slice; HUD backing |
| `panel_rope_frame` | 1 | 9-slice; decorative border |
| `button_brass` | 3 states × 3 shapes | Round / rect / square × up / down / disabled |
| `button_ghost` | 3 states | Low-emphasis |
| `toggle_track` + `toggle_knob` | 2 | |
| `slider_track` + `slider_knob` | 2 | |
| `tab_active` / `_inactive` | 2 | 9-slice |
| `bar_frame` + `bar_fill` | 2 + 4 | Fill tints: hull red, sail cream, cannon steel, xp gold |
| `bar_mini_frame` + `_fill` | 2 | Over-ship health pips |
| `card_upgrade` | 1 | 9-slice, parchment + rope |
| `ribbon_banner` | 2 | Reward / warning headers |
| `burst_reward` | 1 | Radial rays behind loot popups |
| `tooltip_bubble` | 1 | 9-slice with tail |
| `reticle_target` | 4 frames | Animated lock-on |
| `marker_waypoint` | 4 frames | Tap destination |
| `ring_selection` | 4 frames | Under selected ship |
| `ripple_tap` | 4 frames | Touch feedback |
| `arc_broadside` | 1 | Firing-arc cone, additive |
| `telegraph_circle` | 1 | Incoming mortar / AoE, animated by shader |
| `compass_rose` | 1 | 96 sq |
| `wind_indicator` | 1 | 64 sq, arrow rotates |
| `joystick_ring` + `_knob` | 2 | Optional alternate control scheme |
| `fleet_badge` | 3 | 1 / 2 / 3 ship slots |

**Subtotal: ~50 assets, ~35 of them 9-slice.**

## 10. Icons — atlas `icons`

Flat, two-tone, 64 px square, designed on a 4 px grid so they stay crisp at 24 px.

Economy: `gold`, `diamond`, `gem`, `chest`
Ship: `hull`, `sail`, `cannon`, `anchor`, `wheel`, `crew`, `cargo`, `speed`, `turn`
Ammo: `shot_round`, `shot_fire`, `shot_explosive`, `shot_chain`, `shot_grape`
Actions: `ram`, `board`, `repair`, `fire`, `retreat`
Upgrades: `plating`, `rigging`, `reload`, `magazine`, `lookout`, `carpenter`
World: `island`, `port`, `shipyard`, `castle`, `map`, `x_mark`, `fog`, `route`
Status: `heart`, `skull`, `flag`, `burning`, `crippled`, `boost`, `shield`
System: `settings`, `sound_on`, `sound_off`, `music_on`, `music_off`, `pause`, `play`,
`fast_forward`, `back`, `home`, `retry`, `close`, `info`, `plus`, `minus`, `lock`,
`check`, `warning`, `star`

**Subtotal: ~58 icons.**

## 11. Treasure-map layer — atlas `map`

| Asset | Notes |
|---|---|
| `map_parchment` | 1024 sq, seamless-ish, aged paper |
| `map_torn_edge` | Mask, 9-slice |
| `map_compass` | 64 sq, hand-drawn look |
| `map_ship_icon` | 3 — player / ally / captured |
| `map_skull` | Enemy contact |
| `map_x` | Buried treasure |
| `map_port_pin` | Captured island |
| `map_fog_tile` | 128 sq, seamless cloud |
| `map_route_dash` | 16 × 4, tileable dashed line |
| `map_island_stroke` | Brush texture for polygon outlines |

**Subtotal: 12 assets.**

## 12. Fonts

| Role | Requirement |
|---|---|
| Display / titles | Heavy, nautical or slab. Latin + Latin-Ext. Used at 32–96 px. |
| UI body | Rounded geometric sans, legible at 14 px on a phone. Latin + Latin-Ext. |
| Numerals | Tabular figures for counters that must not jitter. Can be a variant of the body font. |

Kenney Future / Kenney Future Narrow (in `inspiration/kenney_ui-pack/Font/`) are usable
stand-ins for both roles. Licensing must be checked before shipping any replacement.

## 13. SFX

Format: OGG Vorbis, mono for spatial sounds, 44.1 kHz, normalised to −3 dBFS peak.
Every repeated sound needs **3–4 variations** to avoid machine-gun repetition.

**Guns & impacts:** cannon fire (×4), cannon distant echo, mortar launch, mortar whistle,
ball whoosh-by (×3), impact wood (×4), impact stone (×3), splash small (×4), splash large,
explosion (×3), fire ignite, fire loop, chain-shot rip, grape scatter, ricochet (×2)

**Ship:** hull creak (×3), rigging creak, sail unfurl, sail tear, anchor drop, anchor
raise, hull scrape on rock, ram crunch (×2), sinking groan, sinking gurgle, bilge pump

**Water & world:** ocean ambience loop, shore ambience loop, gull cry (×3), bow wake loop,
wind gust (×2), rain loop (if weather ships)

**Crew:** shout on hit (×4), cheer on kill (×3), "land ho" (×2), row loop, dig (×3),
chest open, boarding clash (×4)

**UI & rewards:** tap, confirm, cancel, tab switch, purchase, upgrade applied, coin pickup
(×3), diamond pickup, loot fanfare (small / big), level up, island captured, map open /
close, error buzz, warning klaxon, boss horn

**Subtotal: ~95 files (≈45 distinct sounds with variants).**

## 14. Music

| Track | Use | Notes |
|---|---|---|
| `mus_menu` | Title | Solo accordion + strings |
| `mus_sail_calm` | At sea, no threat | Loopable bed |
| `mus_sail_tense` | Enemies in lookout range | Same key, layer in |
| `mus_combat` | Active fight | Percussion + full shanty |
| `mus_boss` | Castle assault | |
| `mus_victory_sting` | Island captured | 4 s, non-looping |
| `mus_defeat_sting` | Fleet lost | 4 s |
| `mus_port` | Port / upgrade screen | Tavern, warm |

Author calm / tense / combat as **stems in the same key and tempo** so they crossfade
without a musical seam.

**Subtotal: 8 tracks (5 loops, 2 stings, 1 menu).**

## 15. Store & platform assets

| Asset | Spec |
|---|---|
| App icon | 1024 sq, no alpha, no rounded corners |
| Android adaptive icon | Foreground 432 sq + background 432 sq |
| iOS icon set | Generated from the 1024 |
| Web favicon | 16 / 32 / 180 / 192 / 512 |
| Splash screen | 1920 × 1080, safe-area-centred logo |
| Logo lockup | Horizontal + stacked, SVG |
| OG / share image | 1200 × 630 |
| Screenshots | 6 per store, phone + tablet |
| Trailer stills | 3 key art frames |

---

## Totals

| Group | Assets | Frames / textures |
|---|---|---|
| Ships & parts | 45 | ~70 |
| Projectiles | 8 | 15 |
| VFX | 19 | ~88 |
| Ocean | 6 | 6 |
| Terrain | 9 | 9 |
| Props & structures | 55 | ~65 |
| Characters | 8 sets | ~74 |
| Pickups | 30 | 40 |
| UI | 50 | ~60 |
| Icons | 58 | 58 |
| Map | 12 | 12 |
| **Art total** | **~300** | **~500** |
| SFX | 45 distinct | ~95 files |
| Music | 8 | 8 |
| Store | 9 | ~25 |

## Generation priority

Build in these waves so the game is playable and *looks* intentional as early as possible.

**Wave 1 — vertical slice (≈45 assets)**
`hull_sloop`, `hull_skiff`, `sail_med`, `flag_wave`, `cannon_mount`, `ball_round`,
`ball_shadow`, `fx_muzzleflash`, `fx_splash_small`, `fx_impact_wood`, `fx_explosion`,
`wake_strip`, water textures + ramps, `fill_sand`, `fill_grass`, `edge_shore`, `palm`×2,
`rock`×2, `treasure_mound`, `x_marks_spot`, `chest_closed/open`, `coin_spin`,
`panel_parchment`, `button_brass`, `bar_frame`+`bar_fill`, `reticle_target`,
`marker_waypoint`, `ring_selection`, map parchment + `map_x` + `map_ship_icon`, ~12 core
icons.

**Wave 2 — full island loop**
Remaining hulls, `shipyard`, `cannon_emplacement`, landing-party character set, remaining
pickups, port UI, full icon set.

**Wave 3 — boss & polish**
Castle set, `hull_bombketch`, `hull_fireship`, remaining VFX, biome fills, all damage
states, music stems.

**Wave 4 — ship it**
Store assets, extra prop variants, SFX variation passes.
