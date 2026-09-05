extends Node
## Wires one voyage together and owns its lifecycle.
##
## The world lives inside a [SubViewport] so that render resolution can be
## dropped independently of the HUD. In GL Compatibility 2D there is no other way
## to actually save fill rate — shrinking the base viewport with a `canvas_items`
## stretch mode changes the canvas transform but still rasterises at window
## resolution. The HUD stays at native resolution on its own CanvasLayer, so text
## remains crisp even at half render scale.

const FLEET_WIPE_DELAY: float = 2.8
## How close to home's mooring buoy counts as being home. Wider than the landing
## party's own trigger, because nothing is being winched aboard here — the fleet
## just has to be recognisably in the harbour.
const HIDEOUT_ARRIVAL: float = 340.0
## Rate the run home is checked at. Arrival is a proximity test on one point; it
## does not need frame accuracy any more than the island loop does.
const HIDEOUT_CHECK_HZ: float = 4.0

## Set by the first half of the `--wipe` harness so the voyage it comes back to
## runs the second half instead of sinking itself again. Static because Router
## frees this node on the way to the menu — nothing instance-side survives the
## trip, and the check is only meaningful across two voyages in one process.
static var _wipe_harness_ran: bool = false

@onready var _viewport_container: SubViewportContainer = $GameViewport
@onready var _world: Node2D = %World
@onready var archipelago: Archipelago = %Archipelago
@onready var ocean: Ocean = %Ocean
@onready var fleet: FleetController = %Fleet
@onready var camera: GameCamera = %GameCamera
@onready var overlay: WorldOverlay = %WorldOverlay
@onready var input_router: InputRouter = %InputRouter
@onready var director: SpawnDirector = %SpawnDirector
@onready var ships_parent: Node2D = %Ships
@onready var wind: WindSystem = %WindSystem
@onready var tutorial: TutorialDirector = %Tutorial
## Reprisals. Built in code rather than authored in the scene because it owns no
## nodes of its own — it only reads the archipelago and hands ships to the spawn
## director. See [RaidDirector].
var raids: RaidDirector = null

## Built once the world exists — see the note where it is created.
var music: MusicDirector = null
@onready var hud: CanvasLayer = %Hud

## Set while the fleet is under orders for the hideout, so arriving there opens
## the port instead of quietly mooring.
## Seed `--ladder` pins itself to. Chosen off a sweep as a middling one rather
## than a kind one: the opening islands come in around half hull and the first
## tier-3 island around a third, so a change that makes the ramp meaningfully
## harsher shows up here rather than needing a lucky roll to catch.
const LADDER_SEED: int = 11

var _returning_home: bool = false
var _hideout_accum: float = 0.0


func _ready() -> void:
	# `--sail` starts in a Sloop instead of the oared Dinghy, so the wind, the
	# wake and the compass ring can be exercised without first playing through
	# the opening islands to earn a set of sails.
	if "--sail" in OS.get_cmdline_user_args():
		GameState.fleet = [{"stats_id": &"sloop", "upgrades": {}}]

	# `--seed=N` pins the archipelago, which a balance harness needs and the game
	# does not. Island layout, tiers and garrison placement all come off this one
	# number, and the swing between two seeds is wider than most of the changes
	# worth measuring: the same build had `--ladder` finishing island two on 74%
	# of its hull and being wiped on it, on consecutive runs. Without a way to
	# hold the world still, tuning against the harness is tuning against noise.
	var pinned: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			GameState.voyage_seed = int(arg.trim_prefix("--seed="))
			pinned = true
	# And `--ladder` pins itself if nothing else did, because it is the one
	# harness whose output is a *measurement* rather than a yes or no. A gate that
	# rolls a fresh world every run cannot tell a balance regression from a bad
	# roll, and would fail CI on the latter often enough to be ignored.
	if not pinned and "--ladder" in OS.get_cmdline_user_args():
		GameState.voyage_seed = LADDER_SEED

	Grid.configure()
	# Pools must exist before anything can fire a gun, and they need a world-space
	# parent — this is the handoff described in PoolManager.
	Pools.set_world_root(_world)

	_apply_render_scale()
	Quality.tier_changed.connect(_on_quality_tier_changed)
	# A phone turned over changes the UI scale, and the UI scale is half of what
	# decides the render shrink.
	get_window().size_changed.connect(_apply_render_scale)

	archipelago.generate(GameState.voyage_seed)
	# The sea is drawn before the land exists and knows nothing about it, so the
	# shallows have to be handed to it once the coastlines are settled.
	ocean.archipelago = archipelago
	camera.set_world_bounds(archipelago.world_bounds)
	camera.fleet = fleet
	input_router.camera = camera
	input_router.fleet = fleet
	overlay.fleet = fleet
	overlay.archipelago = archipelago

	director.fleet = fleet
	director.archipelago = archipelago
	director.ships_parent = ships_parent

	raids = RaidDirector.new()
	raids.name = "RaidDirector"
	raids.fleet = fleet
	raids.archipelago = archipelago
	raids.director = director
	raids.ships_parent = ships_parent
	add_child(raids)

	# Riding at anchor just outside Port Royal's mooring buoy, rather than on top
	# of it. Sitting exactly on the buoy hides the one piece of harbour furniture
	# the opening is trying to teach the player to recognise.
	var start: Vector2 = Vector2(0, -1400)
	if archipelago.home != null:
		var home: Island = archipelago.home
		start = home.anchor_point + (
			home.anchor_point - home.global_position
		).normalized() * 180.0
	fleet.spawn_fleet(start)
	# Snap rather than ease, so the first frame is already at the fleet and the
	# culling manager's first tick sees the real camera rect.
	camera.snap_to(fleet.centroid())

	if hud.has_method(&"bind"):
		hud.call(&"bind", fleet, archipelago)

	tutorial.hud = hud
	tutorial.camera = camera
	tutorial.fleet = fleet
	# Briefings pause the tree, which an automated run has no way to dismiss —
	# the world would sit frozen behind a modal and the harness would faithfully
	# report that nothing happened. `--shot-port` / `--shot-harbour` wait on
	# scene-tree timers that do not tick while a briefing holds the pause.
	# `--wipe` is excluded for a second reason: a fleet is only ever lost well
	# after the opening briefing is done with, so a run that dies behind it is
	# not testing the moment a player actually sees.
	var harness_args: PackedStringArray = OS.get_cmdline_user_args()
	tutorial.enabled = not (
		"--smoke" in harness_args
		or "--shot-port" in harness_args
		or "--wipe" in harness_args
		or "--shot-harbour" in harness_args
		or "--shot-fleet" in harness_args
		or "--shot-flags" in harness_args
		or "--hideout" in harness_args
		or "--arena" in harness_args
		or "--doctrine" in harness_args
		or "--board" in harness_args
		or "--shot-combat" in harness_args
		or "--castle" in harness_args
		or "--ram" in harness_args
		or "--rout" in harness_args
		or "--audio" in harness_args
		or "--rig" in harness_args
		or "--sailing" in harness_args
		or "--helm" in harness_args
		or "--reprisal" in harness_args
		or "--ladder" in harness_args
		or "--touch" in harness_args
		or "--shot-mobile" in harness_args
	)

	# Reprisals are off for every automated run but their own. They are rare,
	# they happen where the player is not, and every other gate measures something
	# that a squadron arriving in the middle of would quietly corrupt.
	raids.enabled = harness_args.is_empty() or "--reprisal" in harness_args

	_update_wind_availability()
	EventBus.fleet_changed.connect(_update_wind_availability)

	fleet.fleet_emptied.connect(_on_fleet_emptied)
	EventBus.intent_open_port.connect(_on_open_port)
	EventBus.intent_dig.connect(_on_intent_dig)
	EventBus.intent_sail_home.connect(_on_sail_home)
	EventBus.intent_move.connect(_on_intent_move)
	EventBus.island_captured.connect(_on_island_captured)
	director.landing_started.connect(_on_landing_started)

	# The sea and the shanty. Started here rather than in `_ready` because the
	# score is a reading of the world, and until the fleet and the archipelago
	# exist there is nothing to read.
	music = MusicDirector.new()
	music.name = "MusicDirector"
	add_child(music)
	music.begin(fleet, archipelago)

	GameState.voyage_active = true
	EventBus.voyage_started.emit(GameState.voyage_seed)
	SaveSystem.request_save()

	tutorial.begin()

	Log.info("Voyage ready — seed %d" % GameState.voyage_seed, "Voyage")

	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--smoke" in args:
		_run_smoke_test()
	elif "--shot" in args:
		_capture_screenshots()
	elif "--shot-port" in args:
		_capture_port()
	elif "--wipe" in args:
		if _wipe_harness_ran:
			_check_voyage_after_wipe()
		else:
			_wipe_harness_ran = true
			_run_wipe_test()
	elif "--shot-harbour" in args:
		_capture_harbours()
	elif "--shot-fleet" in args:
		_capture_fleet()
	elif "--shot-flags" in args:
		_capture_flags()
	elif "--hideout" in args:
		_run_hideout_test()
	elif "--arena" in args:
		_run_arena_test()
	elif "--doctrine" in args:
		_run_doctrine_test()
	elif "--board" in args:
		_run_boarding_test()
	elif "--shot-combat" in args:
		_capture_combat()
	elif "--castle" in args:
		_run_castle_test()
	elif "--ram" in args:
		_run_ram_test()
	elif "--rout" in args:
		_run_rout_test()
	elif "--audio" in args:
		_run_audio_test()
	elif "--reprisal" in args:
		_run_reprisal_test()
	elif "--helm" in args:
		_run_helm_test()
	elif "--sailing" in args:
		_run_sailing_test()
	elif "--rig" in args:
		_run_rig_test()
	elif "--ladder" in args:
		_run_ladder_test()
	elif "--touch" in args:
		_run_touch_test()
	elif "--shot-mobile" in args:
		_capture_mobile()


## Drives the entire game-over path and asserts the player can still play.
##
##   godot --headless src/scenes/voyage.tscn -- --wipe --auto-new
##
## The `--smoke` run deliberately treats a wipe as a failure and quits, so
## nothing else in the harness had ever been through this path — which is how a
## fleet wipe came to leave [member GameState.fleet] empty and the *next* voyage
## with no player ship in it. `--auto-new` is what carries the run back out of
## the menu, so the second half goes through the same two buttons a player does.
func _run_wipe_test() -> void:
	await get_tree().create_timer(0.5).timeout

	# Give the run a bank and a purse. A wipe is supposed to cost one and not the
	# other, and starting at zero cannot tell "kept" from "cleared".
	GameState.banked_gold = 250
	GameState.add_gold(90)

	var hulls: Array[Ship] = fleet.living_ships()
	if hulls.is_empty():
		push_error("WIPE FAIL: voyage started with no player ship")
		await _quit_cleanly(1)
		return
	for ship: Ship in hulls:
		ship.apply_damage(999_999.0, AmmoType.Bar.HULL, null)

	# One frame for the death signal to walk through FleetController and the wipe
	# handler. The scene is still up — Router does not leave for FLEET_WIPE_DELAY.
	await get_tree().process_frame

	var failures: PackedStringArray = []
	if GameState.fleet.is_empty():
		failures.append("roster is empty — the next voyage would spawn no ship")
	if GameState.carried_gold != 0:
		failures.append("carried gold survived the wipe (%d)" % GameState.carried_gold)
	if GameState.banked_gold != 250:
		failures.append("banked gold should be untouched, is %d" % GameState.banked_gold)
	if GameState.voyage_active:
		failures.append("voyage still marked active")

	if not failures.is_empty():
		for line: String in failures:
			push_error("WIPE FAIL: %s" % line)
		await _quit_cleanly(1)
		return

	print("WIPE: fleet sunk, %d hull(s) issued, %d gold still banked" % [
		GameState.fleet.size(), GameState.banked_gold
	])

	# The state being right is only half of it — what the player gets is a toast
	# on a sea with no ship on it, and that has to be readable. Skipped headless,
	# where there is no framebuffer to grab.
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://shots")
		get_viewport().get_texture().get_image().save_png("user://shots/wipe_00.png")
		print("WIPE SHOT: %s" % ProjectSettings.globalize_path("user://shots/wipe_00.png"))
	# Nothing further here: `_on_fleet_emptied` is already counting down to the
	# menu, and `--auto-new` takes it from there into the second half.


## Second half of `--wipe`: the voyage a player gets after losing everything.
func _check_voyage_after_wipe() -> void:
	await get_tree().process_frame

	var afloat: int = fleet.living_ships().size()
	if afloat < 1:
		push_error("WIPE FAIL: new voyage after a wipe has no player ship")
		await _quit_cleanly(1)
		return
	if fleet.selected == null:
		push_error("WIPE FAIL: new voyage after a wipe has no ship under command")
		await _quit_cleanly(1)
		return

	print("WIPE OK: sailing again with %d hull(s), %d gold banked" % [
		afloat, GameState.banked_gold
	])
	await _quit_cleanly(0)


## Frames each island's [Port] and writes the frames to `user://shots/`.
##
## The harbour is the one structure the player is asked to steer to, and whether
## it reads as a harbour at gameplay zoom is not a question the smoke test can
## answer — only a rendered frame can. Captures all three states it is ever seen
## in: hostile, held with cargo still on the quay, and unloading.
##
##   godot src/scenes/voyage.tscn -- --shot-harbour
func _capture_harbours() -> void:
	const STATES: PackedStringArray = ["hostile", "held", "unloading"]
	var dir: String = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	if hud.has_method(&"dismiss_briefing"):
		hud.call(&"dismiss_briefing")
	input_router.enabled = false

	var shot: int = 0
	for island: Island in archipelago.islands:
		if shot >= 4:
			break
		# Halfway between quay and buoy, so the frame holds the whole approach —
		# sheds, jetty and the water the player is actually steering for.
		var seaward: Vector2 = (island.anchor_point - island.global_position).normalized()
		for state: String in STATES:
			if state != "hostile" and not island.is_captured:
				island.capture()
			if state == "unloading" and island.port != null:
				island.port.begin_unloading(island.anchor_point + seaward * 200.0, 4.5)
			camera.target_zoom = 0.95
			camera.point_out(
				island.treasure_world_position().lerp(island.anchor_point, 0.6), 4.0
			)
			await get_tree().create_timer(1.4).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				"%s/harbour_%02d_%s.png" % [dir, shot, state]
			)
			if island.port != null:
				island.port.finish_unloading()
		shot += 1

	print("HARBOUR SHOTS: %s" % ProjectSettings.globalize_path(dir))
	await _quit_cleanly(0)


## Drives the Hideout button end to end and asserts the port actually opens.
##
##   godot --headless src/scenes/voyage.tscn -- --hideout
##
## The run home is the one feature in the game whose payoff is asynchronous: the
## button only sets a course, and everything that makes going home worth doing —
## the bank, the carpenter, the shop — happens when the fleet arrives, several
## thousand metres and half a minute later. A course order that quietly fails to
## arrive looks exactly like a button that does nothing, so it is asserted rather
## than eyeballed.
func _run_hideout_test() -> void:
	const SAIL_LIMIT: float = 90.0
	const TIME_SCALE: float = 6.0

	await get_tree().create_timer(0.5).timeout
	var home: Island = archipelago.home
	if home == null:
		push_error("HIDEOUT FAIL: no home port was generated")
		await _quit_cleanly(1)
		return

	# Stand the fleet off, or it starts inside the arrival radius and the test
	# proves only that the button works when it has nothing to do.
	#
	# Off to one side of the harbour rather than straight out from it: the opening
	# island is deliberately placed on home's harbour bearing (see
	# [constant Archipelago.OPENING_ISLAND_BEARING_SPREAD]), so "2,200 m seaward of
	# the buoy" is a spot that lands the fleet on a beach.
	var seaward: Vector2 = (home.anchor_point - home.global_position).normalized()
	var offshore: Vector2 = home.global_position + seaward.rotated(1.2) * 2600.0
	for ship: Ship in fleet.living_ships():
		ship.global_position = ship.clamp_to_navigable(offshore)
	await get_tree().process_frame

	GameState.add_gold(120)
	# Through the button, so the run covers the wiring as well as the sailing.
	var button: Button = hud.find_child("HideoutButton", true, false) as Button
	if button == null:
		push_error("HIDEOUT FAIL: the HUD has no hideout button")
		await _quit_cleanly(1)
		return
	button.pressed.emit()

	Engine.time_scale = TIME_SCALE
	var elapsed: float = 0.0
	var arrived: bool = false
	while elapsed < SAIL_LIMIT:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
		if hud.get_node_or_null(^"Port") != null:
			arrived = true
			break
		var lead: Ship = fleet.selected
		if lead != null and is_equal_approx(elapsed, floorf(elapsed)) and int(elapsed) % 10 == 0:
			print("HIDEOUT: t=%ds to_home=%d helm[%s]" % [
				int(elapsed),
				roundi(lead.global_position.distance_to(home.anchor_point)),
				lead.debug_state(),
			])
	Engine.time_scale = 1.0

	var failures: PackedStringArray = []
	if not arrived:
		failures.append(
			"the fleet never reached the hideout — %d m short after %ds"
			% [roundi(fleet.centroid().distance_to(home.anchor_point)), roundi(elapsed)]
		)
	# Arriving home is what makes gold safe. If that stopped happening the button
	# would still look like it worked and the player would lose a voyage's takings
	# to the next thing that sank them.
	elif GameState.carried_gold != 0:
		failures.append("arriving home left %d gold unbanked" % GameState.carried_gold)

	if failures.is_empty():
		print("HIDEOUT OK: home in %ds, %d gold banked" % [roundi(elapsed), GameState.banked_gold])
		await _quit_cleanly(0)
	else:
		for line: String in failures:
			push_error("HIDEOUT FAIL: %s" % line)
		await _quit_cleanly(1)


