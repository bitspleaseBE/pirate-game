extends Node
## The player's persistent and per-voyage state.
##
## Deliberately dumb: it holds numbers and emits when they change. All the rules
## about *when* those numbers change live in the systems that own the rule.

## Gold carried but not yet banked. Lost with the ship that carries it.
var carried_gold: int = 0
## Gold safely banked at a port. This is the real score.
var banked_gold: int = 0
var diamonds: int = 0

## How many ships the player may field. 1 to 3.
var fleet_slots: int = 1
## One entry per active ship: { stats_id: StringName, upgrades: Dictionary }
var fleet: Array[Dictionary] = []

## Ammo stock by ammo id. Round shot is unlimited and absent from here.
var ammo_stock: Dictionary = {}
var selected_ammo: StringName = &"round"

var voyage_seed: int = 0
var voyage_active: bool = false
## IslandDef.id -> { discovered: bool, captured: bool, treasure_dug: int }
var island_progress: Dictionary = {}

## Set the first time the player commands a sailed hull, so the wind is explained
## exactly once and never again.
var seen_wind_intro: bool = false
## Briefing ids already shown, so no explanation ever repeats. See
## [TutorialDirector].
var seen_briefings: Dictionary = {}

## The hull a player always has, however badly things went.
const STARTING_HULL: StringName = &"dinghy"

var stats_islands_captured: int = 0
var stats_ships_sunk: int = 0
var stats_voyages_completed: int = 0


func _ready() -> void:
	reset_run()


## Fresh save / new game.
func reset_run() -> void:
	carried_gold = 0
	banked_gold = 0
	diamonds = 0
	fleet_slots = 1
	# You start in an oared boat, so the first islands teach tap-to-move,
	# broadsides and the capture loop on a still sea. The wind arrives with your
	# first set of sails — see WindSystem.
	fleet = [{"stats_id": &"dinghy", "upgrades": {}}]
	ammo_stock = {&"fire": 6, &"explosive": 4, &"chain": 6, &"grape": 6}
	selected_ammo = &"round"
	voyage_seed = 0
	voyage_active = false
	island_progress.clear()
	seen_wind_intro = false
	seen_briefings.clear()
	stats_islands_captured = 0
	stats_ships_sunk = 0
	stats_voyages_completed = 0


func has_seen(briefing_id: StringName) -> bool:
	return bool(seen_briefings.get(briefing_id, false))


func mark_seen(briefing_id: StringName) -> void:
	seen_briefings[briefing_id] = true


## Guarantees the player owns at least one hull.
##
## Losing your fleet costs you the ships you were sailing, not the ability to
## play — you always get a dinghy back. This is also the backstop against a save
## whose fleet entry is empty or malformed: without it the voyage loads a world
## with no player ship in it, which presents as a game that boots to an empty sea
## and is deeply confusing to diagnose.
func ensure_fleet() -> void:
	var valid: Array[Dictionary] = []
	for entry: Dictionary in fleet:
		if String(entry.get("stats_id", "")).is_empty():
			continue
		valid.append(entry)

	if valid.is_empty():
		valid.append({"stats_id": STARTING_HULL, "upgrades": {}})
		Log.warn("Fleet was empty — issuing a %s" % STARTING_HULL, "GameState")

	fleet = valid


## Puts the player back on the water after the last hull afloat goes down.
##
## A wipe costs the ships and everything unbanked on them. It does not cost the
## bank, and it does not cost the ability to sail — see docs/GAME_DESIGN.md
## §Economy. [FleetController] drops each entry from [member fleet] as its hull
## sinks, so by the time the fleet is emptied the roster is empty too, and until
## this ran nothing put a hull back before the game returned to the menu.
##
## That is not a cosmetic gap. [method FleetController.spawn_fleet] spawns one
## ship per entry, so the next voyage began with no ship at all: no hull to
## steer, no centroid for the camera, and a HUD bound to nothing. It only
## reproduced through the live wipe path, because a save reloaded from disk goes
## through [method from_dict] and [method ensure_fleet] and heals itself on the
## way in — which is exactly why quitting and relaunching appeared to "fix" it.
func wipe_fleet() -> void:
	fleet = [{"stats_id": STARTING_HULL, "upgrades": {}}]
	# Belt and braces: the sinking hull already dropped its cargo, but a wipe is
	# the one moment the player must be certain nothing unbanked came home.
	lose_carried_gold()
	# Slots are a permanent purchase and survive; only the hulls in them are
	# consumable. PortScreen prices the next hull off `fleet.size()`, so a
	# rebuilt fleet costs the same as the first one did.
	EventBus.fleet_changed.emit()


func total_gold() -> int:
	return carried_gold + banked_gold


func add_gold(amount: int) -> void:
	if amount == 0:
		return
	carried_gold = maxi(0, carried_gold + amount)
	EventBus.gold_changed.emit(total_gold(), amount)


