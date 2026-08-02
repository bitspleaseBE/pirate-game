extends Node
## JSON save/load with a debounced autosave.
##
## Two files, on purpose: settings must survive a corrupted save, and a player
## who loses progress should not also lose their volume and quality choices.
##
## On web, `user://` is backed by IndexedDB. Writes are asynchronous there, which
## is why saves are debounced rather than fired on every gold pickup — a save per
## coin would thrash the browser's storage layer.

const SAVE_PATH: String = "user://save.json"
const SETTINGS_PATH: String = "user://settings.json"
const SAVE_VERSION: int = 1
## Seconds of quiet before a requested save actually writes.
const AUTOSAVE_DEBOUNCE: float = 2.0

signal saved()
signal loaded()
signal save_failed(reason: String)

var _dirty: bool = false
var _debounce_left: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	# Persist on the way out, including a browser tab close.
	get_tree().auto_accept_quit = false


func _process(delta: float) -> void:
	if not _dirty:
		return
	_debounce_left -= delta
	if _debounce_left <= 0.0:
		save_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _dirty:
			save_now()
		if what == NOTIFICATION_WM_CLOSE_REQUEST:
			get_tree().quit()


## Ask for a save. Cheap to call often — the write is debounced.
func request_save() -> void:
	_dirty = true
	_debounce_left = AUTOSAVE_DEBOUNCE


func save_now() -> bool:
	_dirty = false
	_debounce_left = 0.0

	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"game": GameState.to_dict(),
	}

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		var reason: String = "Cannot open %s (error %d)" % [SAVE_PATH, FileAccess.get_open_error()]
		Log.error(reason, "Save")
		save_failed.emit(reason)
		return false

	file.store_string(JSON.stringify(payload))
	file.close()
	Log.debug("Saved", "Save")
	saved.emit()
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_game() -> bool:
	if not has_save():
		return false

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		Log.error("Cannot read save", "Save")
		return false
	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		# A corrupt save must not brick the game. Move it aside and start fresh
		# so the player can play, and we still have the file for a bug report.
		Log.error("Save file is not valid JSON — quarantining it", "Save")
		_quarantine_save()
		return false

	var data: Dictionary = parsed
	var version: int = int(data.get("version", 0))
	if version > SAVE_VERSION:
		Log.warn(
			"Save is from a newer build (v%d > v%d); loading anyway" % [version, SAVE_VERSION],
			"Save"
		)
	elif version < SAVE_VERSION:
		data = _migrate(data, version)

	GameState.from_dict(data.get("game", {}))
	Log.info("Loaded save v%d" % version, "Save")
	loaded.emit()
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	GameState.reset_run()


# --- Settings ---------------------------------------------------------------

func save_settings() -> void:
	var payload: Dictionary = {
		"master": Audio.get_bus_volume(&"Master"),
		"music": Audio.get_bus_volume(&"Music"),
		"sfx": Audio.get_bus_volume(&"SFX"),
		"quality_tier": int(Quality.tier),
		"quality_auto": Quality.auto_adapt,
	}
	var file: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload))
	file.close()


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		return

	var data: Dictionary = parsed
	Audio.set_bus_volume(&"Master", float(data.get("master", 1.0)))
	Audio.set_bus_volume(&"Music", float(data.get("music", 0.5)))
	Audio.set_bus_volume(&"SFX", float(data.get("sfx", 1.0)))
	if not bool(data.get("quality_auto", true)):
		Quality.set_tier_manual(int(data.get("quality_tier", Quality.Tier.MEDIUM)) as Quality.Tier)


func _quarantine_save() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null:
		dir.rename("save.json", "save.corrupt.json")


## Hook for future format changes. Each version bump gets its own step so that a
## save from any old build walks forward one version at a time.
func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	Log.info("Migrating save from v%d to v%d" % [from_version, SAVE_VERSION], "Save")
	# v0 -> v1: no changes needed; v0 saves predate the version field.
	return data
