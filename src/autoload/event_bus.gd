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
## "Load this shot." One rack button, named. Distinct from the cycle above rather
## than replacing it: cycling is still the right verb for a keyboard or gamepad
## binding, where there is nothing to point at.
signal intent_select_ammo(id: StringName)
## "Put a party over the side onto that." Only ever emitted while
## [method FleetController.boarding_candidate] has something to offer.
signal intent_board(entity: Node2D)

# --- Combat ---
signal shot_fired(from: Node2D, ammo_id: StringName, origin: Vector2, target: Vector2)
signal projectile_impact(world_pos: Vector2, ammo_id: StringName, hit: Node2D)
signal ship_damaged(ship: Node2D, amount: float, bar: StringName)
## The player put a ball down the length of something. Worth its own signal
## rather than a flag on `ship_damaged`: it is the one hit the game wants to
## celebrate, because it is the one the player had to manoeuvre for.
signal rake_landed(victim: Node2D, world_pos: Vector2)
signal ship_sunk(ship: Node2D, killed_by: Node2D)
signal ship_crippled(ship: Node2D)
## A defender broke off and got clear. It is alive, it still carries its bounty,
## and it has stopped counting towards its island's garrison.
signal enemy_routed(ship: Node2D, island: Node2D)
signal fireship_detonated(world_pos: Vector2)
## Two hulls met. `force` is 0..1.6, the closing speed against a bow-to-bow
## reference — so listeners can tell a scrape from a proper ram.
signal ships_collided(a: Node2D, b: Node2D, force: float)
signal boarding_started(boarder: Node2D, prize: Node2D)
## A hull was taken rather than sunk. `kept` is true when it joined the fleet and
## false when there was no berth for it and it was stripped instead.
signal prize_taken(hull_name: String, kept: bool)

# --- World / progression ---
signal island_discovered(island: Node2D)
signal island_alerted(island: Node2D)
signal island_captured(island: Node2D)
## An island's slipway has been burned: no more reinforcements from it. Worth its
## own signal because it is a thing the player *chose* to do, and the game should
## say so out loud — see [Shipyard].
signal shipyard_destroyed(island: Node2D)
## The castle's walls are down. The end of a voyage, and the loudest moment in it.
signal castle_breached(island: Node2D)
## A shot bounced off the keep's armour. Emitted once per castle, so the rule can
## be explained at the exact moment the player runs into it.
signal keep_shrugged_off(island: Node2D)
signal treasure_dug(island: Node2D, loot: Dictionary)
signal loot_collected(loot: Dictionary)
signal gold_changed(new_total: int, delta: int)
signal diamonds_changed(new_total: int, delta: int)
signal fleet_changed()
## The loaded shot changed, by whichever route. The rack listens rather than
## refreshing itself off its own button press, because stock also falls as the
## guns fire and a shot can run dry with nobody having touched the HUD.
signal ammo_changed(id: StringName)
signal voyage_started(seed_value: int)
signal voyage_completed()
signal fleet_wiped()

# --- System ---
signal quality_tier_changed(tier: int)
signal camera_registered(camera: Camera2D)
signal game_paused(is_paused: bool)
