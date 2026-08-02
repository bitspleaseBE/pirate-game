class_name ObjectPool
extends RefCounted
## Fixed-parent object pool.
##
## Pooled nodes stay parented for their whole life and are recycled by toggling
## `visible` and `process_mode`. Reparenting is not free, and `queue_free()` in
## a fight is how a web build ends up hitching on garbage collection.
##
## Pooled scenes may implement:
##   `_pool_acquire()` — called after the node is handed out
##   `_pool_release()` — called before it goes back on the shelf
## Neither is required; a plain sprite works fine.

var pool_name: StringName
var high_water: int = 0
var grew_past_prewarm: bool = false

var _scene: PackedScene
var _parent: Node
var _prewarm: int
var _available: Array[Node] = []
var _in_use: Dictionary = {}  # Node -> true


func _init(p_name: StringName, p_scene: PackedScene, p_parent: Node, p_prewarm: int = 0) -> void:
	pool_name = p_name
	_scene = p_scene
	_parent = p_parent
	_prewarm = p_prewarm
	for _i: int in p_prewarm:
		_available.append(_make())


func acquire() -> Node:
	var node: Node
	if _available.is_empty():
		node = _make()
		if not grew_past_prewarm:
			grew_past_prewarm = true
			Log.warn(
				"Pool '%s' grew past its prewarm of %d — raise it." % [pool_name, _prewarm],
				"ObjectPool"
			)
	else:
		node = _available.pop_back()

	_in_use[node] = true
	high_water = maxi(high_water, _in_use.size())

	node.process_mode = Node.PROCESS_MODE_INHERIT
	if node is CanvasItem:
		(node as CanvasItem).visible = true
	if node.has_method(&"_pool_acquire"):
		node.call(&"_pool_acquire")
	return node


func release(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not _in_use.has(node):
		return  # Double release — harmless, but do not corrupt the free list.

	_in_use.erase(node)
	if node.has_method(&"_pool_release"):
		node.call(&"_pool_release")
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_available.append(node)


func release_all() -> void:
	for node: Node in _in_use.keys():
		if is_instance_valid(node):
			if node.has_method(&"_pool_release"):
				node.call(&"_pool_release")
			if node is CanvasItem:
				(node as CanvasItem).visible = false
			node.process_mode = Node.PROCESS_MODE_DISABLED
			_available.append(node)
	_in_use.clear()


func in_use_count() -> int:
	return _in_use.size()


func available_count() -> int:
	return _available.size()


func total_count() -> int:
	return _in_use.size() + _available.size()


func stats() -> Dictionary:
	return {
		"name": pool_name,
		"in_use": _in_use.size(),
		"available": _available.size(),
		"total": total_count(),
		"high_water": high_water,
		"prewarm": _prewarm,
		"grew": grew_past_prewarm,
	}


func destroy() -> void:
	for node: Node in _available:
		if is_instance_valid(node):
			node.queue_free()
	for node: Node in _in_use.keys():
		if is_instance_valid(node):
			node.queue_free()
	_available.clear()
	_in_use.clear()


func _make() -> Node:
	var node: Node = _scene.instantiate()
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	_parent.add_child(node)
	return node
