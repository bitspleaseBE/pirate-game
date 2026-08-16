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
	# The mechanics added since the combat rework. Each of these marks something
	# the player did or something about to happen to them; none of them had a
	# sound, which for the mortar warning in particular meant the only notice of
	# an incoming shell was a ring drawn on water off the side of the screen.
	&"rake_hit": {"path": "res://assets/audio/sfx/rake_hit.wav", "bus": &"SFX", "cooldown": 0.12, "pitch_variation": 0.08},
	&"boarding_clash": {"path": "res://assets/audio/sfx/boarding_clash.wav", "bus": &"SFX", "cooldown": 0.4},
	&"prize_taken": {"path": "res://assets/audio/sfx/prize_taken.wav", "bus": &"SFX", "cooldown": 0.5},
	&"castle_breach": {"path": "res://assets/audio/sfx/castle_breach.wav", "bus": &"SFX", "cooldown": 1.0},
	# Long cooldown: a battery of ketches all winding up at once should sound like
	# incoming fire, not like a klaxon.
	&"mortar_incoming": {"path": "res://assets/audio/sfx/mortar_incoming.wav", "bus": &"SFX", "cooldown": 0.9, "volume_db": -3.0},
}

# --- Layered music ---------------------------------------------------------
#
# The three stems are one piece of music, not three tracks. They share a key, a
# tempo and a length to the sample (see tools/audio/make_placeholder_music.py),
# they all start together and none of them ever stops — the director only moves
# their volumes.
#
# That is what makes the music able to react *immediately*. Crossfading whole
# tracks needs a musically safe moment to switch, which means either waiting for
# one — so the music arrives after the fight it is reacting to, which is worse
# than no music — or cutting on the beat, which puts a seam in every time a
# skiff appears. Volumes have neither problem.

## Stems, quietest first. Order is the escalation order and [method
## set_music_intensity] indexes into it, so it is meaningful rather than cosmetic.
const MUSIC_LAYERS: Array[StringName] = [&"calm", &"tense", &"combat"]
const MUSIC_LAYER_PATHS: Dictionary = {
	&"calm": "res://assets/audio/music/mus_layer_calm.wav",
	&"tense": "res://assets/audio/music/mus_layer_tense.wav",
	&"combat": "res://assets/audio/music/mus_layer_combat.wav",
}
## Intensity at which each layer starts and finishes fading in. Deliberately
## overlapping: a layer that arrives exactly as the one below it finishes reads
## as a switch, where an overlap reads as the music thickening.
const MUSIC_LAYER_RAMP: Dictionary = {
	# The bed never fades. A degenerate ramp (end <= start) means "always on", and
	# that is what "strips back to solo accordion at sea" actually asks for: the
	# calm stem is the piece of music, and tense and combat are things added to
	# it. Ramping it in from zero made an empty sea silent and, worse, made the
	# escalation a crossfade — the bed dropping out as the drums arrived, which is
	# a track change with extra steps.
	&"calm": Vector2(0.0, 0.0),
	&"tense": Vector2(0.12, 0.45),
	&"combat": Vector2(0.40, 0.80),
}
## Full volume for each stem, in dB. The bed sits under the parts that carry the
## information, so a fight is legible over it rather than competing with it.
const MUSIC_LAYER_DB: Dictionary = {
	&"calm": -4.0,
	&"tense": -6.0,
	&"combat": -5.0,
}
## Below this a layer is silenced outright rather than left running at a level
## nobody can hear but every device still has to mix.
const MUSIC_LAYER_FLOOR_DB: float = -40.0
## How fast a layer's gain chases its target, per second, rising and falling.
##
## Asymmetric on purpose. Music should arrive with the fight — a broadside out of
## a silent sea is the moment escalation exists for — and leave slowly, because
## an ambush that ends in two seconds should not take the score with it, and a
## reload lull is not the end of a battle.
const MUSIC_RISE_PER_SEC: float = 2.4
const MUSIC_FALL_PER_SEC: float = 0.45

const AMBIENCE_PATH: String = "res://assets/audio/music/amb_sea.wav"
const AMBIENCE_DB: float = -6.0

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
## Stem id -> AudioStreamPlayer, all playing whenever the music is running.
var _layers: Dictionary = {}
## Stem id -> current gain, 0..1. Chases the target set by the intensity.
var _layer_gain: Dictionary = {}
var _music_intensity: float = 0.0
var _layers_playing: bool = false
var _ambience: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_library()
	_build_players()


func _exit_tree() -> void:
	shutdown()


