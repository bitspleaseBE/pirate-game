class_name AmmoLibrary
extends Object
## Lookup for the five shot types.
##
## **Right now the code tables at the bottom of this file are the balance.** The
## `.tres` files under `assets/data/ammo/` do not exist yet; when they do they
## take precedence and the code tables become a safety net for a missing or
## mid-edit resource. Until then, tune here.
##
## Two sources of truth is a maintenance trap, so this is deliberately one-way:
## a `.tres` always wins, and the day the first one is authored is the day this
## file stops being where you change numbers.

const ORDER: Array[StringName] = [&"round", &"fire", &"explosive", &"chain", &"grape"]

const ICON_ROUND: Texture2D = preload("res://assets/wave1/icons/icon_shot_round.png")
const ICON_FIRE: Texture2D = preload("res://assets/wave1/icons/icon_fire.png")
const ICON_CANNON: Texture2D = preload("res://assets/wave1/icons/icon_cannon.png")
const ICON_SAIL: Texture2D = preload("res://assets/wave1/icons/icon_sail.png")

const PATHS: Dictionary = {
	&"round": "res://assets/data/ammo/round.tres",
	&"fire": "res://assets/data/ammo/fire.tres",
	&"explosive": "res://assets/data/ammo/explosive.tres",
	&"chain": "res://assets/data/ammo/chain.tres",
	&"grape": "res://assets/data/ammo/grape.tres",
}

static var _cache: Dictionary = {}


static func get_ammo(id: StringName) -> AmmoType:
	if _cache.has(id):
		return _cache[id]

	var path: String = PATHS.get(id, "")
	var ammo: AmmoType = null
	if not path.is_empty() and ResourceLoader.exists(path):
		ammo = load(path) as AmmoType
	if ammo == null:
		# Expected for now — the code tables below are still the source of truth.
		# This becomes a warning once the .tres files land.
		ammo = _fallback(id)
		Log.debug("Ammo '%s' has no .tres yet — using code table" % id, "AmmoLibrary")

	_cache[id] = ammo
	return ammo


static func all() -> Array[AmmoType]:
	var out: Array[AmmoType] = []
	for id: StringName in ORDER:
		out.append(get_ammo(id))
	return out


## Next shot type the player has stock for, wrapping around. Skipping empty types
## means the cycle button never lands on something that cannot fire.
static func next_available(current: StringName) -> StringName:
	var start: int = maxi(0, ORDER.find(current))
	for step: int in range(1, ORDER.size() + 1):
		var candidate: StringName = ORDER[(start + step) % ORDER.size()]
		var ammo: AmmoType = get_ammo(candidate)
		if ammo.unlimited or GameState.get_ammo(candidate) > 0:
			return candidate
	return &"round"


static func clear_cache() -> void:
	_cache.clear()


static func _fallback(id: StringName) -> AmmoType:
	var a := AmmoType.new()
	a.id = id
	match id:
		&"fire":
			a.display_name = "Fire Shot"
			a.icon = ICON_FIRE
			a.role = "burns hulls"
			a.tint = Color(1.0, 0.55, 0.22)
			a.visual_scale = 1.05
			a.damage_mul = 0.55
			a.burn_dps = 5.0
			a.burn_duration = 5.0
			a.muzzle_speed = 640.0
			a.max_stock = 12
		&"explosive":
			a.display_name = "Explosive Shot"
			a.icon = ICON_FIRE
			a.role = "hits groups"
			a.tint = Color(0.95, 0.82, 0.35)
			a.visual_scale = 1.25
			a.damage_mul = 1.3
			a.aoe_radius = 170.0
			a.splash_bar_mul = 0.3
			a.reload_mul = 1.6
			a.muzzle_speed = 580.0
			a.arc_height = 60.0
			a.impact_pool = &"explosion"
			a.max_stock = 8
		&"chain":
			a.display_name = "Chain Shot"
			a.icon = ICON_SAIL
			a.role = "shreds sails"
			a.tint = Color(0.72, 0.78, 0.86)
			a.visual_scale = 1.35
			a.damage_mul = 1.6
			a.primary_bar = AmmoType.Bar.SAILS
			a.muzzle_speed = 620.0
			a.range_mul = 0.85
			a.max_stock = 12
		&"grape":
			a.display_name = "Grape Shot"
			a.icon = ICON_CANNON
			a.role = "kills crew"
			a.tint = Color(0.86, 0.62, 0.66)
			a.visual_scale = 0.7
			a.damage_mul = 1.1
			a.primary_bar = AmmoType.Bar.CANNONS
			a.crew_kill = 0.12
			a.range_mul = 0.45
			a.muzzle_speed = 760.0
			a.arc_height = 20.0
			a.max_stock = 12
		_:
			a.display_name = "Round Shot"
			a.icon = ICON_ROUND
			a.role = "all-purpose"
			a.tint = Color(0.85, 0.85, 0.88)
			a.damage_mul = 1.0
			a.unlimited = true
	return a
