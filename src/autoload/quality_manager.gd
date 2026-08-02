extends Node
## Picks a graphics tier for the device, then keeps adjusting it.
##
## Two responsibilities:
##   1. Guess a sensible starting tier from what we can detect up front.
##   2. Watch the real frame time and move between tiers, with hysteresis so it
##      cannot oscillate.
##
## Everything expensive in the game reads its budget from here rather than
## hardcoding a number, so one tier change reaches the whole game at once.
## See docs/ARCHITECTURE.md §6 for the knob table.

enum Tier { LOW, MEDIUM, HIGH }

signal tier_changed(tier: Tier)

const TIER_NAMES: PackedStringArray = ["LOW", "MEDIUM", "HIGH"]

## Sampling window for the adaptive controller.
const SAMPLE_WINDOW_SEC: float = 1.0
## Below this average fps the tier drops.
const FPS_FLOOR: float = 45.0
## Above this average fps the tier may rise again.
const FPS_CEILING: float = 57.0
## Consecutive bad windows before dropping a tier.
const BAD_WINDOWS_TO_DROP: int = 2
## Consecutive good windows before raising a tier. Deliberately slow.
const GOOD_WINDOWS_TO_RAISE: int = 30
## Frames longer than this are treated as hitches (tab switch, asset load) and
## excluded from the average instead of being blamed on the graphics tier.
const HITCH_THRESHOLD_SEC: float = 0.2

# --- Live knobs. Read these; never write them from gameplay code. ---
var particle_scale: float = 1.0
var max_visible_ships: int = 32
var max_projectiles: int = 160
var ocean_wave_octaves: int = 4
var ocean_caustics: bool = true
var ocean_shore_foam: bool = true
## Foam-spray particles: 0 = none, 1 = selected ship only, 2 = every ship.
## The wake *ribbon* is not gated by this — it is one draw call and it is the only
## thing telling a player on a slow device that anything is moving. See [WakeTrail].
var wake_mode: int = 2
## 0 = no blob shadows, 1 = ships only, 2 = ships and props.
var shadow_mode: int = 2
## Extra fraction of the viewport kept simulated around the camera.
var cull_margin: float = 0.35
var damage_numbers: bool = true
## SubViewportContainer.stretch_shrink — the only real fill-rate lever in 2D.
var render_shrink: int = 1
var max_audio_voices: int = 24

var tier: Tier = Tier.HIGH
## When false the adaptive controller stops and the player's choice stands.
var auto_adapt: bool = true
## Human-readable trace of how the starting tier was chosen. Shown in the overlay.
var detection_reason: String = ""

var _accum_time: float = 0.0
var _accum_frames: int = 0
var _bad_windows: int = 0
var _good_windows: int = 0
var _last_avg_fps: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Headless has no renderer to adapt to and its frame times are meaningless.
	# Left on, the controller ratchets CI runs down to LOW and quietly changes
	# what the smoke test is exercising.
	if DisplayServer.get_name() == "headless":
		auto_adapt = false
	_apply_tier(_detect_tier(), true)


func _process(delta: float) -> void:
	if not auto_adapt:
		return
	if delta > HITCH_THRESHOLD_SEC:
		# A hitch tells us nothing about sustained performance. Drop the window.
		_accum_time = 0.0
		_accum_frames = 0
		return

	_accum_time += delta
	_accum_frames += 1
	if _accum_time < SAMPLE_WINDOW_SEC:
		return

	_last_avg_fps = float(_accum_frames) / _accum_time
	_accum_time = 0.0
	_accum_frames = 0

	if _last_avg_fps < FPS_FLOOR:
		_bad_windows += 1
		_good_windows = 0
		if _bad_windows >= BAD_WINDOWS_TO_DROP and tier > Tier.LOW:
			Log.info(
				"Dropping quality to %s (%.1f fps)" % [TIER_NAMES[tier - 1], _last_avg_fps],
				"Quality"
			)
			_apply_tier((tier - 1) as Tier)
			_bad_windows = 0
	elif _last_avg_fps > FPS_CEILING:
		_good_windows += 1
		_bad_windows = 0
		if _good_windows >= GOOD_WINDOWS_TO_RAISE and tier < Tier.HIGH:
			Log.info(
				"Raising quality to %s (%.1f fps)" % [TIER_NAMES[tier + 1], _last_avg_fps],
				"Quality"
			)
			_apply_tier((tier + 1) as Tier)
			_good_windows = 0
	else:
		_bad_windows = 0
		_good_windows = 0