## Stops everything and drops every stream reference.
##
## Without this, quitting while a cannon is still ringing leaves the
## AudioStreamPlayback objects alive inside the audio server, which in turn pin
## the AudioStreamWAV resources they are reading — and Godot reports both as
## leaked instances at exit.
##
## Nothing is actually broken by that, but it prints a leak warning on every run
## and, worse, it is exactly the noise that a real leak would hide behind later.
## A shutdown that leaves no references is also simply the correct behaviour when
## a browser tab closes or a phone backgrounds the app.
func shutdown() -> void:
	stop_music()
	stop_ambience()
	for player: AudioStreamPlayer2D in _spatial:
		player.stop()
		player.stream = null
	for player: AudioStreamPlayer in _ui:
		player.stop()
		player.stream = null
	if _music_a != null:
		_music_a.stream = null
	if _music_b != null:
		_music_b.stream = null
	# The stems and the sea hold references too, and they are the longest-lived
	# streams in the game — exactly the ones that would be reported as leaked.
	for id: StringName in MUSIC_LAYERS:
		var layer: AudioStreamPlayer = _layers.get(id)
		if layer != null:
			layer.stream = null
	if _ambience != null:
		_ambience.stream = null
	_streams.clear()
	_last_played.clear()


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

	for id: StringName in MUSIC_LAYERS:
		var player := AudioStreamPlayer.new()
		player.bus = &"Music"
		player.name = "Layer_%s" % id
		player.volume_db = MUSIC_LAYER_FLOOR_DB
		var path: String = MUSIC_LAYER_PATHS[id]
		if ResourceLoader.exists(path):
			player.stream = load(path)
		add_child(player)
		_layers[id] = player
		_layer_gain[id] = 0.0

	_ambience = AudioStreamPlayer.new()
	_ambience.bus = &"Ambience"
	_ambience.name = "Ambience"
	_ambience.volume_db = AMBIENCE_DB
	if ResourceLoader.exists(AMBIENCE_PATH):
		_ambience.stream = load(AMBIENCE_PATH)
	add_child(_ambience)


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
	stop_music_layers()


# --- Layered music ---------------------------------------------------------

## Starts every stem at once, silent, and lets [method set_music_intensity]
## decide what is audible.
##
## All of them, always, including the ones nobody will hear for another ten
## minutes: starting a stem late means starting it out of phase with the others,
## and three bars of shanty running against themselves is worse than no music at
## all. They are cheap — three streams on one bus, decoded once.
func start_music_layers(initial_intensity: float = 0.0) -> void:
	if _layers_playing:
		return
	_music_intensity = clampf(initial_intensity, 0.0, 1.0)
	for id: StringName in MUSIC_LAYERS:
		var player: AudioStreamPlayer = _layers[id]
		if player.stream == null:
			continue
		_layer_gain[id] = _target_gain(id)
		_apply_layer_gain(id)
		player.play()
	_layers_playing = true


func stop_music_layers() -> void:
	_layers_playing = false
	for id: StringName in MUSIC_LAYERS:
		var player: AudioStreamPlayer = _layers[id]
		player.stop()
		_layer_gain[id] = 0.0
		player.volume_db = MUSIC_LAYER_FLOOR_DB


## How loud the fight is, 0 (empty sea) to 1 (the castle). Set every frame by
## [MusicDirector]; the smoothing lives here so callers can hand over a raw,
## twitchy reading without having to filter it themselves.
func set_music_intensity(value: float) -> void:
	_music_intensity = clampf(value, 0.0, 1.0)


func music_intensity() -> float:
	return _music_intensity


## Current audible gain of one stem, 0..1. Exists for the audio harness: "is the
## music reacting" is otherwise a question only a human with speakers can answer.
func music_layer_gain(id: StringName) -> float:
	return float(_layer_gain.get(id, 0.0))


func is_music_playing() -> bool:
	return _layers_playing


func start_ambience() -> void:
	if _ambience != null and _ambience.stream != null and not _ambience.playing:
		_ambience.play()


func stop_ambience() -> void:
	if _ambience != null:
		_ambience.stop()


func is_ambience_playing() -> bool:
	return _ambience != null and _ambience.playing


func _process(delta: float) -> void:
	if not _layers_playing:
		return
	for id: StringName in MUSIC_LAYERS:
		var current: float = float(_layer_gain[id])
		var target: float = _target_gain(id)
		var rate: float = MUSIC_RISE_PER_SEC if target > current else MUSIC_FALL_PER_SEC
		_layer_gain[id] = move_toward(current, target, rate * delta)
		_apply_layer_gain(id)


## Where a stem should sit at the current intensity, from its own ramp.
func _target_gain(id: StringName) -> float:
	var ramp: Vector2 = MUSIC_LAYER_RAMP.get(id, Vector2(0.0, 1.0))
	if ramp.y <= ramp.x:
		return 1.0 if _music_intensity >= ramp.y else 0.0
	return clampf(inverse_lerp(ramp.x, ramp.y, _music_intensity), 0.0, 1.0)


func _apply_layer_gain(id: StringName) -> void:
	var player: AudioStreamPlayer = _layers[id]
	if player == null:
		return
	var gain: float = float(_layer_gain[id])
	if gain <= 0.001:
		player.volume_db = MUSIC_LAYER_FLOOR_DB
		return
	# Gain is a musical fader, so it moves in dB rather than linearly — a linear
	# ramp spends most of its travel in the range where nothing audibly changes
	# and then arrives all at once.
	player.volume_db = lerpf(
		MUSIC_LAYER_FLOOR_DB, float(MUSIC_LAYER_DB.get(id, -6.0)), gain
	)


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