## Measures how *busy* a real fight is, which is the one thing about this game
## that no other harness could see.
##
##   godot --headless src/scenes/voyage.tscn -- --arena
##
## `--smoke` sails at the nearest island, which is deliberately one skiff on a
## still sea, and then reports whatever happened. For a long time what happened
## was three shots in eighty seconds — and it passed, every time, because nothing
## it asserts is about density. "Is the combat any good" is not a question you can
## answer by checking that combat occurred.
##
## So this one picks the heaviest island in the voyage, puts a mid-game hull in
## front of it, and counts: shots fired, hits landed, rakes, kills, and damage
## taken, per minute of fighting. Those numbers are the argument for every balance
## change in the combat model, and a regression in them is a regression in the
## game whether or not anything is broken.
func _run_arena_test() -> void:
	const SECONDS: float = 90.0
	const TIME_SCALE: float = 6.0
	const WALL_CLOCK_LIMIT_SEC: float = 120.0
	## Shots per minute below which the fight has gone quiet again. Set well under
	## what the run actually produces: this is a floor against regression, not a
	## target to tune towards.
	const MIN_SHOTS_PER_MIN: float = 12.0
	## And a fight the player never has to react to is not a fight. If nothing the
	## enemy does lands, the difficulty is a formality.
	const MIN_DAMAGE_TAKEN: float = 1.0

	var tally: Dictionary = {
		"shots": 0, "impacts": 0, "sunk": 0, "rakes": 0, "taken": 0.0, "music_peak": 0.0,
	}
	EventBus.shot_fired.connect(func(from: Node2D, _b: StringName, _c: Vector2, _d: Vector2) -> void:
		var ship := from as Ship
		if ship != null and ship.team == Teams.PLAYER:
			tally["shots"] += 1
	)
	EventBus.projectile_impact.connect(func(_a: Vector2, _b: StringName, hit: Node2D) -> void:
		if hit != null and not (hit is Ship and (hit as Ship).team == Teams.PLAYER):
			tally["impacts"] += 1
	)
	EventBus.ship_sunk.connect(func(ship: Node2D, _b: Node2D) -> void:
		if ship is Ship and (ship as Ship).team == Teams.ENEMY:
			tally["sunk"] += 1
	)
	EventBus.rake_landed.connect(func(_v: Node2D, _p: Vector2) -> void:
		tally["rakes"] += 1
	)
	EventBus.ship_damaged.connect(func(ship: Node2D, amount: float, _bar: StringName) -> void:
		if ship is Ship and (ship as Ship).team == Teams.PLAYER:
			tally["taken"] = float(tally["taken"]) + amount
	)

	# A mid-game hull against a mid-game island, which is the matchup worth
	# measuring: the opening Dinghy cannot exercise the combat model at all — one
	# gun a side, no rig, no wind — and the far end of the voyage is a fleet
	# fight this single-hull harness has no way to represent.
	GameState.fleet = [{"stats_id": &"brig", "upgrades": {&"plating": 2, &"gunnery": 1}}]
	GameState.banked_gold = 400
	fleet.refit()
	await get_tree().process_frame

	var arena: Island = _heaviest_island()
	if arena == null:
		push_error("ARENA FAIL: voyage has no hostile island")
		await _quit_cleanly(1)
		return

	# Just outside the alert radius, so the run includes the approach — which is
	# when the shore batteries get their free shots and is half of what makes an
	# island an island.
	var bearing: Vector2 = (arena.anchor_point - arena.global_position).normalized()
	var standoff: Vector2 = arena.global_position + bearing * (
		arena.def.radius + arena.def.alert_radius * 0.95
	)
	for ship: Ship in fleet.living_ships():
		ship.global_position = ship.clamp_to_navigable(standoff)
	camera.snap_to(fleet.centroid())
	await get_tree().process_frame

	Log.info(
		"ARENA: %s, tier %d, %d defenders, %d batteries, shipyard=%s"
		% [
			arena.def.display_name, arena.def.tier, arena.def.garrison_ships,
			arena.def.fort_cannons, arena.def.has_shipyard,
		],
		"Arena"
	)

	# Dictionaries, not locals: GDScript lambdas capture by value, so a plain bool
	# set from the handler below would be set on a copy. The same note is on the
	# tally above and on the smoke test's counters.
	var outcome: Dictionary = {"wiped": false, "done": false, "started": Time.get_ticks_msec()}

	# A wipe is data, not a failure. The harness sails straight at whatever is
	# nearest and never once uses the helm it is here to measure, so losing a
	# single hull to the heaviest island in the voyage says nothing about the
	# game. What it must not do is hang: a wipe routes to the main menu, which
	# frees this node mid-await — the coroutine stops, nothing calls quit(), and
	# the run dies at its timeout with no output. So the report is a method both
	# paths call, and the wipe path calls it immediately rather than racing the
	# scene change.
	fleet.fleet_emptied.connect(func() -> void:
		if bool(outcome["done"]):
			return
		outcome["wiped"] = true
		_finish_arena(arena, tally, outcome, TIME_SCALE, MIN_SHOTS_PER_MIN, MIN_DAMAGE_TAKEN)
	)

	Engine.time_scale = TIME_SCALE
	var elapsed: float = 0.0
	# Stops at the capture, not at the clock. Every rate below is *per minute of
	# fighting*, and the island being taken is the moment the fighting stops — a
	# shipyard keeps launching hulls for as long as it stands, so an island that is
	# still contested is still a fight and this keeps running.
	#
	# It used to run the full ninety seconds regardless, which quietly turned the
	# shots-per-minute floor into a measure of how long the fight lasted. Taking
	# the shore battery off tier-3 islands is what exposed it: the arena's island
	# lost the one target that does not sink, the garrison went down in half the
	# clock, and the harness spent the rest of it sailing in circles with nothing
	# to shoot at and reported the combat model had gone quiet. It had not — the
	# same run sank both defenders, took 42 damage and captured the island.
	while elapsed < SECONDS and not bool(outcome["wiped"]) and not arena.is_captured:
		var lead: Ship = fleet.selected
		if lead != null and is_instance_valid(lead) and lead.alive:
			var enemy: Node2D = Grid.query_nearest(
				lead.global_position, 3000.0,
				SpatialGrid.KIND_ENEMY_SHIP | SpatialGrid.KIND_STRUCTURE
			)
			if enemy != null:
				EventBus.intent_target.emit(enemy)
			elif not arena.is_captured:
				lead.set_course(arena.global_position)
		# The score is a gameplay system, so it is measured like one. A fight the
		# music never notices is a bug in the same way a fight with no shots in it
		# is, and it is just as invisible from a log.
		if music != null and is_instance_valid(music):
			tally["music_peak"] = maxf(float(tally["music_peak"]), music.measure_intensity())

		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5

		if float(Time.get_ticks_msec() - int(outcome["started"])) / 1000.0 > WALL_CLOCK_LIMIT_SEC:
			break

	if not bool(outcome["done"]):
		_finish_arena(arena, tally, outcome, TIME_SCALE, MIN_SHOTS_PER_MIN, MIN_DAMAGE_TAKEN)


## The sail is bent, and it answers the wind.
##
##   godot --headless src/scenes/voyage.tscn -- --rig
##
## Ships sailed under bare poles for the entire life of the project. Wave 0
## delivered a sail master, `ShipStats.sail_texture` was declared to hold it, and
## no line of code ever read either — and no test noticed, because no test has
## ever asked what a ship looks like.
##
## The sail is a read-out of the wind model rather than decoration, which makes
## "does it respond" a functional question with a functional answer. Yards braced
## sharp when a ship is trying to point, squared as the wind draws aft, and the
## cloth bellying to the side the wind is actually going. Those last two are the
## parts that would break silently and invisibly if a sign were ever flipped,
## because a sail braced or bellied the wrong way still looks like a sail — which
## is exactly how the first version of this shipped past a screenshot.
func _run_rig_test() -> void:
	director.set_process(false)

	var failures: PackedStringArray = []

	# An oared hull must not carry canvas. It is the one stat on the resource the
	# player can see at a glance, and a Dinghy under sail would be a lie about the
	# thing that separates the opening boat from the first real ship. Asked of a
	# built hull rather than of the resource, because whether a rig gets stepped
	# is a decision the ship makes and the stats only inform.
	GameState.fleet = [{"stats_id": &"dinghy", "upgrades": {}}]
	fleet.refit()
	await get_tree().process_frame
	if fleet.selected != null and fleet.selected.has_sail():
		failures.append("the oared Dinghy was given a sail")

	GameState.fleet = [{"stats_id": &"sloop", "upgrades": {}}]
	fleet.refit()
	await get_tree().process_frame
	_update_wind_availability()

	var ship: Ship = fleet.selected
	if ship == null:
		push_error("RIG FAIL: no player hull")
		await _quit_cleanly(1)
		return

	if not ship.has_sail():
		failures.append("a Sloop has no sail on it")
	if WindSystem.instance == null or not WindSystem.instance.active:
		failures.append("the wind never woke up behind a sailed hull")

	if failures.is_empty():
		var open: Vector2 = archipelago.world_bounds.end + Vector2(6000.0, 6000.0)
		camera.set_world_bounds(
			Rect2(open - Vector2(8000.0, 8000.0), Vector2(16000.0, 16000.0))
		)
		ship.global_position = open
		camera.snap_to(open)
		Cull.force_tick()

		# Measured against the live wind rather than a wind forced to a constant:
		# the vector drifts under a degree a second, which is nothing across the
		# couple of seconds each reading takes, and reaching into the system to
		# pin it would be testing a rig that the game never actually sails.
		var readings: Dictionary = {}
		for row: Array in [
			["running", 0.0], ["into_wind", PI],
			["wind_to_port", PI * 0.5], ["wind_to_starboard", -PI * 0.5],
		]:
			var label: String = row[0]
			var turn: float = row[1]
			# `turn` is the heading relative to running dead before the wind.
			var heading: Vector2 = WindSystem.instance.direction.rotated(turn)
			var settle: float = 0.0
			while settle < 2.2:
				ship.stop()
				ship.set_target(null)
				ship.rotation = heading.angle() + PI * 0.5
				await get_tree().physics_frame
				settle += 1.0 / 60.0
			readings[label] = ship.sail_brace()
			# How far downwind the belly is pointing, -1 to 1. Read here rather
			# than after the loop because it depends on the heading being held.
			readings[label + "_lee"] = (
				ship.sail_belly_world().dot(WindSystem.instance.direction)
			)

		var running: float = absf(float(readings["running"]))
		var pointing: float = absf(float(readings["into_wind"]))
		var to_port: float = float(readings["wind_to_port"])
		var to_starboard: float = float(readings["wind_to_starboard"])

		if pointing <= running:
			failures.append(
				"the yards are not braced sharper into the wind than before it (%.2f vs %.2f)"
				% [pointing, running]
			)
		if running > 0.25:
			failures.append(
				"the yards are not square running before the wind (%.2f rad off)" % running
			)
		if signf(to_port) == signf(to_starboard):
			# The sign is the whole tell. A rig braced the same way on both tacks
			# is a rig that is not reading the wind at all, and it looks fine.
			failures.append(
				"the yards brace the same way on both tacks (%.2f, %.2f)"
				% [to_port, to_starboard]
			)
		else:
			print("RIG: running %.2f, close-hauled %.2f, tacks %.2f / %.2f rad" % [
				running, pointing, to_port, to_starboard
			])

		# And the cloth has to be downwind of its own yard, on every point of
		# sail. Wind blows a sail away from itself; a belly on the windward side
		# is the rig being blown through its own spar, and it renders perfectly
		# happily. This is the one assertion in the file that a screenshot could
		# never replace.
		for label: String in ["running", "into_wind", "wind_to_port", "wind_to_starboard"]:
			var downwind: float = float(readings[label + "_lee"])
			if downwind <= 0.05:
				failures.append(
					"the canvas bellies into the wind %s (%.2f downwind)"
					% [label.replace("_", " "), downwind]
				)

		# Shot the rigging away and the canvas has to go with it, or a crippled
		# ship still looks like it is under sail.
		ship.sails = 0.0
		await get_tree().physics_frame
		await get_tree().physics_frame
		var canvas: Node = ship.find_child("Sail", true, false)
		if canvas != null and (canvas as CanvasItem).visible:
			failures.append("a ship with its rigging shot away is still showing canvas")

	if failures.is_empty():
		print("RIG PASS")
		await _quit_cleanly(0)
	else:
		for line: String in failures:
			push_error("RIG FAIL: %s" % line)
		await _quit_cleanly(1)


## They have to be able to take it back.
##
##   godot --headless src/scenes/voyage.tscn -- --reprisal
##
## Three properties, and all three are design rules rather than correctness ones,
## which is why they are asserted rather than eyeballed:
##
##   * an ignored reprisal **takes the island** — otherwise the warning is theatre
##     and the player learns to sail on;
##   * a fought reprisal **saves it** — otherwise it is a tax, not a decision;
##   * the tribes **never** raid, so the opening islands stay safe to leave.
##
## The middle one is the one that would rot quietly. A raid that cannot be beaten
## looks identical to one that has not been beaten *yet*, and the difference only
## shows up as players slowly deciding the mechanic is unfair.
func _run_reprisal_test() -> void:
	const TIME_SCALE: float = 8.0
	var TICK: float = (1.0 / 60.0) * TIME_SCALE

	director.set_process(false)
	tutorial.enabled = false
	var failures: PackedStringArray = []

	# A held island belonging to somebody who wants it back.
	var target: Island = null
	var tribal: Island = null
	for raw: Variant in archipelago.islands:
		if not is_instance_valid(raw) or raw == archipelago.home:
			continue
		var island: Island = raw
		var owner: Faction = FactionLibrary.get_faction(island.def.faction)
		if tribal == null and island.def.faction == &"tribes":
			tribal = island
		if target == null and owner.raids() and not island.def.has_castle:
			target = island
	if target == null or tribal == null:
		push_error("REPRISAL FAIL: voyage has no raiding-faction island, or no tribal one")
		await _quit_cleanly(1)
		return

	# The tribes never come back. Asserted before anything else, because it is the
	# rule that protects a brand new player and the one most likely to be broken
	# by somebody tuning raid pressure without reading why it is zero.
	tribal.capture()
	await get_tree().physics_frame
	if raids.force_raid(tribal):
		failures.append(
			"a reprisal was launched on %s, which is the tribes' — they do not"
			% tribal.def.display_name
			+ " campaign, and the opening islands have to be safe to leave"
		)

	Engine.time_scale = TIME_SCALE

	# --- Ignored: the island falls -------------------------------------------
	target.capture()
	await get_tree().physics_frame
	# Well out of the way, so the reprisal is genuinely unopposed. PLAYER_PRESENCE
	# would otherwise hold the island for free.
	var away: Vector2 = target.global_position + Vector2(9000.0, 9000.0)
	camera.set_world_bounds(Rect2(away - Vector2(9000.0, 9000.0), Vector2(24000.0, 24000.0)))
	for ship: Ship in fleet.living_ships():
		ship.global_position = away
		ship.stop()
	camera.snap_to(away)
	Cull.force_tick()

	var warned: Dictionary = {"seen": false}
	EventBus.island_threatened.connect(func(_i: Node2D, _f: String, _s: float) -> void:
		warned["seen"] = true
	)
	if not raids.force_raid(target):
		failures.append("no reprisal could be launched on %s" % target.def.display_name)
	await get_tree().physics_frame
	if not bool(warned["seen"]):
		failures.append("the reprisal was never announced — the player got no warning")

	var elapsed: float = 0.0
	while elapsed < 140.0 and target.is_captured:
		await get_tree().physics_frame
		elapsed += TICK
	if target.is_captured:
		failures.append(
			"%s was still held after %.0fs of unopposed reprisal — an ignored raid"
			% [target.def.display_name, elapsed]
			+ " has to actually cost the island or the warning is theatre"
		)
	else:
		# And the raiders that took it are the garrison. Nothing was despawned.
		var standing: int = director.active_enemy_count()
		if standing == 0:
			failures.append(
				"%s fell but left no garrison — the squadron that took it should be"
				% target.def.display_name
				+ " what the player has to beat to take it back"
			)

	# --- Fought: the island holds --------------------------------------------
	target.capture()
	await get_tree().physics_frame
	if not raids.force_raid(target):
		failures.append("a second reprisal could not be launched")
	# Let it arrive, then sink it.
	var waited: float = 0.0
	while waited < 60.0 and raids.raid_target() != null and director.active_enemy_count() == 0:
		await get_tree().physics_frame
		waited += TICK
	var sunk: int = 0
	for raw: Variant in ships_parent.get_children():
		var enemy: EnemyShip = raw as EnemyShip
		if enemy != null and enemy.alive:
			enemy.apply_damage(enemy.stats.max_hull * 4.0, AmmoType.Bar.HULL, fleet.selected)
			sunk += 1
	if sunk == 0:
		failures.append("the reprisal never put a hull on the water to fight")
	var settle: float = 0.0
	while settle < 20.0 and raids.raid_target() != null:
		await get_tree().physics_frame
		settle += TICK
	if not target.is_captured:
		failures.append(
			"%s was lost even though every raider was sunk — beating a reprisal"
			% target.def.display_name
			+ " has to save the island or it is a tax rather than a decision"
		)

	Engine.time_scale = 1.0
	print("REPRISAL: warned=%s fell=%s sank=%d held_after=%s" % [
		bool(warned["seen"]), not target.is_captured == false, sunk, target.is_captured
	])

	if failures.is_empty():
		print("REPRISAL PASS")
		await _quit_cleanly(0)
	else:
		for line: String in failures:
			push_error("REPRISAL FAIL: %s" % line)
		await _quit_cleanly(1)


## What tapping the water actually gets you.
##
##   godot --headless src/scenes/voyage.tscn -- --helm
##
## Every other harness here asks whether a system *works*. This one asks whether
## the one control the game has feels like anything, which nothing had ever
## measured — `--smoke` proves a ship reaches an island and `--touch` proves the
## tap arrives at the router, and between them a helm could be arriving three
## ship-lengths past the point you tapped and both would pass.
##
## Four numbers, one per complaint, all of them things a player feels within a
## minute and none of them visible in a screenshot:
##
##   * **overshoot** — how far past the tapped point she ends up;
##   * **response** — how long from a course order to actually being on it;
##   * **handover** — how long a manual course is honoured before the engagement
##     assist takes the helm back;
##   * **rounding** — whether a course to the far side of an island gets there.
##
## Every order here goes through [method Ship.steer_by_hand] rather than
## [method Ship.set_course], and the difference is the whole point of the
## handover measurement. `set_course` is what the engagement assist uses; only
## `steer_by_hand` marks the order as the player's. The first draft of this file
## used `set_course` throughout and duly reported that the assist seized the helm
## 0.2 seconds after a manual course completed — which it does not, because there
## had never been a manual course. A harness that drives the game through the
## wrong entry point measures a game nobody is playing.
func _run_helm_test() -> void:
	const TIME_SCALE: float = 3.0
	## A tap should land you within about a ship's length of the point. Past that
	## the boat is visibly ignoring where you put your finger.
	const MAX_OVERSHOOT_RADII: float = 2.5
	## Seconds from a course order to being within 20 degrees of it, from rest.
	const MAX_RESPONSE_SEC: float = 5.0
	## Seconds a manual course must be honoured after arrival before the assist
	## may take over. Zero means the two fight each other.
	const MIN_HANDOVER_SEC: float = 2.0
	const ROUNDING_BUDGET_SEC: float = 60.0

	## Game time in one physics tick. Every clock below counts in *game* seconds,
	## which is what a player experiences, and the harness runs the world at
	## TIME_SCALE — so a raw 1/60 per frame would measure real seconds and report
	## every duration at a third of its true value. It did, for one round of this:
	## a 2.5-second helm grace period came back as 0.9.
	var TICK: float = (1.0 / 60.0) * TIME_SCALE

	director.set_process(false)
	var failures: PackedStringArray = []

	GameState.fleet = [{"stats_id": &"sloop", "upgrades": {}}]
	fleet.refit()
	await get_tree().process_frame
	_update_wind_availability()

	var ship: Ship = fleet.selected
	if ship == null:
		push_error("HELM FAIL: no player hull")
		await _quit_cleanly(1)
		return

	var open: Vector2 = archipelago.world_bounds.end + Vector2(7000.0, 7000.0)
	camera.set_world_bounds(Rect2(open - Vector2(9000.0, 9000.0), Vector2(18000.0, 18000.0)))
	camera.snap_to(open)
	Engine.time_scale = TIME_SCALE

	# --- Overshoot -----------------------------------------------------------
	#
	# Sailed from a standing start to a point well inside the hull's own coasting
	# distance, which is the case a player generates constantly: tap somewhere
	# close, expect to stop there.
	var overshoot_radii: float = 0.0
	for run: int in 2:
		ship.global_position = open
		ship.rotation = 0.0
		ship.stop()
		ship.set_target(null)
		await get_tree().physics_frame
		var mark: Vector2 = open + Vector2(0.0, -1200.0)
		ship.steer_by_hand(mark)
		var elapsed: float = 0.0
		var closest: float = INF
		var furthest_after: float = 0.0
		var reached: bool = false
		while elapsed < 30.0:
			await get_tree().physics_frame
			elapsed += TICK
			var d: float = ship.global_position.distance_to(mark)
			closest = minf(closest, d)
			if not ship.has_nav_target:
				reached = true
			if reached:
				furthest_after = maxf(furthest_after, d)
				if ship.velocity.length() < 4.0:
					break
		overshoot_radii = maxf(overshoot_radii, furthest_after / maxf(1.0, ship.stats.hull_radius))

	if overshoot_radii > MAX_OVERSHOOT_RADII:
		failures.append(
			"she coasts %.1f hull radii past the tapped point (limit %.1f) — the helm"
			% [overshoot_radii, MAX_OVERSHOOT_RADII]
			+ " drives at full speed right up to the mark and only then lets go"
		)

	# --- Response ------------------------------------------------------------
	#
	# From rest, ordered to reverse course. The worst case and the one that reads
	# as the boat ignoring you: stopped hulls have almost no rudder authority.
	ship.global_position = open
	ship.rotation = 0.0
	ship.stop()
	ship.set_target(null)
	await get_tree().physics_frame
	var astern: Vector2 = open + Vector2(0.0, 2400.0)
	ship.steer_by_hand(astern)
	var response: float = 0.0
	while response < 20.0:
		await get_tree().physics_frame
		response += TICK
		var want: Vector2 = (astern - ship.global_position).normalized()
		if absf(ship.forward().angle_to(want)) < deg_to_rad(20.0):
			break
	if response >= MAX_RESPONSE_SEC:
		failures.append(
			"%.1fs from a course order to being on it from rest (limit %.0f) — a"
			% [response, MAX_RESPONSE_SEC]
			+ " stopped hull has almost no rudder and cannot build way while turning"
		)

	# --- Handover ------------------------------------------------------------
	#
	# The player's order has to outlive its own arrival. Otherwise steering out of
	# a bad position and having the assist immediately sail you back into it is
	# the whole experience of trying to fight and steer at once.
	var handover: float = -1.0
	var mark_ship: EnemyShip = SpawnDirector.ENEMY_SCENE.instantiate() as EnemyShip
	mark_ship.faction = FactionLibrary.get_faction(&"navy_crown")
	mark_ship.stats = mark_ship.faction.build(&"enemy_sloop")
	mark_ship.global_position = open + Vector2(900.0, 0.0)
	ships_parent.add_child(mark_ship)
	mark_ship.stop()
	mark_ship.set_physics_process(false)
	await get_tree().physics_frame

	ship.global_position = open
	ship.stop()
	# Spike both batteries, the way `--ram` does and for the same reason. This
	# measures who has the helm, not who wins — and with the guns live the marked
	# hull simply sank partway through, which took the target away and left the
	# measurement reading as "the assist never moved her".
	ship.cannons_hp = 0.0
	mark_ship.cannons_hp = 0.0
	ship.set_target(mark_ship)
	var held: Vector2 = open + Vector2(-260.0, 0.0)
	ship.steer_by_hand(held)
	var settle: float = 0.0
	while settle < 25.0 and ship.has_nav_target:
		await get_tree().physics_frame
		settle += TICK
	# Arrived under the player's own order. How long before the assist issues one
	# of its own?
	#
	# Detected by a new course appearing, not by the hull moving. She is still
	# carrying way at the moment she arrives, and "has she travelled sixty units"
	# — which is what this asked first — cannot tell coasting apart from being
	# steered, so it reported the assist seizing the helm while the assist was
	# still waiting its turn.
	var free: float = 0.0
	while free < 8.0:
		await get_tree().physics_frame
		free += TICK
		if ship.has_nav_target:
			break
	handover = free
	if handover < MIN_HANDOVER_SEC:
		failures.append(
			"the engagement assist takes the helm back %.1fs after a manual course"
			% handover
			+ " completes (needs %.1f) — steering and fighting fight each other"
			% MIN_HANDOVER_SEC
		)
	if is_instance_valid(mark_ship):
		mark_ship.queue_free()

	# --- Rounding ------------------------------------------------------------
	#
	# A course to the far side of an island. The one navigation task the game asks
	# for constantly — every harbour is on the other side of something — and the
	# one the avoidance field can fail at silently by orbiting forever.
	# The biggest, raggedest island in the voyage, and the destination is its
	# harbour rather than a point in open water. That is the navigation task the
	# game actually asks for over and over — every quay is round the far side of
	# something, tucked into the most sheltered bay on the coast — and it is a
	# far harder one than clearing a headland: the anchor sits *inside* the
	# standoff band, so the avoidance field has to let go of the hull at exactly
	# the point it is pushing hardest.
	var island: Island = null
	for raw: Variant in archipelago.islands:
		if not is_instance_valid(raw) or raw == archipelago.home:
			continue
		var candidate: Island = raw
		if island == null or candidate.def.radius > island.def.radius:
			island = candidate
	var rounded: bool = true
	var rounding: float = 0.0
	if island != null:
		# Back inside the real world. The tests above pushed the camera bounds out
		# to a box round the open-water station, and leaving them there put the
		# island thousands of units outside them — the camera could not follow, the
		# hull culled to dormant, and `--helm` reported a ship that "could not round
		# the island" when what it had actually done was stop being simulated.
		camera.set_world_bounds(archipelago.world_bounds)
		# Start diametrically opposite the harbour, so the whole island is in the
		# way whichever direction she breaks.
		var far_side: Vector2 = island.anchor_point
		var from_harbour: Vector2 = (far_side - island.global_position).normalized()
		var reach: float = island.def.radius + 700.0
		ship.global_position = island.global_position - from_harbour * reach
		ship.rotation = 0.0
		ship.stop()
		ship.set_target(null)
		await get_tree().physics_frame
		camera.snap_to(ship.global_position)
		Cull.force_tick()
		ship.steer_by_hand(far_side)
		rounded = false
		# How far round the island she actually gets, and how close she comes to
		# the beach doing it. "Did not arrive" is not a diagnosis: crawling round
		# at half speed, orbiting at a fixed bearing and grinding along the sand
		# all fail identically and want completely different fixes.
		var swept: float = 0.0
		var last_bearing: float = (ship.global_position - island.global_position).angle()
		var nearest_coast: float = INF
		while rounding < ROUNDING_BUDGET_SEC:
			await get_tree().physics_frame
			rounding += TICK
			var bearing: float = (ship.global_position - island.global_position).angle()
			swept += absf(angle_difference(last_bearing, bearing))
			last_bearing = bearing
			nearest_coast = minf(nearest_coast, island.distance_to_coast(ship.global_position))
			if ship.global_position.distance_to(far_side) < ship.stats.hull_radius * 3.0:
				rounded = true
				break
			# Re-issue, the way a player would when the boat is visibly not going
			# where it was sent. If even that cannot get her round, it is stuck.
			if not ship.has_nav_target:
				ship.steer_by_hand(far_side)
		if not rounded:
			failures.append(
				"she could not round a %.0f-unit island in %.0fs — got %.0f deg round it,"
				% [island.def.radius, ROUNDING_BUDGET_SEC, rad_to_deg(swept)]
				+ " closest approach %.0f units of coast" % nearest_coast
			)

	Engine.time_scale = 1.0
	print(
		"HELM: overshoot %.1f radii, response %.1fs, handover %.1fs, rounding %s (%.0fs)"
		% [overshoot_radii, response, handover, "yes" if rounded else "NO", rounding]
	)

	if failures.is_empty():
		print("HELM PASS")
		await _quit_cleanly(0)
	else:
		for line: String in failures:
			push_error("HELM FAIL: %s" % line)
		await _quit_cleanly(1)


