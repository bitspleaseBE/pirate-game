class_name TutorialDirector
extends Node
## Decides what the player needs told, and when.
##
## The design premise: this game is easy once you know what it is, and baffling
## for about ninety seconds before that. Every briefing here exists to shorten
## those ninety seconds, and each is triggered by the moment it becomes relevant
## rather than dumped in a menu up front — you are told about enemies when enemies
## appear, and about the wind when you first have sails.
##
## Each briefing fires once per save. That is stored in [GameState] so it survives
## a reload; a tutorial that repeats is worse than none.
##
## Adding one is a single entry: an id, a trigger, and at most three lines.

## Seconds the camera lingers on whatever a briefing pointed at.
const POINT_OUT_HOLD: float = 2.2
## Small delay before the opening briefing so the world is visibly there behind
## it — a modal over a blank screen reads as a loading error.
const OPENING_DELAY: float = 0.55

## Turned off for automated runs, which cannot press a button to close a modal.
var enabled: bool = true

var hud: Node = null
var camera: GameCamera = null
var fleet: FleetController = null

var _showing: bool = false
var _queue: Array[StringName] = []


func _ready() -> void:
	EventBus.island_alerted.connect(_on_island_alerted)
	EventBus.ship_sunk.connect(_on_ship_sunk)
	EventBus.island_captured.connect(_on_island_captured)
	EventBus.treasure_dug.connect(_on_treasure_dug)


## Called by the voyage once everything is wired.
func begin() -> void:
	if not enabled or GameState.has_seen(&"opening"):
		return
	await get_tree().create_timer(OPENING_DELAY).timeout
	_show(
		&"opening",
		"MAKE SAIL",
		[
			"Tap open water to set a course. Your ship turns slowly and cannot stop on a coin — plan ahead.",
			"Somewhere out there is an island with treasure stacked on its quay, and people who would rather you did not have it.",
			"The map in the corner shows what you have found. Sail for the island.",
		],
		"WEIGH ANCHOR"
	)


## Called when the fleet first commands a hull with sails on it.
func wind_came_up(compass: String) -> void:
	_show(
		&"wind",
		"THE WIND IS UP",
		[
			"Your oars are gone. Sails answer to the wind, and it is blowing from the %s." % compass,
			"Fastest across the wind, slowest sailing into it. The compass ring turns green when you are making good speed.",
			"You can still steer anywhere — a bad angle only costs you time.",
		],
		"WEIGH ANCHOR"
	)


func _on_island_alerted(island: Node2D) -> void:
	if GameState.has_seen(&"first_enemies"):
		_maybe_teach_shipyard(island as Island)
		return
	# Point the camera at what we are talking about. "There are enemies" is a
	# sentence; seeing them turn toward you is the actual information.
	var enemy: Node2D = Grid.query_nearest(
		island.global_position, island.def.alert_radius * 2.0, SpatialGrid.KIND_ENEMY_SHIP
	)
	_show(
		&"first_enemies",
		"ENEMY SHIPS",
		[
			"Tap an enemy to mark it. Your guns fire the instant she comes into a broadside arc — you never have to tap to shoot.",
			"Cannons fire from the sides, never the bow, so charging straight at something is the one way to hit nothing. Keep tapping the water: you have the helm, and putting her beam-on is your job.",
			"The arcs either side of your ship fill as the guns reload, and light up when they bear. Sink every defender and the island is yours.",
		],
		"SHOW ME",
		enemy.global_position if enemy != null else island.global_position
	)


