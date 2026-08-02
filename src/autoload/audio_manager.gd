extends Node
## Voice-limited, pooled audio playback.
##
## A broadside is six cannons firing inside 300 ms. Played naively that is six
## identical streams stacking to +15 dB and six voices spent on one event, which
## on a phone browser is both ugly and expensive. So:
##
##   * players are pooled and reused, never instantiated per shot
##   * each sound id has a re-trigger cooldown; retriggers inside it are dropped
##   * the total simultaneous voice count is capped by the quality tier, and the
##     oldest voice is stolen when the cap is hit
##
## Streams are looked up by id from [member LIBRARY] so gameplay code never
## carries a resource path.

const SPATIAL_PLAYERS: int = 24
const UI_PLAYERS: int = 6
const MUSIC_FADE_SEC: float = 1.5

## Minimum gap between two plays of the same id, in seconds.
const DEFAULT_RETRIGGER_COOLDOWN: float = 0.05

## id -> { path, bus, cooldown, volume_db, pitch_variation }
## Entries whose file does not exist yet are skipped at load with one warning, so
## the game runs silently rather than erroring while the audio assets are still
## being produced.
const LIBRARY: Dictionary = {
	&"cannon_fire": {"path": "res://assets/audio/sfx/cannon_fire.wav", "bus": &"SFX", "cooldown": 0.06, "pitch_variation": 0.12},
	&"impact_wood": {"path": "res://assets/audio/sfx/impact_wood.wav", "bus": &"SFX", "cooldown": 0.04, "pitch_variation": 0.15},
	&"splash": {"path": "res://assets/audio/sfx/splash.wav", "bus": &"SFX", "cooldown": 0.05, "pitch_variation": 0.2},
	&"explosion": {"path": "res://assets/audio/sfx/explosion.wav", "bus": &"SFX", "cooldown": 0.08, "pitch_variation": 0.1},
	&"ship_sink": {"path": "res://assets/audio/sfx/ship_sink.wav", "bus": &"SFX", "cooldown": 0.5},
	&"coin_pickup": {"path": "res://assets/audio/sfx/coin_pickup.wav", "bus": &"SFX", "cooldown": 0.03, "pitch_variation": 0.25},
	&"island_captured": {"path": "res://assets/audio/sfx/island_captured.wav", "bus": &"SFX", "cooldown": 1.0},
	&"ui_tap": {"path": "res://assets/audio/sfx/ui_tap.wav", "bus": &"UI", "cooldown": 0.05},
	&"ui_confirm": {"path": "res://assets/audio/sfx/ui_confirm.wav", "bus": &"UI", "cooldown": 0.1},
	&"ui_cancel": {"path": "res://assets/audio/sfx/ui_cancel.wav", "bus": &"UI", "cooldown": 0.1},
}

var _streams: Dictionary = {}       # StringName -> AudioStream
var _last_played: Dictionary = {}   # StringName -> msec
var _spatial: Array[AudioStreamPlayer2D] = []
var _ui: Array[AudioStreamPlayer] = []
var _spatial_next: int = 0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active_is_a: bool = true
var _music_tween: Tween
var _current_music_id: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_library()
	_build_players()


func _load_library() -> void:
	var missing: int = 0
	for id: StringName in LIBRARY:
		var path: String = LIBRARY[id]["path"]
		if ResourceLoader.exists(path):
			_streams[id] = load(path)
		else:
			missing += 1
	if missing > 0:
		Log.warn(
			"%d/%d sounds not yet authored — those cues will be silent."
			% [missing, LIBRARY.size()],
			"Audio"
		)


func _build_players() -> void:
	var spatial_root := Node.new()
	spatial_root.name = "SpatialPlayers"
	add_child(spatial_root)
	for i: int in SPATIAL_PLAYERS:
		var p := AudioStreamPlayer2D.new()
		p.bus = &"SFX"
		# Ships fight at 600-2000px range; audio should fade over roughly that.
		p.max_distance = 2400.0
		p.attenuation = 1.5
		spatial_root.add_child(p)
		_spatial.append(p)

	var ui_root := Node.new()
	ui_root.name = "UiPlayers"
	add_child(ui_root)
	for i: int in UI_PLAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = &"UI"
		ui_root.add_child(p)
		_ui.append(p)

	_music_a = AudioStreamPlayer.new()
	_music_a.bus = &"Music"
	_music_a.name = "MusicA"
	add_child(_music_a)
	_music_b = AudioStreamPlayer.new()
	_music_b.bus = &"Music"
	_music_b.name = "MusicB"
	add_child(_music_b)


