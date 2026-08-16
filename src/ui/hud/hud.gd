extends CanvasLayer
## Gameplay HUD.
##
## Everything reachable with one thumb: the ammo cycle button sits bottom-right
## where a right thumb rests, the minimap bottom-left, and the counters top-left
## out of the way of both. No control sits in the middle third of the screen,
## because that is where the player taps to sail.
##
## The layout lives in `hud.tscn`; this script only wires it to state.
##
## Two typefaces, split by job, both defined as FontVariations in the scene:
##
## - **Cinzel** (`Font_label`) for the tags — GOLD, DBL, FLEET, the ammo name.
##   A Roman inscriptional face cut for stone and ship's nameplates, so it
##   carries the period without costing anything: these are short all-caps
##   words the player recognises by shape, never reads letter by letter.
## - **Alegreya** (`Font_number`, `Font_body`) for everything the player
##   actually has to read — the counters and the toast. `tnum` puts the digits
##   on a fixed pitch so a gold tally does not shuffle sideways as it ticks up.
##
## The old Kenney Future was a wide geometric display face: thin at 14 px over
## a moving ocean, and its zero was a plain rounded rectangle, so "GOLD 0" read
## as a missing glyph.

const TOAST_DURATION: float = 2.6
## How often the range to the hideout is recomputed. It is a number the player
## glances at between decisions, not one they steer by, so twice a second is
## generous and a per-frame distance check is pure waste.
const HIDEOUT_REFRESH: float = 0.5

## How often the boarding prompt re-checks whether it should be on screen. It
## appears and disappears with the geometry of a fight, so it has to keep up with
## one — but it is a button, not a crosshair, and four times a second is plenty.
const BOARD_REFRESH: float = 0.25

const ICON_ANCHOR: Texture2D = preload("res://assets/wave1/icons/icon_anchor.png")
const ICON_WHEEL: Texture2D = preload("res://assets/wave1/icons/icon_wheel.png")

@onready var _gold_label: Label = %GoldLabel
@onready var _diamond_label: Label = %DiamondLabel
@onready var _ammo_button: Button = %AmmoButton
@onready var _ammo_count: Label = %AmmoCount
@onready var _fleet_label: Label = %FleetLabel
@onready var _fleet_button: Button = %FleetButton
@onready var _hideout_button: Button = %HideoutButton
@onready var _toast: Label = %Toast
@onready var minimap: Minimap = %Minimap
@onready var _root: Control = $Root

var _toast_left: float = 0.0
var _hideout_left: float = 0.0
var _wind_indicator: WindIndicator
var _board_button: Button
var _board_left: float = 0.0
var _fleet: FleetController = null
var _archipelago: Archipelago = null


func _ready() -> void:
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.diamonds_changed.connect(_on_diamonds_changed)
	EventBus.fleet_changed.connect(_refresh_fleet)
	EventBus.island_captured.connect(_on_island_captured)
	EventBus.island_discovered.connect(_on_island_discovered)
	EventBus.shipyard_destroyed.connect(_on_shipyard_destroyed)
	EventBus.prize_taken.connect(_on_prize_taken)
	EventBus.keep_shrugged_off.connect(_on_keep_shrugged_off)
	EventBus.enemy_routed.connect(_on_enemy_routed)
	EventBus.castle_breached.connect(_on_castle_breached)
	EventBus.treasure_dug.connect(_on_treasure_dug)
	EventBus.ship_sunk.connect(_on_ship_sunk)

	_ammo_button.pressed.connect(_on_ammo_pressed)
	Wave1UI.apply_brass(_ammo_button)
	_hideout_button.pressed.connect(_on_hideout_pressed)
	Wave1UI.apply_brass(_hideout_button)
	Wave1UI.set_icon(_hideout_button, ICON_ANCHOR, 26)
	_fleet_button.pressed.connect(_on_fleet_pressed)

	_build_wind_indicator()
	_build_board_button()
	_refresh_all()
	_toast.modulate.a = 0.0


## Called by the voyage scene once the world exists.
func bind(fleet: FleetController, archipelago: Archipelago) -> void:
	_fleet = fleet
	_archipelago = archipelago
	minimap.fleet = fleet
	minimap.archipelago = archipelago
	_wind_indicator.fleet = fleet
	fleet.selection_changed.connect(_on_selection_changed)
	_refresh_all()
	_refresh_hideout()