## The first island that can replace what you sink.
##
## Reinforcements are the one mechanic in the game that reads as the game being
## unfair rather than as a problem with a solution — you clear the water, and
## more of them arrive. It stops reading that way the instant the player knows
## there is a building on the beach making them, so this fires the first time
## they meet one, and points the camera at it.
func _maybe_teach_shipyard(island: Island) -> void:
	if island == null or not is_instance_valid(island) or not island.can_reinforce():
		return
	if GameState.has_seen(&"first_shipyard"):
		return
	_show(
		&"first_shipyard",
		"THEY ARE BUILDING MORE",
		[
			"There is a slipway on the far side of that island, and it will keep launching hulls at you for as long as it stands.",
			"You can grind the defenders down and eat every wave, or take the long way round the coast, past the guns, and burn it.",
			"That choice is the fight. Tap the yard to mark it, same as a ship.",
		],
		"UNDERSTOOD",
		island.shipyard.global_position if is_instance_valid(island.shipyard) else island.global_position
	)


func _on_ship_sunk(ship: Node2D, killer: Node2D) -> void:
	if killer == null or not (killer is Ship) or (killer as Ship).team != Teams.PLAYER:
		return
	if GameState.has_seen(&"first_kill"):
		return
	# Taught here, after a kill, rather than up front: a player who has just won a
	# fight with round shot has the context to care that other shot exists. The
	# same three lines before their first shot would be noise.
	_show(
		&"first_kill",
		"ONE DOWN",
		[
			"That is the whole game: read the angle, get your side facing them, let the broadside do the rest.",
			"Two things pay for good sailing. Shot loses its weight at long range, so close. And a ball that goes in over a ship's bow or stern runs the whole length of her — cross their end-on and you hit twice as hard. Watch for RAKE.",
			"The button bottom-right cycles your shot. Chain shreds sails so nothing escapes; grape kills crew, and a ship whose crew cannot hold her can be boarded and taken instead of sunk.",
		]
	)


func _on_island_captured(island: Node2D) -> void:
	if GameState.has_seen(&"first_capture"):
		return
	_show(
		&"first_capture",
		"ISLAND TAKEN",
		[
			"Every island has a harbour. Sail to the red buoy off the end of its jetty and a boat will bring the treasure out to you. Tap the island to set that course again if you wander off.",
			"A harbour you hold is a port: it repairs your ships and banks your gold. Gold you are still carrying is lost if you sink.",
		],
		"GOT IT",
		(island as Island).anchor_point
	)


func _on_treasure_dug(_island: Node2D, _loot: Dictionary) -> void:
	if GameState.has_seen(&"first_treasure"):
		return
	if not enabled:
		return
	_show(
		&"first_treasure",
		"TREASURE",
		[
			"Gold buys bigger hulls and more guns, and a bigger hull is how you take on a harder island.",
			"Tap any island you have taken to visit its port and spend it. Opening one now.",
		],
		"OPEN THE PORT"
	)
	# Open it *for* them, once. Every other reward in the game announces itself, so
	# a shop the player has to guess is behind an unlabelled tap on some scenery is
	# the one place the loop can silently fail to close. After this they know it is
	# there, and tapping the island is enough.
	if not GameState.has_seen(&"first_port_opened"):
		GameState.mark_seen(&"first_port_opened")
		await get_tree().create_timer(0.4).timeout
		EventBus.intent_open_port.emit(_island)


## Shows a briefing once, optionally panning the camera to `point_at` afterwards.
func _show(
	id: StringName,
	title: String,
	lines: PackedStringArray,
	button_text: String = "GOT IT",
	point_at: Variant = null
) -> void:
	if not enabled or GameState.has_seen(id):
		return
	# Two briefings can become due in the same frame (a kill that clears the last
	# defender fires first_kill and first_capture together). Queue rather than
	# stack — two modals at once is worse than either.
	if _showing:
		return
	GameState.mark_seen(id)
	SaveSystem.request_save()

	if hud == null or not hud.has_method(&"show_briefing"):
		return

	_showing = true
	var panel: BriefingPanel = hud.call(&"show_briefing", title, lines, button_text)
	if panel == null:
		_showing = false
		return

	await panel.dismissed
	_showing = false

	if point_at != null and camera != null and is_instance_valid(camera):
		camera.point_out(point_at as Vector2, POINT_OUT_HOLD)