## A ship under canvas has to sail, not drive.
##
##   godot --headless src/scenes/voyage.tscn -- --sailing
##
## Leeway is the reason this exists. A hull whose track lies a few degrees to
## *windward* of her heading looks very nearly identical to one crabbing the
## correct way — she is still visibly not going where she points, the wake still
## streams off a quarter, and every screenshot of it is convincing. It is only
## wrong if you know where the wind is. That is precisely the class of bug the rig
## harness was written for when the canvas could belly to windward, and it is the
## same fix: assert the sign against the wind vector, because no amount of looking
## will catch it.
##
## The magnitudes are checked loosely and the *shape* strictly. What must hold is
## that leeway exists on a reach, vanishes dead before the wind, and never once
## points the wrong way.
func _run_sailing_test() -> void:
	## Long enough for the hull to reach its speed cap and for the velocity lerp
	## to settle onto the new track — hull_grip is 3.2, so this is several time
	## constants.
	const SETTLE_SEC: float = 4.0
	## A beam reach must produce at least this much crab, in degrees, or the effect
	## is present in the arithmetic and invisible on screen.
	const MIN_REACH_LEEWAY_DEG: float = 3.0
	## And running dead downwind must produce almost none.
	const MAX_RUNNING_LEEWAY_DEG: float = 1.0

	director.set_process(false)
	var failures: PackedStringArray = []

	GameState.fleet = [{"stats_id": &"sloop", "upgrades": {}}]
	fleet.refit()
	await get_tree().process_frame
	_update_wind_availability()

	var ship: Ship = fleet.selected
	if ship == null or WindSystem.instance == null or not WindSystem.instance.active:
		push_error("SAILING FAIL: no sailed hull, or the wind never woke up")
		await _quit_cleanly(1)
		return

	# Open water well outside the archipelago, so nothing here is coast avoidance
	# steering the ship off her heading.
	var open: Vector2 = archipelago.world_bounds.end + Vector2(6000.0, 6000.0)
	camera.set_world_bounds(Rect2(open - Vector2(9000.0, 9000.0), Vector2(18000.0, 18000.0)))
	camera.snap_to(open)

	var readings: Dictionary = {}
	for row: Array in [
		["running", 0.0], ["reach_to_port", PI * 0.5],
		["reach_to_starboard", -PI * 0.5], ["close_hauled", PI * 0.75],
	]:
		var label: String = row[0]
		# `turn` is the heading relative to running dead before the wind.
		var heading: Vector2 = WindSystem.instance.direction.rotated(float(row[1]))
		ship.global_position = open
		ship.rotation = heading.angle() + PI * 0.5
		ship.stop()
		ship.set_target(null)
		Cull.force_tick()
		# Sailed rather than forced: a course far enough off that she spends the
		# whole reading making way toward it, which is the code path the game runs.
		ship.set_course(open + heading * 9000.0)

		var settle: float = 0.0
		while settle < SETTLE_SEC:
			await get_tree().physics_frame
			settle += 1.0 / 60.0

		readings[label] = {
			# Signed angle from where she points to where she is actually going.
			"leeway": rad_to_deg(ship.forward().angle_to(ship.velocity)),
			"beam": ship.beam_wind(),
			"speed": ship.velocity.length(),
		}

	for label: String in readings:
		var r: Dictionary = readings[label]
		var leeway: float = float(r["leeway"])
		var beam: float = float(r["beam"])
		if float(r["speed"]) < 10.0:
			failures.append("%s: the hull never got under way (%.1f px/s)" % [label, r["speed"]])
			continue
		# The sign check, and the whole reason for the file.
		if absf(beam) > 0.15 and signf(leeway) != signf(beam):
			failures.append(
				"%s: she makes leeway to *windward* (%.1f deg of crab against %.2f of beam wind)"
				% [label, leeway, beam]
			)

	var to_port: float = float(readings["reach_to_port"]["leeway"])
	var to_starboard: float = float(readings["reach_to_starboard"]["leeway"])
	if signf(to_port) == signf(to_starboard):
		failures.append(
			"she crabs the same way on both tacks (%.1f, %.1f deg) — the leeway is not"
			% [to_port, to_starboard]
			+ " reading the wind at all"
		)
	var reach: float = maxf(absf(to_port), absf(to_starboard))
	if reach < MIN_REACH_LEEWAY_DEG:
		failures.append(
			"only %.1f deg of leeway on a beam reach — it is in the arithmetic and not"
			% reach
			+ " on the screen (floor is %.0f)" % MIN_REACH_LEEWAY_DEG
		)
	var running: float = absf(float(readings["running"]["leeway"]))
	if running > MAX_RUNNING_LEEWAY_DEG:
		failures.append(
			"%.1f deg of leeway running dead before the wind — there is no side force"
			% running
			+ " on that point of sail"
		)

	# And an oared hull is not a sailing one. This is the stat the whole
	# distinction hangs off, and the player's first sail is supposed to change how
	# the boat *moves*, not only how fast it goes.
	GameState.fleet = [{"stats_id": &"dinghy", "upgrades": {}}]
	fleet.refit()
	await get_tree().process_frame
	var rowed: Ship = fleet.selected
	if rowed != null:
		rowed.global_position = open
		rowed.rotation = WindSystem.instance.direction.rotated(PI * 0.5).angle() + PI * 0.5
		await get_tree().physics_frame
		if not is_zero_approx(rowed.beam_wind()) or rowed.leeway_drift() != Vector2.ZERO:
			failures.append("an oared hull is making leeway — rowers pull a boat where it points")

	print("SAILING: " + ", ".join(PackedStringArray([
		"running %.1f" % float(readings["running"]["leeway"]),
		"reach %.1f / %.1f" % [to_port, to_starboard],
		"close-hauled %.1f deg" % float(readings["close_hauled"]["leeway"]),
	])))

	if failures.is_empty():
		print("SAILING PASS")
		await _quit_cleanly(0)
	else:
		for line: String in failures:
			push_error("SAILING FAIL: %s" % line)
		await _quit_cleanly(1)


## Every cue has a file behind it, and the music actually reacts to the game.
##
##   godot --headless src/scenes/voyage.tscn -- --audio
##
## Audio is the one subsystem whose entire failure mode is silence, and this
## project is already built to fail that way politely: [AudioManager] skips a
## missing file with one warning at boot and then plays nothing, forever, with no
## error at any call site. A cue whose path is wrong is indistinguishable from a
## cue nobody has triggered yet.
##
## The music needs its own check for a different reason. `Audio.play_music()` had
## a working crossfade and was never called from anywhere in the project — the
## only thing in the codebase that referenced music at all was the save file,
## faithfully persisting the volume of a bus with nothing on it. Layered music is
## a *gameplay* system, so "does the score respond to a fight" is a functional
## question, and it is answered here by moving the intensity and reading the
## faders rather than by anyone putting headphones on.
func _run_audio_test() -> void:
	var failures: PackedStringArray = []

	# --- Every declared cue resolves ---------------------------------------
	var silent: PackedStringArray = []
	for id: StringName in Audio.LIBRARY:
		var path: String = Audio.LIBRARY[id]["path"]
		if not ResourceLoader.exists(path):
			silent.append("%s (%s)" % [id, path])
	if not silent.is_empty():
		failures.append(
			"%d cue(s) have no file and would be silent: %s"
			% [silent.size(), ", ".join(silent)]
		)

	# --- The stems exist and are the same length ---------------------------
	var lengths: Array[float] = []
	for id: StringName in Audio.MUSIC_LAYERS:
		var path: String = Audio.MUSIC_LAYER_PATHS[id]
		if not ResourceLoader.exists(path):
			failures.append("music stem '%s' is missing (%s)" % [id, path])
			continue
		var stream: AudioStream = load(path)
		lengths.append(stream.get_length())
		var wav := stream as AudioStreamWAV
		# A stem that does not loop leaves the score playing once and then
		# stopping dead, which reads as the game having crashed its audio.
		if wav != null and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			failures.append("music stem '%s' is not set to loop" % id)
	if lengths.size() > 1:
		for length: float in lengths:
			# Stems are only stems if they stay in lockstep. Drift would not error;
			# it would slowly turn a chord into a cluster over a voyage.
			if absf(length - lengths[0]) > 0.001:
				failures.append("music stems differ in length: %s" % str(lengths))
				break

	if not ResourceLoader.exists(Audio.AMBIENCE_PATH):
		failures.append("the sea ambience is missing (%s)" % Audio.AMBIENCE_PATH)

	# --- It is actually running --------------------------------------------
	if music == null or not is_instance_valid(music):
		failures.append("the voyage built no MusicDirector")
	elif not Audio.is_music_playing():
		failures.append("the music stems are not playing")
	elif not Audio.is_ambience_playing():
		failures.append("the sea is not playing")
	else:
		# --- And it reacts -------------------------------------------------
		# The director is silenced for this half. It samples the world at 4 Hz and
		# writes the result over whatever is set, so driving the faders by hand
		# while it runs means measuring the fleet sitting quietly at Port Royal —
		# which is what the first version of this did, and it reported that the
		# combat stem never comes up. Its own reading is checked separately below.
		music.set_process(false)
		var readings: Dictionary = {}
		for intensity: float in [0.0, 1.0]:
			Audio.set_music_intensity(intensity)
			# Waited in seconds, not frames. A headless frame is a few milliseconds,
			# so forty of them is a fraction of a second — the first version of
			# this read the calm bed at 0.38 while it was still travelling and
			# reported that the stems were not additive.
			#
			# Four seconds covers the slow fall as well: the rise and fall rates
			# are deliberately asymmetric, and settling back down takes the longer
			# of the two.
			await get_tree().create_timer(4.0).timeout
			var row: Dictionary = {}
			for id: StringName in Audio.MUSIC_LAYERS:
				row[id] = Audio.music_layer_gain(id)
			readings[intensity] = row

		var quiet: Dictionary = readings[0.0]
		var loud: Dictionary = readings[1.0]
		if float(loud[&"combat"]) <= float(quiet[&"combat"]):
			failures.append(
				"the combat stem does not come up with intensity (%.2f quiet, %.2f loud)"
				% [float(quiet[&"combat"]), float(loud[&"combat"])]
			)
		if float(quiet[&"combat"]) > 0.05:
			failures.append(
				"the combat stem is audible on an empty sea (%.2f)" % float(quiet[&"combat"])
			)
		if float(loud[&"calm"]) < 0.9:
			# Additive, not exclusive: the bed stays under everything, or the
			# escalation is a track change with extra steps.
			failures.append(
				"the calm bed drops out under combat (%.2f) — the stems are not additive"
				% float(loud[&"calm"])
			)
		else:
			print("AUDIO: quiet %s / loud %s" % [str(quiet), str(loud)])

		# --- Derived from the world, not from a timer ----------------------
		music.set_process(true)
		var measured: float = music.measure_intensity()
		if measured > 0.35:
			failures.append(
				"intensity reads %.2f with the fleet alone at its home port" % measured
			)

	print("AUDIO: %d cues, %d stems" % [Audio.LIBRARY.size(), Audio.MUSIC_LAYERS.size()])
	if failures.is_empty():
		print("AUDIO PASS")
		await _quit_cleanly(0)
	else:
		for line: String in failures:
			push_error("AUDIO FAIL: %s" % line)
		await _quit_cleanly(1)


## Plays the opening of the game and reports whether it can actually be survived.
##
##   godot --headless src/scenes/voyage.tscn -- --ladder
##
## Every other harness here answers "does this work". This one answers "is the
## start of the game fair", which is a different question and the one that was
## going unasked. `--smoke` sails at island one, which is deliberately one skiff
## on a still sea, and stops. `--arena` starts from a mid-game Brig with 400 gold
## banked. Between the two of them nothing had ever played islands one, two and
## three *in order*, off the starting Dinghy, spending only what the run actually
## earned — which is the only part of the game every single player sees.
##
## The shape of the early ramp is not obvious from the tables, either. Island one
## is a skiff; islands two and three are each one Navy Sloop, which out-guns the
## Dinghy two barrels to one, out-ranges it by 80 m, and has ten more hull. The
## design's answer is that you shop in between — so the harness shops, with the
## most obvious policy a new player could have, and reports whether that is
## enough. If it is not, the difficulty is not a skill check, it is a wall.
##
## Deliberately not a pass/fail on *winning*: a harness that steers in a straight
## line is a much worse captain than a person, so it should be losing hull the
## whole way. What it fails on is being wiped, which no amount of clumsiness
## should cause this early, and on finishing the third island with nothing left.
func _run_ladder_test() -> void:
	## Five, not three. Islands one to three are the ones a player complains about
	## first, but a fix that only moves the wall from island two to island four is
	## not a fix — and island four is the first tier 3, which is where the count
	## goes up, the shipyard starts sending reinforcements and the fireship
	## arrives. The run has to reach that to prove anything.
	##
	## `--islands=N` runs further, and there is now a reason to: the chain has
	## five factions along it ([constant Archipelago.FACTION_LADDER]) and the
	## default five only ever meets two of them. Balance written for the Armada,
	## the Marine Royale and the Brethren and never played is balance nobody has
	## checked. Twelve is the whole voyage, and it is a slow run — the default
	## stays five so the everyday check stays quick.
	const DEFAULT_ISLANDS: int = 5
	const PER_ISLAND_SEC: float = 120.0
	const TIME_SCALE: float = 6.0
	## Per island rather than a flat budget, so a longer run gets longer rather
	## than getting cut off at the same place a short one finishes.
	const WALL_CLOCK_PER_ISLAND_SEC: float = 104.0

	var islands_wanted: int = DEFAULT_ISLANDS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--islands="):
			islands_wanted = maxi(1, int(arg.trim_prefix("--islands=")))
	var wall_clock_limit: float = WALL_CLOCK_PER_ISLAND_SEC * float(islands_wanted)

	## Same lookout range `--smoke` uses: the harness has to see a garrison the
	## way a player does rather than waiting until the arcs already overlap.
	const ACQUIRE_RANGE: float = 2600.0
	## Time allowed to sail to the mooring and get the cargo off the quay.
	const LANDING_SEC: float = 70.0
	## Fraction of maximum hull the fleet must still have at the end.
	## Low on purpose — this is a floor against "the opening is unsurvivable",
	## not a target.
	const MIN_HULL_LEFT: float = 0.15
	## And how close any single island may bring the fleet to sinking.
	##
	## Measured lows across seeds run from about a quarter to about three
	## quarters, so ten per cent is clear of the noise and still catches the thing
	## that went wrong here: before the opening chest paid for the first hull,
	## island two ended on nine per cent with the arithmetic against the player
	## from the start. A survivable-but-terrifying fight and an unwinnable one both
	## end in a capture when the harness gets lucky, and only this number tells
	## them apart.
	const MIN_HULL_LOW: float = 0.10

	var failures: PackedStringArray = []
	var rows: Array[String] = []
	# Dictionary because a lambda captures locals by value; see `--smoke`.
	var run: Dictionary = {"at": "the approach", "taken": 0.0, "low": 1.0}
	EventBus.ship_damaged.connect(func(ship: Node2D, amount: float, _bar: StringName) -> void:
		if ship is Ship and (ship as Ship).team == Teams.PLAYER:
			run["taken"] = float(run["taken"]) + amount
	)

	fleet.fleet_emptied.connect(func() -> void:
		# Naming the island matters more than it looks: "the opening is not
		# survivable" is not actionable, and the answer moved from island two to
		# island five twice during this work without the message changing a word.
		for line: String in rows:
			print(line)
		push_error(
			"LADDER FAIL: the fleet was wiped out at %s — seed %d"
			% [run["at"], GameState.voyage_seed]
		)
		await _quit_cleanly(1)
	)

	# The chain in the order a player meets it. `islands[0]` is home.
	#
	# Not the castle. It is a different fight with different rules — the keep
	# shrugs off everything until every battery around it is silenced — and it has
	# a harness of its own that knows that (`--castle`). This one steers at the
	# nearest threat and would charge the keep, die, and report a balance failure
	# on the one island whose balance it has not measured. A gate that fails for a
	# reason unrelated to what it tests is a gate people learn to ignore.
	var chain: Array[Island] = []
	for island: Island in archipelago.islands:
		if island.def.id == &"home" or island.def.has_castle:
			continue
		chain.append(island)
		if chain.size() >= islands_wanted:
			break
	# A voyage is 8–12 islands, so "run the whole chain" means a different number
	# on every seed. Asking for more than there are is answered with all of them
	# rather than with a failure — the run is still the thing that was wanted.
	# Fewer than the default is a real problem with the generator.
	if chain.size() < mini(islands_wanted, DEFAULT_ISLANDS):
		push_error("LADDER FAIL: voyage has only %d islands" % chain.size())
		await _quit_cleanly(1)
		return

	print("LADDER: seed %d" % GameState.voyage_seed)
	Engine.time_scale = TIME_SCALE
	var started_msec: int = Time.get_ticks_msec()

	for index: int in chain.size():
		var goal: Island = chain[index]
		var before: float = _fleet_hull_fraction()
		var before_gold: int = GameState.total_gold()
		var elapsed: float = 0.0
		run["taken"] = 0.0
		run["low"] = before
		# The flag is in the label because with factions the tier no longer says
		# what kind of fight this is. "Island 8, tier 4" and "island 8, tier 4,
		# Brethren" are the same sentence with and without the answer in it.
		var flag: String = FactionLibrary.get_faction(goal.def.faction).display_name
		run["at"] = "island %d (%s, tier %d, %s)" % [
			index + 1, goal.def.display_name, goal.def.tier, flag
		]

		while elapsed < PER_ISLAND_SEC and not goal.is_captured:
			if float(Time.get_ticks_msec() - started_msec) / 1000.0 > wall_clock_limit:
				break
			var ship: Ship = fleet.selected
			if ship != null and is_instance_valid(ship):
				var enemy: Node2D = Grid.query_nearest(
					ship.global_position, ACQUIRE_RANGE, SpatialGrid.KIND_ENEMY_SHIP
				)
				# Only this island's garrison. Islands sit ~2,200 m apart and this
				# acquires at 2,600, so without the scope the run charges the next
				# island's defenders the moment one falls.
				if enemy != null and not _near_island(enemy, goal):
					enemy = null
				var aim: Node2D = _ladder_target(ship, goal, enemy)
				if aim != null:
					EventBus.intent_target.emit(aim)
				else:
					ship.set_course(goal.global_position)
			run["low"] = minf(float(run["low"]), _fleet_hull_fraction())
			await get_tree().create_timer(0.4).timeout
			elapsed += 0.4

		if not goal.is_captured:
			rows.append(
				"LADDER: island %d (%s, tier %d) NOT TAKEN in %ds"
				% [index + 1, goal.def.display_name, goal.def.tier, roundi(elapsed)]
			)
			failures.append(
				"island %d (%s, tier %d) was not taken in %ds"
				% [index + 1, goal.def.display_name, goal.def.tier, roundi(PER_ISLAND_SEC)]
			)
			break

		# Then go and get the cargo, because that is where the money is and
		# leaving it is not something a player does. Clearing the garrison pays
		# only prize money — 14 gold off the opening skiff — and the chest is ten
		# times that. Sailing on without it made the harness's first run look like
		# a brutal difficulty curve when what it had actually modelled was a
		# player who never collects. The boat launches itself once a hull is on
		# the mooring; see [method SpawnDirector._tick_landing].
		var landing: float = 0.0
		while landing < LANDING_SEC and goal.def.is_treasure_remaining():
			var hull: Ship = fleet.selected
			if hull != null and is_instance_valid(hull):
				hull.set_target(null)
				hull.set_course(hull.clamp_to_navigable(goal.anchor_point))
			await get_tree().create_timer(0.4).timeout
			landing += 0.4
		if goal.def.is_treasure_remaining():
			failures.append(
				"the cargo on %s could not be collected in %ds"
				% [goal.def.display_name, roundi(LANDING_SEC)]
			)
			break

		if float(run["low"]) < MIN_HULL_LOW:
			failures.append(
				"island %d (%s, tier %d) took the fleet down to %d%% hull"
				% [
					index + 1, goal.def.display_name, goal.def.tier,
					roundi(float(run["low"]) * 100.0),
				]
			)

		# Reported after the cargo is aboard, because the takings are the point
		# and the prize money alone is a tenth of them. Reporting it at the moment
		# of capture had the opening island paying 14 gold and then somehow
		# affording a 260-gold hull two lines later.
		#
		# The low-water mark rather than the hull at the end: what matters is how
		# close the fight came, and a ship that drops to a fifth and then takes
		# the island looks untouched by the time anything samples it.
		var hull_id: StringName = GameState.fleet[0].get("stats_id", GameState.STARTING_HULL)
		rows.append(
			"LADDER: island %d (%s, t%d, %s) in %ds — %s, hull %d%% -> %d%% (low %d%%), took %d, gold %d -> %d"
			% [
				index + 1, goal.def.display_name, goal.def.tier, flag, roundi(elapsed), hull_id,
				roundi(before * 100.0), roundi(_fleet_hull_fraction() * 100.0),
				roundi(float(run["low"]) * 100.0), roundi(float(run["taken"])),
				before_gold, GameState.total_gold(),
			]
		)

		# The port. Repair and bank exactly as [method _on_open_port] does, then
		# spend, then refit — the same order and the same calls the real screen
		# makes, so the harness cannot pass on a path the player has not got.
		GameState.bank_carried_gold()
		fleet.repair_all()
		var spent: String = _ladder_shop()
		fleet.refit()
		await get_tree().process_frame
		rows.append("LADDER:   port — %s, %d gold left" % [spent, GameState.banked_gold])

	Engine.time_scale = 1.0

	var left: float = _fleet_hull_fraction()
	if failures.is_empty() and left < MIN_HULL_LEFT:
		failures.append(
			"the fleet came off the last island on %d%% hull, with the castle "
			% roundi(left * 100.0)
			+ "still ahead of it"
		)

	for line: String in rows:
		print(line)
	if failures.is_empty():
		print(
			"LADDER PASS: %d islands taken, %d%% hull left"
			% [chain.size(), roundi(left * 100.0)]
		)
		await _quit_cleanly(0)
	else:
		for line: String in failures:
			push_error("LADDER FAIL: %s" % line)
		await _quit_cleanly(1)


