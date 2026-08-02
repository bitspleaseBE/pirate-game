class_name PooledEffect
extends Node2D
## One-shot visual effect that returns itself to its pool when it finishes.
##
## Driven by `_process` rather than a Tween on purpose. A pooled node's tween has
## to be killed and rebuilt on every reuse, and forgetting to kill it leaves a
## tween animating a node that has already been handed to someone else — a bug
## that shows up as effects that inexplicably drift or resize.
##
## The child `Sprite` is what animates; the root's own `scale` is left alone so
## callers can pass a size multiplier through [method PoolManager.spawn_effect].

@export var pool_name: StringName = &"impact"
@export var duration: float = 0.35
@export var start_scale: float = 0.35
@export var end_scale: float = 1.5
@export var fade_out: bool = true
## Radians per second. A little spin hides the fact that it is one static sprite.
@export var spin: float = 0.0
## Extra random rotation on spawn, so repeated hits do not look stamped.
@export var random_rotation: bool = true

var _elapsed: float = 0.0
var _sprite: Node2D


func _ready() -> void:
	_sprite = get_node_or_null(^"Sprite")


func _pool_acquire() -> void:
	_elapsed = 0.0
	if _sprite == null:
		return
	_sprite.scale = Vector2.ONE * start_scale
	_sprite.modulate.a = 1.0
	_sprite.rotation = randf() * TAU if random_rotation else 0.0
	# Autoplay only fires on first entry to the tree, so a recycled node has to be
	# restarted by hand or every reuse after the first shows a frozen last frame.
	if _sprite is AnimatedSprite2D:
		(_sprite as AnimatedSprite2D).play(&"default")


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = _elapsed / maxf(0.01, duration)
	if t >= 1.0:
		Pools.release(pool_name, self)
		return

	if _sprite == null:
		return
	# Ease out: effects should burst and settle, not grow linearly.
	var eased: float = 1.0 - pow(1.0 - t, 2.2)
	_sprite.scale = Vector2.ONE * lerpf(start_scale, end_scale, eased)
	if fade_out:
		_sprite.modulate.a = 1.0 - eased
	if spin != 0.0:
		_sprite.rotation += spin * delta


func _pool_release() -> void:
	_elapsed = 0.0
