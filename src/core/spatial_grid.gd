class_name SpatialGrid
extends RefCounted
## Uniform spatial hash over world space.
##
## Exists so that gameplay queries ("what is within 90px of this impact?",
## "which ship did the player tap?", "how close is that coast?") never touch the
## physics server. On a web build a few hundred `intersect_shape` calls per second
## is a measurable cost; this is a dictionary lookup and a handful of distance
## checks.
##
## Entities register once and call [method update] when they move. Updates are
## cheap: recompute the covered cells and early-out if they did not change.
##
## **Entries are bucketed by area, not by centre.** An island with a 700px radius
## is inserted into every cell its bounding box touches, so a ship half a cell
## away still finds it. Bucketing only at the centre — the obvious implementation
## — silently breaks every query about a large object: the caller asks "is there
## land within 200px?", the grid walks the two cells around the query point, the
## island's single entry lives in a cell 700px away, and the answer comes back
## empty. Nothing errors; ships just sail through coastlines.

# Kind flags. Queries take a mask so callers ask for exactly what they need.
const KIND_NONE: int = 0
const KIND_PLAYER_SHIP: int = 1 << 0
const KIND_ENEMY_SHIP: int = 1 << 1
const KIND_STRUCTURE: int = 1 << 2
const KIND_ISLAND: int = 1 << 3
const KIND_PICKUP: int = 1 << 4
const KIND_SHIP: int = KIND_PLAYER_SHIP | KIND_ENEMY_SHIP
const KIND_TARGETABLE: int = KIND_SHIP | KIND_STRUCTURE
const KIND_ANY: int = 0x7FFFFFFF

const DEFAULT_CELL_SIZE: int = 512

## Largest number of cells a single query may sweep.
##
## A radius or rect much larger than intended turns a hash-grid lookup into an
## O(world area) walk — precisely the cost the grid exists to avoid, and one that
## presents as a hang rather than an error, because nothing is technically wrong.
## At the default cell size this cap is a ~32,000px square: far larger than any
## legitimate gameplay query, far smaller than a whole voyage.
const MAX_QUERY_CELLS: int = 4096

## An entry covering more cells than this is almost certainly a mistake — a stray
## huge radius would otherwise be inserted thousands of times.
const MAX_ENTRY_CELLS: int = 1024


class Entry:
	var node: Node2D
	var kind: int
	var radius: float
	var min_cell: Vector2i = Vector2i.ZERO
	## `max_cell.x < min_cell.x` is the "not currently bucketed" sentinel, so a
	## fresh or already-removed entry can be unbucketed again harmlessly.
	var max_cell: Vector2i = Vector2i(-1, 0)
	## Set to the grid's query counter when this entry is returned, so a single
	## query can dedupe an entry it finds in several cells without allocating.
	var stamp: int = -1

	func _init(p_node: Node2D, p_kind: int, p_radius: float) -> void:
		node = p_node
		kind = p_kind
		radius = p_radius


var cell_size: int = DEFAULT_CELL_SIZE

var _cells: Dictionary = {}    # Vector2i -> Array[Entry]
var _entries: Dictionary = {}  # Node2D   -> Entry
var _query_counter: int = 0


func _init(p_cell_size: int = DEFAULT_CELL_SIZE) -> void:
	cell_size = maxi(32, p_cell_size)


func add(node: Node2D, kind: int, radius: float = 0.0) -> void:
	var existing: Entry = _entries.get(node) as Entry
	if existing != null:
		existing.kind = kind
		if not is_equal_approx(existing.radius, radius):
			existing.radius = radius
			_rebucket(existing, true)
		return

	var entry := Entry.new(node, kind, radius)
	_entries[node] = entry
	_rebucket(entry, true)


func remove(node: Node2D) -> void:
	var entry: Entry = _entries.get(node) as Entry
	if entry == null:
		return
	_unbucket(entry)
	_entries.erase(node)


## Call from the entity when it moves. Early-outs unless its covered cells changed.
func update(node: Node2D) -> void:
	var entry: Entry = _entries.get(node) as Entry
	if entry != null:
		_rebucket(entry, false)


func has(node: Node2D) -> bool:
	return _entries.has(node)


func set_kind(node: Node2D, kind: int) -> void:
	var entry: Entry = _entries.get(node) as Entry
	if entry != null:
		entry.kind = kind


## Everything whose circle overlaps the given circle.
func query_radius(pos: Vector2, radius: float, mask: int = KIND_ANY) -> Array[Node2D]:
	var out: Array[Node2D] = []
	_query_counter += 1

	var min_cell: Vector2i = _cell_of(pos - Vector2(radius, radius))
	var max_cell: Vector2i = _cap_span(
		min_cell, _cell_of(pos + Vector2(radius, radius)), "query_radius(r=%.0f)" % radius
	)

	for cx: int in range(min_cell.x, max_cell.x + 1):
		for cy: int in range(min_cell.y, max_cell.y + 1):
			for entry: Entry in _cells.get(Vector2i(cx, cy), []) as Array:
				if entry.stamp == _query_counter or entry.kind & mask == 0:
					continue
				entry.stamp = _query_counter
				var reach: float = radius + entry.radius
				if pos.distance_squared_to(entry.node.global_position) <= reach * reach:
					out.append(entry.node)
	return out