## What the harness shoots at next, in the order a player who understands the
## island would pick.
##
## Not simply "the nearest ship". Capturing an island wants its garrison gone
## *and* its batteries silent, and from tier 3 a shipyard keeps feeding hulls in
## until it is rubble — so a run that only ever shoots ships fights a queue that
## never ends. That is exactly how this harness first failed on island five: 120
## seconds, plenty of kills, island still hostile, and nothing in the output
## saying the yard was the reason.
##
## Anything in a position to hurt you comes first. Buildings are for the gaps.
##
## The threshold took two tries in both directions. At 1,100 the run broke off
## mid-duel to shell a shed and was wiped at island four, having taken it with two
## thirds of its hull the run before. With no threshold at all — ships first,
## always — it never reached the yard on a tier-3 island, because the yard is
## exactly what keeps a ship on the water: the garrison refills faster than the
## gaps appear, capture wants the garrison empty, and the run fought an unwinnable
## queue until it sank. 750 is inside a Navy Sloop's standoff, so anything that
## has actually closed still gets shot first.
func _ladder_target(ship: Ship, goal: Island, enemy: Node2D) -> Node2D:
	const CLOSE_THREAT: float = 750.0
	var pressed: bool = (
		enemy != null
		and ship.global_position.distance_to(enemy.global_position) <= CLOSE_THREAT
	)
	if pressed:
		return enemy
	# Then the yard, because it is the tap that stops the queue.
	if goal.can_reinforce():
		return goal.shipyard
	# Then the batteries, which capture requires silenced and which nothing else
	# in this run would ever fire at.
	for entry: Variant in goal.forts:
		if is_instance_valid(entry) and (entry as Fort).alive:
			return entry as Node2D
	return null


## Spends the takings the way an unsophisticated player plausibly would: buy the
## better hull the moment it is affordable, otherwise buy the cheapest thing on
## the shelf until the money runs out.
##
## Not an optimal policy, and it should not be. The question the harness exists to
## answer is whether the opening survives *ordinary* play, so modelling a player
## who knows the tables would answer the wrong question.
func _ladder_shop() -> String:
	var entry: Dictionary = GameState.fleet[0]
	var bought: PackedStringArray = []

	var hull_id: StringName = entry.get("stats_id", GameState.STARTING_HULL)
	var better: StringName = ShipStatsLibrary.next_tier(hull_id)
	var hull_cost: int = ShipStatsLibrary.upgrade_cost(hull_id)
	if better != &"" and hull_cost > 0 and GameState.spend_gold(hull_cost):
		entry["stats_id"] = better
		bought.append(String(better))

	var upgrades: Dictionary = entry.get("upgrades", {})
	while true:
		var cheapest: StringName = &""
		var best: int = -1
		for id: StringName in UpgradeLibrary.ORDER:
			var cost: int = UpgradeLibrary.next_cost(upgrades, id)
			if cost < 0 or cost > GameState.banked_gold:
				continue
			if best < 0 or cost < best:
				best = cost
				cheapest = id
		if cheapest == &"":
			break
		if not UpgradeLibrary.purchase(upgrades, cheapest):
			break
		bought.append("%s %d" % [cheapest, UpgradeLibrary.level_of(upgrades, cheapest)])
	entry["upgrades"] = upgrades

	return "bought nothing" if bought.is_empty() else "bought " + ", ".join(bought)


## Hull left across the whole fleet, 0 to 1.
func _fleet_hull_fraction() -> float:
	var have: float = 0.0
	var most: float = 0.0
	for ship: Ship in fleet.living_ships():
		have += ship.hull
		most += ship.stats.max_hull
	return 0.0 if most <= 0.0 else have / most


## A beaten ship that gets clear must stop counting as a defender.
##
##   godot --headless src/scenes/voyage.tscn -- --rout
##
## Written because two full arena runs produced zero routs: a competent hull kills
## a fleeing ship long before it reaches open water, so the path never executes in
## ordinary play and would sit there rotting. It matters in exactly the case the
## harness cannot reach — the player who lets one go — and if it broke, the
## symptom would be an island that simply refuses to be captured while a ship the
## player cannot even see sails away from it forever.
func _run_rout_test() -> void:
	const TIME_SCALE: float = 4.0
	const PATIENCE: float = 20.0

	await get_tree().create_timer(0.4).timeout

	# Tier 2 or better, deliberately. The opening island fields skiffs, and a skiff
	# is SWARM doctrine — it is sent to be spent and never breaks off, so it can
	# never rout. Pointing this test at the nearest island picked exactly that
	# hull, which then charged back in and got shot, and the failure read as
	# "pruned by dying, not by routing". The enemy has to be one that can run.
	var goal: Island = null
	var nearest: float = INF
	for raw: Variant in archipelago.islands:
		if not is_instance_valid(raw) or raw == archipelago.home:
			continue
		var island: Island = raw
		if island.def.tier < 2:
			continue
		var d: float = island.distance_to_coast(fleet.centroid())
		if d < nearest:
			nearest = d
			goal = island
	if goal == null:
		push_error("ROUT FAIL: no island above tier 1 to rout a defender from")
		await _quit_cleanly(1)
		return

	# Sail in far enough to wake the garrison up.
	var toward: Vector2 = (fleet.centroid() - goal.global_position).normalized()
	for ship: Ship in fleet.living_ships():
		ship.global_position = ship.clamp_to_navigable(
			goal.global_position + toward * (goal.def.radius + goal.def.alert_radius * 0.5)
		)
	camera.snap_to(fleet.centroid())

	Engine.time_scale = TIME_SCALE
	var waited: float = 0.0
	while waited < PATIENCE and director.active_enemy_count() == 0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25

	var before: int = director.active_enemy_count()
	var failures: PackedStringArray = []
	if before == 0:
		failures.append("the island never fielded a garrison to rout")
	else:
		# Beat one hull and put it where a beaten hull ends up. Both halves are
		# required: the rout condition is "broken *and* clear", so a ship that is
		# merely damaged or merely distant must not count.
		var beaten: EnemyShip = null
		for node: Node in ships_parent.get_children():
			var enemy := node as EnemyShip
			if enemy == null or not enemy.alive:
				continue
			# Only a hull whose doctrine lets it break off in the first place.
			if enemy.stats.doctrine == ShipStats.Doctrine.SWARM:
				continue
			beaten = enemy
			break

		if beaten == null:
			failures.append("the garrison spawned nothing that is able to break off")
		else:
			# Call the fleet off first: a ball already in the air, or a fresh
			# broadside, sinks the runner and the test measures the wrong pruning
			# path — which is precisely how the first version failed.
			EventBus.intent_target.emit(null)
			for ship: Ship in fleet.living_ships():
				ship.set_target(null)
			beaten.hull = beaten.stats.max_hull * 0.1
			var away: Vector2 = (
				beaten.global_position - goal.global_position
			).normalized()
			beaten.global_position = goal.global_position + away * (
				goal.def.radius + goal.def.alert_radius * 2.0
			)
			Grid.update(beaten)

			waited = 0.0
			while waited < PATIENCE and director.active_enemy_count() >= before:
				await get_tree().create_timer(0.25).timeout
				waited += 0.25

			if director.active_enemy_count() >= before:
				failures.append(
					"a broken defender %d m clear of the island still counts as a garrison"
					% roundi(goal.distance_to_coast(beaten.global_position))
				)
			elif not beaten.alive:
				failures.append("the defender was pruned by dying, not by routing")
			else:
				print("ROUT: garrison %d -> %d with the runner still afloat, in %.0fs" % [
					before, director.active_enemy_count(), waited
				])

	Engine.time_scale = 1.0
	if failures.is_empty():
		print("ROUT PASS")
		await _quit_cleanly(0)
	else:
		for line: String in failures:
			push_error("ROUT FAIL: %s" % line)
		await _quit_cleanly(1)


## Ramming has to hurt both parties, and hurt the small one more.
##
##   godot --headless src/scenes/voyage.tscn -- --ram
##
## Hulls have always collided and the collision has always done nothing, so the
## risk here is not that ramming breaks — it is that it quietly does not happen
## at all, which is indistinguishable from the state this shipped in for months.
## The asymmetry is the design: the same manoeuvre is a massacre in a Galleon and
## suicide in a Dinghy, and it falls out of the tonnage ratio rather than a
## special case, so it is worth pinning down that the ratio is the right way up.
## Puts the fleet off the castle's seaward side and photographs it.
##
## The fleet has to be moved rather than only the camera: [GameCamera] re-reads
## the fleet centroid every frame, so a bare `snap_to` somewhere else is undone
## on the next `_process` and the frame comes back as open water — which is
## exactly what the first version of this produced.
func _frame_castle(castle: Island) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute("user://shots")
	if hud.has_method(&"dismiss_briefing"):
		hud.call(&"dismiss_briefing")

	# Framed on the keep itself, not the middle of the island — the keep is set
	# back on the far coast and the island is 900 units across, so centring the
	# island puts the thing we came to photograph off the edge of the frame.
	var keep_at: Vector2 = castle.keep.global_position
	var outward: Vector2 = (keep_at - castle.global_position).normalized()
	for ship: Ship in fleet.living_ships():
		ship.global_position = ship.clamp_to_navigable(keep_at + outward * 620.0)
	camera.set_world_bounds(Rect2(
		castle.global_position - Vector2(5000.0, 5000.0), Vector2(10000.0, 10000.0)
	))
	camera.target_zoom = 0.62
	camera.snap_to(keep_at)
	# `snap_to` alone is not enough: GameCamera re-reads the fleet centroid every
	# frame, so the view slides straight back off the keep. `point_out` is the
	# API that actually holds a look somewhere.
	camera.point_out(keep_at, 6.0)
	Cull.force_tick()
	await get_tree().create_timer(1.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shots/castle_00.png")
	print("CASTLE SHOT: %s" % ProjectSettings.globalize_path("user://shots/castle_00.png"))


func _run_ram_test() -> void:
	const TIME_SCALE: float = 3.0
	const PATIENCE: float = 22.0

	director.set_process(false)
	var hits: Dictionary = {"count": 0}
	EventBus.ships_collided.connect(func(_a: Node2D, _b: Node2D, _f: float) -> void:
		hits["count"] += 1
	)

	var open: Vector2 = archipelago.world_bounds.end + Vector2(6000.0, 6000.0)
	camera.set_world_bounds(Rect2(open - Vector2(8000.0, 8000.0), Vector2(16000.0, 16000.0)))

	# A Galleon against a Skiff: the most lopsided pairing in the game, so if the
	# ratio is inverted it will be unmistakable rather than a rounding error.
	GameState.fleet = [{"stats_id": &"galleon", "upgrades": {}}]
	fleet.refit()
	await get_tree().process_frame

	var heavy: Ship = fleet.selected
	heavy.global_position = open
	camera.snap_to(open)

	# Laid out downwind, which is the whole reason this test was ever flaky.
	#
	# A Galleon is a sailing hull, so her speed is the wind's to give: the polar
	# runs from 0.55 of `max_speed` beating upwind to 1.0 on a broad reach. Eighty
	# knots of hull becomes forty-four upwind — under `RAM_MIN_CLOSING_SPEED`, so
	# the contact is correctly not a ram — and the harness had been placing the
	# two ships on a fixed east-west line against a wind that turns. It passed or
	# failed on where the weather happened to be pointing that run.
	#
	# Which is a real rule of the game and worth stating plainly: **you cannot ram
	# upwind.** Running down on a target is not a flourish, it is the difference
	# between a ram and a nudge.
	var run_axis: Vector2 = Vector2.RIGHT
	if WindSystem.instance != null and WindSystem.instance.active:
		run_axis = WindSystem.instance.direction
	var light: EnemyShip = _spawn_test_enemy(&"skiff", open + run_axis * 900.0)
	# Bow to bow before either of them moves.
	#
	# Ramming is deliberately not something a glancing contact counts as — see
	# `RAM_MIN_CLOSING_SPEED`, which prices the closing speed *along the line
	# between the hulls* so that two ships rubbing shoulders are not attacking
	# each other. That rule is correct, and it is also what made this test flaky:
	# left to turn onto their courses, a Galleon skids (velocity lags heading, by
	# design) and the contact came in oblique, with the closing component under
	# the threshold. Diagnosed off the failure message, which had them one unit
	# apart with 119 of relative speed and no ram: not a broken collision handler,
	# a harness staging a sideswipe and calling it a head-on.
	heavy.rotation = (light.global_position - heavy.global_position).angle() + PI * 0.5
	light.rotation = (heavy.global_position - light.global_position).angle() + PI * 0.5

	# And the skiff holds still while the Galleon runs it down.
	#
	# It is a lesser thing than two ships converging, and it is the version that
	# actually tests what this is for. The skiff is an [EnemyShip] with its own
	# helm: it re-decides its course every physics frame, the harness could only
	# countermand that five times a second, and the AI won thirty frames out of
	# thirty-one. What the run staged was not a head-on at all — the two of them
	# spiralled towards each other for a minute of game time and the contact,
	# when it came, was oblique enough that `RAM_MIN_CLOSING_SPEED` correctly
	# refused to call it a ram. Nothing about the collision code was ever wrong.
	#
	# Freezing one hull makes the closing speed the Galleon's own, along the axis,
	# every time. The pricing being tested — both parties hurt, the lighter one
	# more — does not care which of them was moving.
	light.stop()
	light.set_physics_process(false)
	await get_tree().process_frame
	Cull.force_tick()

	# Spike both batteries. This is a test of hulls hitting hulls, and leaving the
	# guns loaded made it a coin flip: a Galleon closing on a Skiff has nine
	# hundred units to cross, the Skiff drifts into a broadside arc somewhere in
	# the middle of it, and one salvo is enough — the Skiff sank before contact in
	# roughly one run out of three, and the harness reported it as "never
	# registered a collision", which is true and completely misleading.
	heavy.cannons_hp = 0.0
	light.cannons_hp = 0.0

	var heavy_before: float = heavy.hull
	var light_before: float = light.hull

	# Drive the Galleon onto her. The closing speed is then unambiguous, which
	# matters because a glancing contact is deliberately not a ram and a test that
	# produced one would be testing the wrong thing.
	Engine.time_scale = TIME_SCALE
	var waited: float = 0.0
	var died_early: String = ""
	while waited < PATIENCE and int(hits["count"]) == 0:
		if not is_instance_valid(heavy) or not heavy.alive:
			died_early = "the galleon"
			break
		if not is_instance_valid(light) or not light.alive:
			died_early = "the skiff"
			break
		# Aimed well beyond the skiff, so the Galleon is still under way when she
		# hits rather than settling onto a waypoint.
		#
		# This is the last thing the flakiness turned out to be, and the most
		# interesting. A course set on or just past the target is a course a ship
		# *arrives* at, and arriving means slowing down: the diagnostic caught two
		# runs touching the skiff at 53 and 55 units a second against a
		# `RAM_MIN_CLOSING_SPEED` of 55. Not a collision failure — a Galleon
		# genuinely coasting into something too gently to call it a ram, which is
		# the rule working. Aiming nine hundred units past keeps her at full speed
		# through the contact.
		#
		# Worth knowing as a player, too: to ram something, tap the water *behind*
		# it. Tapping the ship itself is an order to pull up alongside.
		const OVERSHOOT: float = 900.0
		heavy.set_target(null)
		heavy.nav_target = light.global_position + (
			light.global_position - heavy.global_position
		).normalized() * OVERSHOOT
		heavy.has_nav_target = true
		light.suppress_engage_steering = true
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	Engine.time_scale = 1.0

	var failures: PackedStringArray = []
	if died_early != "":
		# Distinct from the collision failure below, because the two have nothing
		# to do with each other and one masquerading as the other is what cost an
		# afternoon.
		failures.append("%s sank before the two hulls ever met" % died_early)
	elif int(hits["count"]) == 0:
		# With the gap and the closing speed in it, because "no collision" on its
		# own does not distinguish a broken collision handler from two ships that
		# never actually got near each other.
		var gap: float = -1.0
		var closing: float = 0.0
		if is_instance_valid(heavy) and is_instance_valid(light):
			gap = heavy.global_position.distance_to(light.global_position) - (
				heavy.stats.hull_radius + light.stats.hull_radius
			)
			closing = (heavy.velocity - light.velocity).length()
		failures.append(
			"a Galleon run straight onto a stationary skiff never registered a "
			+ "collision (%.0f units apart after %.0fs, closing at %.0f)"
			% [gap, waited, closing]
		)
	else:
		var heavy_took: float = heavy_before - heavy.hull
		var light_took: float = (light_before - light.hull) if is_instance_valid(light) else light_before
		if light_took <= 0.0:
			failures.append("the rammed skiff took no damage")
		elif heavy_took <= 0.0:
			# Both parties, always. A free ram is a dominant strategy and it would
			# make every other verb in the game pointless.
			failures.append("the ramming galleon took no damage — ramming must cost both")
		elif light_took <= heavy_took:
			failures.append(
				"the skiff took %.0f and the galleon %.0f — the tonnage ratio is inverted"
				% [light_took, heavy_took]
			)
		else:
			print("RAM: galleon took %.0f, skiff took %.0f, in %.0fs" % [
				heavy_took, light_took, waited
			])

	if failures.is_empty():
		print("RAM PASS")
		await _quit_cleanly(0)
	else:
		for line: String in failures:
			push_error("RAM FAIL: %s" % line)
		await _quit_cleanly(1)


## The castle at the end of a voyage has to be the hardest thing in it, and its
## two-phase shape has to actually hold.
##
##   godot --headless src/scenes/voyage.tscn -- --castle
##
## For most of this project the final island was the *least* defended one on the
## map: the generator authored `fort_cannons = 0` and `has_shipyard = false` for
## it, so the climax of a twenty-minute run was four ships in open water, and a
## tier-4 island on the way there was strictly harder. Nothing caught it, because
## nothing ever asked what was on the objective.
##
## Four things are asserted, and every one of them is a way the boss can silently
## stop being a boss: the castle exists and is ringed with batteries; the keep
## shrugs off fire while any battery stands; it becomes vulnerable when the last
## one falls; and the island cannot be captured with the walls still up.
func _run_castle_test() -> void:
	director.set_process(false)

	var castle: Island = null
	for raw: Variant in archipelago.islands:
		if is_instance_valid(raw) and (raw as Island).def.has_castle:
			castle = raw
			break

	var failures: PackedStringArray = []
	if castle == null:
		push_error("CASTLE FAIL: the voyage generated no castle island at all")
		await _quit_cleanly(1)
		return

	# --- It has to be defended ---------------------------------------------
	if castle.def.fort_cannons <= 0:
		failures.append(
			"%s is the objective of the voyage and fields no batteries"
			% castle.def.display_name
		)
	if not castle.keep_standing():
		failures.append("the castle island has no keep on it")
	if castle.def.garrison_ships < 3:
		failures.append("the castle fields only %d defenders" % castle.def.garrison_ships)

	if castle.keep_standing():
		var keep: CastleKeep = castle.keep
		var batteries: int = castle.forts_remaining()

		# --- Armoured while the ring stands --------------------------------
		if batteries <= 0:
			failures.append("the castle's batteries were gone before the fight started")
		elif not keep.is_armoured():
			failures.append("the keep is not armoured despite %d batteries standing" % batteries)
		else:
			var before: float = keep.health
			keep.apply_damage(100.0, AmmoType.Bar.HULL, null)
			var soaked: float = before - keep.health
			if soaked > 100.0 * CastleKeep.ARMOURED_DAMAGE_MUL * 1.5:
				failures.append(
					"the armoured keep took %.0f of a 100-point broadside — the walls do nothing"
					% soaked
				)
			elif soaked <= 0.0:
				# Zero is its own failure: a target that visibly cannot be hurt at
				# all reads as a bug, and the player concludes the game is broken
				# rather than that they are shooting the wrong thing.
				failures.append("the armoured keep took no damage at all, which reads as a bug")

			# Framed while the ring is still standing, which is the only moment
			# the armour shell exists to be looked at. The keep is drawn from
			# vector shapes with no authored art and its armour is a *rule*
			# expressed as a graphic — neither is something a headless assertion
			# can judge.
			await _frame_castle(castle)

			# --- And it must not be capturable with the walls up ------------
			for entry: Variant in castle.forts.duplicate():
				if is_instance_valid(entry):
					(entry as Fort).apply_damage(9999.0, AmmoType.Bar.HULL, null)
			await get_tree().process_frame

			if castle.forts_remaining() != 0:
				failures.append("the batteries survived being shot to pieces")
			elif keep.is_armoured():
				failures.append("the keep is still armoured with every battery silenced")
			else:
				var open_before: float = keep.health
				keep.apply_damage(100.0, AmmoType.Bar.HULL, null)
				var open_soaked: float = open_before - keep.health
				if open_soaked < 90.0:
					failures.append(
						"an unarmoured keep still soaked %.0f of a 100-point broadside"
						% (100.0 - open_soaked)
					)
				else:
					print(
						"CASTLE: %s — %d batteries, keep %.0f hp; armoured hit %.0f, open hit %.0f"
						% [
							castle.def.display_name, batteries, CastleKeep.MAX_HEALTH,
							soaked, open_soaked,
						]
					)

	if failures.is_empty():
		print("CASTLE PASS")
		await _quit_cleanly(0)
	else:
		for line: String in failures:
			push_error("CASTLE FAIL: %s" % line)
		await _quit_cleanly(1)


## Frames an actual engagement, which is the only way to check the combat readout.
##
##   godot src/scenes/voyage.tscn -- --shot-combat
##
## The plain `--shot` run sails at an island and photographs whatever it finds,
## and what it mostly finds is open water — none of its fourteen frames reliably
## contains a marked target, so none of them shows the firing arcs, the reload
## meter inside them, a mortar's telegraph ring or a boarding. Those are exactly
## the things that are unreadable-or-fine rather than working-or-broken, and a
## rendered frame is the only thing that can tell the difference.
func _capture_combat() -> void:
	var dir: String = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Quality.set_tier_manual(Quality.Tier.HIGH)

	GameState.fleet = [{"stats_id": &"brig", "upgrades": {&"plating": 2}}]
	GameState.banked_gold = 400
	fleet.refit()
	await get_tree().process_frame
	if hud.has_method(&"dismiss_briefing"):
		hud.call(&"dismiss_briefing")

	var arena: Island = _heaviest_island(3)
	if arena == null:
		push_error("--shot-combat: no hostile island to fight")
		await _quit_cleanly(1)
		return

	var bearing: Vector2 = (arena.anchor_point - arena.global_position).normalized()
	for ship: Ship in fleet.living_ships():
		ship.global_position = ship.clamp_to_navigable(
			arena.global_position + bearing * (arena.def.radius + arena.def.alert_radius * 0.8)
		)
	camera.snap_to(fleet.centroid())
	camera.target_zoom = 0.7
	await get_tree().process_frame

	fleet.fleet_emptied.connect(func() -> void:
		print("COMBAT SHOTS: fleet lost — stopping early. %s"
			% ProjectSettings.globalize_path(dir))
		await _quit_cleanly(0)
	)

	for shot: int in 10:
		var lead: Ship = fleet.selected
		if lead != null and is_instance_valid(lead) and lead.alive:
			var enemy: Node2D = Grid.query_nearest(
				lead.global_position, 2400.0,
				SpatialGrid.KIND_ENEMY_SHIP | SpatialGrid.KIND_STRUCTURE
			)
			if enemy != null:
				EventBus.intent_target.emit(enemy)
			else:
				lead.set_course(arena.global_position)
		await get_tree().create_timer(2.2).timeout
		if hud.has_method(&"dismiss_briefing"):
			hud.call(&"dismiss_briefing")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"%s/combat_%02d.png" % [dir, shot]
		)

	print("COMBAT SHOTS: %s" % ProjectSettings.globalize_path(dir))
	await _quit_cleanly(0)


