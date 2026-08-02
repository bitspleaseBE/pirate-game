extends Node
## Decides, several times a second, how much work each entity is allowed to do.
##
## Four levels of detail rather than a binary visible/invisible, because a
## binary switch produces the two classic bugs: ships that teleport when they
## come back on screen, and a fight that silently stops happening off-camera.
##
##   FULL      on screen and near   — everything runs
##   REDUCED   on screen and far    — no particles, no wake, halved anim rate
##   SIMULATED off screen, nearby   — node disabled, position advanced at 4 Hz
##   DORMANT   off screen and far   — nothing runs at all
##
## Registered entities must implement `set_lod_tier(tier: int)`. They may also
## implement `sim_step(delta: float)` to be advanced while SIMULATED, and
## `get_cull_radius() -> float` if their sprite is much bigger than a point.
##
## Runs on its own slow tick: culling state does not need frame accuracy, and
## paying for it every frame would defeat the point. See ARCHITECTURE.md §3.

enum Lod { FULL, REDUCED, SIMULATED, DORMANT }

const LOD_NAMES: PackedStringArray = ["FULL", "REDUCED", "SIMULATED", "DORMANT"]

## How often LOD tiers are reconsidered.
const TICK_HZ: float = 6.0
## How often off-screen entities are advanced.
const SIM_HZ: float = 4.0
## Beyond this multiple of the culled rect's half-extent, entities go DORMANT.
const DORMANT_DISTANCE_FACTOR: float = 4.0
## A viewport smaller than this in either axis is not a real viewport yet.
const MIN_VALID_VIEWPORT: float = 8.0

signal tick_completed()

var enabled: bool = true
var camera: Camera2D = null

# Live counts, for the debug overlay.
var count_full: int = 0
var count_reduced: int = 0
var count_simulated: int = 0
var count_dormant: int = 0
var last_tick_usec: int = 0

var _entities: Array[Node2D] = []
var _tiers: Dictionary = {}  # Node2D -> Lod
var _tick_accum: float = 0.0
var _sim_accum: float = 0.0
var _inner_rect: Rect2 = Rect2()
var _outer_rect: Rect2 = Rect2()
## Scratch arrays, reused every tick so the manager itself never allocates.
var _scratch_dist: Array[float] = []
var _scratch_nodes: Array[Node2D] = []


func _ready() -> void:
	EventBus.camera_registered.connect(_on_camera_registered)


func register(entity: Node2D) -> void:
	if _tiers.has(entity):
		return
	if not entity.has_method(&"set_lod_tier"):
		Log.error("%s registered for culling but has no set_lod_tier()" % entity.name, "Cull")
		return
	_entities.append(entity)
	_tiers[entity] = Lod.FULL
	entity.tree_exiting.connect(unregister.bind(entity), CONNECT_ONE_SHOT)


func unregister(entity: Node2D) -> void:
	if not _tiers.has(entity):
		return
	_tiers.erase(entity)
	var idx: int = _entities.find(entity)
	if idx >= 0:
		_entities.remove_at(idx)


func clear() -> void:
	_entities.clear()
	_tiers.clear()


func get_tier(entity: Node2D) -> Lod:
	return _tiers.get(entity, Lod.DORMANT)


func get_cull_rect() -> Rect2:
	return _outer_rect


func registered_count() -> int:
	return _entities.size()


## Forces an immediate re-evaluation. Call after teleporting the camera so the
## first frame at the new location is not a frame of pop-in.
func force_tick() -> void:
	_tick_accum = 0.0
	if camera != null and is_instance_valid(camera):
		_do_tick()


func _process(delta: float) -> void:
	if not enabled or camera == null or not is_instance_valid(camera):
		return

	_tick_accum += delta
	if _tick_accum >= 1.0 / TICK_HZ:
		_tick_accum = 0.0
		_do_tick()

	_sim_accum += delta
	if _sim_accum >= 1.0 / SIM_HZ:
		var sim_delta: float = _sim_accum
		_sim_accum = 0.0
		_do_sim_step(sim_delta)


