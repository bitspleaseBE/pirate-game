class_name FleetController
extends Node2D
## Owns the player's ships and turns input intents into orders.
##
## The fleet is up to three hulls but the player has one thumb, so unselected
## ships keep a loose escort station on the selected one. That is the whole
## reason a three-ship fleet is playable on a phone: you steer one ship and the
## others behave sensibly.

const SHIP_SCENE: PackedScene = preload("res://src/entities/ships/ship.tscn")

## Escort stations, in multiples of the leader's hull radius, relative to the
## leader's heading. Astern and to either quarter — never ahead, where they would
## block the leader's own guns.
const ESCORT_STATIONS: Array[Vector2] = [Vector2(-2.6, 2.2), Vector2(2.6, 2.2)]
## Escorts only re-issue a course when their station has moved this far, so they
## are not given a new order every frame.
const ESCORT_REORDER_DISTANCE: float = 220.0

# --- Boarding --------------------------------------------------------------
#
# The one verb in the game that ends a fight with a ship still floating, and the
# reason the shot types are a decision rather than a colour scheme.
#
# Grape shot has always swept a deck and cut the victim's reload speed. Nothing
# ever showed the player that number, and the ship it was cutting was one they
# were about to sink anyway — so the whole ammo system came down to "round shot,
# unless you are bored". Boarding is what that mechanic was for: thin a crew and
# the hull stops being something to sink and becomes something to take.
#
# Deliberately not a minigame. One button that appears when it is possible, then
# a few seconds of holding station while it resolves — which is itself the cost,
# because those are seconds spent stopped, alongside, in the middle of a fight.

## How close the two hulls must be, as a multiple of their combined radii.
const BOARD_RANGE_MUL: float = 1.75
## Seconds the party needs on the enemy's deck.
const BOARD_DURATION: float = 2.8
## Drifting further apart than this fraction of the grapple range breaks it off.
const BOARD_BREAK_MUL: float = 1.9

signal selection_changed(ship: Ship)
signal fleet_emptied()
## Boarding has begun, finished, or been broken off. The HUD listens so the
## prompt can get out of the way while it is resolving.
signal boarding_changed()

var ships: Array[Ship] = []
var selected: Ship = null

var _spawn_origin: Vector2 = Vector2.ZERO
## The boarding in progress: { boarder: Ship, prize: Ship, left: float }.
var _boarding: Dictionary = {}


func _ready() -> void:
	EventBus.intent_move.connect(_on_intent_move)
	EventBus.intent_target.connect(_on_intent_target)
	EventBus.intent_select_ship.connect(_on_intent_select)
	EventBus.intent_cycle_ammo.connect(_on_intent_cycle_ammo)
	EventBus.intent_select_ammo.connect(_on_intent_select_ammo)
	EventBus.intent_board.connect(_on_intent_board)


## Spawns one hull per entry in GameState.fleet, in a line abeam of `origin`.
func spawn_fleet(origin: Vector2) -> void:
	_spawn_origin = origin
	for i: int in GameState.fleet.size():
		var entry: Dictionary = GameState.fleet[i]
		var stats_id: StringName = entry.get("stats_id", GameState.STARTING_HULL)
		var upgrades: Dictionary = entry.get("upgrades", {})
		var offset := Vector2(float(i) * 260.0 - float(GameState.fleet.size() - 1) * 130.0, 0.0)
		_spawn_ship(stats_id, upgrades, origin + offset)

	if not ships.is_empty():
		_select(ships[0])
	EventBus.fleet_changed.emit()


func _spawn_ship(stats_id: StringName, upgrades: Dictionary, at: Vector2) -> Ship:
	var ship: Ship = SHIP_SCENE.instantiate() as Ship
	ship.stats = ShipStatsLibrary.build(stats_id, upgrades)
	ship.team = Teams.PLAYER
	# Your own colours, so the flag at the stern means the same thing on your hull
	# as it does on theirs. It bends no stats — see the `player` entry in
	# [FactionLibrary]; the player's numbers come from the hull and the shop.
	ship.faction = FactionLibrary.get_faction(&"player")
	ship.global_position = at
	add_child(ship)
	ship.loaded_ammo = AmmoLibrary.get_ammo(GameState.selected_ammo)
	ship.died.connect(_on_ship_died.bind(ship))
	ships.append(ship)
	return ship


func _physics_process(delta: float) -> void:
	_tick_boarding(delta)
	_update_escorts()


# --- Boarding ---------------------------------------------------------------