## The toast fades on its own, and the range home ticks over.
##
## Pauses with the world, which is what you want for both: a toast should not
## time out while the player is reading a briefing over the top of it, and the
## fleet is not moving, so neither is the range home.
func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		# Hold it solid for most of its life, then fade over the last half second:
		# a toast that starts fading immediately reads as already leaving.
		_toast.modulate.a = clampf(_toast_left * 2.0, 0.0, 1.0)

	_hideout_left -= delta
	if _hideout_left <= 0.0:
		_hideout_left = HIDEOUT_REFRESH
		_refresh_hideout()

	_board_left -= delta
	if _board_left <= 0.0:
		_board_left = BOARD_REFRESH
		_refresh_board()


func _build_wind_indicator() -> void:
	_wind_indicator = WindIndicator.new()
	_wind_indicator.name = "WindIndicator"
	# Top-right, clear of the counters and out of the thumb's way.
	_wind_indicator.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_wind_indicator.offset_left = -108.0
	_wind_indicator.offset_top = 14.0
	_wind_indicator.offset_right = -16.0
	_wind_indicator.offset_bottom = 106.0
	_root.add_child(_wind_indicator)


## The boarding prompt: hidden almost always, and the most valuable button in the
## game for the few seconds it is not.
##
## Built here rather than in `hud.tscn` because it is the only control that comes
## and goes, and a scene file makes something look permanent. It sits above the
## ammo button, in the same right-thumb column, so the hand that is already
## cycling shot does not have to travel to take a prize.
func _build_board_button() -> void:
	_board_button = Button.new()
	_board_button.name = "BoardButton"
	_board_button.visible = false
	_board_button.focus_mode = Control.FOCUS_NONE
	_board_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_board_button.offset_left = -228.0
	_board_button.offset_top = -232.0
	_board_button.offset_right = -24.0
	_board_button.offset_bottom = -160.0
	_board_button.pressed.connect(_on_board_pressed)
	_root.add_child(_board_button)
	Wave1UI.apply_brass(_board_button)
	Wave1UI.set_icon(_board_button, ICON_WHEEL, 32)


func _refresh_board() -> void:
	if _board_button == null or _fleet == null or not is_instance_valid(_fleet):
		return

	# Nothing to offer mid-boarding: the party is already over the side, and a
	# live button there would just be a way to double-order something in progress.
	if _fleet.is_boarding():
		_board_button.visible = false
		return

	var prize: Ship = _fleet.boarding_candidate()
	if prize == null:
		_board_button.visible = false
		return

	# Say what it is worth, because the answer changes: a hull if a berth is
	# standing empty, cargo if not. That is the whole reason to buy a slot before
	# you can afford to fill it, and it is invisible unless the prompt says so.
	var berth_free: bool = GameState.fleet.size() < GameState.fleet_slots
	_board_button.text = "BOARD\n%s" % ("take her" if berth_free else "strip her")
	_board_button.visible = true


func _on_board_pressed() -> void:
	if _fleet == null or not is_instance_valid(_fleet):
		return
	var prize: Ship = _fleet.boarding_candidate()
	if prize == null:
		return
	EventBus.intent_board.emit(prize)
	_board_button.visible = false


## Prize money that just sailed over the horizon. Worth saying, because the
## garrison count dropping with nothing having sunk is otherwise unreadable.
func _on_enemy_routed(ship: Node2D, _island: Node2D) -> void:
	var hull: String = "A defender"
	if ship is Ship and is_instance_valid(ship):
		hull = (ship as Ship).stats.display_name
	show_toast("%s strikes her colours and runs — her prize money with her." % hull)


## The castle is shrugging off broadsides. Said the moment it first happens,
## because a target that ignores your guns with no explanation reads as the game
## being broken rather than as a rule with an answer.
func _on_keep_shrugged_off(_island: Node2D) -> void:
	show_toast("The walls hold — silence the shore batteries first!")


func _on_castle_breached(_island: Node2D) -> void:
	show_toast("The keep is breached!")


