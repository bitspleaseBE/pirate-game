class_name LootTable
extends Resource
## Weighted loot roll.
##
## Kept as data so drop rates can be tuned without a code change, and so the
## distribution can be unit-tested (see tests/test_loot_table.gd) instead of
## being discovered by players.

@export var id: StringName = &"island_tier_1"
## Each entry: { kind: StringName, weight: float, min: int, max: int }
## `kind` is one of: gold, doubloon, ammo_round, ammo_fire, ammo_explosive,
## ammo_chain, ammo_grape, repair_kit, life, boost, blueprint, map_fragment
@export var entries: Array[Dictionary] = []
## How many independent rolls one chest makes.
@export_range(1, 6) var roll_count: int = 2
## Always granted on top of the rolls, scaled by island tier.
@export var guaranteed_gold: int = 40


## Rolls the table. `rng` is passed in so a voyage seed produces reproducible
## loot, which matters for both testing and for players comparing seeds.
func roll(rng: RandomNumberGenerator, tier: int = 1) -> Dictionary:
	var result: Dictionary = {}
	if guaranteed_gold > 0:
		result[&"gold"] = guaranteed_gold * tier

	var total_weight: float = 0.0
	for entry: Dictionary in entries:
		total_weight += float(entry.get("weight", 0.0))
	if total_weight <= 0.0:
		return result

	for _i: int in roll_count:
		var pick: float = rng.randf() * total_weight
		for entry: Dictionary in entries:
			pick -= float(entry.get("weight", 0.0))
			if pick > 0.0:
				continue
			var kind: StringName = entry.get("kind", &"gold")
			var lo: int = int(entry.get("min", 1))
			var hi: int = int(entry.get("max", lo))
			var amount: int = rng.randi_range(lo, maxi(lo, hi))
			if kind == &"gold":
				amount *= tier
			result[kind] = int(result.get(kind, 0)) + amount
			break

	return result