## Drives a boarding end to end, in both the outcomes it has.
##
##   godot --headless src/scenes/voyage.tscn -- --board
##
## Boarding is the only way in this game to end a fight with the other ship still
## floating, and it is the only reason grape shot exists. It is also the most
## conditional thing in the game — it needs a marked target, a thinned crew and
## two hulls alongside at the same moment — so it is exactly the feature that can
## rot untouched while every other harness goes on passing.
##
## Both branches are exercised, because they are different code and the wrong one
## silently firing is a real bug the player would read as the game eating a prize:
## with a berth free the hull must join the fleet; with none it must pay out
## instead. And it goes through the same prompt the player does — a boarding that
## works but cannot be reached is not a feature.
func _run_boarding_test() -> void:
	const TIME_SCALE: float = 3.0
	const PATIENCE: float = 14.0

	director.set_process(false)
	var taken: Dictionary = {"kept": 0, "stripped": 0}
	EventBus.prize_taken.connect(func(_name: String, kept: bool) -> void:
		taken["kept" if kept else "stripped"] += 1
	)

	var open: Vector2 = archipelago.world_bounds.end + Vector2(6000.0, 6000.0)
	camera.set_world_bounds(Rect2(open - Vector2(8000.0, 8000.0), Vector2(16000.0, 16000.0)))

	var failures: PackedStringArray = []
	Engine.time_scale = TIME_SCALE

	# Round one: no spare berth, so the prize must be stripped for cargo.
	var stripped: Dictionary = await _board_once(open, 1, PATIENCE)
	if not bool(stripped["boarded"]):
		failures.append("with no berth free, the boarding prompt never appeared or never resolved")
	elif int(taken["stripped"]) != 1 or int(taken["kept"]) != 0:
		failures.append(
			"a prize taken with no berth free should be stripped, not kept (kept=%d stripped=%d)"
			% [int(taken["kept"]), int(taken["stripped"])]
		)
	elif int(stripped["gold_after"]) <= int(stripped["gold_before"]):
		failures.append("stripping a prize paid nothing")

	# Round two: a berth standing empty, so the hull must actually join.
	var owned_before: int = 0
	taken["kept"] = 0
	taken["stripped"] = 0
	GameState.fleet_slots = 2
	var kept: Dictionary = await _board_once(open + Vector2(0.0, 5000.0), 2, PATIENCE)
	owned_before = int(kept["fleet_before"])
	if not bool(kept["boarded"]):
		failures.append("with a berth free, the boarding never resolved")
	elif int(taken["kept"]) != 1:
		failures.append("a prize taken with a berth free was not kept")
	elif GameState.fleet.size() != owned_before + 1:
		failures.append(
			"the captured hull never reached the roster (%d hulls, expected %d)"
			% [GameState.fleet.size(), owned_before + 1]
		)
	elif fleet.living_ships().size() < 2:
		failures.append("the captured hull is on the roster but not on the water")

	Engine.time_scale = 1.0
	if failures.is_empty():
		print("BOARD PASS")
		await _quit_cleanly(0)
	else:
		for line: String in failures:
			push_error("BOARD FAIL: %s" % line)
		await _quit_cleanly(1)


## Sets up one boardable enemy alongside the player and takes it, through the
## HUD's own prompt rather than by calling the fleet controller directly — the
## button being wired to the action is half of what is under test.
func _board_once(at: Vector2, slots: int, patience: float) -> Dictionary:
	GameState.fleet_slots = slots
	GameState.fleet = [{"stats_id": &"brig", "upgrades": {}}]
	fleet.refit()
	await get_tree().process_frame

	var boarder: Ship = fleet.selected
	boarder.global_position = at
	boarder.stop()
	camera.snap_to(at)

	var prize: EnemyShip = _spawn_test_enemy(&"enemy_sloop", at + Vector2(90.0, 0.0))
	# Grape shot's job, applied directly: sweep the deck until the crew cannot
	# hold her. This is the state the whole ammo system exists to produce.
	prize.apply_crew_loss(0.5)
	prize.stop()
	await get_tree().process_frame
	Cull.force_tick()

	# Mark her, which is what a player does before boarding anything.
	EventBus.intent_target.emit(prize)

	var result: Dictionary = {
		"boarded": false,
		"gold_before": GameState.total_gold(),
		"gold_after": 0,
		"fleet_before": GameState.fleet.size(),
	}

	var waited: float = 0.0
	var pressed: bool = false
	while waited < patience:
		# Both hulls held still: the grapple range is a real distance and two
		# ships left to their own devices drift out of it.
		if is_instance_valid(boarder):
			boarder.stop()
		if is_instance_valid(prize) and prize.alive:
			prize.stop()

		if not pressed:
			var button: Button = hud.find_child("BoardButton", true, false) as Button
			if button != null and button.visible:
				button.pressed.emit()
				pressed = true
		elif not fleet.is_boarding():
			result["boarded"] = true
			break

		await get_tree().create_timer(0.2).timeout
		waited += 0.2

	result["gold_after"] = GameState.total_gold()
	return result


## Proves the two enemies that are not gun duels actually do their one thing.
##
##   godot --headless src/scenes/voyage.tscn -- --doctrine
##
## A fireship that never reaches anything is a slow skiff with no guns, and a
## bomb ketch whose telegraph never appears is unavoidable damage from off
## screen. Both fail *silently* — the ships still spawn, still sail, still get
## shot at, and every other harness in the project would go on passing. So each
## is put in front of a stationary target and asked to perform.
##
## Deliberately in open water rather than at an island: this is a test of two
## brains, and running it inside a live garrison would let a stray broadside from
## something else decide the result.
func _run_doctrine_test() -> void:
	const TIME_SCALE: float = 4.0
	const PATIENCE: float = 26.0

	# The archipelago is live around us and its garrisons contain both of the
	# hulls under test. Left running, the director alerts whatever island the mark
	# was parked near and the counters below happily tally *its* fireships and
	# *its* shells — which is exactly how the first version of this test reported
	# a fireship doing six detonations' worth of damage and a bomb ketch firing
	# with no telegraph. Silence the director; nothing here needs it.
	director.set_process(false)

	var fired: Dictionary = {"mortar": 0, "detonations": 0}
	EventBus.shot_fired.connect(func(_a: Node2D, ammo: StringName, _c: Vector2, _d: Vector2) -> void:
		if ammo == &"mortar":
			fired["mortar"] += 1
	)
	EventBus.fireship_detonated.connect(func(_at: Vector2) -> void:
		fired["detonations"] += 1
	)

	# A hull tough enough to survive being tested on, held still: the point is
	# what the *enemy* does, and a target manoeuvring away would make a failure to
	# arrive ambiguous.
	GameState.fleet = [{"stats_id": &"galleon", "upgrades": {&"plating": 4}}]
	fleet.refit()
	await get_tree().process_frame

	var mark: Ship = fleet.selected
	if mark == null:
		push_error("DOCTRINE FAIL: no player hull to test against")
		await _quit_cleanly(1)
		return
	# Outside the archipelago entirely, not merely in a gap in it. The centre of
	# the world bounds is open water on a map but it sits inside somebody's alert
	# radius on most seeds, and a coastline in reach would have the enemies under
	# test steering around land instead of at the mark.
	var open: Vector2 = archipelago.world_bounds.end + Vector2(6000.0, 6000.0)
	mark.global_position = open
	mark.stop()
	# The camera is clamped to the voyage bounds, and this test water is outside
	# them on purpose — so the limits have to come too. Without this the camera
	# stays pinned at the edge of the archipelago, the cull rect never covers the
	# test, and every ship in it goes DORMANT: nothing runs, nothing happens, and
	# both doctrines "fail" without ever having been asked a question.
	camera.set_world_bounds(Rect2(open - Vector2(8000.0, 8000.0), Vector2(16000.0, 16000.0)))
	camera.snap_to(open)
	Cull.force_tick()

	var failures: PackedStringArray = []
	Engine.time_scale = TIME_SCALE

	# --- The fireship has to arrive and go up -------------------------------
	var burner: EnemyShip = _spawn_test_enemy(&"fireship", open + Vector2(1500.0, 0.0))
	var hull_before: float = mark.hull
	var waited: float = 0.0
	while waited < PATIENCE and int(fired["detonations"]) == 0:
		mark.stop()
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if int(fired["detonations"]) == 0:
		failures.append(
			"a fireship spent %.0fs closing on a stationary hull and never detonated" % waited
		)
	elif mark.hull >= hull_before:
		failures.append("a fireship detonated alongside and did no damage")
	else:
		print("DOCTRINE: fireship closed and detonated in %.0fs for %.0f hull" % [
			waited, hull_before - mark.hull
		])
	if is_instance_valid(burner):
		burner.queue_free()

	# --- The bomb ketch has to telegraph, then fire --------------------------
	mark.repair_all()
	var ketch: EnemyShip = _spawn_test_enemy(&"bomb_ketch", open + Vector2(0.0, -1000.0))
	var saw_ring: bool = false
	waited = 0.0
	while waited < PATIENCE and int(fired["mortar"]) == 0:
		mark.stop()
		if is_instance_valid(ketch) and not ketch.mortar_telegraph().is_empty():
			saw_ring = true
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if int(fired["mortar"]) == 0:
		failures.append("a bomb ketch held station for %.0fs and never fired" % waited)
	elif not saw_ring:
		# The shell landing is not the feature. Being able to see where it will
		# land, before it is fired, is the entire feature.
		failures.append("a bomb ketch fired with no telegraph — the shell is undodgeable")
	else:
		print("DOCTRINE: bomb ketch telegraphed and fired in %.0fs" % waited)
	if is_instance_valid(ketch):
		ketch.queue_free()

	Engine.time_scale = 1.0
	if failures.is_empty():
		print("DOCTRINE PASS")
		await _quit_cleanly(0)
	else:
		for line: String in failures:
			push_error("DOCTRINE FAIL: %s" % line)
		await _quit_cleanly(1)


func _spawn_test_enemy(hull: StringName, at: Vector2) -> EnemyShip:
	var enemy: EnemyShip = preload(
		"res://src/entities/ships/enemy_ship.tscn"
	).instantiate() as EnemyShip
	enemy.stats = ShipStatsLibrary.get_stats(hull)
	enemy.global_position = at
	ships_parent.add_child(enemy)
	enemy.assign_station(at, 400.0, 4000.0)
	return enemy


## Reports an arena run and quits. Called either when the clock runs out or the
## instant the fleet is lost, whichever comes first — see [method _run_arena_test].
func _finish_arena(
	arena: Island,
	tally: Dictionary,
	outcome: Dictionary,
	time_scale: float,
	min_shots_per_min: float,
	min_damage_taken: float
) -> void:
	outcome["done"] = true
	# Game time actually fought, taken off the wall clock: the wipe path can
	# arrive between two ticks of the loop's own counter.
	var elapsed: float = maxf(
		0.5, float(Time.get_ticks_msec() - int(outcome["started"])) / 1000.0 * time_scale
	)
	Engine.time_scale = 1.0

	var shots_per_min: float = float(tally["shots"]) / maxf(0.01, elapsed / 60.0)
	print(
		("ARENA: island=%s tier=%d fought=%.0fs shots=%d (%.1f/min) hits=%d rakes=%d"
		+ " sunk=%d damage_taken=%.0f music_peak=%.2f captured=%s survived=%s")
		% [
			arena.def.display_name, arena.def.tier, elapsed,
			int(tally["shots"]), shots_per_min, int(tally["impacts"]), int(tally["rakes"]),
			int(tally["sunk"]), float(tally["taken"]), float(tally["music_peak"]),
			arena.is_captured, not bool(outcome["wiped"]),
		]
	)

	var failures: PackedStringArray = []
	if shots_per_min < min_shots_per_min:
		failures.append(
			"only %.1f shots a minute — the fight has gone quiet (floor is %.0f)"
			% [shots_per_min, min_shots_per_min]
		)
	if int(tally["impacts"]) == 0:
		failures.append("nothing the player fired ever connected")
	if int(tally["sunk"]) == 0:
		failures.append("a mid-game hull sank nothing in %.0fs" % elapsed)
	if float(tally["taken"]) < min_damage_taken:
		failures.append("the garrison never landed a single hit — there is no fight here")
	if float(tally["music_peak"]) < 0.4:
		# 0.4 is where the combat stem starts coming in. A whole island fight that
		# never crosses it means the score sat on the calm bed through a battle,
		# which is the failure the layering exists to prevent.
		failures.append(
			"the music never escalated past %.2f during an entire island fight"
			% float(tally["music_peak"])
		)

	if failures.is_empty():
		print("ARENA PASS")
		await _quit_cleanly(0)
	else:
		for line: String in failures:
			push_error("ARENA FAIL: %s" % line)
		await _quit_cleanly(1)


## The island the arena fights: the heaviest one at or below [param max_tier].
##
## Deliberately the middle of the voyage rather than the end of it. The outer
## islands are balanced against a fleet of two or three hulls, and this harness
## drives exactly one, badly — it sails at whatever is nearest and never uses the
## helm it exists to measure. Pointing it at a tier-5 island measures nothing
## except that five guns beat one, which was never in doubt.
func _heaviest_island(max_tier: int = 3) -> Island:
	var best: Island = null
	for raw: Variant in archipelago.islands:
		if not is_instance_valid(raw):
			continue
		var island: Island = raw
		if island == archipelago.home or island.is_captured or island.def.has_castle:
			continue
		if island.def.tier > max_tier:
			continue
		if best == null or island.def.tier > best.def.tier:
			best = island
	return best


