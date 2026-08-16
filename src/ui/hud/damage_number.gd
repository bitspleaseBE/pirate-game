extends Node2D
## Floating damage number. Pooled, and driven by its own `_process` rather than a
## Tween — a pooled node's tween has to be killed and rebuilt on every reuse, and
## getting that wrong leaks tweens that keep animating recycled nodes.

const RISE_DISTANCE: float = 46.0
const DURATION: float = 0.75
const COLOR_INCOMING: Color = Color("ff8a7a")
const COLOR_OUTGOING: Color = Color("ffe9a8")
## Flourishes ride higher and hang around longer than a damage number — they are
## the game saying "that was the good thing", so they have to outlast the numbers
## going up around them.
const FLOURISH_COLOR: Color = Color("ffd24a")
const FLOURISH_DURATION: float = 1.15
const FLOURISH_RISE: float = 78.0
const FLOURISH_SCALE: float = 1.5

@onready var _label: Label = $Label

var _elapsed: float = 0.0
var _origin: Vector2 = Vector2.ZERO
var _duration: float = DURATION
var _rise: float = RISE_DISTANCE


func show_amount(amount: float, is_own_ship: bool) -> void:
	_label.text = str(roundi(amount))
	_label.modulate = COLOR_INCOMING if is_own_ship else COLOR_OUTGOING
	_duration = DURATION
	_rise = RISE_DISTANCE
	scale = Vector2.ONE
	_restart()
	# Small horizontal jitter so a broadside's worth of numbers does not stack
	# into one illegible column.
	_origin.x += randf_range(-18.0, 18.0)
	position = _origin


## A word rather than a number: "RAKE!" and anything else the game wants to
## shout. Same pooled node, because a second pool for four characters of text
## would be a second prewarm budget to get wrong.
func show_flourish(text: String) -> void:
	_label.text = text
	_label.modulate = FLOURISH_COLOR
	_duration = FLOURISH_DURATION
	_rise = FLOURISH_RISE
	scale = Vector2.ONE * FLOURISH_SCALE
	_restart()


func _restart() -> void:
	_elapsed = 0.0
	_origin = position
	modulate.a = 1.0


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = _elapsed / _duration
	if t >= 1.0:
		Pools.release(&"damage_number", self)
		return
	# Ease out on the rise, fade only in the second half.
	position = _origin + Vector2(0, -_rise * (1.0 - pow(1.0 - t, 2.0)))
	modulate.a = clampf((1.0 - t) * 2.0, 0.0, 1.0)


func _pool_release() -> void:
	_elapsed = 0.0
	_duration = DURATION
	_rise = RISE_DISTANCE
	scale = Vector2.ONE
	modulate.a = 1.0
