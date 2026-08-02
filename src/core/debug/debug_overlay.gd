extends CanvasLayer
## On-device performance overlay. Toggle with F3, or a four-finger tap on touch.
##
## A phone browser has no console and no profiler, so the numbers that decide
## whether the culling and pooling are actually working have to be visible on the
## device itself. This is the instrument panel for everything in
## docs/ARCHITECTURE.md.

const REFRESH_INTERVAL: float = 0.25
const TOUCH_TOGGLE_FINGERS: int = 4

var visible_overlay: bool = false

var _label: Label
var _panel: PanelContainer
var _accum: float = 0.0
var _frame_peak_ms: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(10, 10)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.62)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.9))
	_panel.add_child(_label)

	add_child(_panel)
	_panel.visible = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug"):
		toggle()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		if (event as InputEventScreenTouch).index == TOUCH_TOGGLE_FINGERS - 1:
			toggle()


func toggle() -> void:
	visible_overlay = not visible_overlay
	_panel.visible = visible_overlay
	if visible_overlay:
		_frame_peak_ms = 0.0
		_refresh()


func _process(delta: float) -> void:
	_frame_peak_ms = maxf(_frame_peak_ms, delta * 1000.0)
	if not visible_overlay:
		return
	_accum += delta
	if _accum < REFRESH_INTERVAL:
		return
	_accum = 0.0
	_refresh()
	_frame_peak_ms = 0.0


func _refresh() -> void:
	var lines: PackedStringArray = []

	lines.append(
		"FPS %d   frame %.1f ms   peak %.1f ms"
		% [
			Engine.get_frames_per_second(),
			1000.0 / maxf(1.0, float(Engine.get_frames_per_second())),
			_frame_peak_ms,
		]
	)
	lines.append(
		"draw calls %d   objects %d"
		% [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		]
	)
	lines.append(
		"video mem %.1f MB"
		% (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)
	)

	lines.append("")
	lines.append(
		"QUALITY %s%s   avg %.0f fps"
		% [
			Quality.get_tier_name(),
			"" if Quality.auto_adapt else " (manual)",
			Quality.get_last_avg_fps(),
		]
	)
	lines.append(
		"  particles x%.2f   shrink %d   ships<=%d   shots<=%d"
		% [
			Quality.particle_scale,
			Quality.render_shrink,
			Quality.max_visible_ships,
			Quality.max_projectiles,
		]
	)
	lines.append("  detect: %s" % Quality.detection_reason)

	lines.append("")
	lines.append(
		"CULL  full %d  reduced %d  sim %d  dormant %d   (%.2f ms/tick)"
		% [
			Cull.count_full,
			Cull.count_reduced,
			Cull.count_simulated,
			Cull.count_dormant,
			float(Cull.last_tick_usec) / 1000.0,
		]
	)
	lines.append(
		"GRID  entities %d  cells %d" % [Grid.entity_count(), Grid.cell_count()]
	)
	if ProjectileSystem.instance != null:
		lines.append("SHOTS in flight %d" % ProjectileSystem.instance.active_count())
	lines.append("AUDIO voices %d/%d" % [Audio.active_voice_count(), Quality.max_audio_voices])

	lines.append("")
	lines.append("POOLS  (in use / total / high water)")
	for stats: Dictionary in Pools.all_stats():
		lines.append(
			"  %-14s %3d / %3d / %3d%s"
			% [
				stats["name"],
				stats["in_use"],
				stats["total"],
				stats["high_water"],
				"  GREW" if stats["grew"] else "",
			]
		)

	_label.text = "\n".join(lines)
