class_name ShipStatsLibrary
extends Object
## Lookup for hull types, mirroring [AmmoLibrary].
##
## The fallbacks are the current balance pass, expressed in code so the game is
## playable before the `.tres` files exist. Each one is a deliberate tradeoff, not
## a strict upgrade: a Galleon out-guns a Sloop and cannot turn inside it.

## Wave 0 art. Masters are exported at 2x nominal, so a hull whose nominal width
## matches its sprite renders at sprite_scale 0.5 — see docs/ASSETS.md §0.
const ART_SLOOP: String = "res://assets/wave0/ships/hull_sloop.png"
const ART_SKIFF: String = "res://assets/wave0/ships/hull_skiff.png"
## Nominal width of the sloop master, in world units. Every hull that borrows the
## sloop art scales relative to this until its own master exists.
const SLOOP_NOMINAL_WIDTH: float = 96.0

const PLAYER_ORDER: Array[StringName] = [&"dinghy", &"sloop", &"brig", &"galleon"]

const PATHS: Dictionary = {
	&"dinghy": "res://assets/data/ships/dinghy.tres",
	&"sloop": "res://assets/data/ships/sloop.tres",
	&"brig": "res://assets/data/ships/brig.tres",
	&"galleon": "res://assets/data/ships/galleon.tres",
	&"skiff": "res://assets/data/ships/skiff.tres",
	&"enemy_sloop": "res://assets/data/ships/enemy_sloop.tres",
	&"enemy_brig": "res://assets/data/ships/enemy_brig.tres",
}

static var _cache: Dictionary = {}


static func get_stats(id: StringName) -> ShipStats:
	if _cache.has(id):
		return _cache[id]

	var path: String = PATHS.get(id, "")
	var stats: ShipStats = null
	if not path.is_empty() and ResourceLoader.exists(path):
		stats = load(path) as ShipStats
	if stats == null:
		stats = _fallback(id)

	_cache[id] = stats
	return stats


## The hull one tier above `id`, or an empty StringName at the top of the tree.
static func next_tier(id: StringName) -> StringName:
	var idx: int = PLAYER_ORDER.find(id)
	if idx < 0 or idx >= PLAYER_ORDER.size() - 1:
		return &""
	return PLAYER_ORDER[idx + 1]


static func clear_cache() -> void:
	_cache.clear()