## Screenshots the fleet roster with every card state in one frame.
##
##   godot src/scenes/voyage.tscn -- --shot-fleet
##
## A three-berth fleet is the only configuration that shows what the panel is
## for, and reaching one in play means a diamond, eight hundred gold and most of
## a voyage. So it is built here: a knocked-about flagship, a healthy escort, and
## a berth whose hull is still at the yard — which is precisely the state that
## used to leave the fleet badge reading "1 / 1" with no explanation.
func _capture_fleet() -> void:
	var dir: String = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(0.6).timeout
	if hud.has_method(&"dismiss_briefing"):
		hud.call(&"dismiss_briefing")
	await get_tree().process_frame

	GameState.banked_gold = 640
	GameState.add_gold(210)
	GameState.fleet[0] = {"stats_id": &"sloop", "upgrades": {&"plating": 2, &"gunnery": 1}}
	GameState.fleet.append({"stats_id": &"sloop", "upgrades": {}})
	fleet.refit()

	var hulls: Array[Ship] = fleet.living_ships()
	if hulls.is_empty():
		push_error("--shot-fleet: no player ship to photograph")
		await _quit_cleanly(1)
		return
	hulls[0].apply_damage(46.0, AmmoType.Bar.HULL, null)
	hulls[0].apply_damage(22.0, AmmoType.Bar.SAILS, null)
	hulls[0].apply_crew_loss(0.35)

	# The third berth is added *after* the refit on purpose: that is what a hull
	# bought in a port looks like until the fleet sails.
	GameState.fleet.append({"stats_id": &"sloop", "upgrades": {}})
	EventBus.fleet_changed.emit()

	# Through the badge itself rather than through show_fleet(). The panel being
	# right and the badge being wired to it are two different things, and the badge
	# is a transparent button laid over a panel — exactly the sort of arrangement
	# that renders perfectly and swallows every tap.
	var badge: Button = hud.find_child("FleetButton", true, false) as Button
	if badge == null:
		push_error("--shot-fleet: the HUD has no fleet badge to press")
		await _quit_cleanly(1)
		return
	badge.pressed.emit()
	await get_tree().create_timer(0.6).timeout
	var panel: Node = hud.get_node_or_null(^"Fleet")
	if panel == null:
		push_error("--shot-fleet: pressing the fleet badge opened nothing")
		await _quit_cleanly(1)
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/fleet_00.png" % dir)

	# And the bottom of the list, where the berth with no hull in it lives.
	if panel != null:
		for node: Node in panel.find_children("*", "ScrollContainer", true, false):
			(node as ScrollContainer).scroll_vertical = 4000
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/fleet_01_scrolled.png" % dir)

	if hud.has_method(&"dismiss_fleet"):
		hud.call(&"dismiss_fleet")
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/fleet_02_hud.png" % dir)

	print("FLEET SHOT: %s" % ProjectSettings.globalize_path(dir))
	await _quit_cleanly(0)


## Musters one hull under every flag in the game, in one frame.
##
##   godot src/scenes/voyage.tscn -- --shot-flags
##
## A flag has exactly one job: to answer "whose ship is that" from further away
## than the player can count gunports. That job is not verifiable from the code —
## five [Color] pairs on a page tell you nothing about whether they are five
## *different things* on open water at gameplay zoom, through a wave field, at
## thirty pixels, in whatever direction the wind happens to be blowing.
##
## The Brethren are the reason this exists. Their field is very nearly black,
## which is right for a pirate and is also the one value that could plausibly
## vanish into deep water — and there is no way to find that out except to look.
##
## Lined up rather than photographed in play, because in play the five factions
## are thousands of metres apart and eight islands of progression apart. Side by
## side is the comparison that matters: the failure mode is not "this flag is
## invisible", it is "these two are the same flag".
func _capture_flags() -> void:
	## Far enough apart that the hulls do not collide and shove each other out of
	## the frame while the shot is being set up, close enough that all of them fit.
	const SPACING: float = 112.0
	## One hull for everybody, so the only difference in the frame is the colours.
	## A Sloop because it is the hull the player spends most of the game looking
	## at, and because it carries canvas — a flag has to stay legible next to a
	## large pale sail, which is the hardest background it gets.
	const MUSTER_HULL: StringName = &"enemy_sloop"

	var dir: String = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(0.6).timeout
	if hud.has_method(&"dismiss_briefing"):
		hud.call(&"dismiss_briefing")

	# The player's own hull is refitted to the muster hull and left in the middle
	# of the line rather than being spawned alongside it, because the camera
	# follows the fleet and will not be talked out of it — `snap_to` puts the view
	# where you ask and the next frame walks it back to the flagship. Standing the
	# flagship where the shot wants to be is the version of that argument nobody
	# has to win.
	GameState.fleet[0] = {"stats_id": MUSTER_HULL, "upgrades": {}}
	fleet.refit()
	await get_tree().process_frame

	var lead: Ship = fleet.selected
	if lead == null or not is_instance_valid(lead):
		push_error("--shot-flags: no player hull to muster on")
		await _quit_cleanly(1)
		return

	# Out in open water, well clear of any coast: sand and surf behind a flag
	# would be a different legibility question from the one being asked, and the
	# answer that matters is the one over deep water.
	var centre: Vector2 = lead.global_position
	var flags: Array[StringName] = []
	flags.append_array(FactionLibrary.ORDER)

	# The player sits in the middle with the factions either side of them, which
	# is also the comparison most worth having: their crimson has to be nobody
	# else's, and the Brethren's black is the one it could be mistaken for.
	var slots: int = flags.size() + 1
	var span: float = SPACING * float(slots - 1)
	var player_slot: int = slots / 2
	lead.global_position = centre + Vector2(float(player_slot) * SPACING - span * 0.5, 0.0)
	lead.rotation = 0.0
	lead.stop()

	var slot: int = 0
	for id: StringName in flags:
		if slot == player_slot:
			slot += 1
		var faction: Faction = FactionLibrary.get_faction(id)
		var hull: EnemyShip = SpawnDirector.ENEMY_SCENE.instantiate() as EnemyShip
		hull.faction = faction
		hull.stats = faction.build(MUSTER_HULL)
		hull.global_position = centre + Vector2(float(slot) * SPACING - span * 0.5, 0.0)
		# Beam-on and dead in the water. A ship under way would drift out of the
		# frame before the shutter, and every hull pointing the same way is what
		# makes this a comparison rather than five photographs.
		hull.rotation = 0.0
		ships_parent.add_child(hull)
		hull.stop()
		hull.set_physics_process(false)
		slot += 1

	camera.snap_to(centre)
	# Long enough for the ensigns to settle onto the wind and for the ripple to be
	# somewhere other than its starting phase — a flag caught at rest is the one
	# frame that flatters it.
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/flags_00.png" % dir)

	var names: PackedStringArray = []
	for id: StringName in flags:
		names.append(FactionLibrary.get_faction(id).display_name)
	names.insert(player_slot, "Your Colours")
	print("FLAGS: %s — %s" % [", ".join(names), ProjectSettings.globalize_path(dir)])
	await _quit_cleanly(0)


## Screenshots the port screen on the home island. The port is a modal over a
## paused world, so the normal `--shot` loop never sees it.
##
##   godot src/scenes/voyage.tscn -- --shot-port
func _capture_port() -> void:
	var dir: String = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(0.6).timeout

	var port: Island = archipelago.home
	for island: Island in archipelago.islands:
		if island.is_captured:
			port = island
			break
	if port == null:
		push_error("--shot-port: no captured island to open a port on")
		await _quit_cleanly(1)
		return

	# Clear any briefing first — show_port refuses to stack modals, correctly.
	if hud.has_method(&"dismiss_briefing"):
		hud.call(&"dismiss_briefing")
	await get_tree().process_frame

	# A fresh save banks nothing, so the shot used to be a column of identically
	# dead rows — which is the one state that tells you nothing about how the shop
	# looks. Enough gold for the cheap upgrades and not enough for a new hull puts
	# both the affordable and the unaffordable treatment in the same frame.
	GameState.banked_gold = maxi(GameState.banked_gold, 182)

	EventBus.intent_open_port.emit(port)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/port_00.png" % dir)

	print("PORT SHOT: %s" % ProjectSettings.globalize_path(dir))
	await _quit_cleanly(0)


## Sails to the nearest hostile island and writes frames to `user://shots/`.
## A rendered frame is the only way to check that art, scale, z-order and the
## ocean shader actually agree with each other.
##
##   godot src/scenes/voyage.tscn -- --shot
func _capture_screenshots() -> void:
	var dir: String = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Engine.time_scale = 3.0

	# Pin the tier. Every capture reads back the viewport texture, which stalls the
	# pipeline hard enough that the adaptive controller sees a 30fps game and
	# ratchets to LOW within a few seconds — so the frames used to check the look
	# of the game were the frames of the lowest tier, whatever the device.
	Quality.set_tier_manual(Quality.Tier.HIGH)

	# Bail out if the fleet dies, exactly as the smoke test does. Otherwise the wipe
	# handler routes to the main menu, which frees this node in the middle of the
	# await below — the coroutine simply stops, nothing ever calls quit(), and the
	# harness hangs with no output saying why. Cheap insurance, and the capture run
	# is far more likely to die than the smoke run: it sails straight at whatever is
	# nearest with no regard for its own hull.
	fleet.fleet_emptied.connect(func() -> void:
		print("SHOTS: fleet lost — stopping early. %s" % ProjectSettings.globalize_path(dir))
		await _quit_cleanly(0)
	)

	var shot: int = 0
	var goal: Island = null
	var nearest: float = INF
	for island: Island in archipelago.islands:
		if island.is_captured:
			continue
		var d: float = island.distance_to_coast(fleet.centroid())
		if d < nearest:
			nearest = d
			goal = island

	for step: int in 14:
		if fleet.selected != null and is_instance_valid(fleet.selected) and goal != null:
			var enemy: Node2D = Grid.query_nearest(
				fleet.selected.global_position,
				fleet.selected.stats.cannon_range,
				SpatialGrid.KIND_ENEMY_SHIP
			)
			if enemy != null:
				EventBus.intent_target.emit(enemy)
			else:
				fleet.selected.set_course(goal.anchor_point)
		await get_tree().create_timer(4.0).timeout
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png("%s/shot_%02d.png" % [dir, shot])
		shot += 1
		# Capture the wind intro on the first frame, then close it — it pauses the
		# tree, so leaving it up would give us fourteen identical screenshots.
		if hud.has_method(&"dismiss_briefing"):
			hud.call(&"dismiss_briefing")
		if hud.has_method(&"dismiss_port"):
			hud.call(&"dismiss_port")

	print("SHOTS: %s" % ProjectSettings.globalize_path(dir))
	await _quit_cleanly(0)


## Headless smoke test: sail at the nearest hostile island, let the fight happen,
## and assert that the loop actually turned over. Run in CI so a broken voyage
## cannot reach GitHub Pages.
##
##   godot --headless src/scenes/voyage.tscn -- --smoke
func _run_smoke_test() -> void:
	# Long enough for a sailed hull beating upwind to still reach an island, since
	# that is the slowest the game legitimately gets.
	const SECONDS: float = 80.0
	## Headless has no vsync, so game time is still wall time. Speed it up rather
	## than making CI wait a real minute for a ship to sail across the map.
	const TIME_SCALE: float = 6.0
	## Hard wall-clock ceiling. Without it a stall anywhere in the game hangs CI
	## until the job times out with no clue as to why.
	const WALL_CLOCK_LIMIT_SEC: float = 90.0
	## Same radius the minimap uses for contacts. The harness has to "see" a
	## garrison the way a player does, not wait until the arcs already overlap.
	const SMOKE_ACQUIRE_RANGE: float = 2600.0

	# A Dictionary, not two ints: GDScript lambdas capture locals **by value**, so
	# `shots += 1` inside a lambda would increment a copy and the counter would
	# read zero forever. Reference types are the way to accumulate from a closure.
	var tally: Dictionary = {"shots": 0, "impacts": 0, "sunk": 0}
	EventBus.shot_fired.connect(func(_a: Node2D, _b: StringName, _c: Vector2, _d: Vector2) -> void:
		tally["shots"] += 1
	)
	EventBus.projectile_impact.connect(func(_a: Vector2, _b: StringName, _c: Node2D) -> void:
		tally["impacts"] += 1
	)
	EventBus.ship_sunk.connect(func(_a: Node2D, _b: Node2D) -> void:
		tally["sunk"] += 1
	)

	# Bail out the moment the fleet dies. Otherwise the wipe handler routes to the
	# main menu, which frees this node mid-`await` — the coroutine simply stops,
	# nothing ever calls quit(), and CI hangs until the job times out with no
	# output explaining why.
	fleet.fleet_emptied.connect(func() -> void:
		push_error("SMOKE FAIL: player fleet was wiped out")
		await _quit_cleanly(1)
	)

	var start: Vector2 = fleet.centroid()
	var goal: Island = null
	var goal_distance: float = INF
	for island: Island in archipelago.islands:
		if island.is_captured:
			continue
		var d: float = island.distance_to_coast(start)
		if d < goal_distance:
			goal_distance = d
			goal = island
	if goal == null:
		push_error("SMOKE FAIL: archipelago has no hostile island")
		await _quit_cleanly(1)
		return

	Log.info(
		"SMOKE: heading for %s, %d px away" % [goal.def.display_name, roundi(goal_distance)],
		"Smoke"
	)
	Engine.time_scale = TIME_SCALE
	var started_msec: int = Time.get_ticks_msec()
	var elapsed: float = 0.0
	## Closest any hull came to a coastline over the whole run. Negative means a
	## ship was overlapping land, which must never happen.
	var min_clearance: float = INF
	while elapsed < SECONDS:
		# Re-issue each tick: the fleet controller clears the course on arrival,
		# and the enemy AI will have knocked us off it.
		if fleet.selected != null and is_instance_valid(fleet.selected):
			# Exercise the real intent path rather than poking the ship directly:
			# engage the nearest defender if there is one, otherwise keep sailing.
			#
			# Acquire at lookout range, not gun range. A player sees the garrison
			# on the minimap and taps it long before the arcs overlap; querying
			# only `cannon_range` left the harness sailing past a defender that
			# had been culled to SIMULATED just outside the camera, never issuing
			# an attack order, and failing with "no shots fired".
			var enemy: Node2D = Grid.query_nearest(
				fleet.selected.global_position,
				SMOKE_ACQUIRE_RANGE,
				SpatialGrid.KIND_ENEMY_SHIP
			)
			# Only the garrison of the island under test. Islands sit 2,200 m
			# apart and this acquires at 2,600, so the moment the first island
			# fell the harness would lock onto the *next* island's defenders and
			# charge them — a Dinghy that has never been to a shop against a Navy
			# Sloop, which is a fight the design intends it to lose. That is one
			# island loop more than a test of one island loop, and it made "the
			# game works" a coin flip on how fast the first fight resolved.
			if enemy != null and not _near_island(enemy, goal):
				enemy = null
			if enemy != null:
				EventBus.intent_target.emit(enemy)
			elif goal.is_captured:
				fleet.selected.set_course(goal.anchor_point)
			else:
				fleet.selected.set_course(goal.global_position)
		min_clearance = minf(min_clearance, _min_hull_clearance())
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5

		var wall: float = float(Time.get_ticks_msec() - started_msec) / 1000.0
		if int(elapsed) % 10 == 0 and is_equal_approx(elapsed, floorf(elapsed)):
			var lead: Ship = fleet.selected
			print(
				"SMOKE: t=%ds wall=%.1fs fps=%d shots=%d to_goal=%d helm[%s]"
				% [
					int(elapsed),
					wall,
					Engine.get_frames_per_second(),
					int(tally["shots"]),
					roundi(goal.distance_to_coast(fleet.centroid())),
					lead.debug_state() if lead != null else "fleet lost",
				]
			)
		if wall > WALL_CLOCK_LIMIT_SEC:
			Engine.time_scale = 1.0
			push_error(
				"SMOKE FAIL: wall-clock limit hit after %.0fs (only %.0fs of game time)"
				% [wall, elapsed]
			)
			await _quit_cleanly(1)
			return
	Engine.time_scale = 1.0

	var report: String = (
		"SMOKE: alerted=%s captured=%s garrison=%d shots=%d impacts=%d sunk=%d gold=%d"
		+ " min_coast_clearance=%.0f cull(full/red/sim/dorm)=%d/%d/%d/%d grid=%d"
	) % [
		goal.is_alerted,
		goal.is_captured,
		director.active_enemy_count(),
		tally["shots"],
		tally["impacts"],
		tally["sunk"],
		GameState.total_gold(),
		min_clearance,
		Cull.count_full,
		Cull.count_reduced,
		Cull.count_simulated,
		Cull.count_dormant,
		Grid.entity_count(),
	]
	print(report)

	var failures: PackedStringArray = []
	if not goal.is_alerted:
		failures.append("island never alerted — fleet did not reach it")
	if int(tally["shots"]) == 0:
		failures.append("no shots fired")
	if int(tally["impacts"]) == 0:
		failures.append("no shot ever connected")
	if Grid.entity_count() == 0:
		failures.append("spatial grid is empty")
	if fleet.living_ships().is_empty():
		failures.append("player fleet did not survive a tier-1 island")
	# A hull on land at any point in the run is a hard failure, not a cosmetic one
	# — see Ship.clamp_out_of_land.
	#
	# The small tolerance is measurement error, not slack: clearance is computed
	# against the coast radius sampled at the nearest outline vertex, while the
	# real coastline is the chord between two vertices and sits slightly inside
	# that. A hull resting exactly on the polygon edge measures a few pixels
	# negative against the vertex radius.
	const AGROUND_TOLERANCE: float = -4.0
	if min_clearance < AGROUND_TOLERANCE:
		failures.append("a ship ran aground (clearance %.0f)" % min_clearance)
	for stats: Dictionary in Pools.all_stats():
		if bool(stats["grew"]):
			failures.append("pool '%s' outgrew its prewarm" % stats["name"])
	failures.append_array(_check_wind())
	failures.append_array(_check_upgrades())
	failures.append_array(_check_opening_island())
	failures.append_array(_check_spacing())
	failures.append_array(_check_ramp())
	failures.append_array(_check_lethality())
	failures.append_array(_check_unlocks())
	failures.append_array(_check_economy())
	failures.append_array(_check_forts())

	if failures.is_empty():
		print("SMOKE PASS")
		await _quit_cleanly(0)
	else:
		push_error("SMOKE FAIL: " + "; ".join(failures))
		await _quit_cleanly(1)


## Is this hull part of `island`'s defence, rather than a neighbour's?
##
## Measured by proximity rather than by asking the spawn director which garrison
## it belongs to: a defender that has chased the player halfway to the next
## island has stopped being that island's problem in every sense the harness
## cares about.
func _near_island(entity: Node2D, island: Island) -> bool:
	return (
		entity.global_position.distance_to(island.global_position)
		<= island.def.radius + island.def.alert_radius * 2.0
	)


## The wind must stay asleep behind an oared hull, and its polar must have the
## right shape once it is up.
##
## Checking the shape rather than exact numbers: the values are balance and will
## move, but "upwind is worst, a broad reach is best, running is in between" is
## the design, and inverting it by accident would be very easy and very hard to
## notice by eye.
func _check_wind() -> PackedStringArray:
	var out: PackedStringArray = []

	var fleet_has_sails: bool = false
	for ship: Ship in fleet.living_ships():
		if not ship.stats.is_oared():
			fleet_has_sails = true
			break

	if wind.active != fleet_has_sails:
		out.append(
			"wind active=%s but fleet_has_sails=%s" % [wind.active, fleet_has_sails]
		)

	wind.activate()
	wind.strength = 1.0
	var into: Vector2 = -wind.direction
	var upwind: float = wind.speed_multiplier(into)
	var broad_reach: float = wind.speed_multiplier(into.rotated(deg_to_rad(110.0)))
	var running: float = wind.speed_multiplier(wind.direction)

	if not (upwind < running and running < broad_reach):
		out.append(
			"wind polar is the wrong shape (upwind %.2f, running %.2f, broad reach %.2f)"
			% [upwind, running, broad_reach]
		)
	return out


## Quits without leaving audio mid-flight.
##
## `AudioServer` releases a playback on its next mix, not on `stop()`, so calling
## `quit()` in the same frame as the last cannon shot leaves that playback and the
## stream behind it alive at exit — reported as leaked instances. Stopping
## everything and yielding a couple of frames lets the server drain, which keeps
## the leak check in CI meaningful instead of permanently noisy.
## The only way a harness may leave the game.
##
## Every automated exit goes through here, and since the score started playing
## that is a hard rule rather than a tidiness one: the music stems and the sea
## ambience never stop, so at the moment any run ends there are always four
## streams live in the audio server. A bare `get_tree().quit()` tears the process
## down before the server gets a beat to release them, and Godot reports four
## leaked resources and eight leaked objects — which CI fails the build on.
##
## That is exactly how it presented: `--wipe` was the one gate that had never
## been routed through here, because when it was written nothing happened to be
## playing at the moment it quit. Nothing about the wipe path changed; what
## changed is that silence is no longer the default state of the game.
func _quit_cleanly(code: int) -> void:
	Engine.time_scale = 1.0
	Audio.shutdown()
	# A fixed number of frames is not reliable — how many mixes the server needs
	# depends on where in its buffer the last sound started. A short real-time
	# wait is, and a second shutdown catches anything that slipped through.
	await get_tree().create_timer(0.25, true, false, true).timeout
	Audio.shutdown()
	# And a beat *after* the last stop, which the first version of this missed.
	# `stop()` only marks a playback for removal; the audio server drops it on its
	# next mix, so quitting on the very next process frame tears the process down
	# with the playbacks — and the streams they pin — still alive. It showed up on
	# `--castle` alone, because that is the shortest harness there is: everything
	# it starts is a fraction of a second old when it ends, and every other run
	# happened to give the server enough idle mixes to catch up.
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(code)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		Router.goto(&"main_menu")


