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
## The sail overlay. docs/ASSETS.md §Ships: "Modular: hull + sail overlay + flag,
## composed at runtime." Wave 0 delivered this master and nothing ever loaded it —
## [member ShipStats.sail_texture] was declared and referenced by no line in the
## project, so every hull in the game has been sailing under bare poles.
const ART_SAIL: String = "res://assets/wave0/ships/sail_med.png"
## Nominal width of each master, in world units. Every hull that borrows one
## scales relative to it until its own master exists.
const SLOOP_NOMINAL_WIDTH: float = 96.0
const SKIFF_NOMINAL_WIDTH: float = 56.0
## Small hulls that borrow the skiff master rather than the sloop's.
const SKIFF_ART_HULLS: Array[StringName] = [&"skiff", &"fireship"]

const PLAYER_ORDER: Array[StringName] = [&"dinghy", &"sloop", &"brig", &"galleon"]

const PATHS: Dictionary = {
	&"dinghy": "res://assets/data/ships/dinghy.tres",
	&"sloop": "res://assets/data/ships/sloop.tres",
	&"brig": "res://assets/data/ships/brig.tres",
	&"galleon": "res://assets/data/ships/galleon.tres",
	&"skiff": "res://assets/data/ships/skiff.tres",
	&"enemy_sloop": "res://assets/data/ships/enemy_sloop.tres",
	&"enemy_brig": "res://assets/data/ships/enemy_brig.tres",
	&"fireship": "res://assets/data/ships/fireship.tres",
	&"bomb_ketch": "res://assets/data/ships/bomb_ketch.tres",
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


## A hull with its upgrades folded in, ready to hand to a [Ship].
##
## Always a duplicate when upgrades are present. [method get_stats] returns one
## shared cached resource per hull id, so applying upgrades to it directly would
## buff every other ship of that type in the world — including the enemy's.
## Un-upgraded hulls share the cached copy, which is safe because a Ship only ever
## reads its stats, and matters because enemies spawn in waves.
static func build(stats_id: StringName, upgrades: Dictionary) -> ShipStats:
	var base: ShipStats = get_stats(stats_id)
	if upgrades == null or upgrades.is_empty():
		return base
	var owned: ShipStats = base.duplicate(true) as ShipStats
	UpgradeLibrary.apply(owned, upgrades)
	return owned


## Gold price of the next hull up from `id`, or -1 if there is none.
static func upgrade_cost(id: StringName) -> int:
	var idx: int = PLAYER_ORDER.find(id)
	if idx < 0 or idx >= PLAYER_ORDER.size() - 1:
		return -1
	# Steep, because a new hull is a bigger jump than any single upgrade and
	# should feel like the thing you save up for.
	const HULL_PRICES: Array[int] = [260, 700, 1600]
	return HULL_PRICES[idx]


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
			s.reload_time = 2.2
			s.base_damage = 15.0
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
			s.reload_time = 3.3
			s.base_damage = 21.0
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
			s.reload_time = 4.0
			s.base_damage = 24.0
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
			s.reload_time = 2.8
			s.base_damage = 9.0
			s.hull_radius = 28.0
			s.tonnage = 30.0
			s.bounty_gold = 14
			s.doctrine = ShipStats.Doctrine.SWARM
			# Inside your arc rather than politely out on the edge of it. A skiff
			# is cheap and expendable and it knows it — that is the whole reason
			# it is frightening in a pack and pathetic alone.
			s.engage_range_mul = 0.34
			s.accent_color = Color(0.82, 0.62, 0.55)
		&"fireship":
			# Not a warship: a hull packed with powder and steered by men who plan
			# to swim home. It has no guns at all, so nothing about it is a duel —
			# it is a timer sailing at you, and the only questions are whether you
			# can kill it first and which way you turn if you cannot.
			s.display_name = "Fireship"
			s.propulsion = ShipStats.Propulsion.OAR
			s.rig = ShipStats.Rig.FORE_AFT
			s.doctrine = ShipStats.Doctrine.RAMMER
			s.hull_grip = 3.4
			s.tier = 2
			# Glass. Two clean hits from a Sloop put it down, which is exactly the
			# margin that makes "shoot it or dodge it" a real decision rather than
			# a formality in either direction.
			s.max_hull = 46.0
			s.max_sails = 20.0
			s.max_cannons_health = 10.0
			s.max_speed = 148.0
			s.acceleration = 74.0
			# Quick, but not quick enough to follow a hull that commits to a turn.
			# This number *is* the dodge window.
			s.turn_rate_deg = 62.0
			s.cannons_per_side = 0
			s.cannon_range = 0.0
			s.reload_time = 1.0
			s.base_damage = 0.0
			# Enough to take most of a Sloop with it. A fireship that reaches you
			# has to be a disaster, or shooting it off is optional — and this is
			# the one enemy in the game whose counterplay is entirely a matter of
			# having noticed it in time.
			s.detonation_damage = 70.0
			s.detonation_radius = 210.0
			s.hull_radius = 30.0
			s.tonnage = 40.0
			s.bounty_gold = 45
			s.accent_color = Color(0.95, 0.55, 0.32)
		&"bomb_ketch":
			# The reason an island can have an approach worth surviving. It
			# out-ranges every hull in the game and lobs shells you can see coming,
			# so it cannot be traded with — it has to be closed on, and closing on
			# it means eating whatever else the garrison is doing meanwhile.
			s.display_name = "Bomb Ketch"
			s.propulsion = ShipStats.Propulsion.SAIL
			s.rig = ShipStats.Rig.SQUARE
			s.doctrine = ShipStats.Doctrine.MORTAR
			s.hull_grip = 2.6
			s.tier = 4
			s.max_hull = 88.0
			s.max_sails = 50.0
			s.max_cannons_health = 40.0
			# Slow and clumsy: once you are alongside it is helpless, which is the
			# payoff for having crossed the water it was shelling.
			s.max_speed = 76.0
			s.acceleration = 28.0
			s.turn_rate_deg = 34.0
			s.cannons_per_side = 1
			s.cannon_range = 1250.0
			s.reload_time = 6.5
			s.base_damage = 26.0
			s.hull_radius = 44.0
			s.tonnage = 110.0
			s.bounty_gold = 70
			s.accent_color = Color(0.7, 0.68, 0.58)
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
			s.reload_time = 3.5
			s.base_damage = 19.0
			s.hull_radius = 56.0
			s.tonnage = 230.0
			s.bounty_gold = 85
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
			s.reload_time = 3.0
			s.base_damage = 16.0
			s.hull_radius = 46.0
			s.tonnage = 100.0
			s.bounty_gold = 38
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
	var small: bool = s.id in SKIFF_ART_HULLS
	var path: String = ART_SKIFF if small else ART_SLOOP
	if not ResourceLoader.exists(path):
		return

	s.hull_texture = load(path) as Texture2D
	# hull_radius is half the nominal width, so width = radius * 2. Scaling every
	# hull off its own physical size means a borrowed master still reads at the
	# right size — a Fireship is visibly a launch, not a Sloop painted orange.
	var nominal: float = SKIFF_NOMINAL_WIDTH if small else SLOOP_NOMINAL_WIDTH
	s.sprite_scale = 0.5 * (s.hull_radius * 2.0) / nominal

	# Only what actually carries canvas. An oared hull with a sail on it would be
	# a lie about the one stat that matters most on this resource — the Dinghy,
	# the Skiff and the Fireship are rowed, they ignore the wind entirely, and
	# their whole identity is that they are not sailing ships. It also makes the
	# first Sloop a visible promotion rather than a number in a shop.
	if not s.is_oared() and ResourceLoader.exists(ART_SAIL):
		s.sail_texture = load(ART_SAIL) as Texture2D