func _on_prize_taken(hull_name: String, kept: bool) -> void:
	if kept:
		show_toast("%s taken as a prize — she joins your fleet!" % hull_name)
	else:
		show_toast("%s stripped — no berth free for her." % hull_name)
	_refresh_fleet()
	_refresh_ammo()


## Shows a briefing modal and returns it, so the caller can await `dismissed`.
## Returns null if one is already up — two modals at once is worse than either.
func show_briefing(
	title: String, lines: PackedStringArray, button_text: String = "GOT IT"
) -> BriefingPanel:
	if get_node_or_null(^"Briefing") != null:
		return null
	var panel := BriefingPanel.new()
	panel.name = "Briefing"
	# Runs while the tree is paused, so its own button still works when it has
	# stopped the world.
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(panel)
	panel.present(title, lines, button_text)
	return panel


## Closes any open briefing. Used by the screenshot harness, and as a guarantee
## that nothing can leave the game paused behind a modal.
func dismiss_briefing() -> bool:
	var panel: BriefingPanel = get_node_or_null(^"Briefing") as BriefingPanel
	if panel == null:
		return false
	panel.force_dismiss()
	return true


## Opens the port. Returns null if a modal is already up.
func show_port(island_name: String) -> PortScreen:
	if get_node_or_null(^"Port") != null or get_node_or_null(^"Briefing") != null:
		return null
	var screen := PortScreen.new()
	screen.name = "Port"
	screen.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(screen)
	screen.present(island_name)
	return screen


func dismiss_port() -> bool:
	var screen: PortScreen = get_node_or_null(^"Port") as PortScreen
	if screen == null:
		return false
	screen.force_close()
	return true


## Opens the fleet roster. Returns null if a modal is already up.
func show_fleet() -> FleetPanel:
	if (
		_fleet == null
		or get_node_or_null(^"Fleet") != null
		or get_node_or_null(^"Port") != null
		or get_node_or_null(^"Briefing") != null
	):
		return null
	var panel := FleetPanel.new()
	panel.name = "Fleet"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(panel)
	panel.present(_fleet)
	return panel


func dismiss_fleet() -> bool:
	var panel: FleetPanel = get_node_or_null(^"Fleet") as FleetPanel
	if panel == null:
		return false
	panel.force_close()
	return true


func _refresh_all() -> void:
	_on_gold_changed(GameState.total_gold(), 0)
	_on_diamonds_changed(GameState.diamonds, 0)
	_refresh_ammo()
	_refresh_fleet()


## The ammo button carries the shot's *purpose*, not just its name.
##
## Five options behind one cycle button is only a decision if the player can tell
## what each one is for. "Chain Shot" teaches nothing; "shreds sails" teaches the
## whole mechanic. The colour matches the ball in flight, so the button and the
## thing it fires are visibly the same object.
func _refresh_ammo() -> void:
	var ammo: AmmoType = AmmoLibrary.get_ammo(GameState.selected_ammo)
	_ammo_button.text = "%s\n%s" % [ammo.display_name, ammo.role]
	if ammo.icon != null:
		Wave1UI.set_icon(_ammo_button, ammo.icon, 38)
	_ammo_button.add_theme_color_override("font_color", ammo.tint)
	_ammo_count.add_theme_color_override("font_color", ammo.tint)
	if ammo.unlimited:
		_ammo_count.text = "∞"
	else:
		var stock: int = GameState.get_ammo(ammo.id)
		_ammo_count.text = "%d left" % stock


## "hulls afloat / hulls owned".
##
## Counted off the fleet controller, not off `GameState.fleet`. The roster is the
## ships you own; only the controller knows which of them are still floating, and
## the whole point of the readout is to tell you when one is not. Counting the
## roster made this a constant "1 / 1" that could never report a loss — harmless
## while the fleet was capped at one hull, wrong the moment a second one exists.
##
## The denominator is the roster rather than [member GameState.fleet_slots].
## Slots are a permanent purchase and never fall, so a fleet of one that owns
## three slots read "1 / 3" for the rest of the run and looked like two ships had
## sunk. What the player wants to know is how many of the hulls they have are
## still under them.
##
## Two numbers can only ever be two numbers, though, and buying a second ship
## moves the second one silently — see [FleetPanel], which the badge opens.
func _refresh_fleet() -> void:
	var owned: int = GameState.fleet.size()
	var afloat: int = owned
	if _fleet != null and is_instance_valid(_fleet):
		afloat = _fleet.living_ships().size()
	_fleet_label.text = "%d / %d" % [afloat, owned]