## Player-facing override. Turns off adaptation.
func set_tier_manual(new_tier: Tier) -> void:
	auto_adapt = false
	_apply_tier(new_tier)


func resume_auto_adapt() -> void:
	auto_adapt = true
	_bad_windows = 0
	_good_windows = 0


func get_tier_name() -> String:
	return TIER_NAMES[tier]


func get_last_avg_fps() -> float:
	return _last_avg_fps


## Scales a particle emitter's amount by the current budget. Returns at least 1
## so an emitter never silently becomes a no-op that looks like a bug.
func scaled_particles(base_amount: int) -> int:
	return maxi(1, roundi(float(base_amount) * particle_scale))


func _detect_tier() -> Tier:
	var reasons: PackedStringArray = []
	var score: int = 0

	var is_web: bool = OS.has_feature("web")
	var os_name: String = OS.get_name()
	var is_handheld: bool = os_name == "Android" or os_name == "iOS"
	# A phone-sized touch screen in a browser is a mobile browser, which is the
	# hardest target we have; OS.get_name() reports "Web" there and cannot tell us.
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var small_screen: bool = mini(screen_size.x, screen_size.y) <= 1100
	var touch_only: bool = DisplayServer.is_touchscreen_available()

	if is_web:
		score -= 1
		reasons.append("web")
	if is_handheld or (is_web and touch_only and small_screen):
		score -= 1
		reasons.append("handheld")

	var cores: int = OS.get_processor_count()
	reasons.append("%d cores" % cores)
	if cores >= 8:
		score += 1
	elif cores <= 4:
		score -= 1

	var mem_mb: int = int(OS.get_memory_info().get("physical", 0)) / (1024 * 1024)
	if mem_mb > 0:
		reasons.append("%d MB RAM" % mem_mb)
		if mem_mb >= 6000:
			score += 1
		elif mem_mb <= 2500:
			score -= 1

	var chosen: Tier
	if score <= -2:
		chosen = Tier.LOW
	elif score <= 0:
		chosen = Tier.MEDIUM
	else:
		chosen = Tier.HIGH

	detection_reason = "%s → %s (score %d)" % [", ".join(reasons), TIER_NAMES[chosen], score]
	Log.info("Quality detection: " + detection_reason, "Quality")
	return chosen


func _apply_tier(new_tier: Tier, force: bool = false) -> void:
	if new_tier == tier and not force:
		return
	tier = new_tier

	match tier:
		Tier.LOW:
			particle_scale = 0.25
			max_visible_ships = 12
			max_projectiles = 60
			ocean_wave_octaves = 2
			ocean_caustics = false
			ocean_shore_foam = false
			wake_mode = 0
			shadow_mode = 0
			cull_margin = 0.10
			damage_numbers = false
			render_shrink = 2
			max_audio_voices = 10
		Tier.MEDIUM:
			particle_scale = 0.6
			max_visible_ships = 20
			max_projectiles = 100
			ocean_wave_octaves = 3
			ocean_caustics = false
			ocean_shore_foam = true
			wake_mode = 1
			shadow_mode = 1
			cull_margin = 0.20
			damage_numbers = true
			render_shrink = 1
			max_audio_voices = 16
		Tier.HIGH:
			particle_scale = 1.0
			max_visible_ships = 32
			max_projectiles = 160
			ocean_wave_octaves = 4
			ocean_caustics = true
			ocean_shore_foam = true
			wake_mode = 2
			shadow_mode = 2
			cull_margin = 0.35
			damage_numbers = true
			render_shrink = 1
			max_audio_voices = 24

	tier_changed.emit(tier)
	EventBus.quality_tier_changed.emit(int(tier))
