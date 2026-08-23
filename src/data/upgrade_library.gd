class_name UpgradeLibrary
extends Object
## What gold buys.
##
## This is the half of the loop that makes a fight worth winning: you beat an
## island, you dig up gold, you spend it, and the next island is beatable. Without
## it the combat is a skill check with no memory.
##
## Every upgrade moves a number a [Ship] already reads, so nothing here needs
## special-casing in gameplay code — see [method apply]. Costs grow geometrically
## so the first point in anything is cheap enough to buy on your first payday.

## Order shown in the port. Cheapest and most legible first: a player who does not
## yet know what "rigging" means should still find "more hull" at the top.
const ORDER: Array[StringName] = [&"plating", &"gunnery", &"crew", &"rigging", &"lookout"]

const DEFS: Dictionary = {
	&"plating": {
		"name": "Hull Plating",
		"blurb": "Take more punishment before you sink.",
		"max_level": 4,
		"base_cost": 60,
		"cost_growth": 1.7,
		"per_level": {"max_hull": 22.0},
	},
	&"gunnery": {
		"name": "Gunnery",
		"blurb": "Every ball hits harder.",
		"max_level": 4,
		"base_cost": 75,
		"cost_growth": 1.8,
		"per_level": {"base_damage": 5.0},
	},
	&"crew": {
		"name": "Reload Crew",
		"blurb": "Shorter wait between broadsides.",
		"max_level": 3,
		"base_cost": 90,
		"cost_growth": 1.9,
		"per_level": {"reload_time": -0.5},
	},
	&"rigging": {
		"name": "Rigging",
		"blurb": "Faster, and turns more willingly.",
		"max_level": 3,
		"base_cost": 70,
		"cost_growth": 1.8,
		"per_level": {"max_speed": 10.0, "max_sails": 10.0, "turn_rate_deg": 4.0},
	},
	&"lookout": {
		"name": "Long Guns",
		"blurb": "Open fire from further out.",
		"max_level": 3,
		"base_cost": 110,
		"cost_growth": 1.9,
		"per_level": {"cannon_range": 60.0},
	},
}

## Floors, so no amount of upgrading can produce a nonsense ship.
const FIELD_MINIMUM: Dictionary = {"reload_time": 1.4}


static func display_name(id: StringName) -> String:
	return DEFS.get(id, {}).get("name", String(id))


static func blurb(id: StringName) -> String:
	return DEFS.get(id, {}).get("blurb", "")


static func max_level(id: StringName) -> int:
	return int(DEFS.get(id, {}).get("max_level", 0))


static func level_of(upgrades: Dictionary, id: StringName) -> int:
	return int(upgrades.get(id, 0))


## Cost of the next point in `id`, or -1 if it cannot be bought right now —
## because it is maxed, or because it has not been unlocked yet.
##
## Both reasons collapse into -1 deliberately: every caller already means "is
## there a price on this" by asking, and a locked line that quotes a price is a
## trap. It cost a harness run to find out — the ladder's shopper picks the
## cheapest thing on the shelf, Rigging was the cheapest thing on the shelf and
## was locked, and the purchase silently failed so it bought nothing at all and
## sailed on to the next island with 478 gold in the bank. A caller that wants to
## *show* a locked line (the port does, as a signpost) asks
## [method UnlockTable.upgrade_unlocked] and says so in words.
static func next_cost(upgrades: Dictionary, id: StringName) -> int:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty() or not UnlockTable.upgrade_unlocked(id):
		return -1
	var level: int = level_of(upgrades, id)
	if level >= int(def["max_level"]):
		return -1
	return int(round(float(def["base_cost"]) * pow(float(def["cost_growth"]), float(level))))


## Buys one point. Returns false and changes nothing if it is locked, maxed or
## unaffordable.
##
## The lock is checked here rather than only in the shop UI for the same reason
## the ammo lock is checked in [FleetController]: the port screen is not the only
## caller, and a gate that can be walked round is not a gate. See [UnlockTable].
static func purchase(upgrades: Dictionary, id: StringName) -> bool:
	if not UnlockTable.upgrade_unlocked(id):
		return false
	var cost: int = next_cost(upgrades, id)
	if cost < 0 or not GameState.spend_gold(cost):
		return false
	upgrades[id] = level_of(upgrades, id) + 1
	return true


## Folds an upgrade dictionary into a [ShipStats].
##
## Mutates in place, so callers **must** pass a duplicate — the library hands out
## one shared cached resource per hull id, and upgrading a player's Sloop must not
## quietly buff every Navy Sloop in the archipelago. See
## [method ShipStatsLibrary.build].
static func apply(stats: ShipStats, upgrades: Dictionary) -> void:
	for id: StringName in upgrades:
		var def: Dictionary = DEFS.get(id, {})
		if def.is_empty():
			continue
		var level: int = clampi(level_of(upgrades, id), 0, int(def["max_level"]))
		var per_level: Dictionary = def["per_level"]
		for field: String in per_level:
			var value: float = float(stats.get(field)) + float(per_level[field]) * float(level)
			if FIELD_MINIMUM.has(field):
				value = maxf(value, float(FIELD_MINIMUM[field]))
			stats.set(field, value)


## One-line summary of what a hull is carrying, for the port screen.
static func summarise(upgrades: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id: StringName in ORDER:
		var level: int = level_of(upgrades, id)
		if level > 0:
			parts.append("%s %d" % [display_name(id), level])
	return "No upgrades yet" if parts.is_empty() else ", ".join(parts)