func show_toast(text: String) -> void:
	_toast.text = text
	_toast_left = TOAST_DURATION
	_toast.modulate.a = 1.0


func _on_gold_changed(total: int, _delta: int) -> void:
	_gold_label.text = str(total)


func _on_diamonds_changed(total: int, _delta: int) -> void:
	_diamond_label.text = str(total)


func _on_ammo_pressed() -> void:
	EventBus.intent_cycle_ammo.emit()
	_refresh_ammo()


func _on_fleet_pressed() -> void:
	Audio.play_ui(&"ui_tap")
	show_fleet()


## Sets a course for home. The button carries the range, which is the other half
## of the decision — "push one more island or go and bank it" is not a decision
## the player can weigh without knowing how far back it is.
func _on_hideout_pressed() -> void:
	Audio.play_ui(&"ui_confirm")
	EventBus.intent_sail_home.emit()


func _refresh_hideout() -> void:
	var home: Island = null
	if _archipelago != null and is_instance_valid(_archipelago):
		home = _archipelago.home
	if home == null or _fleet == null or not is_instance_valid(_fleet):
		_hideout_button.text = "Hideout"
		_hideout_button.disabled = home == null
		return

	var range_home: float = maxf(0.0, home.distance_to_coast(_fleet.centroid()))
	_hideout_button.disabled = false
	_hideout_button.text = "Hideout\n%s" % _range_text(range_home)


## Metres up to a kilometre, then kilometres to one decimal. A four-figure number
## on a button is read as "a lot" rather than as a distance.
func _range_text(metres: float) -> String:
	if metres < 1000.0:
		return "%d m" % roundi(metres)
	return "%.1f km" % (metres / 1000.0)


func _on_selection_changed(ship: Node2D) -> void:
	if ship is Ship:
		show_toast("%s selected" % (ship as Ship).stats.display_name)


func _on_island_discovered(island: Node2D) -> void:
	show_toast("Land ho — %s" % (island as Island).def.display_name)


func _on_island_captured(island: Node2D) -> void:
	show_toast("%s captured!" % (island as Island).def.display_name)


## Burning a slipway is the one thing in an island fight the player *chose* to
## do rather than had to, so it is worth saying out loud — otherwise the only
## evidence is reinforcements that stop arriving, which is the absence of a thing
## and reads as nothing at all.
func _on_shipyard_destroyed(island: Node2D) -> void:
	var where: String = "the yard"
	if island is Island and is_instance_valid(island):
		where = "%s's yard" % (island as Island).def.display_name
	show_toast("%s is burning — no more reinforcements." % where.capitalize())


func _on_treasure_dug(_island: Node2D, loot: Dictionary) -> void:
	var parts: PackedStringArray = []
	for kind: StringName in loot:
		parts.append("%s x%d" % [String(kind).capitalize(), int(loot[kind])])
	show_toast("Treasure! " + ", ".join(parts))
	_refresh_ammo()


## "Ship lost!" is for losing *a* ship, not for losing the last one.
##
## [method Ship._sink] emits `died` before `ship_sunk`, and `died` is what walks
## through FleetController into the voyage's game-over handler — so by the time
## this runs the "your fleet is lost, this much gold is safe ashore" toast has
## already been posted, and showing another one here silently replaced it. There
## is only one toast slot, so the wipe read as an unexplained trip back to the
## menu with the player's gold apparently untouched. The last hull is the one
## moment the smaller message has nothing to add.
func _on_ship_sunk(ship: Node2D, _killer: Node2D) -> void:
	if ship is Ship and (ship as Ship).team == Teams.PLAYER:
		var fleet_alive: bool = (
			_fleet != null and is_instance_valid(_fleet) and not _fleet.living_ships().is_empty()
		)
		if fleet_alive:
			show_toast("Ship lost!")
	_refresh_fleet()
