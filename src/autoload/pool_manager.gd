extends Node
## Owns every [ObjectPool] in the game.
##
## Pooled nodes must render in world space, and the world lives inside a
## SubViewport, so pools cannot simply parent to this autoload — the game scene
## hands us a world root on load via [method set_world_root].
##
## The rule this exists to enforce: nothing in gameplay calls `instantiate()` or
## `queue_free()` per frame.

## Pools are declared here rather than at each call site so prewarm counts are
## visible in one place and can be tuned against the quality tier.
const POOL_DEFS: Array[Dictionary] = [
	{
		"name": &"cannonball",
		"path": "res://src/entities/projectiles/cannonball.tscn",
		"prewarm": 48,
		"scales_with_quality": true,
	},
	{
		"name": &"splash",
		"path": "res://src/entities/effects/effect_splash.tscn",
		"prewarm": 16,
		"scales_with_quality": true,
	},
	{
		"name": &"impact",
		"path": "res://src/entities/effects/effect_impact.tscn",
		"prewarm": 16,
		"scales_with_quality": true,
	},
	{
		"name": &"muzzle_flash",
		"path": "res://src/entities/effects/effect_muzzle_flash.tscn",
		"prewarm": 12,
		"scales_with_quality": true,
	},
	{
		"name": &"explosion",
		"path": "res://src/entities/effects/effect_explosion.tscn",
		"prewarm": 8,
		"scales_with_quality": true,
	},
	{
		"name": &"damage_number",
		"path": "res://src/ui/hud/damage_number.tscn",
		"prewarm": 12,
		"scales_with_quality": false,
	},
]

var _pools: Dictionary = {}  # StringName -> ObjectPool
var _world_root: Node = null


## Called by the gameplay scene once its world node exists. Recreates every pool
## under the new root; the previous root's pooled nodes die with it.
func set_world_root(root: Node) -> void:
	_pools.clear()
	_world_root = root
	if root == null:
		return

	var container := Node2D.new()
	container.name = "PooledObjects"
	# Pooled effects are visual noise behind gameplay; keep them off the y-sort
	# path of the ships so a splash never draws over a hull.
	container.z_index = -1
	root.add_child(container)

	for def: Dictionary in POOL_DEFS:
		var path: String = def["path"]
		if not ResourceLoader.exists(path):
			Log.warn("Pool scene missing, skipping: %s" % path, "Pools")
			continue

		var scene: PackedScene = load(path)
		var prewarm: int = def["prewarm"]
		if def["scales_with_quality"]:
			prewarm = maxi(4, roundi(float(prewarm) * _prewarm_factor()))

		var pool_container := Node2D.new()
		pool_container.name = String(def["name"])
		container.add_child(pool_container)

		_pools[def["name"]] = ObjectPool.new(def["name"], scene, pool_container, prewarm)

	Log.info("Prewarmed %d pools" % _pools.size(), "Pools")


func get_pool(pool_name: StringName) -> ObjectPool:
	return _pools.get(pool_name) as ObjectPool


func acquire(pool_name: StringName) -> Node:
	var pool: ObjectPool = get_pool(pool_name)
	if pool == null:
		Log.error("No pool named '%s'" % pool_name, "Pools")
		return null
	return pool.acquire()


func release(pool_name: StringName, node: Node) -> void:
	var pool: ObjectPool = get_pool(pool_name)
	if pool != null:
		pool.release(node)


## Convenience for one-shot visual effects: acquire, place, and let the effect
## return itself to the pool when it finishes.
func spawn_effect(
	pool_name: StringName, world_pos: Vector2, rotation_rad: float = 0.0, scale_mul: float = 1.0
) -> Node2D:
	var node: Node2D = acquire(pool_name) as Node2D
	if node == null:
		return null
	node.global_position = world_pos
	node.rotation = rotation_rad
	node.scale = Vector2.ONE * scale_mul
	return node


func release_all() -> void:
	for pool: ObjectPool in _pools.values():
		pool.release_all()


func all_stats() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pool: ObjectPool in _pools.values():
		out.append(pool.stats())
	return out


func _prewarm_factor() -> float:
	match Quality.tier:
		Quality.Tier.LOW:
			return 0.4
		Quality.Tier.MEDIUM:
			return 0.7
		_:
			return 1.0