func _apply_render_scale() -> void:
	_viewport_container.stretch = true
	_viewport_container.stretch_shrink = _render_shrink()


## The shrink the world is actually rendered at.
##
## [member Quality.render_shrink] halves the world's resolution on the LOW
## tier, which is exactly the tier a phone lands on — and on a phone the canvas
## has *already* been divided, by the UI scale that makes the HUD legible (see
## [ScreenFit]). Both at once is a quarter of the pixels: a 1170-wide phone screen
## drawing a 195-wide world, six times upscaled, which is not a quality tier but a
## smear.
##
## The saving the shrink exists for has already been banked by then, and by more
## than the shrink ever delivered: fitting the canvas to CSS pixels takes a
## portrait phone from 1280x2770 to 390x844, which is a 2.7x cut in fill on its
## own. So when the interface has been scaled, the shrink stands down.
func _render_shrink() -> int:
	if Wave1UI.ui_scale(get_window()) > 1.0:
		return 1
	return Quality.render_shrink


func _on_quality_tier_changed(_tier: int) -> void:
	_apply_render_scale()


## Wakes the wind the moment the fleet contains anything with sails on it, and
## explains it once.
##
## Tying it to the hull rather than to an island count or a timer means the
## lesson always lands at the moment it becomes true: you bought sails, so now
## the wind is your problem. Until then the sea is still and the player has one
## fewer thing to hold in their head.
func _update_wind_availability() -> void:
	if wind.active:
		return
	var has_sails: bool = false
	for ship: Ship in fleet.living_ships():
		if not ship.stats.is_oared():
			has_sails = true
			break
	if not has_sails:
		return

	wind.activate()
	tutorial.wind_came_up(wind.compass_name())


## The run home, and the reason the home port is a place rather than a spawn
## point.
##
## Port Royal is the only harbour in the voyage that is yours before you have
## fought for it, and until there was a button for it the only way back was to
## pan the camera across the whole archipelago and tap an island the size of a
## thumbnail. Everything the player wants from home — the bank, the carpenter,
## the shop — is behind [method _on_open_port], so this only has to get them
## there and then open it.
func _on_sail_home() -> void:
	var home: Island = archipelago.home
	if home == null or not is_instance_valid(home):
		return
	var ship: Ship = fleet.selected
	if ship == null or not is_instance_valid(ship) or not ship.alive:
		return

	_returning_home = true
	# A course order, not a teleport, and it goes to the selected hull so the
	# escorts follow it in — same rule as the landing party.
	ship.set_target(null)
	ship.set_course(ship.clamp_to_navigable(home.anchor_point))
	_toast(
		"Making for the hideout at %s — %d m" % [
			home.def.display_name, roundi(maxf(0.0, home.distance_to_coast(fleet.centroid())))
		]
	)


## Tapping the sea calls off the run home, exactly as it calls off a fire order.
## The alternative is a player who changed their mind three islands ago being
## ambushed by a shop opening on them.
func _on_intent_move(_world_pos: Vector2) -> void:
	_returning_home = false


func _process(delta: float) -> void:
	if not _returning_home:
		return
	_hideout_accum += delta
	if _hideout_accum < 1.0 / HIDEOUT_CHECK_HZ:
		return
	_hideout_accum = 0.0

	var home: Island = archipelago.home
	if home == null or not is_instance_valid(home):
		_returning_home = false
		return
	for ship: Ship in fleet.living_ships():
		if ship.global_position.distance_to(home.anchor_point) <= HIDEOUT_ARRIVAL:
			_returning_home = false
			EventBus.intent_open_port.emit(home)
			return


func _on_landing_started(island: Node2D) -> void:
	_toast("Boat away from the quay at %s…" % (island as Island).def.display_name)


## Tapping an island you hold that still has cargo on its quay sets a course for
## its mooring. The toast is what tells the player the tap did something, since
## the ship itself may take a while to come about.
func _on_intent_dig(island: Node2D) -> void:
	Audio.play_ui(&"ui_confirm")
	_toast("Making for the harbour at %s…" % (island as Island).def.display_name)


func _on_island_captured(island: Node2D) -> void:
	var def: IslandDef = (island as Island).def
	# Arriving at a port is the only place gold becomes safe.
	var banked: int = GameState.bank_carried_gold()
	if banked > 0:
		_toast("%d gold banked at %s" % [banked, def.display_name])
	fleet.repair_all()
	SaveSystem.request_save()

	if def.has_castle:
		GameState.stats_voyages_completed += 1
		GameState.voyage_active = false
		EventBus.voyage_completed.emit()
		_toast("Fort Diablo has fallen. Voyage complete!")


## Opens the port on a captured island.
##
## Repairing and banking happen on arrival rather than as things to buy. Both are
## strictly good and always affordable, so making them purchases would only
## punish a player who had not yet worked out the interface.
func _on_open_port(island: Node2D) -> void:
	var port_name: String = (island as Island).def.display_name
	var banked: int = GameState.bank_carried_gold()
	fleet.repair_all()
	if banked > 0:
		_toast("%d gold banked at %s" % [banked, port_name])
	SaveSystem.request_save()

	if not hud.has_method(&"show_port"):
		Audio.play_ui(&"ui_confirm")
		return

	var screen: PortScreen = hud.call(&"show_port", port_name)
	if screen == null:
		return
	await screen.closed
	# Whatever they bought has to be under them when they sail out.
	fleet.refit()


## The voyage is over. Hand the player back a hull, tell them what survived, and
## return to the menu.
##
## The message names the bank on purpose. A wipe keeps banked gold by design, but
## the only thing the player saw was a menu still showing the gold they had before
## they died, which reads as the game having failed to reset rather than as the
## banking mechanic paying out. If the rule is going to be generous it has to be
## legible at the moment it applies.
func _on_fleet_emptied() -> void:
	input_router.enabled = false
	GameState.voyage_active = false
	GameState.wipe_fleet()

	var kept: int = GameState.banked_gold
	if kept > 0:
		_toast("Your fleet is lost… %d gold is safe ashore." % kept)
	else:
		_toast("Your fleet is lost… and nothing was banked.")

	SaveSystem.save_now()

	var timer: SceneTreeTimer = get_tree().create_timer(FLEET_WIPE_DELAY)
	await timer.timeout
	Router.goto(&"main_menu")


## The first island a player meets has to be the gentle one.
##
## Island tier rises with distance from home, so the opening island is only easy
## if it is genuinely the closest. It is placed by rejection sampling against a
## minimum channel width, and a distance set even slightly too low makes *every*
## attempt fail — the island is skipped, and the player's first fight silently
## becomes whichever tier-2-or-worse island happened to land nearest. That failure
## is invisible from the code and only shows up as "the game is unfair at the
## start", so it is asserted here.
##
## Measured from home's mooring buoy rather than from the middle of the island,
## because that is where the fleet actually weighs anchor. The two are the better
## part of a thousand metres apart, which was enough — once the islands were
## packed closer together — for the nearest island *to the player* to be a
## different island from the nearest one to home.
## Ceilings on the first two islands, as a share of one Crown Navy Sloop — see
## [method _reference_threat].
##
## The opening island is a Dinghy with one gun a side against whatever is there,
## so it gets a fraction of a warship: enough to be a fight, not enough to be a
## wipe. The second is the player's first proper duel and is allowed to be worth
## about one warship, however many hulls that is spread across.
const OPENING_THREAT_SHARE: float = 0.60
const SECOND_THREAT_SHARE: float = 1.10


func _check_opening_island() -> PackedStringArray:
	var out: PackedStringArray = []
	if archipelago.home == null:
		out.append("no home port was generated")
		return out
	var from: Vector2 = archipelago.home.anchor_point

	var nearest: Island = null
	var nearest_distance: float = INF
	for raw: Variant in archipelago.islands:
		if not is_instance_valid(raw):
			continue
		var island: Island = raw
		# Skip home by identity, not by `is_captured`. This is a check on world
		# *generation*, and it runs at the end of the smoke run — by which point the
		# run has usually taken the opening island. Filtering captured islands
		# therefore measured the second-nearest island and failed precisely when the
		# game had worked, which is the worst possible time for an assertion to fire.
		if island == archipelago.home:
			continue
		var distance: float = island.distance_to_coast(from)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = island

	if nearest == null:
		out.append("voyage has no hostile island at all")
		return out
	if nearest.def.tier != 1:
		out.append(
			"nearest island to home is tier %d (%s) — the opening island was not placed"
			% [nearest.def.tier, nearest.def.display_name]
		)
	var threat: float = _garrison_threat(nearest.def)
	var reference: float = _reference_threat()
	if threat > reference * OPENING_THREAT_SHARE:
		out.append(
			"opening island fields %d defenders worth %.0f threat — no more than %.0f"
			% [
				nearest.def.garrison_ships,
				threat,
				reference * OPENING_THREAT_SHARE,
			]
		)
	return out


## What a garrison is actually worth, in one number.
##
## Hull count used to be the measure, and factions retired it: two war canoes and
## one Crown Navy Sloop are both "one more hull than the island before", and one
## of them is a quarter of the fight the other is. The unit that survived the
## change is how much of the player the garrison can take away — timber to chew
## through, plus damage aimed back over the length of a fight.
##
## Rough on purpose. It cannot model doctrine, positioning or the wind, and it is
## not trying to: it is a tripwire on the shape of the ramp, and the numbers it
## produces mean nothing except relative to each other.
func _garrison_threat(def: IslandDef) -> float:
	## Seconds of exposure a fight is priced over. A fight is not this long; what
	## matters is the ratio between hull and rate of fire, and this is the number
	## that puts the two on comparable footing at the scale the game is balanced
	## at.
	const EXPOSURE: float = 12.0
	var faction: Faction = FactionLibrary.get_faction(def.faction)
	var total: float = 0.0
	for i: int in def.garrison_ships:
		var s: ShipStats = faction.build(SpawnDirector.hull_for(def, i))
		total += s.max_hull
		total += float(s.cannons_per_side) * s.base_damage / maxf(s.reload_time, 0.1) * EXPOSURE
		# A fireship has no guns and is still the most dangerous thing on a tier-3
		# island. Its whole cost is paid in one moment, so it is counted whole.
		total += s.detonation_damage
	return total


## One Crown Navy Sloop: the yardstick every other garrison is measured against.
##
## Named rather than numeric, so the invariants below track the balance instead
## of freezing a number from the day they were written. It is the right yardstick
## because it is the game's definition of "one proper warship" — the fight the
## second island has always been.
func _reference_threat() -> float:
	var def := IslandDef.new()
	def.faction = &"navy_crown"
	def.tier = 2
	def.garrison_ships = 1
	return _garrison_threat(def)


## No island may be marooned at the far end of a long, empty sail.
##
## The generator says nothing about leg length directly: it says ring distance,
## ring spacing, jitter and minimum channel width, in four places, and the number
## that actually decides whether the game is boring — how far it is from where you
## are to the next thing that happens — falls out of all four at once. Twenty
## seconds of open water is a breather. A minute of it is the player putting the
## phone down, and nothing else in this harness would ever notice.
func _check_spacing() -> PackedStringArray:
	## A leg longer than this is a sail rather than a crossing. Sits above the
	## 3,000 m design target with room for jitter and an unlucky angle.
	const MAX_LEG: float = 3600.0
	var out: PackedStringArray = []

	for raw: Variant in archipelago.islands:
		if not is_instance_valid(raw):
			continue
		var island: Island = raw
		if island == archipelago.home:
			continue
		var nearest: float = INF
		for other_raw: Variant in archipelago.islands:
			if not is_instance_valid(other_raw) or other_raw == raw:
				continue
			nearest = minf(
				nearest,
				island.global_position.distance_to((other_raw as Island).global_position)
			)
		if nearest > MAX_LEG:
			out.append(
				"%s is %d m from its nearest neighbour — nothing may be further than %d"
				% [island.def.display_name, roundi(nearest), roundi(MAX_LEG)]
			)
	return out


## Difficulty must climb with distance from home, and climb gently at the bottom.
##
## Tier comes from the island's place in the outward order rather than from its
## raw distance ([constant Archipelago.TIER_LADDER]), which is what makes the
## second island reliably a single Navy Sloop instead of a coin flip between that
## and a Navy Sloop with an escort. But "order" and "distance" only agree while
## the rings stay separated, so both halves are asserted: the ladder is what the
## player feels, and the ordering is what the design promises.
func _check_ramp() -> PackedStringArray:
	var out: PackedStringArray = []

	var ranked: Array[Island] = []
	for raw: Variant in archipelago.islands:
		if is_instance_valid(raw) and raw != archipelago.home:
			ranked.append(raw)
	if ranked.size() < 2:
		return out
	ranked.sort_custom(func(a: Island, b: Island) -> bool:
		return a.global_position.length() < b.global_position.length()
	)

	var previous: int = 0
	for island: Island in ranked:
		if island.def.tier < previous:
			out.append(
				"%s is tier %d but sits outside a tier-%d island — the ramp runs backwards"
				% [island.def.display_name, island.def.tier, previous]
			)
			break
		previous = island.def.tier

	# The second island the player meets is the one that decides whether they keep
	# playing: their first fight against something that shoots back properly, still
	# in whatever hull the opening island paid for.
	var second: Island = ranked[1]
	var second_threat: float = _garrison_threat(second.def)
	var reference: float = _reference_threat()
	if second_threat > reference * SECOND_THREAT_SHARE:
		out.append(
			"the second island (%s, tier %d) is worth %.0f threat — no more than %.0f,"
			% [second.def.display_name, second.def.tier, second_threat, reference * SECOND_THREAT_SHARE]
			+ " which is one warship"
		)
	if second.def.fort_cannons > 0:
		out.append("the second island fields %d batteries" % second.def.fort_cannons)
	if second.def.has_shipyard:
		out.append("the second island sends reinforcements")
	return out


## Checks that upgrades apply, and — more importantly — that buying one does not
## leak into anybody else's ship.
##
## [method ShipStatsLibrary.get_stats] hands out one shared cached resource per
## hull id. If upgrades were applied to that instead of to a duplicate, plating on
## the player's Sloop would silently buff every Navy Sloop in the archipelago. That
## failure is invisible in play — the game just gets mysteriously harder as you get
## stronger — so it has to be asserted rather than eyeballed.
func _check_upgrades() -> PackedStringArray:
	var out: PackedStringArray = []

	var base_hull: float = ShipStatsLibrary.get_stats(&"dinghy").max_hull
	var upgraded: ShipStats = ShipStatsLibrary.build(&"dinghy", {&"plating": 2})
	var expected: float = base_hull + float(UpgradeLibrary.DEFS[&"plating"]["per_level"]["max_hull"]) * 2.0

	if not is_equal_approx(upgraded.max_hull, expected):
		out.append(
			"plating 2 gave %.0f hull, expected %.0f" % [upgraded.max_hull, expected]
		)
	if not is_equal_approx(ShipStatsLibrary.get_stats(&"dinghy").max_hull, base_hull):
		out.append("applying upgrades mutated the shared cached ShipStats")

	# Costs must rise, or there is no saving-up decision.
	var wallet: Dictionary = {}
	var first: int = UpgradeLibrary.next_cost(wallet, &"plating")
	var second: int = UpgradeLibrary.next_cost({&"plating": 1}, &"plating")
	if second <= first:
		out.append("upgrade cost does not increase with level (%d then %d)" % [first, second])

	# And a maxed upgrade must report as unbuyable rather than free.
	var maxed: Dictionary = {&"plating": UpgradeLibrary.max_level(&"plating")}
	if UpgradeLibrary.next_cost(maxed, &"plating") != -1:
		out.append("a maxed upgrade still reports a price")

	# Purchasing must actually debit, and must refuse when the wallet is short.
	var before: int = GameState.banked_gold
	GameState.banked_gold = first
	var bought: Dictionary = {}
	if not UpgradeLibrary.purchase(bought, &"plating"):
		out.append("could not buy an upgrade with exactly enough gold")
	elif GameState.banked_gold != 0 or int(bought.get(&"plating", 0)) != 1:
		out.append("purchase did not debit the gold or record the level")
	if UpgradeLibrary.purchase(bought, &"plating"):
		out.append("bought an upgrade with an empty wallet")
	GameState.banked_gold = before

	return out


## No single ball may sink the weakest enemy hull.
##
## A two-hit Skiff is the opening island's whole lesson: present a beam, land a
## shot, come around, land another. A shot type that kills in one replaces that
## with "fire once and look away" — and fire shot did exactly that for a while,
## putting 25 points of burn on top of an 11-damage impact against 34 hull, so the
## kill landed several seconds after the shot and read as the game sinking ships
## by itself.
##
## Checked against the *starting* hull on purpose. Both damage and enemy hulls
## scale with tier, so the opening matchup is the tightest one — and it is the
## matchup a new player judges the whole game on.
func _check_lethality() -> PackedStringArray:
	var out: PackedStringArray = []
	var player: ShipStats = ShipStatsLibrary.get_stats(GameState.STARTING_HULL)
	# Found rather than named. This used to read `get_stats(&"skiff")`, which
	# checked the invariant against whichever hull happened to be flimsiest on the
	# day it was written — so the tribes' War Canoe arrived underneath it and was
	# never checked at all.
	var weakest: ShipStats = ShipStatsLibrary.weakest_enemy()

	for ammo: AmmoType in AmmoLibrary.all():
		# Everything one ball can take off a hull: the impact if it is aimed at the
		# hull bar, whatever splashes onto it if it is not, and the whole burn.
		var hull_damage: float = ammo.burn_dps * ammo.burn_duration
		var impact: float = player.base_damage * ammo.damage_mul
		if ammo.primary_bar == AmmoType.Bar.HULL:
			hull_damage += impact
		else:
			hull_damage += impact * ammo.splash_bar_mul

		if hull_damage >= weakest.max_hull:
			out.append(
				"one %s ball does %.0f to a %.0f-hull %s — no single ball may sink one"
				% [ammo.display_name, hull_damage, weakest.max_hull, weakest.display_name]
			)
	return out


## Progression has to start small and finish reachable.
##
## Two failure modes, opposite to each other and both easy to introduce by
## editing one line of [UnlockTable]:
##
##   * **Too much at the start.** The whole reason anything is locked is that a
##     new player cannot answer eleven questions at once. Four shot types and
##     five upgrade lines on the opening island is the state this replaced.
##   * **Locked forever.** A voyage is [constant Archipelago.ISLAND_COUNT_MIN]
##     islands at its shortest. Anything gated past that is content nobody will
##     ever see, and nothing in the game would say so — it would simply never
##     appear, which is indistinguishable from it not being implemented.
##
## Read off the table rather than off live state, because by the time the smoke
## run reaches its checks it has already taken an island.
func _check_unlocks() -> PackedStringArray:
	## Round shot, and three upgrade lines: tougher, hits harder, shoots faster.
	const OPENING_UPGRADE_LINES: int = 3
	var out: PackedStringArray = []

	var open_ammo: PackedStringArray = []
	for id: StringName in AmmoLibrary.ORDER:
		if UnlockTable.ammo_requirement(id) == 0:
			open_ammo.append(String(id))
	if open_ammo != PackedStringArray(["round"]):
		out.append(
			"a new captain starts with shot types [%s] — it must be round shot alone"
			% ", ".join(open_ammo)
		)

	var open_upgrades: int = 0
	for id: StringName in UpgradeLibrary.ORDER:
		if UnlockTable.upgrade_requirement(id) == 0:
			open_upgrades += 1
	if open_upgrades != OPENING_UPGRADE_LINES:
		out.append(
			"the opening shop offers %d upgrade lines — it must offer %d"
			% [open_upgrades, OPENING_UPGRADE_LINES]
		)

	var reachable: int = Archipelago.ISLAND_COUNT_MIN
	for id: StringName in AmmoLibrary.ORDER:
		if UnlockTable.ammo_requirement(id) > reachable:
			out.append(
				"%s needs %d islands, and the shortest voyage has %d"
				% [id, UnlockTable.ammo_requirement(id), reachable]
			)
	for id: StringName in UpgradeLibrary.ORDER:
		if UnlockTable.upgrade_requirement(id) > reachable:
			out.append(
				"%s needs %d islands, and the shortest voyage has %d"
				% [id, UnlockTable.upgrade_requirement(id), reachable]
			)
	return out