## Positional sound effect. Returns false if it was dropped by the cooldown or
## the voice cap — callers do not need to care, but tests do.
func play_at(id: StringName, world_pos: Vector2, volume_db: float = 0.0) -> bool:
	if not _can_trigger(id):
		return false
	var stream: AudioStream = _streams.get(id)
	if stream == null:
		return false

	var player: AudioStreamPlayer2D = _next_spatial_player()
	if player == null:
		return false

	var def: Dictionary = LIBRARY[id]
	player.stream = stream
	player.global_position = world_pos
	player.bus = def.get("bus", &"SFX")
	player.volume_db = volume_db + float(def.get("volume_db", 0.0))
	player.pitch_scale = _pitch_for(def)
	player.play()
	_last_played[id] = Time.get_ticks_msec()
	return true


## Non-positional sound, for UI and global cues.
func play_ui(id: StringName, volume_db: float = 0.0) -> bool:
	if not _can_trigger(id):
		return false
	var stream: AudioStream = _streams.get(id)
	if stream == null:
		return false

	for player: AudioStreamPlayer in _ui:
		if player.playing:
			continue
		var def: Dictionary = LIBRARY[id]
		player.stream = stream
		player.bus = def.get("bus", &"UI")
		player.volume_db = volume_db + float(def.get("volume_db", 0.0))
		player.pitch_scale = _pitch_for(def)
		player.play()
		_last_played[id] = Time.get_ticks_msec()
		return true
	return false


## Crossfades to a new music track. Passing the id already playing is a no-op,
## so callers can fire this from a state machine without guarding.
func play_music(id: StringName, path: String) -> void:
	if id == _current_music_id:
		return
	if not ResourceLoader.exists(path):
		return

	_current_music_id = id
	var incoming: AudioStreamPlayer = _music_b if _music_active_is_a else _music_a
	var outgoing: AudioStreamPlayer = _music_a if _music_active_is_a else _music_b
	_music_active_is_a = not _music_active_is_a

	incoming.stream = load(path)
	incoming.volume_db = -60.0
	incoming.play()

	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(incoming, "volume_db", 0.0, MUSIC_FADE_SEC)
	_music_tween.tween_property(outgoing, "volume_db", -60.0, MUSIC_FADE_SEC)
	_music_tween.chain().tween_callback(outgoing.stop)


func stop_music() -> void:
	_current_music_id = &""
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_a.stop()
	_music_b.stop()


func set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))


func get_bus_volume(bus_name: StringName) -> float:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 0.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


func active_voice_count() -> int:
	var n: int = 0
	for p: AudioStreamPlayer2D in _spatial:
		if p.playing:
			n += 1
	return n


func _can_trigger(id: StringName) -> bool:
	var def: Dictionary = LIBRARY.get(id, {})
	if def.is_empty():
		return false
	var cooldown_ms: int = roundi(float(def.get("cooldown", DEFAULT_RETRIGGER_COOLDOWN)) * 1000.0)
	var last: int = _last_played.get(id, -100000)
	return Time.get_ticks_msec() - last >= cooldown_ms


func _pitch_for(def: Dictionary) -> float:
	var variation: float = def.get("pitch_variation", 0.0)
	if variation <= 0.0:
		return 1.0
	return 1.0 + randf_range(-variation, variation)


## Round-robins through the voice budget, stealing the oldest voice when full.
## Stealing beats dropping: the newest event is almost always the one the player
## just caused, so it is the one that must be audible.
func _next_spatial_player() -> AudioStreamPlayer2D:
	var budget: int = clampi(Quality.max_audio_voices, 1, _spatial.size())
	for i: int in budget:
		var idx: int = (_spatial_next + i) % budget
		if not _spatial[idx].playing:
			_spatial_next = (idx + 1) % budget
			return _spatial[idx]

	var steal: AudioStreamPlayer2D = _spatial[_spatial_next]
	_spatial_next = (_spatial_next + 1) % budget
	return steal