func _do_tick() -> void:
	# Refuse to classify anything against a viewport that has no size yet.
	#
	# A SubViewport created by `change_scene_to_file` reports 0x0 until its
	# container lays it out on the following frame. Ticking then computes a
	# zero-area camera rect, decides every entity in the world is DORMANT, and
	# hides all of them — and if anything pauses the tree before the next tick
	# (the wind intro does exactly that), they never come back. The symptom is a
	# game that loads to an empty sea with a working HUD, which looks nothing like
	# a culling bug.
	if not _viewport_is_ready():
		return

	var started: int = Time.get_ticks_usec()

	_update_rects()
	Grid.prune_invalid()

	_scratch_nodes.clear()
	_scratch_dist.clear()

	var center: Vector2 = _inner_rect.get_center()
	var dormant_distance: float = _outer_rect.size.length() * 0.5 * DORMANT_DISTANCE_FACTOR
	var dormant_distance_sq: float = dormant_distance * dormant_distance

	# Untyped read: a freed entity assigned to a typed variable raises before we
	# can test it, and this loop exists precisely to find freed entities.
	var dead: Array = []
	for raw: Variant in _entities:
		if not is_instance_valid(raw):
			dead.append(raw)
			continue
		var entity: Node2D = raw

		var pos: Vector2 = entity.global_position
		var radius: float = 0.0
		if entity.has_method(&"get_cull_radius"):
			radius = entity.call(&"get_cull_radius")

		var want: Lod
		if _inner_rect.grow(radius).has_point(pos):
			# Candidate for FULL, but the visible-entity budget may demote it.
			want = Lod.FULL
			_scratch_nodes.append(entity)
			_scratch_dist.append(center.distance_squared_to(pos))
		elif _outer_rect.grow(radius).has_point(pos):
			want = Lod.REDUCED
		elif center.distance_squared_to(pos) <= dormant_distance_sq:
			want = Lod.SIMULATED
		else:
			want = Lod.DORMANT

		_set_tier(entity, want)

	# `dead` holds freed objects by construction, so it too must stay untyped.
	for gone: Variant in dead:
		unregister(gone)

	_enforce_visible_budget()
	_recount()

	last_tick_usec = Time.get_ticks_usec() - started
	tick_completed.emit()


## Keeps the on-screen entity count inside the quality budget by demoting the
## furthest FULL entities to REDUCED. A busy fight degrades from the edges in,
## which is where the player is least likely to be looking.
func _enforce_visible_budget() -> void:
	var budget: int = Quality.max_visible_ships
	if _scratch_nodes.size() <= budget:
		return

	var order: Array[int] = []
	order.resize(_scratch_nodes.size())
	for i: int in _scratch_nodes.size():
		order[i] = i
	var dist: Array[float] = _scratch_dist
	order.sort_custom(func(a: int, b: int) -> bool: return dist[a] < dist[b])

	for rank: int in range(budget, order.size()):
		_set_tier(_scratch_nodes[order[rank]], Lod.REDUCED)


func _do_sim_step(delta: float) -> void:
	for raw: Variant in _entities:
		if not is_instance_valid(raw):
			continue
		var entity: Node2D = raw
		if _tiers.get(entity) != Lod.SIMULATED:
			continue
		if entity.has_method(&"sim_step"):
			# The node is disabled, so its _process is not running — but calling
			# a method on it directly still works. That is the whole trick: the
			# world stays coherent for a fraction of the full cost.
			entity.call(&"sim_step", delta)


func _set_tier(entity: Node2D, want: Lod) -> void:
	if _tiers.get(entity) == want:
		return
	_tiers[entity] = want

	var active: bool = want == Lod.FULL or want == Lod.REDUCED
	entity.visible = active
	entity.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	entity.call(&"set_lod_tier", int(want))


func _recount() -> void:
	count_full = 0
	count_reduced = 0
	count_simulated = 0
	count_dormant = 0
	for tier_value: Lod in _tiers.values():
		match tier_value:
			Lod.FULL:
				count_full += 1
			Lod.REDUCED:
				count_reduced += 1
			Lod.SIMULATED:
				count_simulated += 1
			_:
				count_dormant += 1


func _viewport_is_ready() -> bool:
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return false
	var size: Vector2 = camera.get_viewport_rect().size
	return size.x >= MIN_VALID_VIEWPORT and size.y >= MIN_VALID_VIEWPORT


func _update_rects() -> void:
	var viewport_size: Vector2 = camera.get_viewport_rect().size
	var zoom: Vector2 = camera.zoom
	var world_size: Vector2 = Vector2(
		viewport_size.x / maxf(0.01, zoom.x), viewport_size.y / maxf(0.01, zoom.y)
	)
	var center: Vector2 = camera.get_screen_center_position()

	_inner_rect = Rect2(center - world_size * 0.5, world_size)

	var margin: float = 1.0 + Quality.cull_margin * 2.0
	var outer_size: Vector2 = world_size * margin
	_outer_rect = Rect2(center - outer_size * 0.5, outer_size)


func _on_camera_registered(new_camera: Camera2D) -> void:
	camera = new_camera
	force_tick()