## The enemy the selected hull could put a party onto right now, or null.
##
## Polled by the HUD to decide whether to offer the prompt. Cheap: one distance
## check against the ship the player has already marked, rather than a grid sweep
## — you board what you are fighting.
func boarding_candidate() -> Ship:
	if is_boarding() or selected == null or not is_instance_valid(selected):
		return null
	if not selected.alive or selected.grappled:
		return null
	# Validity before the cast: the marked target may already have been sunk and
	# freed this frame, and casting a freed object raises rather than returning
	# null. See [method boarding_pair].
	var raw: Variant = selected.target
	if not is_instance_valid(raw) or not (raw is Ship):
		return null
	var prize: Ship = raw
	if prize.team == Teams.PLAYER:
		return null
	if not prize.is_boardable() or prize.grappled:
		return null
	if selected.global_position.distance_to(prize.global_position) > _grapple_range(selected, prize):
		return null
	return prize


func is_boarding() -> bool:
	return not _boarding.is_empty()


## Progress through the boarding in progress, 0 to 1. -1 when there is none.
## Drawn by [WorldOverlay] as a bar between the two hulls.
func boarding_progress() -> float:
	if _boarding.is_empty():
		return -1.0
	return clampf(1.0 - float(_boarding["left"]) / BOARD_DURATION, 0.0, 1.0)


## The two hulls currently lashed together, or an empty array.
##
## Read untyped first. Assigning an already-freed object into a *typed* array
## raises "Trying to cast a freed object" before any validity check can run, and
## a prize is freed the instant it is taken — so the overlay drawing the grapples
## on the same frame the boarding resolved was throwing every time it worked.
## The same hazard is noted on [method living_ships] and in the spawn director.
func boarding_pair() -> Array[Ship]:
	if _boarding.is_empty():
		return []
	var out: Array[Ship] = []
	for entry: Variant in [_boarding["boarder"], _boarding["prize"]]:
		if not is_instance_valid(entry):
			return []
		out.append(entry)
	return out


func _grapple_range(boarder: Ship, prize: Ship) -> float:
	return (boarder.stats.hull_radius + prize.stats.hull_radius) * BOARD_RANGE_MUL


func _on_intent_board(_entity: Node2D) -> void:
	var prize: Ship = boarding_candidate()
	if prize == null:
		return

	_boarding = {"boarder": selected, "prize": prize, "left": BOARD_DURATION}
	# Both hulls are lashed together: neither steers, and the prize stops
	# shooting. The boarder keeps its guns, which matters — an escort of the
	# prize's can and will come and shoot you off it.
	selected.stop()
	selected.grappled = true
	prize.stop()
	prize.grappled = true
	Audio.play_at(&"boarding_clash", prize.global_position)
	EventBus.boarding_started.emit(selected, prize)
	boarding_changed.emit()


func _tick_boarding(delta: float) -> void:
	if _boarding.is_empty():
		return

	# Untyped first, then validated, then cast. A prize is freed the moment it is
	# taken and a boarder can be sunk out from under its own party, and casting an
	# already-freed object into a typed variable raises before any check on it can
	# run. Same hazard as [method living_ships] and [method boarding_pair].
	var raw_boarder: Variant = _boarding["boarder"]
	var raw_prize: Variant = _boarding["prize"]
	if not is_instance_valid(raw_boarder) or not is_instance_valid(raw_prize):
		_end_boarding(false)
		return

	var boarder: Ship = raw_boarder
	var prize: Ship = raw_prize

	# Either hull going down under the party's feet ends it, and so does drifting
	# apart — the swell moves two stopped ships, and grapples do part.
	if not boarder.alive or not prize.alive:
		_end_boarding(false)
		return
	if (
		boarder.global_position.distance_to(prize.global_position)
		> _grapple_range(boarder, prize) * BOARD_BREAK_MUL
	):
		_end_boarding(false)
		return

	_boarding["left"] = float(_boarding["left"]) - delta
	if float(_boarding["left"]) <= 0.0:
		_take_prize(boarder, prize)
		_end_boarding(true)