## Everything whose bounding circle overlaps the rect.
func query_rect(rect: Rect2, mask: int = KIND_ANY) -> Array[Node2D]:
	var out: Array[Node2D] = []
	_query_counter += 1

	var min_cell: Vector2i = _cell_of(rect.position)
	var max_cell: Vector2i = _cap_span(
		min_cell, _cell_of(rect.end), "query_rect(%s)" % str(rect.size.round())
	)

	for cx: int in range(min_cell.x, max_cell.x + 1):
		for cy: int in range(min_cell.y, max_cell.y + 1):
			for entry: Entry in _cells.get(Vector2i(cx, cy), []) as Array:
				if entry.stamp == _query_counter or entry.kind & mask == 0:
					continue
				entry.stamp = _query_counter
				if rect.grow(entry.radius).has_point(entry.node.global_position):
					out.append(entry.node)
	return out


## Closest matching entity, or null. `exclude` skips one node (usually the caller).
func query_nearest(
	pos: Vector2, radius: float, mask: int = KIND_ANY, exclude: Node2D = null
) -> Node2D:
	var best: Node2D = null
	var best_dist_sq: float = radius * radius
	for node: Node2D in query_radius(pos, radius, mask):
		if node == exclude:
			continue
		var d: float = pos.distance_squared_to(node.global_position)
		if d <= best_dist_sq:
			best_dist_sq = d
			best = node
	return best


func clear() -> void:
	_cells.clear()
	_entries.clear()


func get_entity_count() -> int:
	return _entries.size()


func get_cell_count() -> int:
	return _cells.size()


## Drops entries whose node was freed without calling [method remove]. Cheap
## insurance; the culling manager runs it on its slow tick.
func prune_invalid() -> int:
	# Untyped throughout: these entries are freed by definition, and a typed
	# assignment would raise on every one of them.
	var dead: Array = []
	for node: Variant in _entries.keys():
		if not is_instance_valid(node):
			dead.append(node)
	for node: Variant in dead:
		_unbucket(_entries[node])
		_entries.erase(node)
	return dead.size()


## Recomputes the cells an entry covers and moves it if they changed.
func _rebucket(entry: Entry, force: bool) -> void:
	var pos: Vector2 = entry.node.global_position
	var extent := Vector2(entry.radius, entry.radius)
	var min_cell: Vector2i = _cell_of(pos - extent)
	var max_cell: Vector2i = _cell_of(pos + extent)

	if not force and min_cell == entry.min_cell and max_cell == entry.max_cell:
		return

	var span: int = (max_cell.x - min_cell.x + 1) * (max_cell.y - min_cell.y + 1)
	if span > MAX_ENTRY_CELLS:
		push_error(
			"SpatialGrid: %s has radius %.0f, covering %d cells (limit %d). Clamping."
			% [entry.node.name, entry.radius, span, MAX_ENTRY_CELLS]
		)
		var side: int = maxi(1, int(sqrt(float(MAX_ENTRY_CELLS))))
		max_cell = Vector2i(mini(max_cell.x, min_cell.x + side - 1), mini(max_cell.y, min_cell.y + side - 1))

	_unbucket(entry)
	entry.min_cell = min_cell
	entry.max_cell = max_cell

	for cx: int in range(min_cell.x, max_cell.x + 1):
		for cy: int in range(min_cell.y, max_cell.y + 1):
			_bucket(Vector2i(cx, cy)).append(entry)


func _bucket(cell: Vector2i) -> Array:
	var bucket: Array = _cells.get(cell, [])
	if bucket.is_empty():
		_cells[cell] = bucket
	return bucket


func _unbucket(entry: Entry) -> void:
	if entry.max_cell.x < entry.min_cell.x:
		return  # Never bucketed.
	for cx: int in range(entry.min_cell.x, entry.max_cell.x + 1):
		for cy: int in range(entry.min_cell.y, entry.max_cell.y + 1):
			var cell := Vector2i(cx, cy)
			var bucket: Array = _cells.get(cell, [])
			var idx: int = bucket.find(entry)
			if idx >= 0:
				# Order in a bucket is meaningless, so swap-and-pop beats remove_at.
				bucket[idx] = bucket[bucket.size() - 1]
				bucket.resize(bucket.size() - 1)
			if bucket.is_empty():
				_cells.erase(cell)
	# Mark as unbucketed so a double-unbucket is a no-op.
	entry.max_cell = entry.min_cell - Vector2i.ONE


## Clamps a query's cell range to [constant MAX_QUERY_CELLS] and complains.
##
## Clamping silently would hide the caller's bug; refusing outright would break
## gameplay for what is usually a bad constant. So: return a truncated answer and
## make sure someone sees why.
func _cap_span(min_cell: Vector2i, max_cell: Vector2i, context: String) -> Vector2i:
	var width: int = max_cell.x - min_cell.x + 1
	var height: int = max_cell.y - min_cell.y + 1
	if width * height <= MAX_QUERY_CELLS:
		return max_cell

	var side: int = maxi(1, int(sqrt(float(MAX_QUERY_CELLS))))
	push_error(
		"SpatialGrid: %s would sweep %d cells (limit %d). Truncating — this is a bug in the caller."
		% [context, width * height, MAX_QUERY_CELLS]
	)
	return Vector2i(mini(max_cell.x, min_cell.x + side - 1), mini(max_cell.y, min_cell.y + side - 1))


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.y / cell_size))
