extends Node
## Global signal hub.
##
## Only for events that genuinely cross system boundaries — combat telling the
## HUD something happened, the world telling the save system to persist. Direct
## signals between a parent and its own children should stay local; routing
## those through here would just make the call graph unreadable.

# --- Input intents (emitted by InputRouter, consumed by the fleet controller) ---
signal intent_move(world_pos: Vector2)
signal intent_target(entity: Node2D)
signal intent_select_ship(ship: Node2D)
signal intent_open_port(island: Node2D)
## "Go and get the treasure on that island." Consumed by the spawn director,
## which owns the landing party.
signal intent_dig(island: Node2D)
## "Take us home." Consumed by the voyage, which sets the course and opens the
## hideout when the fleet gets there.
signal intent_sail_home()
signal intent_cycle_ammo()

# --- Combat ---
signal shot_fired(from: Node2D, ammo_id: StringName, origin: Vector2, target: Vector2)
signal projectile_impact(world_pos: Vector2, ammo_id: StringName, hit: Node2D)
signal ship_damaged(ship: Node2D, amount: float, bar: StringName)
signal ship_sunk(ship: Node2D, killed_by: Node2D)
signal ship_crippled(ship: Node2D)

# --- World / progression ---
signal island_discovered(island: Node2D)
signal island_alerted(island: Node2D)
signal island_captured(island: Node2D)
signal treasure_dug(island: Node2D, loot: Dictionary)
signal loot_collected(loot: Dictionary)
signal gold_changed(new_total: int, delta: int)
signal diamonds_changed(new_total: int, delta: int)
signal fleet_changed()
signal voyage_started(seed_value: int)
signal voyage_completed()
signal fleet_wiped()

# --- System ---
signal quality_tier_changed(tier: int)
signal camera_registered(camera: Camera2D)
signal game_paused(is_paused: bool)