func add_diamonds(amount: int) -> void:
	if amount == 0:
		return
	diamonds = maxi(0, diamonds + amount)
	EventBus.diamonds_changed.emit(diamonds, amount)


## Called on arrival at a port. Moving gold from carried to banked is the
## player's only protection against a wipe, so it is an explicit act.
func bank_carried_gold() -> int:
	var moved: int = carried_gold
	banked_gold += moved
	carried_gold = 0
	if moved > 0:
		EventBus.gold_changed.emit(total_gold(), 0)
	return moved


## Everything unbanked is lost. Returns what was dropped, for the results screen.
func lose_carried_gold() -> int:
	var lost: int = carried_gold
	carried_gold = 0
	if lost > 0:
		EventBus.gold_changed.emit(total_gold(), -lost)
	return lost


func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	# Spending happens at a port, so banked gold is the wallet.
	if banked_gold < amount:
		return false
	banked_gold -= amount
	EventBus.gold_changed.emit(total_gold(), -amount)
	return true


func spend_diamonds(amount: int) -> bool:
	if diamonds < amount:
		return false
	diamonds -= amount
	EventBus.diamonds_changed.emit(diamonds, -amount)
	return true


func get_ammo(id: StringName) -> int:
	return int(ammo_stock.get(id, 0))


func add_ammo(id: StringName, amount: int) -> void:
	ammo_stock[id] = maxi(0, get_ammo(id) + amount)


## Consumes one round. Round shot is free, so it always succeeds.
func consume_ammo(id: StringName) -> bool:
	if id == &"round":
		return true
	var have: int = get_ammo(id)
	if have <= 0:
		return false
	ammo_stock[id] = have - 1
	return true


func apply_loot(loot: Dictionary) -> void:
	for kind: StringName in loot:
		var amount: int = int(loot[kind])
		match kind:
			&"gold":
				add_gold(amount)
			&"diamond":
				add_diamonds(amount)
			_:
				if String(kind).begins_with("ammo_"):
					add_ammo(StringName(String(kind).trim_prefix("ammo_")), amount)
	EventBus.loot_collected.emit(loot)


func mark_island(id: StringName, discovered: bool = true, captured: bool = false) -> void:
	var entry: Dictionary = island_progress.get(id, {"discovered": false, "captured": false, "treasure_dug": 0})
	entry["discovered"] = entry["discovered"] or discovered
	if captured and not entry["captured"]:
		entry["captured"] = true
		stats_islands_captured += 1
	island_progress[id] = entry


func is_island_captured(id: StringName) -> bool:
	return bool(island_progress.get(id, {}).get("captured", false))


func to_dict() -> Dictionary:
	return {
		"banked_gold": banked_gold,
		"carried_gold": carried_gold,
		"diamonds": diamonds,
		"fleet_slots": fleet_slots,
		"fleet": fleet,
		"ammo_stock": ammo_stock,
		"selected_ammo": String(selected_ammo),
		"seen_wind_intro": seen_wind_intro,
		"seen_briefings": seen_briefings,
		"voyage_seed": voyage_seed,
		"voyage_active": voyage_active,
		"island_progress": island_progress,
		"stats": {
			"islands_captured": stats_islands_captured,
			"ships_sunk": stats_ships_sunk,
			"voyages_completed": stats_voyages_completed,
		},
	}


func from_dict(data: Dictionary) -> void:
	reset_run()
	banked_gold = int(data.get("banked_gold", 0))
	carried_gold = int(data.get("carried_gold", 0))
	# Diamonds were called doubloons until the rename. Reading the old key keeps
	# anyone mid-voyage from having the one currency they cannot grind back reset
	# to zero — they only drop from outer islands and the castle.
	diamonds = int(data.get("diamonds", data.get("doubloons", 0)))
	fleet_slots = clampi(int(data.get("fleet_slots", 1)), 1, 3)

	var loaded_fleet: Array = data.get("fleet", [])
	if not loaded_fleet.is_empty():
		fleet.clear()
		for entry: Variant in loaded_fleet:
			if entry is Dictionary:
				fleet.append(entry)

	ammo_stock = data.get("ammo_stock", ammo_stock)
	selected_ammo = StringName(data.get("selected_ammo", "round"))
	seen_wind_intro = bool(data.get("seen_wind_intro", false))
	seen_briefings = data.get("seen_briefings", {})
	voyage_seed = int(data.get("voyage_seed", 0))
	voyage_active = bool(data.get("voyage_active", false))
	island_progress = data.get("island_progress", {})

	ensure_fleet()

	var stats: Dictionary = data.get("stats", {})
	stats_islands_captured = int(stats.get("islands_captured", 0))
	stats_ships_sunk = int(stats.get("ships_sunk", 0))
	stats_voyages_completed = int(stats.get("voyages_completed", 0))

	EventBus.gold_changed.emit(total_gold(), 0)
	EventBus.diamonds_changed.emit(diamonds, 0)
	EventBus.fleet_changed.emit()