## Hands the player whatever they just captured.
##
## A hull if they have a berth standing empty, and cargo if they do not — which
## is the answer the design settled on, and the reason fleet slots are worth
## buying before you can afford a ship to put in one. Capturing is always worth
## doing; *what* it is worth depends on what you prepared.
func _take_prize(boarder: Ship, prize: Ship) -> void:
	var stats: ShipStats = prize.stats
	var berth_free: bool = GameState.fleet.size() < GameState.fleet_slots

	if berth_free:
		GameState.fleet.append({"stats_id": stats.id, "upgrades": {}})
		var taken: Ship = _spawn_ship(stats.id, {}, prize.global_position)
		taken.rotation = prize.rotation
		EventBus.prize_taken.emit(stats.display_name, true)
	else:
		# No berth: strip her and let her go down. Worth appreciably more than
		# sinking the same hull, because it cost you seconds stopped in a fight.
		GameState.add_gold(stats.bounty_gold * 3)
		for ammo: StringName in [&"chain", &"grape", &"fire"]:
			GameState.add_ammo(ammo, 2)
		EventBus.prize_taken.emit(stats.display_name, false)

	Audio.play_at(&"prize_taken", prize.global_position)
	GameState.stats_ships_boarded += 1
	# Off the board without going through _sink: this hull was taken, not sunk,
	# so it pays no prize money and counts as nobody's kill.
	prize.grappled = false
	prize.alive = false
	Grid.remove(prize)
	Cull.unregister(prize)
	prize.queue_free()

	boarder.repair_all_crew()
	SaveSystem.request_save()


func _end_boarding(_succeeded: bool) -> void:
	if _boarding.is_empty():
		return
	for entry: Variant in [_boarding["boarder"], _boarding["prize"]]:
		if is_instance_valid(entry):
			(entry as Ship).grappled = false
	_boarding.clear()
	boarding_changed.emit()


func _update_escorts() -> void:
	if selected == null or not is_instance_valid(selected):
		return
	var leader_forward: Vector2 = selected.forward()
	var leader_right: Vector2 = selected.starboard()
	var station_index: int = 0

	for entry: Variant in ships:
		if not is_instance_valid(entry):
			continue
		var ship: Ship = entry
		if ship == selected or not ship.alive:
			continue
		var station_local: Vector2 = ESCORT_STATIONS[station_index % ESCORT_STATIONS.size()]
		station_index += 1

		var station: Vector2 = (
			selected.global_position
			+ leader_right * station_local.x * selected.stats.hull_radius
			+ leader_forward * -station_local.y * selected.stats.hull_radius
		)
		# An escort that is already fighting keeps fighting; station-keeping is
		# what it does when it has nothing better to do.
		if ship.target != null and is_instance_valid(ship.target):
			continue
		if not ship.has_nav_target or ship.nav_target.distance_to(station) > ESCORT_REORDER_DISTANCE:
			ship.set_course(station)


# --- Intents ---------------------------------------------------------------

## Tapping the sea steers; it does not holster the guns.
##
## It used to clear the target as well, on the reasoning that "tapping the sea
## means disengage". The effect was that steering by hand and shooting were
## mutually exclusive, so the only way to fight was to hand the helm to the
## engagement solver and watch — which is how a naval combat game ended up with
## one decision per fight.
##
## Now a course order takes the helm and leaves the target marked: your guns keep
## firing the instant a beam bears, and the whole fight is you working the ship
## into the angle you want. Tapping the enemy you are already engaging is what
## breaks off — see [InputRouter._tap].
func _on_intent_move(world_pos: Vector2) -> void:
	if selected == null or not is_instance_valid(selected):
		return
	selected.steer_by_hand(world_pos)


func _on_intent_target(entity: Node2D) -> void:
	if selected == null or not is_instance_valid(selected):
		return
	selected.set_target(entity)
	# The rest of the fleet concentrates fire on the same enemy, which is the
	# only fleet-level tactic a one-thumb interface can express.
	for entry: Variant in ships:
		if not is_instance_valid(entry):
			continue
		var ship: Ship = entry
		if ship != selected and ship.alive:
			ship.set_target(entity)


func _on_intent_select(ship: Node2D) -> void:
	if ship is Ship and ships.has(ship):
		_select(ship as Ship)


func _on_intent_cycle_ammo() -> void:
	_load_ammo(AmmoLibrary.next_available(GameState.selected_ammo))


## Loads a named shot, if there is any of it.
##
## The stock check is here rather than in the HUD because the rack is not the
## only way in — a shot can run dry while it is the one selected, and the answer
## has to be the same whoever asked.
func _on_intent_select_ammo(id: StringName) -> void:
	var ammo: AmmoType = AmmoLibrary.get_ammo(id)
	if not ammo.unlimited and GameState.get_ammo(id) <= 0:
		return
	_load_ammo(id)


