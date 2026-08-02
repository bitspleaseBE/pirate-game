extends Node
## The player's persistent and per-voyage state.
##
## Deliberately dumb: it holds numbers and emits when they change. All the rules
## about *when* those numbers change live in the systems that own the rule.

## Gold carried but not yet banked. Lost with the ship that carries it.
var carried_gold: int = 0
## Gold safely banked at a port. This is the real score.
var banked_gold: int = 0
var doubloons: int = 0

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

var stats_islands_captured: int = 0
var stats_ships_sunk: int = 0
var stats_voyages_completed: int = 0


func _ready() -> void:
	reset_run()


## Fresh save / new game.
func reset_run() -> void:
	carried_gold = 0
	banked_gold = 0
	doubloons = 0
	fleet_slots = 1
	fleet = [{"stats_id": &"sloop", "upgrades": {}}]
	ammo_stock = {&"fire": 6, &"explosive": 4, &"chain": 6, &"grape": 6}
	selected_ammo = &"round"
	voyage_seed = 0
	voyage_active = false
	island_progress.clear()
	stats_islands_captured = 0
	stats_ships_sunk = 0
	stats_voyages_completed = 0


func total_gold() -> int:
	return carried_gold + banked_gold


func add_gold(amount: int) -> void:
	if amount == 0:
		return
	carried_gold = maxi(0, carried_gold + amount)
	EventBus.gold_changed.emit(total_gold(), amount)


func add_doubloons(amount: int) -> void:
	if amount == 0:
		return
	doubloons = maxi(0, doubloons + amount)
	EventBus.doubloons_changed.emit(doubloons, amount)


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


func spend_doubloons(amount: int) -> bool:
	if doubloons < amount:
		return false
	doubloons -= amount
	EventBus.doubloons_changed.emit(doubloons, -amount)
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
			&"doubloon":
				add_doubloons(amount)
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
		"doubloons": doubloons,
		"fleet_slots": fleet_slots,
		"fleet": fleet,
		"ammo_stock": ammo_stock,
		"selected_ammo": String(selected_ammo),
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
	doubloons = int(data.get("doubloons", 0))
	fleet_slots = clampi(int(data.get("fleet_slots", 1)), 1, 3)

	var loaded_fleet: Array = data.get("fleet", [])
	if not loaded_fleet.is_empty():
		fleet.clear()
		for entry: Variant in loaded_fleet:
			if entry is Dictionary:
				fleet.append(entry)

	ammo_stock = data.get("ammo_stock", ammo_stock)
	selected_ammo = StringName(data.get("selected_ammo", "round"))
	voyage_seed = int(data.get("voyage_seed", 0))
	voyage_active = bool(data.get("voyage_active", false))
	island_progress = data.get("island_progress", {})

	var stats: Dictionary = data.get("stats", {})
	stats_islands_captured = int(stats.get("islands_captured", 0))
	stats_ships_sunk = int(stats.get("ships_sunk", 0))
	stats_voyages_completed = int(stats.get("voyages_completed", 0))

	EventBus.gold_changed.emit(total_gold(), 0)
	EventBus.doubloons_changed.emit(doubloons, 0)
	EventBus.fleet_changed.emit()