## The shop has to be reachable from one island's takings.
##
## This is the loop's whole payoff, and it is the easiest thing in the game to
## break by accident: every number involved lives in a different file — the chest
## in [method Island._fallback_loot], prize money on each [ShipStats], the hull
## price in [ShipStatsLibrary] — so nothing errors when they drift apart. It just
## quietly becomes a grind, which no test would notice and a player would feel
## within five minutes.
func _check_economy() -> PackedStringArray:
	var out: PackedStringArray = []

	var cheapest_upgrade: int = -1
	for id: StringName in UpgradeLibrary.ORDER:
		var cost: int = UpgradeLibrary.next_cost({}, id)
		if cost > 0 and (cheapest_upgrade < 0 or cost < cheapest_upgrade):
			cheapest_upgrade = cost

	# What the opening island actually paid this run. Banked, because the run
	# captured it, so this is real income rather than a projection.
	var takings: int = GameState.total_gold()
	if takings <= 0:
		out.append("capturing an island paid nothing at all")
	elif cheapest_upgrade > 0 and takings < cheapest_upgrade:
		out.append(
			"one island paid %d gold but the cheapest upgrade is %d — the first payday buys nothing"
			% [takings, cheapest_upgrade]
		)

	# And prize money has to exist, or a garrison is worth nothing but the right to dig.
	for hull: StringName in [&"skiff", &"enemy_sloop", &"enemy_brig"]:
		if ShipStatsLibrary.get_stats(hull).bounty_gold <= 0:
			out.append("%s carries no prize money" % hull)

	return out


## Forts have to exist, defend, and stay off the opening island.
##
## `fort_cannons` was authored per island from the day the generator was written
## and read by nothing at all, so the check that matters is simply that some island
## in a voyage actually builds a battery. The tier-1 exemption is the same promise
## [method _check_opening_island] makes: the first island a player meets teaches
## the broadside rule, and it cannot do that while something out-ranging them by
## two to one is shelling the approach.
func _check_forts() -> PackedStringArray:
	var out: PackedStringArray = []
	var with_forts: int = 0

	for raw: Variant in archipelago.islands:
		if not is_instance_valid(raw):
			continue
		var island: Island = raw
		if island.def.fort_cannons > 0:
			with_forts += 1
		if island == archipelago.home and island.def.fort_cannons > 0:
			out.append("the home port has shore batteries")
		if island.def.tier == 1 and island.def.fort_cannons > 0:
			out.append(
				"tier-1 %s fields %d batteries — the opening island must stay gentle"
				% [island.def.display_name, island.def.fort_cannons]
			)
		# A captured island must never be holding guns: capture requires silencing
		# them, so one still standing means the capture condition let it through.
		if island.is_captured and island.forts_remaining() > 0:
			out.append(
				"%s was captured with %d batteries still firing"
				% [island.def.display_name, island.forts_remaining()]
			)
		# And no battery may be standing on the harbour. The ring is laid out from
		# the port bearing precisely so this cannot happen (see
		# [method Island._build_forts]), but the failure is a stone bastion drawn
		# on top of the quay — cosmetic enough to survive every other check here
		# and glaring the moment anyone looks at the island.
		out.append_array(_check_harbour_clearance(island))

	if with_forts == 0:
		out.append("no island in this voyage has a single shore battery")
	return out


## The objective of a voyage has to be the hardest thing in it.
##
## Cheap enough to run in the smoke test, and it belongs there rather than only
## in `--castle`: CI gates on `--smoke` alone, and the failure this guards against
## is one that survived undetected for the whole project so far. The generator
## authored the final island with `fort_cannons = 0` and no shipyard, so the
## climax of a twenty-minute run was four ships in open water — strictly easier
## than the tier-4 islands on the way to it. Nothing errored. Nothing looked
## wrong. The voyage just quietly had no ending worth sailing to.
func _check_castle() -> PackedStringArray:
	var out: PackedStringArray = []

	var castle: Island = null
	for raw: Variant in archipelago.islands:
		if is_instance_valid(raw) and (raw as Island).def.has_castle:
			castle = raw
			break
	if castle == null:
		out.append("the voyage has no castle island — there is nothing to sail to")
		return out

	if castle.def.fort_cannons <= 0:
		out.append(
			"%s is the objective and fields no batteries" % castle.def.display_name
		)
	# Only meaningful while it is still hostile: the smoke run can, on a short
	# archipelago, have taken the thing before this runs.
	if not castle.is_captured and not castle.keep_standing():
		out.append("%s has no keep — the castle is just a big island" % castle.def.display_name)
	if castle.def.garrison_ships < 3:
		out.append(
			"%s fields only %d defenders" % [castle.def.display_name, castle.def.garrison_ships]
		)
	return out


## Every shore battery has to stand clear of the island's harbour.
func _check_harbour_clearance(island: Island) -> PackedStringArray:
	## Half the tightest even spacing the generator will ever produce, which is a
	## four-gun ring. Anything closer than this means the layout rule broke.
	const MIN_SEPARATION: float = PI / 4.0 - 0.01

	var out: PackedStringArray = []
	if island.port == null or island.port.position.length_squared() < 1.0:
		return out
	for fort: Fort in island.forts:
		if not is_instance_valid(fort):
			continue
		var apart: float = absf(island.port.position.angle_to(fort.position))
		if apart < MIN_SEPARATION:
			out.append(
				"a battery on %s stands %d° from the harbour"
				% [island.def.display_name, roundi(rad_to_deg(apart))]
			)
	return out


## Smallest gap between any living hull and any coastline, in world units.
##
## Walks the scene tree rather than the spatial grid: a grid query big enough to
## cover the whole voyage would sweep tens of thousands of empty cells, which is
## exactly the kind of accidental O(world size) the grid exists to avoid.
func _min_hull_clearance() -> float:
	var worst: float = INF
	var hulls: Array[Node] = ships_parent.get_children()
	hulls.append_array(fleet.living_ships())

	for node: Node in hulls:
		var ship := node as Ship
		if ship == null or not ship.alive:
			continue
		for island: Island in archipelago.islands:
			var offset: Vector2 = ship.global_position - island.global_position
			var clearance: float = (
				offset.length()
				- island.coast_radius_towards(ship.global_position)
				- ship.stats.hull_radius
			)
			if clearance < worst:
				worst = clearance
				if clearance < 0.0:
					Log.debug(
						"aground: %s (%s) inside %s by %.0f"
						% [ship.name, ship.stats.display_name, island.def.display_name, -clearance],
						"Smoke"
					)
	return worst


func _toast(text: String) -> void:
	if hud.has_method(&"show_toast"):
		hud.call(&"show_toast", text)
	Log.info(text, "Voyage")


## Frames the HUD and every modal at real phone viewports, in both orientations.
##
##   xvfb-run -a godot src/scenes/voyage.tscn -- --shot-mobile
##
## The game is played on a phone and developed on a 1280x720 desktop window, and
## every other screenshot harness runs at the latter — so the layout that most
## needed looking at was the one nothing had ever photographed. The window is
## resized between passes rather than taking one size per run, because the point
## is to compare the same four screens across three shapes and the interesting
## failures (a panel wider than the screen, two corners of the HUD colliding) only
## exist in one of them.
##
## The sizes are CSS pixels, which is what the layout reasons in — see
## [method Wave1UI.ui_scale]. A phone reporting a 3x device pixel ratio has three
## times these numbers of real pixels, and the scale maths cancels that out, so
## 390x844 here is a 1170x2532 iPhone.
func _capture_mobile() -> void:
	const VIEWPORTS: Array[Vector2i] = [
		Vector2i(390, 844),  # iPhone-class portrait, the tightest width that matters
		Vector2i(844, 390),  # the same phone turned over
		Vector2i(820, 1180),  # a tablet, where the UI must stop growing
	]
	var dir: String = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(0.6).timeout
	if hud.has_method(&"dismiss_briefing"):
		hud.call(&"dismiss_briefing")

	# A purse that can afford some of the shop and not the rest, so the port frame
	# shows both treatments — the same reason `--shot-port` sets one.
	GameState.banked_gold = maxi(GameState.banked_gold, 182)
	GameState.add_gold(210)
	GameState.fleet[0] = {"stats_id": &"sloop", "upgrades": {&"plating": 1}}
	fleet.refit()
	await get_tree().process_frame

	var port: Island = archipelago.home
	for island: Island in archipelago.islands:
		if island.is_captured:
			port = island
			break

	for size: Vector2i in VIEWPORTS:
		var tag: String = "%dx%d" % [size.x, size.y]
		# `Window.size`, not [method DisplayServer.window_set_size]: the latter
		# resizes the OS window without the SceneTree's window node noticing, so
		# the stretch and the UI scale go on being computed for the old shape and
		# every frame after the first comes out identical to the first.
		get_window().size = size
		# One frame for the resize to land, then a beat for the relayout and the
		# render scale it triggers.
		await get_tree().process_frame
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/mobile_%s_hud.png" % [dir, tag])

		EventBus.intent_open_port.emit(port)
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/mobile_%s_port.png" % [dir, tag])
		if hud.has_method(&"dismiss_port"):
			hud.call(&"dismiss_port")
		await get_tree().create_timer(0.3).timeout

		var badge: Button = hud.find_child("FleetButton", true, false) as Button
		if badge != null:
			badge.pressed.emit()
			await get_tree().create_timer(0.4).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				"%s/mobile_%s_fleet.png" % [dir, tag]
			)
			if hud.has_method(&"dismiss_fleet"):
				hud.call(&"dismiss_fleet")
			await get_tree().create_timer(0.3).timeout

		if hud.has_method(&"show_briefing"):
			hud.call(
				&"show_briefing",
				"THE WIND",
				PackedStringArray([
					"Your sails only pull with the wind behind or abeam.",
					"The ring around your ship shows where it is coming from.",
					"Beating straight upwind is slow — tack across it instead.",
				]),
				"GOT IT"
			)
			await get_tree().create_timer(0.4).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				"%s/mobile_%s_briefing.png" % [dir, tag]
			)
			if hud.has_method(&"dismiss_briefing"):
				hud.call(&"dismiss_briefing")
			await get_tree().create_timer(0.3).timeout

	print("MOBILE SHOTS: %s" % ProjectSettings.globalize_path(dir))
	await _quit_cleanly(0)


## Taps the sea with a synthesised finger and asserts the helm answers.
##
##   godot --headless src/scenes/voyage.tscn -- --touch
##
## This gate exists because tap-to-sail — the only control the game has — was
## dead on every touchscreen while working perfectly under a mouse, and nothing
## in the harness could see it. The screenshot runs could not: a still frame of a
## ship that was never ordered anywhere looks exactly like a still frame of a ship
## that was. Every other run drives [EventBus] directly, which starts downstream
## of the entire pointer path.
##
## Events go in through [method Input.parse_input_event] rather than being pushed
## at a viewport, and that distinction is the whole test. The failure lived in
## what the *engine* adds on the way in — `emulate_mouse_from_touch` turns one tap
## into an emulated mouse click followed by the real touch — and pushing straight
## at the viewport skips the emulation, and the bug with it. A version of this
## harness that used `Viewport.push_input` passed against the broken build.
func _run_touch_test() -> void:
	## Everything the router resolves a tap against — hulls, islands, the enemy
	## pick radius — is in world units, so the assertions are too. Generous
	## enough to absorb the camera drifting a little between the frame the point
	## is computed on and the frame the event lands on.
	const COURSE_TOLERANCE: float = 90.0

	await get_tree().create_timer(0.5).timeout
	if hud.has_method(&"dismiss_briefing"):
		hud.call(&"dismiss_briefing")
	await get_tree().process_frame

	var ship: Ship = fleet.selected
	if ship == null or not is_instance_valid(ship):
		push_error("TOUCH FAIL: no ship at the helm to steer")
		await _quit_cleanly(1)
		return

	var water: Vector2 = _open_water_near(ship)
	if water == Vector2.INF:
		push_error("TOUCH FAIL: no clear water in sight to tap")
		await _quit_cleanly(1)
		return

	var taps: Dictionary = {"move": 0}
	EventBus.intent_move.connect(func(_p: Vector2) -> void:
		taps["move"] += 1
	)

	# 1. The mouse, first, so a regression here is distinguishable from one in the
	# touch path rather than both failing together with one message.
	ship.stop()
	_send_click(true, _device_point(water))
	await _settle_input()
	_send_click(false, _device_point(water))
	await _settle_input()
	if taps["move"] != 1:
		push_error("TOUCH FAIL: a mouse click on open water raised %d move orders, not 1"
			% taps["move"])
		await _quit_cleanly(1)
		return
	if not ship.has_nav_target or ship.nav_target.distance_to(water) > COURSE_TOLERANCE:
		push_error("TOUCH FAIL: mouse click set no usable course (%s for a tap at %s)"
			% [ship.nav_target, water])
		await _quit_cleanly(1)
		return

	# 2. The same tap with a finger. One order, not zero and not two: zero was the
	# shipped bug, and two would mean the emulated mouse event is being counted as
	# a second tap rather than dropped.
	ship.stop()
	water = _open_water_near(ship)
	_send_touch(0, true, _device_point(water))
	await _settle_input()
	_send_touch(0, false, _device_point(water))
	await _settle_input()
	if taps["move"] != 2:
		push_error(
			"TOUCH FAIL: a finger tap on open water raised %d move orders in total, expected 2"
			% taps["move"]
		)
		await _quit_cleanly(1)
		return
	if not ship.has_nav_target or ship.nav_target.distance_to(water) > COURSE_TOLERANCE:
		push_error("TOUCH FAIL: finger tap set no usable course (%s for a tap at %s)"
			% [ship.nav_target, water])
		await _quit_cleanly(1)
		return
	if not ship.manual_helm:
		push_error("TOUCH FAIL: finger tap did not take the helm off the engagement solver")
		await _quit_cleanly(1)
		return

	# 3. A finger that travels pans the camera and orders nothing. The two
	# gestures share a press, so the only thing keeping them apart is the slop
	# threshold, and that threshold is now resolution-relative.
	ship.stop()
	camera.recenter()
	await get_tree().process_frame
	var pan_from: Vector2 = camera.pan_offset
	var drag_start: Vector2 = _device_point(water)
	## Comfortably past the tap slop, which is a fraction of the viewport rather
	## than a fixed distance — so this has to be expressed the same way.
	var drag_step: Vector2 = _device_offset(Vector2(_touch_slop() * 2.0, 0.0))
	_send_touch(1, true, drag_start)
	await _settle_input()
	for step: int in 6:
		_send_drag(1, drag_start + drag_step * float(step + 1), drag_step)
		await _settle_input()
	_send_touch(1, false, drag_start + drag_step * 6.0)
	await _settle_input()
	if taps["move"] != 2:
		push_error("TOUCH FAIL: dragging the sea issued a move order — a pan read as a tap")
		await _quit_cleanly(1)
		return
	if camera.pan_offset.distance_to(pan_from) < 1.0:
		push_error("TOUCH FAIL: dragging with one finger did not pan the camera")
		await _quit_cleanly(1)
		return

	# 4. Two fingers still zoom. The pinch branch is what a lone tap was being
	# misfiled into, so tightening the pointer bookkeeping has to leave the real
	# gesture intact.
	## Where the two fingers land, as a fraction of the way down the glass. The
	## upper half, because the HUD lives along the bottom edge — the shot rack on
	## one side, the map on the other — and a finger that comes down on a Control
	## belongs to that Control, not to the world.
	const PINCH_LINE: float = 0.35

	var zoom_from: float = camera.target_zoom
	# Straddling the middle of the screen rather than the water that was tapped: a
	# pinch is about the screen, not about anything in the sea under it. Both
	# fingers have to *land* inside the container — an event outside it is never
	# forwarded into the world at all — so the spread gives way to a narrow screen.
	var glass: Vector2 = input_router.get_viewport().get_visible_rect().size
	var spread: Vector2 = _device_offset(Vector2(minf(200.0, glass.x * 0.2), 0))
	var line: Vector2 = _device_from_glass(Vector2(glass.x * 0.5, glass.y * PINCH_LINE))
	var pinch_a: Vector2 = line - spread
	var pinch_b: Vector2 = line + spread
	_send_touch(0, true, pinch_a)
	_send_touch(1, true, pinch_b)
	await _settle_input()
	for step: int in 5:
		_send_drag(1, pinch_b + spread * (0.3 * float(step + 1)), spread * 0.3)
		await _settle_input()
	_send_touch(0, false, pinch_a)
	_send_touch(1, false, pinch_b + spread * 1.5)
	await _settle_input()
	if is_equal_approx(camera.target_zoom, zoom_from):
		push_error("TOUCH FAIL: a two-finger pinch changed nothing")
		await _quit_cleanly(1)
		return

	print("TOUCH PASS")
	await _quit_cleanly(0)


## A world point a tap on which can only mean "sail here": clear of every hull,
## off every island, and outside the router's own enemy pick radius, so the
## assertion is about the pointer path and not about what happened to be moored
## nearby.
func _open_water_near(ship: Ship) -> Vector2:
	## How far out to tap, as a fraction of the smaller half of what is on screen.
	## Measured off the camera rather than fixed, because how much sea a screen
	## holds is exactly what changes between a desktop window and a phone: a flat
	## 300 units was comfortably inside a 1280-wide view and comfortably *outside*
	## a portrait phone's 391, where every synthesised tap landed off the glass and
	## was dropped before it reached the world.
	const PROBE_SHARE: float = 0.55
	## Never closer than this, or the tap is a ship selection rather than a course,
	## and never further than the range the desktop case has always used.
	var probe_range: float = clampf(
		minf(_visible_world().x, _visible_world().y) * 0.5 * PROBE_SHARE,
		InputRouter.PICK_RADIUS_SHIP * 1.3,
		300.0
	)
	## Clearance from any coastline. Wide enough that the router's navigable
	## clamp leaves the point where it is, so the course can be compared against
	## the point that was tapped.
	const COAST_CLEARANCE: float = 200.0

	for step: int in 16:
		var probe: Vector2 = ship.global_position + Vector2.RIGHT.rotated(
			TAU * float(step) / 16.0
		) * probe_range
		if Grid.query_nearest(
			probe,
			InputRouter.PICK_RADIUS_ENEMY,
			SpatialGrid.KIND_ENEMY_SHIP | SpatialGrid.KIND_STRUCTURE
		) != null:
			continue
		if Grid.query_nearest(
			probe, InputRouter.PICK_RADIUS_SHIP, SpatialGrid.KIND_PLAYER_SHIP
		) != null:
			continue
		# And somewhere the player could actually reach. The HUD is a Control layer
		# over the world: a tap that lands on the shot rack is answered by the shot
		# rack, which on a phone in landscape is a third of the right-hand side of
		# the screen and was where this harness kept aiming.
		if _hud_blocks(_canvas_point(probe)):
			continue
		var clear: bool = true
		for island: Island in archipelago.islands:
			if island.distance_to_coast(probe) < COAST_CLEARANCE:
				clear = false
				break
		if clear:
			return probe
	return Vector2.INF


## True when some part of the HUD would take a tap at this point on the canvas.
func _hud_blocks(canvas_point: Vector2) -> bool:
	for node: Node in hud.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if control.get_global_rect().has_point(canvas_point):
			return true
	return false


## Where a world position lands on the glass, in the coordinates a device
## delivers events in.
##
## Two transforms, because there are two viewports. The camera's canvas transform
## puts the world into SubViewport pixels; the container scales those up by the
## render shrink to fill the window; and the root viewport's final transform is
## the project's `canvas_items` stretch, which the engine applies in reverse to
## everything arriving from the platform. Headless runs a 64px window against a
## 1280px canvas, so that last step is a factor of twenty and skipping it puts
## every synthesised tap far outside the screen — where it is silently dropped
## and the harness passes having tested nothing.
func _device_point(world_pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * _canvas_point(world_pos)


## Where a world position lands on the HUD's canvas — the coordinates every
## Control in the game is laid out in, one transform short of a device event.
func _canvas_point(world_pos: Vector2) -> Vector2:
	var in_sub: Vector2 = camera.get_canvas_transform() * world_pos
	return in_sub * float(_viewport_container.stretch_shrink)


## How much sea is on screen, in world units.
func _visible_world() -> Vector2:
	return camera.get_viewport_rect().size / camera.zoom


## A point given in SubViewport pixels, in the coordinates a device delivers
## events in.
func _device_from_glass(point: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * (
		point * float(_viewport_container.stretch_shrink)
	)


## A screen distance, expressed in SubViewport pixels, in the coordinates a
## device delivers events in. The same two transforms [method _device_point]
## applies, minus the origin.
func _device_offset(in_sub: Vector2) -> Vector2:
	return get_viewport().get_final_transform().basis_xform(
		in_sub * float(_viewport_container.stretch_shrink)
	)


## The router's own tap slop, so the harness drags past it by construction rather
## than by a number that has to be kept in step with it by hand.
func _touch_slop() -> float:
	var size: Vector2 = input_router.get_viewport().get_visible_rect().size
	return minf(size.x, size.y) * InputRouter.TAP_SLOP_FRACTION


func _send_touch(index: int, pressed: bool, at: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = at
	Input.parse_input_event(event)


func _send_drag(index: int, at: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	event.relative = relative
	Input.parse_input_event(event)


func _send_click(pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)


## Parsed input is dispatched on the engine's next flush, and the router ages its
## own pointers in `_process`, so an event needs a frame to become a gesture.
func _settle_input() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
