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

@onready var _viewport_container: SubViewportContainer = $GameViewport
@onready var _world: Node2D = %World
@onready var archipelago: Archipelago = %Archipelago
@onready var fleet: FleetController = %Fleet
@onready var camera: GameCamera = %GameCamera
@onready var overlay: WorldOverlay = %WorldOverlay
@onready var input_router: InputRouter = %InputRouter
@onready var director: SpawnDirector = %SpawnDirector
@onready var ships_parent: Node2D = %Ships
@onready var wind: WindSystem = %WindSystem
@onready var tutorial: TutorialDirector = %Tutorial
@onready var hud: CanvasLayer = %Hud


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
	camera.set_world_bounds(archipelago.world_bounds)
	camera.fleet = fleet
	input_router.camera = camera
	input_router.fleet = fleet
	overlay.fleet = fleet
	overlay.archipelago = archipelago

	director.fleet = fleet
	director.archipelago = archipelago
	director.ships_parent = ships_parent

	var start: Vector2 = Vector2(0, -1400)
	if archipelago.home != null:
		start = archipelago.home.anchor_point
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
	# report that nothing happened.
	tutorial.enabled = not ("--smoke" in OS.get_cmdline_user_args())

	_update_wind_availability()
	EventBus.fleet_changed.connect(_update_wind_availability)

	fleet.fleet_emptied.connect(_on_fleet_emptied)
	EventBus.intent_open_port.connect(_on_open_port)
	EventBus.island_captured.connect(_on_island_captured)
	director.landing_started.connect(_on_landing_started)

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
		get_tree().quit(1)
		return

	# Clear any briefing first — show_port refuses to stack modals, correctly.
	if hud.has_method(&"dismiss_briefing"):
		hud.call(&"dismiss_briefing")
	await get_tree().process_frame

	EventBus.intent_open_port.emit(port)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/port_00.png" % dir)

	print("PORT SHOT: %s" % ProjectSettings.globalize_path(dir))
	get_tree().quit(0)


## Sails to the nearest hostile island and writes frames to `user://shots/`.
## A rendered frame is the only way to check that art, scale, z-order and the
## ocean shader actually agree with each other.
##
##   godot src/scenes/voyage.tscn -- --shot
func _capture_screenshots() -> void:
	var dir: String = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	Engine.time_scale = 3.0

	var goal: Island = null
	var nearest: float = INF
	for island: Island in archipelago.islands:
		if island.is_captured:
			continue
		var d: float = island.distance_to_coast(fleet.centroid())
		if d < nearest:
			nearest = d
			goal = island

	var shot: int = 0
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
	get_tree().quit(0)


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
		get_tree().quit(1)
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
		get_tree().quit(1)
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
			var enemy: Node2D = Grid.query_nearest(
				fleet.selected.global_position,
				fleet.selected.stats.cannon_range,
				SpatialGrid.KIND_ENEMY_SHIP
			)
			if enemy != null:
				EventBus.intent_target.emit(enemy)
			else:
				fleet.selected.set_course(goal.anchor_point)
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
			get_tree().quit(1)
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
	failures.append_array(_check_lethality())

	if failures.is_empty():
		print("SMOKE PASS")
		await _quit_cleanly(0)
	else:
		push_error("SMOKE FAIL: " + "; ".join(failures))
		await _quit_cleanly(1)


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
func _quit_cleanly(code: int) -> void:
	Engine.time_scale = 1.0
	Audio.shutdown()
	# A fixed number of frames is not reliable — how many mixes the server needs
	# depends on where in its buffer the last sound started. A short real-time
	# wait is, and a second shutdown catches anything that slipped through.
	await get_tree().create_timer(0.25, true, false, true).timeout
	Audio.shutdown()
	await get_tree().process_frame
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


func _on_landing_started(island: Node2D) -> void:
	_toast("Landing party ashore at %s…" % (island as Island).def.display_name)


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


func _on_fleet_emptied() -> void:
	input_router.enabled = false
	_toast("Your fleet is lost…")
	GameState.voyage_active = false
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
func _check_opening_island() -> PackedStringArray:
	var out: PackedStringArray = []
	if archipelago.home == null:
		out.append("no home port was generated")
		return out

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
		var distance: float = island.global_position.distance_to(archipelago.home.global_position)
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
