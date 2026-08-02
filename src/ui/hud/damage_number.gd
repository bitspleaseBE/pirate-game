extends Node2D
## Floating damage number. Pooled, and driven by its own `_process` rather than a
## Tween — a pooled node's tween has to be killed and rebuilt on every reuse, and
## getting that wrong leaks tweens that keep animating recycled nodes.

const RISE_DISTANCE: float = 46.0
const DURATION: float = 0.75
const COLOR_INCOMING: Color = Color("ff8a7a")
const COLOR_OUTGOING: Color = Color("ffe9a8")

@onready var _label: Label = $Label

var _elapsed: float = 0.0
var _origin: Vector2 = Vector2.ZERO


func show_amount(amount: float, is_own_ship: bool) -> void:
	_label.text = str(roundi(amount))
	_label.modulate = COLOR_INCOMING if is_own_ship else COLOR_OUTGOING
	_elapsed = 0.0
	_origin = position
	# Small horizontal jitter so a broadside's worth of numbers does not stack
	# into one illegible column.
	_origin.x += randf_range(-18.0, 18.0)
	position = _origin


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = _elapsed / DURATION
	if t >= 1.0:
		Pools.release(&"damage_number", self)
		return
	# Ease out on the rise, fade only in the second half.
	position = _origin + Vector2(0, -RISE_DISTANCE * (1.0 - pow(1.0 - t, 2.0)))
	modulate.a = clampf((1.0 - t) * 2.0, 0.0, 1.0)


func _pool_release() -> void:
	_elapsed = 0.0
	modulate.a = 1.0
