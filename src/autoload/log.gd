extends Node
## Tiny leveled logger with a ring buffer the debug overlay can read.
##
## Using this instead of bare `print()` gives us three things that matter for a
## web build: a level filter so release builds stay quiet, a recent-history
## buffer we can show on-device (there is no console on a phone), and one place
## to add crash reporting later.

enum Level { TRACE, DEBUG, INFO, WARN, ERROR }

const HISTORY_SIZE: int = 120

## Messages at or above this level are emitted. Release builds start at INFO.
var min_level: Level = Level.DEBUG

var _history: Array[String] = []

signal message_logged(level: Level, text: String)


func _ready() -> void:
	if not OS.is_debug_build():
		min_level = Level.WARN


func trace(msg: String, ctx: String = "") -> void:
	_write(Level.TRACE, msg, ctx)


func debug(msg: String, ctx: String = "") -> void:
	_write(Level.DEBUG, msg, ctx)


func info(msg: String, ctx: String = "") -> void:
	_write(Level.INFO, msg, ctx)


func warn(msg: String, ctx: String = "") -> void:
	_write(Level.WARN, msg, ctx)


func error(msg: String, ctx: String = "") -> void:
	_write(Level.ERROR, msg, ctx)


## Most recent messages, oldest first.
func get_history() -> Array[String]:
	return _history


func _write(level: Level, msg: String, ctx: String) -> void:
	if level < min_level:
		return

	var prefix: String = Level.keys()[level]
	var line: String = "[%s]%s %s" % [prefix, "" if ctx.is_empty() else " (" + ctx + ")", msg]

	_history.append(line)
	if _history.size() > HISTORY_SIZE:
		_history.remove_at(0)

	match level:
		Level.WARN:
			push_warning(line)
		Level.ERROR:
			push_error(line)
		_:
			print(line)

	message_logged.emit(level, line)