func _load_ammo(id: StringName) -> void:
	GameState.selected_ammo = id
	var ammo: AmmoType = AmmoLibrary.get_ammo(id)
	for entry: Variant in ships:
		if is_instance_valid(entry):
			(entry as Ship).loaded_ammo = ammo
	EventBus.ammo_changed.emit(id)
	Audio.play_ui(&"ui_tap")


func select_next() -> void:
	var alive_ships: Array[Ship] = living_ships()
	if alive_ships.size() <= 1:
		return
	var idx: int = alive_ships.find(selected)
	_select(alive_ships[(idx + 1) % alive_ships.size()])


func _select(ship: Ship) -> void:
	for entry: Variant in ships:
		if is_instance_valid(entry):
			(entry as Ship).selected = entry == ship
	selected = ship
	selection_changed.emit(ship)


# --- Queries ---------------------------------------------------------------

func living_ships() -> Array[Ship]:
	# Untyped read: a freed hull assigned to a typed variable raises before the
	# validity check, and this is the hottest such loop in the game.
	var out: Array[Ship] = []
	for entry: Variant in ships:
		if is_instance_valid(entry) and (entry as Ship).alive:
			out.append(entry)
	return out


## Centre of the living fleet. This is what the camera follows.
func centroid() -> Vector2:
	var alive_ships: Array[Ship] = living_ships()
	if alive_ships.is_empty():
		return _spawn_origin
	var sum := Vector2.ZERO
	for ship: Ship in alive_ships:
		sum += ship.global_position
	return sum / float(alive_ships.size())


## Rebuilds every hull from [GameState], keeping each one where it was.
##
## Called when leaving a port. Without it, buying a Sloop leaves you sailing the
## Dinghy you arrived in until the next voyage — the reward is invisible at exactly
## the moment the player is looking for it, which is the worst possible moment for
## a reward to be invisible.
##
## Replacing the node rather than editing its stats in place is deliberate: a new
## hull changes sprite, scale, collision radius and propulsion, and rebuilding is
## far less error-prone than remembering to re-derive all of it.
func refit() -> void:
	var placements: Array[Transform2D] = []
	for ship: Ship in living_ships():
		placements.append(ship.global_transform)
		ship.queue_free()
	ships.clear()
	selected = null

	for i: int in GameState.fleet.size():
		var entry: Dictionary = GameState.fleet[i]
		var at: Vector2 = _spawn_origin
		var facing: float = 0.0
		if i < placements.size():
			at = placements[i].origin
			facing = placements[i].get_rotation()
		elif not placements.is_empty():
			# A hull the fleet did not arrive with — a slot bought in this port. It has
			# to appear *here*, alongside the flagship, not at `_spawn_origin`, which is
			# where the voyage began and may be the far side of the archipelago. Buying a
			# second ship and watching it fail to exist is the worst possible payoff for
			# the most expensive thing in the shop.
			var lead: Transform2D = placements[0]
			facing = lead.get_rotation()
			var abeam: Vector2 = Vector2.RIGHT.rotated(facing) * 240.0
			at = lead.origin + abeam * (1.0 if i % 2 == 1 else -1.0) - Vector2.UP.rotated(facing) * 120.0
		var ship: Ship = _spawn_ship(
			entry.get("stats_id", GameState.STARTING_HULL), entry.get("upgrades", {}), at
		)
		ship.rotation = facing

	if not ships.is_empty():
		_select(ships[0])
	EventBus.fleet_changed.emit()


func repair_all() -> void:
	for ship: Ship in living_ships():
		ship.repair_all()


func _on_ship_died(_killer: Node2D, ship: Ship) -> void:
	# Drop the hull from the roster as well as from the world. `ships` and
	# `GameState.fleet` are built in lockstep by spawn_fleet and refit, so the index
	# is shared — and it has to be taken *before* the erase below.
	#
	# Without this a sunk ship is only cosmetically lost: the entry survives in the
	# save, and the next call to refit (any port visit) hands it back, free. That was
	# invisible while the fleet was capped at one hull, because losing your only ship
	# ends the voyage before any port can rebuild it.
	var slot: int = ships.find(ship)
	if slot >= 0 and slot < GameState.fleet.size():
		GameState.fleet.remove_at(slot)
	ships.erase(ship)
	# Unbanked gold goes down with the hull that carried it. That is the whole
	# reason banking at a port is a decision.
	GameState.lose_carried_gold()

	var remaining: Array[Ship] = living_ships()
	if remaining.is_empty():
		selected = null
		fleet_emptied.emit()
		EventBus.fleet_wiped.emit()
	elif selected == ship or selected == null:
		_select(remaining[0])

	EventBus.fleet_changed.emit()
