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

## Built once the world exists — see the note where it is created.
var music: MusicDirector = null
@onready var hud: CanvasLayer = %Hud

## Set while the fleet is under orders for the hideout, so arriving there opens
## the port instead of quietly mooring.
var _returning_home: bool = false
var _hideout_accum: float = 0.0


func _ready() -> void:
	# `--sail` starts in a Sloop instead of the oared Dinghy, so the wind, the
	# wake and the compass ring can be exercised without first playing through
	# the opening islands to earn a set of sails.
	if "--sail" in OS.get_cmdline_user_args():
		GameState.fleet = [{"stats_id": &"sloop", "upgrades": {}}]

	Grid.configure()
	# Pools must exist before anything can fire a gun, and they need a world-space
	# parent — this is the handoff described in PoolManager.
	Pools.set_world_root(_world)

	_apply_render_scale()
	Quality.tier_changed.connect(_on_quality_tier_changed)

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
	)

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
	elif "--rig" in args:
		_run_rig_test()


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
	while elapsed < SECONDS and not bool(outcome["wiped"]):
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
	const PATIENCE: float = 16.0

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

	var light: EnemyShip = _spawn_test_enemy(&"skiff", open + Vector2(900.0, 0.0))
	await get_tree().process_frame
	Cull.force_tick()

	var heavy_before: float = heavy.hull
	var light_before: float = light.hull

	# Drive them together. Both are ordered straight at each other so the closing
	# speed is unambiguous — a glancing contact is deliberately not a ram, and a
	# test that produced one would be testing the wrong thing.
	Engine.time_scale = TIME_SCALE
	var waited: float = 0.0
	while waited < PATIENCE and int(hits["count"]) == 0:
		if is_instance_valid(heavy) and heavy.alive and is_instance_valid(light) and light.alive:
			heavy.set_target(null)
			heavy.nav_target = light.global_position
			heavy.has_nav_target = true
			light.suppress_engage_steering = true
			light.nav_target = heavy.global_position
			light.has_nav_target = true
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	Engine.time_scale = 1.0

	var failures: PackedStringArray = []
	if int(hits["count"]) == 0:
		failures.append("two hulls driven straight at each other never registered a collision")
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
	_viewport_container.stretch_shrink = Quality.render_shrink


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
	if nearest.def.garrison_ships > 1:
		out.append("opening island fields %d defenders" % nearest.def.garrison_ships)
	return out


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
	if second.def.garrison_ships != 1:
		out.append(
			"the second island (%s, tier %d) fields %d defenders — it must be one ship alone"
			% [second.def.display_name, second.def.tier, second.def.garrison_ships]
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
	var weakest: ShipStats = ShipStatsLibrary.get_stats(&"skiff")

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
