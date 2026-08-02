extends SceneTree

var _repo_root: String


func _initialize() -> void:
	_repo_root = ProjectSettings.globalize_path("res://../..").simplify_path()
	var failures := _make_contact_sheet() + _make_readability_proof() + _make_production_scene()
	print("Wave 1 proof generation complete: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _make_contact_sheet() -> int:
	var canvas := Image.create(1600, 1240, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#082638"))
	canvas.fill_rect(Rect2i(24, 24, 1552, 260), Color("#DCE1CF"))
	canvas.fill_rect(Rect2i(24, 306, 1552, 280), Color("#203C48"))
	canvas.fill_rect(Rect2i(24, 608, 1552, 250), Color("#E4D3AA"))
	canvas.fill_rect(Rect2i(24, 880, 1552, 336), Color("#F7EDD7"))

	var top := [
		["assets/wave1/ships/wake_strip.png", Rect2i(45, 35, 130, 238)],
		["assets/wave1/ships/wake_foam_0.png", Rect2i(190, 75, 120, 120)],
		["assets/wave1/ships/wake_foam_1.png", Rect2i(315, 75, 120, 120)],
		["assets/wave1/ships/wake_foam_2.png", Rect2i(440, 75, 120, 120)],
		["assets/wave1/ships/wake_foam_3.png", Rect2i(565, 75, 120, 120)],
		["assets/wave1/props/palm_1.png", Rect2i(710, 38, 170, 230)],
		["assets/wave1/props/rock_1.png", Rect2i(900, 65, 180, 180)],
		["assets/wave1/terrain/fill_grass.png", Rect2i(1100, 48, 210, 210)],
		["assets/wave1/ships/ship_shadow.png", Rect2i(1340, 35, 170, 230)]
	]
	_place_group(canvas, top)

	for index in 6:
		_place_fit(canvas, _load("assets/wave1/vfx/fx_splash_small_%d.png" % index), Rect2i(42 + index * 112, 330, 104, 104))
	for index in 5:
		_place_fit(canvas, _load("assets/wave1/vfx/fx_impact_wood_%d.png" % index), Rect2i(42 + index * 130, 455, 120, 110))
	for index in 8:
		_place_fit(canvas, _load("assets/wave1/vfx/fx_explosion_%d.png" % index), Rect2i(730 + (index % 4) * 205, 320 + (index / 4) * 130, 190, 120))
	_place_fit(canvas, _load("assets/wave1/vfx/ball_round.png"), Rect2i(665, 355, 55, 55))
	_place_fit(canvas, _load("assets/wave1/vfx/ball_shadow.png"), Rect2i(665, 455, 55, 55))

	var treasure := [
		["assets/wave1/props/treasure_mound.png", Rect2i(45, 630, 190, 190)],
		["assets/wave1/props/x_marks_spot.png", Rect2i(250, 660, 120, 120)],
		["assets/wave1/props/chest_closed.png", Rect2i(390, 650, 140, 140)],
		["assets/wave1/props/chest_open.png", Rect2i(535, 650, 140, 140)],
		["assets/wave1/ui/reticle_target_2.png", Rect2i(980, 645, 150, 150)],
		["assets/wave1/ui/marker_waypoint_2.png", Rect2i(1150, 645, 150, 150)],
		["assets/wave1/ui/ring_selection_2.png", Rect2i(1320, 625, 190, 190)]
	]
	_place_group(canvas, treasure)
	for index in 6:
		_place_fit(canvas, _load("assets/wave1/props/coin_spin_%d.png" % index), Rect2i(690 + index * 48, 690, 42, 42))

	_place_fit(canvas, _load("assets/wave1/map/map_parchment.png"), Rect2i(42, 900, 290, 290))
	_place_fit(canvas, _load("assets/wave1/map/map_ship_icon.png"), Rect2i(135, 990, 90, 90))
	_place_fit(canvas, _load("assets/wave1/map/map_x.png"), Rect2i(220, 1080, 70, 70))
	_place_fit(canvas, _load("assets/wave1/ui/button_brass_up.png"), Rect2i(350, 900, 300, 90))
	_place_fit(canvas, _load("assets/wave1/ui/button_brass_down.png"), Rect2i(350, 995, 300, 90))
	_place_fit(canvas, _load("assets/wave1/ui/button_brass_disabled.png"), Rect2i(350, 1090, 300, 90))
	_place_fit(canvas, _load("assets/wave1/ui/bar_frame.png"), Rect2i(680, 910, 360, 55))
	for index in 4:
		var fills := ["hull", "sail", "cannon", "xp"]
		_place_fit(canvas, _load("assets/wave1/ui/bar_fill_%s.png" % fills[index]), Rect2i(690, 980 + index * 44, 340, 24))

	var icon_names := ["gold", "chest", "hull", "sail", "cannon", "anchor", "wheel", "shot_round", "fire", "repair", "map", "settings"]
	for index in icon_names.size():
		var col := index % 4
		var row := index / 4
		_place_fit(canvas, _load("assets/wave1/icons/icon_%s.png" % icon_names[index]), Rect2i(1070 + col * 115, 905 + row * 100, 90, 90))

	return _save(canvas, "assets/wave1/wave1_contact_sheet.png")


func _make_readability_proof() -> int:
	var canvas := Image.create(1280, 240, false, Image.FORMAT_RGBA8)
	canvas.fill_rect(Rect2i(0, 0, 640, 240), Color("#143E4B"))
	canvas.fill_rect(Rect2i(640, 0, 640, 240), Color("#ECD79D"))
	var paths := [
		"assets/wave1/props/palm_1.png", "assets/wave1/props/rock_1.png",
		"assets/wave1/props/treasure_mound.png", "assets/wave1/props/chest_closed.png",
		"assets/wave1/vfx/ball_round.png", "assets/wave1/vfx/fx_splash_small_3.png",
		"assets/wave1/vfx/fx_impact_wood_3.png", "assets/wave1/vfx/fx_explosion_4.png",
		"assets/wave1/ui/reticle_target_2.png", "assets/wave1/ui/marker_waypoint_2.png",
		"assets/wave1/icons/icon_gold.png", "assets/wave1/icons/icon_hull.png"
	]
	for side in 2:
		for index in paths.size():
			var x := 28 + side * 640 + (index % 6) * 102
			var y := 38 + (index / 6) * 108
			_place_fit(canvas, _load(paths[index]), Rect2i(x, y, 40, 40))
			_place_fit(canvas, _load(paths[index]), Rect2i(x + 46, y - 10, 54, 54))
	return _save(canvas, "assets/wave1/wave1_40px_proof.png")


func _make_production_scene() -> int:
	var canvas := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#174653"))
	for y in canvas.get_height():
		for x in canvas.get_width():
			var flow := (sin(float(x) * .013 + float(y) * .019) + 1.0) * .5
			canvas.set_pixel(x, y, Color("#174653").lerp(Color("#246371"), flow * .22))
	_fill_ellipse_texture(canvas, Vector2i(1030, 250), Vector2i(220, 160), _load("assets/wave1/terrain/fill_grass.png"))
	_place_fit(canvas, _load("assets/wave1/props/palm_1.png"), Rect2i(965, 105, 150, 225))
	_place_fit(canvas, _load("assets/wave1/props/rock_1.png"), Rect2i(865, 265, 135, 135))
	_place_fit(canvas, _load("assets/wave1/props/treasure_mound.png"), Rect2i(1050, 300, 95, 95))
	_place_fit(canvas, _load("assets/wave1/props/x_marks_spot.png"), Rect2i(1065, 310, 65, 65))
	_place_fit(canvas, _load("assets/wave1/ships/wake_strip.png"), Rect2i(342, 400, 72, 250))
	_place_fit(canvas, _load("assets/wave0/ships/hull_sloop.png"), Rect2i(300, 195, 150, 250))
	_place_fit(canvas, _load("assets/wave1/ships/wake_foam_2.png"), Rect2i(315, 150, 120, 120))
	_place_fit(canvas, _load("assets/wave0/vfx/fx_muzzleflash_2.png"), Rect2i(440, 300, 115, 115))
	_place_fit(canvas, _load("assets/wave1/vfx/ball_round.png"), Rect2i(585, 340, 22, 22))
	_place_fit(canvas, _load("assets/wave1/vfx/fx_splash_small_3.png"), Rect2i(690, 275, 105, 105))
	_place_fit(canvas, _load("assets/wave1/vfx/fx_impact_wood_3.png"), Rect2i(760, 445, 125, 125))
	_place_fit(canvas, _load("assets/wave1/ui/ring_selection_2.png"), Rect2i(265, 250, 220, 150))
	_place_fit(canvas, _load("assets/wave1/ui/reticle_target_2.png"), Rect2i(730, 410, 150, 150))
	_place_fit(canvas, _load("assets/wave1/map/map_parchment.png"), Rect2i(25, 470, 220, 220))
	_place_fit(canvas, _load("assets/wave1/map/map_ship_icon.png"), Rect2i(95, 535, 70, 70))
	_place_fit(canvas, _load("assets/wave1/ui/button_brass_up.png"), Rect2i(1010, 620, 240, 80))
	_place_fit(canvas, _load("assets/wave1/icons/icon_cannon.png"), Rect2i(1080, 620, 75, 75))
	return _save(canvas, "assets/wave1/wave1_production_scene.png")


func _place_group(canvas: Image, items: Array) -> void:
	for item: Array in items:
		_place_fit(canvas, _load(item[0]), item[1])


func _load(relative_path: String) -> Image:
	var image := Image.new()
	if image.load(_repo_root.path_join(relative_path)) != OK:
		push_error("Could not load %s" % relative_path)
	return image


func _place_fit(canvas: Image, source: Image, target: Rect2i) -> void:
	if source.is_empty():
		return
	var scale := minf(float(target.size.x) / source.get_width(), float(target.size.y) / source.get_height())
	var size := Vector2i(maxi(1, roundi(source.get_width() * scale)), maxi(1, roundi(source.get_height() * scale)))
	var resized := source.duplicate()
	resized.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	canvas.blend_rect(resized, Rect2i(Vector2i.ZERO, size), target.position + (target.size - size) / 2)


func _fill_ellipse_texture(canvas: Image, center: Vector2i, radius: Vector2i, texture: Image) -> void:
	for y in range(center.y - radius.y, center.y + radius.y):
		for x in range(center.x - radius.x, center.x + radius.x):
			var normalized := Vector2(float(x - center.x) / radius.x, float(y - center.y) / radius.y)
			if normalized.length_squared() <= 1.0:
				canvas.set_pixel(x, y, texture.get_pixel(posmod(x, texture.get_width()), posmod(y, texture.get_height())))


func _save(image: Image, relative_path: String) -> int:
	var output := _repo_root.path_join(relative_path)
	var error := image.save_png(output)
	if error != OK:
		push_error("Could not save %s: %s" % [relative_path, error_string(error)])
		return 1
	print("Created %s" % output)
	return 0
