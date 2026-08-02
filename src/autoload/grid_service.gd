extends Node
## Autoload wrapper around the world's [SpatialGrid].
##
## The grid itself is a plain RefCounted so it can be unit-tested without a
## scene tree; this node just owns the live instance and gives gameplay code a
## short call site (`Grid.query_radius(...)`).

var grid: SpatialGrid


func _ready() -> void:
	grid = SpatialGrid.new()


## Call when a voyage loads. Cell size should be roughly the largest common
## query radius — too small and queries walk many buckets, too large and each
## bucket holds too much.
func configure(cell_size: int = SpatialGrid.DEFAULT_CELL_SIZE) -> void:
	grid = SpatialGrid.new(cell_size)


func clear() -> void:
	grid.clear()


func add(node: Node2D, kind: int, radius: float = 0.0) -> void:
	grid.add(node, kind, radius)


func remove(node: Node2D) -> void:
	grid.remove(node)


func update(node: Node2D) -> void:
	grid.update(node)


func set_kind(node: Node2D, kind: int) -> void:
	grid.set_kind(node, kind)


func query_radius(
	pos: Vector2, radius: float, mask: int = SpatialGrid.KIND_ANY
) -> Array[Node2D]:
	return grid.query_radius(pos, radius, mask)


func query_rect(rect: Rect2, mask: int = SpatialGrid.KIND_ANY) -> Array[Node2D]:
	return grid.query_rect(rect, mask)


func query_nearest(
	pos: Vector2, radius: float, mask: int = SpatialGrid.KIND_ANY, exclude: Node2D = null
) -> Node2D:
	return grid.query_nearest(pos, radius, mask, exclude)


func entity_count() -> int:
	return grid.get_entity_count()


func cell_count() -> int:
	return grid.get_cell_count()


func prune_invalid() -> int:
	return grid.prune_invalid()
