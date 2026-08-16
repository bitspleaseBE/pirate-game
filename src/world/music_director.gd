class_name MusicDirector
extends Node
## Decides how loud the fight is, and hands that one number to [AudioManager].
##
## The design has always asked for this — docs/GAME_DESIGN.md §10: "Shanty music
## that layers instruments in as a fight escalates and strips back to solo
## accordion at sea." None of it existed. `Audio.play_music()` was written,
## complete with a crossfade, and then never called from anywhere in the project;
## the only thing that referenced music at all was the save file, faithfully
## persisting the volume of a bus that never had anything on it.
##
## This is deliberately a *gameplay* system rather than decoration. Music that
## thickens the moment a garrison wakes tells the player something has changed
## before they have finished parsing the screen, and it does it through a channel
## nothing else in the game is using — the HUD is busy, the screen is busy, and
## the ears are free. Escalation is information.
##
## ## What intensity is made of
##
## Three things, and the loudest wins:
##
##   * **Company.** How many hostile hulls are near the fleet, which is the
##     coarsest possible reading of "is something happening" and the one that
##     tracks a fight from first contact to last kill.
##   * **Violence.** Damage the player has recently dealt or taken. This is what
##     separates two ships circling at range from two ships actually at it, and
##     it is why a lull between broadsides does not drop the score.
##   * **The castle.** Flat maximum. It is the end of a voyage and there is no
##     reading of that moment where the music should be doing anything else.
##
## Sampled at 4 Hz, not per frame. This drives a fader, and a fader that
## re-evaluates sixty times a second is fifty-nine wasted evaluations and one
## opportunity to flicker.

const SAMPLE_HZ: float = 4.0

## How far from the fleet a hostile hull counts as company.
const NEARBY_RADIUS: float = 2200.0
## Enemy count at which company alone is worth a full combat score. Three hulls
## in your lookout is a battle by any reasonable definition.
const CROWD_FOR_FULL: float = 3.0
## Damage over this many seconds feeds the violence reading.
const VIOLENCE_WINDOW: float = 6.0
## Damage within the window worth a full score. Set against a mid-game broadside
## rather than a whole fight, so trading fire reads as violent immediately.
const VIOLENCE_FOR_FULL: float = 90.0
## Company alone never quite reaches the top of the ramp. The last of it is
## reserved for something actually happening, so a stand-off does not sound the
## same as a melee.
const COMPANY_CEILING: float = 0.72

var fleet: FleetController = null
var archipelago: Archipelago = null

var _accum: float = 0.0
var _violence: float = 0.0


func _ready() -> void:
	EventBus.ship_damaged.connect(_on_ship_damaged)


## Called by the voyage once the world exists. Starts the sea and the stems
## together: the ambience runs for as long as the game does, because the one
## thing every frame of this game has in common is that it is happening on water.
func begin(fleet_controller: FleetController, world: Archipelago) -> void:
	fleet = fleet_controller
	archipelago = world
	Audio.start_ambience()
	Audio.start_music_layers(0.0)


func _process(delta: float) -> void:
	# Decays even while not sampling, so a fight that ends off-tick still fades.
	_violence = maxf(0.0, _violence - delta * (VIOLENCE_FOR_FULL / VIOLENCE_WINDOW))

	_accum += delta
	if _accum < 1.0 / SAMPLE_HZ:
		return
	_accum = 0.0
	Audio.set_music_intensity(measure_intensity())


## The current reading, 0 to 1. Public because it is the whole output of this
## class and the audio harness has no other way to ask whether the music is
## responding to the game rather than to a timer.
func measure_intensity() -> float:
	if fleet == null or not is_instance_valid(fleet):
		return 0.0
	var living: Array[Ship] = fleet.living_ships()
	if living.is_empty():
		return 0.0

	var centre: Vector2 = fleet.centroid()
	var company: float = clampf(
		float(_hostiles_near(centre)) / CROWD_FOR_FULL, 0.0, 1.0
	) * COMPANY_CEILING
	var violence: float = clampf(_violence / VIOLENCE_FOR_FULL, 0.0, 1.0)

	var intensity: float = maxf(company, violence)
	if _in_castle_fight(centre):
		intensity = 1.0
	return clampf(intensity, 0.0, 1.0)


## Hostile hulls and shore structures within earshot of the fleet.
##
## Structures count. A shore battery working you over is a fight, and an island
## whose guns are the only thing left firing would otherwise go quiet in the
## score at exactly the moment the player is still under fire.
func _hostiles_near(centre: Vector2) -> int:
	var mask: int = SpatialGrid.KIND_ENEMY_SHIP | SpatialGrid.KIND_STRUCTURE
	var found: Array[Node2D] = Grid.query_radius(centre, NEARBY_RADIUS, mask)
	var count: int = 0
	for node: Node2D in found:
		# A ship that has struck and run is not company any more.
		var enemy := node as EnemyShip
		if enemy != null and enemy.state == EnemyShip.AiState.FLEE:
			continue
		count += 1
	return count


## Is the fleet in front of the castle, with the castle still standing?
func _in_castle_fight(centre: Vector2) -> bool:
	if archipelago == null or not is_instance_valid(archipelago):
		return false
	for raw: Variant in archipelago.islands:
		if not is_instance_valid(raw):
			continue
		var island: Island = raw
		if not island.def.has_castle or island.is_captured:
			continue
		if not island.is_alerted:
			continue
		return island.distance_to_coast(centre) <= island.def.alert_radius
	return false


## Damage in either direction feeds the same meter.
##
## Taking a broadside and landing one are both "this is a fight now"; a score
## that only responded to being hurt would go quiet exactly when the player is
## winning, which is the wrong lesson to teach with a reward channel.
func _on_ship_damaged(ship: Node2D, amount: float, _bar: StringName) -> void:
	var hull := ship as Ship
	if hull == null or not is_instance_valid(hull):
		return
	_violence = minf(_violence + amount, VIOLENCE_FOR_FULL * 1.5)