static func _fallback(id: StringName) -> ShipStats:
	var s := ShipStats.new()
	s.id = id

	match id:
		&"dinghy":
			s.display_name = "Dinghy"
			s.propulsion = ShipStats.Propulsion.OAR
			s.rig = ShipStats.Rig.FORE_AFT
			s.hull_grip = 4.2
			s.tier = 1
			# The starting hull. Tough enough that learning the broadside rule the
			# hard way costs a scare rather than the run.
			s.max_hull = 85.0
			s.max_sails = 40.0
			s.max_cannons_health = 30.0
			s.max_speed = 122.0
			s.acceleration = 58.0
			s.turn_rate_deg = 84.0
			s.cannons_per_side = 1
			s.cannon_range = 520.0
			s.reload_time = 4.0
			s.base_damage = 20.0
			s.hull_radius = 34.0
			s.tonnage = 45.0
			s.cargo_capacity = 100
		&"brig":
			s.display_name = "Brig"
			s.propulsion = ShipStats.Propulsion.SAIL
			s.rig = ShipStats.Rig.MIXED
			s.hull_grip = 2.4
			s.tier = 3
			s.max_hull = 190.0
			s.max_sails = 90.0
			s.max_cannons_health = 80.0
			s.max_speed = 94.0
			s.acceleration = 36.0
			s.turn_rate_deg = 46.0
			s.cannons_per_side = 4
			s.cannon_range = 700.0
			s.reload_time = 5.8
			s.base_damage = 28.0
			s.hull_radius = 58.0
			s.tonnage = 240.0
			s.cargo_capacity = 400
		&"galleon":
			s.display_name = "Galleon"
			s.propulsion = ShipStats.Propulsion.SAIL
			s.rig = ShipStats.Rig.SQUARE
			s.hull_grip = 1.8
			s.tier = 4
			s.max_hull = 300.0
			s.max_sails = 120.0
			s.max_cannons_health = 120.0
			s.max_speed = 80.0
			s.acceleration = 27.0
			s.turn_rate_deg = 32.0
			s.cannons_per_side = 6
			s.cannon_range = 780.0
			s.reload_time = 7.0
			s.base_damage = 32.0
			s.hull_radius = 74.0
			s.tonnage = 460.0
			s.cargo_capacity = 700
		&"skiff":
			s.display_name = "Skiff"
			s.propulsion = ShipStats.Propulsion.OAR
			s.rig = ShipStats.Rig.FORE_AFT
			s.hull_grip = 4.6
			s.tier = 1
			s.max_hull = 34.0
			s.max_sails = 26.0
			s.max_cannons_health = 20.0
			s.max_speed = 134.0
			s.acceleration = 68.0
			s.turn_rate_deg = 96.0
			s.cannons_per_side = 1
			s.cannon_range = 430.0
			s.reload_time = 4.6
			s.base_damage = 12.0
			s.hull_radius = 28.0
			s.tonnage = 30.0
			s.accent_color = Color(0.82, 0.62, 0.55)
		&"enemy_brig":
			s.display_name = "Navy Brig"
			s.propulsion = ShipStats.Propulsion.SAIL
			s.rig = ShipStats.Rig.MIXED
			s.hull_grip = 2.5
			s.tier = 3
			s.max_hull = 170.0
			s.max_sails = 85.0
			s.max_cannons_health = 75.0
			s.max_speed = 90.0
			s.acceleration = 34.0
			s.turn_rate_deg = 43.0
			s.cannons_per_side = 4
			s.cannon_range = 680.0
			s.reload_time = 6.2
			s.base_damage = 26.0
			s.hull_radius = 56.0
			s.tonnage = 230.0
			s.accent_color = Color(0.72, 0.74, 0.8)
		&"enemy_sloop":
			s.display_name = "Navy Sloop"
			s.propulsion = ShipStats.Propulsion.SAIL
			s.rig = ShipStats.Rig.FORE_AFT
			s.hull_grip = 3.0
			s.tier = 2
			s.max_hull = 95.0
			s.max_sails = 58.0
			s.max_cannons_health = 46.0
			s.max_speed = 105.0
			s.acceleration = 45.0
			s.turn_rate_deg = 60.0
			s.cannons_per_side = 2
			s.cannon_range = 600.0
			s.reload_time = 5.2
			s.base_damage = 22.0
			s.hull_radius = 46.0
			s.tonnage = 100.0
			s.accent_color = Color(0.78, 0.8, 0.86)
		_:
			s.id = &"sloop"
			s.display_name = "Sloop"
			s.propulsion = ShipStats.Propulsion.SAIL
			s.rig = ShipStats.Rig.FORE_AFT
			s.hull_grip = 3.0
			s.tier = 2
			# Field defaults on ShipStats are already the Sloop.

	_apply_art(s)
	return s


## Assigns the sprite and derives its scale from the hull's physical size, so a
## Brig borrowing the Sloop master still reads as a bigger ship. Wave 1 replaces
## the borrowed masters; the scale maths stays.
static func _apply_art(s: ShipStats) -> void:
	var path: String = ART_SKIFF if s.id == &"skiff" else ART_SLOOP
	if not ResourceLoader.exists(path):
		return

	s.hull_texture = load(path) as Texture2D
	if s.id == &"skiff":
		s.sprite_scale = 0.5
	else:
		# hull_radius is half the nominal width, so width = radius * 2.
		s.sprite_scale = 0.5 * (s.hull_radius * 2.0) / SLOOP_NOMINAL_WIDTH
