extends SceneTree

var _repo_root: String


func _initialize() -> void:
	_repo_root = ProjectSettings.globalize_path("res://../..").simplify_path()
	var failures := 0
	failures += _make_contact_sheet()
	failures += _make_rotation_proof()
	failures += _make_readability_proof()
	failures += _make_production_scene()
	print("Wave 0 proof generation complete: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _make_contact_sheet() -> int:
	var canvas := Image.create(1600, 1000, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#082638"))
	canvas.fill_rect(Rect2i(24, 24, 1552, 396), Color("#F7EDD7"))
	canvas.fill_rect(Rect2i(24, 444, 1552, 256), Color("#E4D3AA"))
	canvas.fill_rect(Rect2i(24, 724, 776, 252), Color("#2DAEB6"))
	canvas.fill_rect(Rect2i(800, 724, 776, 252), Color("#EACB83"))

	var top_assets := [
		["assets/wave0/ships/hull_sloop.png", Rect2i(50, 42, 200, 360)],
		["assets/wave0/ships/hull_sloop_blue_proof.png", Rect2i(260, 42, 200, 360)],
		["assets/wave0/ships/hull_sloop_green_proof.png", Rect2i(470, 42, 200, 360)],
		["assets/wave0/ships/hull_sloop_gold_proof.png", Rect2i(680, 42, 200, 360)],
		["assets/wave0/ships/sail_med.png", Rect2i(900, 70, 230, 230)],
		["assets/wave0/ships/hull_skiff.png", Rect2i(1140, 62, 150, 250)],
		["assets/wave0/ships/cannon_mount.png", Rect2i(1305, 75, 210, 100)],
		["assets/wave0/ships/flag_wave_0.png", Rect2i(1325, 190, 80, 140)],
		["assets/wave0/ships/flag_wave_1.png", Rect2i(1425, 190, 80, 140)]
	]
	for item: Array in top_assets:
		_place_fit(canvas, _load_image(item[0]), item[1])

	var family_assets := [
		["assets/wave0/props/palm_0.png", Rect2i(50, 458, 180, 225)],
		["assets/wave0/props/rock_0.png", Rect2i(245, 475, 180, 180)],
		["assets/wave0/ui/panel_parchment.png", Rect2i(445, 470, 380, 200)],
		["assets/wave0/icons/icon_cannon.png", Rect2i(845, 480, 170, 170)],
		["assets/wave0/vfx/fx_muzzleflash_0.png", Rect2i(1035, 490, 140, 140)],
		["assets/wave0/vfx/fx_muzzleflash_1.png", Rect2i(1165, 490, 140, 140)],
		["assets/wave0/vfx/fx_muzzleflash_2.png", Rect2i(1295, 490, 140, 140)],
		["assets/wave0/vfx/fx_muzzleflash_3.png", Rect2i(1425, 490, 140, 140)]
	]
	for item: Array in family_assets:
		_place_fit(canvas, _load_image(item[0]), item[1])

	var readability_assets := [
		"assets/wave0/ships/hull_sloop.png",
		"assets/wave0/ships/hull_skiff.png",
		"assets/wave0/props/palm_0.png",
		"assets/wave0/props/rock_0.png",
		"assets/wave0/icons/icon_cannon.png",
		"assets/wave0/vfx/fx_muzzleflash_1.png"
	]
	for side in 2:
		for index in readability_assets.size():
			var target_x := 80 + side * 800 + index * 112
			_place_fit(canvas, _load_image(readability_assets[index]), Rect2i(target_x, 785, 72, 72))
			_place_fit(canvas, _load_image(readability_assets[index]), Rect2i(target_x + 16, 885, 40, 40))

	var output := _repo_root.path_join("assets/wave0/wave0_contact_sheet.png")
	var error := canvas.save_png(output)
	if error != OK:
		push_error("Could not save contact sheet: %s" % error_string(error))
		return 1
	print("Created %s" % output)
	return 0


func _make_rotation_proof() -> int:
	var canvas := Image.create(1600, 460, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#2DAEB6"))
	var source := _load_image("assets/wave0/ships/hull_sloop.png")
	var angles := [0.0, 45.0, 90.0, 135.0, 180.0]
	for index in angles.size():
		var rotated := _rotate_image(source, deg_to_rad(angles[index]))
		_place_fit(canvas, rotated, Rect2i(35 + index * 312, 35, 282, 390))
	var output := _repo_root.path_join("assets/wave0/ships/sloop_rotation_proof.png")
	var error := canvas.save_png(output)
	if error != OK:
		push_error("Could not save rotation proof: %s" % error_string(error))
		return 1
	print("Created %s" % output)
	return 0


func _make_readability_proof() -> int:
	var canvas := Image.create(800, 200, false, Image.FORMAT_RGBA8)
	canvas.fill_rect(Rect2i(0, 0, 400, 200), Color("#178D9C"))
	canvas.fill_rect(Rect2i(400, 0, 400, 200), Color("#F4DDA2"))
	var paths := [
		"assets/wave0/ships/hull_sloop.png",
		"assets/wave0/ships/hull_skiff.png",
		"assets/wave0/props/palm_0.png",
		"assets/wave0/props/rock_0.png",
		"assets/wave0/icons/icon_cannon.png"
	]
	for side in 2:
		for index in paths.size():
			_place_fit(canvas, _load_image(paths[index]), Rect2i(35 + side * 400 + index * 72, 65, 40, 40))
	var output := _repo_root.path_join("assets/wave0/wave0_40px_proof.png")
	var error := canvas.save_png(output)
	if error != OK:
		push_error("Could not save readability proof: %s" % error_string(error))
		return 1
	print("Created %s" % output)
	return 0


func _make_production_scene() -> int:
	var canvas := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	_fill_water(canvas)

	_fill_ellipse(canvas, Vector2i(1035, 255), Vector2i(225, 165), Color("#54B9B6"))
	_fill_ellipse(canvas, Vector2i(1035, 255), Vector2i(212, 152), Color("#D6D1A4"))
	_fill_ellipse_texture(canvas, Vector2i(1035, 255), Vector2i(199, 140), _load_image("assets/wave0/terrain/fill_sand.png"))
	_place_fit(canvas, _load_image("assets/wave0/props/palm_0.png"), Rect2i(990, 135, 120, 180))
	_place_fit(canvas, _load_image("assets/wave0/props/rock_0.png"), Rect2i(895, 280, 105, 105))

	var sloop := _compose_sloop()
	_place_fit(canvas, _rotate_image(sloop, deg_to_rad(-12.0)), Rect2i(275, 155, 300, 420))
	var skiff := _load_image("assets/wave0/ships/hull_skiff.png")
	_place_fit(canvas, _rotate_image(skiff, deg_to_rad(72.0)), Rect2i(670, 140, 190, 190))
	_place_fit(canvas, _rotate_image(skiff, deg_to_rad(105.0)), Rect2i(720, 360, 190, 190))
	_place_fit(canvas, _rotate_image(skiff, deg_to_rad(145.0)), Rect2i(930, 475, 170, 170))
	_place_fit(canvas, _load_image("assets/wave0/vfx/fx_muzzleflash_1.png"), Rect2i(530, 280, 120, 120))

	var panel := _load_image("assets/wave0/ui/panel_parchment.png")
	_place_fit(canvas, panel, Rect2i(30, 500, 260, 180))
	_place_fit(canvas, _load_image("assets/wave0/ships/hull_skiff.png"), Rect2i(118, 545, 70, 90))
	_place_fit(canvas, _load_image("assets/wave0/icons/icon_cannon.png"), Rect2i(1135, 565, 115, 115))

	var output := _repo_root.path_join("assets/wave0/wave0_production_scene.png")
	var error := canvas.save_png(output)
	if error != OK:
		push_error("Could not save production scene: %s" % error_string(error))
		return 1
	print("Created %s" % output)
	return 0


func _fill_water(canvas: Image) -> void:
	var deep := Color("#218C99")
	var light := Color("#38AAB0")
	for y in canvas.get_height():
		for x in canvas.get_width():
			var broad := (sin(float(x) * 0.012 + float(y) * 0.023) + 1.0) * 0.5
			var fine := (sin(float(x) * 0.071 - float(y) * 0.037) + 1.0) * 0.5
			canvas.set_pixel(x, y, deep.lerp(light, 0.18 + broad * 0.16 + fine * 0.035))


func _compose_sloop() -> Image:
	var result := Image.create(240, 350, false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))
	var hull := _load_image("assets/wave0/ships/hull_sloop.png")
	var sail := _load_image("assets/wave0/ships/sail_med.png")
	var flag := _load_image("assets/wave0/ships/flag_wave_0.png")
	result.blend_rect(hull, Rect2i(Vector2i.ZERO, hull.get_size()), Vector2i(24, 18))
	result.blend_rect(sail, Rect2i(Vector2i.ZERO, sail.get_size()), Vector2i(10, 50))
	result.blend_rect(flag, Rect2i(Vector2i.ZERO, flag.get_size()), Vector2i(116, 18))
	return result


func _fill_ellipse(canvas: Image, center: Vector2i, radius: Vector2i, color: Color) -> void:
	var left := maxi(0, center.x - radius.x)
	var right := mini(canvas.get_width() - 1, center.x + radius.x)
	var top := maxi(0, center.y - radius.y)
	var bottom := mini(canvas.get_height() - 1, center.y + radius.y)
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			var normalized := Vector2(float(x - center.x) / radius.x, float(y - center.y) / radius.y)
			if normalized.length_squared() <= 1.0:
				canvas.set_pixel(x, y, color)


func _fill_ellipse_texture(canvas: Image, center: Vector2i, radius: Vector2i, texture: Image) -> void:
	if texture.is_empty():
		return
	var left := maxi(0, center.x - radius.x)
	var right := mini(canvas.get_width() - 1, center.x + radius.x)
	var top := maxi(0, center.y - radius.y)
	var bottom := mini(canvas.get_height() - 1, center.y + radius.y)
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			var normalized := Vector2(float(x - center.x) / radius.x, float(y - center.y) / radius.y)
			if normalized.length_squared() <= 1.0:
				canvas.set_pixel(x, y, texture.get_pixel(posmod(x - left, texture.get_width()), posmod(y - top, texture.get_height())))


func _load_image(relative_path: String) -> Image:
	var image := Image.new()
	var error := image.load(_repo_root.path_join(relative_path))
	if error != OK:
		push_error("Could not load %s" % relative_path)
	return image


func _place_fit(canvas: Image, source: Image, target: Rect2i) -> void:
	if source.is_empty():
		return
	var scale: float = minf(float(target.size.x) / source.get_width(), float(target.size.y) / source.get_height())
	var size := Vector2i(maxi(1, roundi(source.get_width() * scale)), maxi(1, roundi(source.get_height() * scale)))
	var resized := source.duplicate()
	resized.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var position := target.position + (target.size - size) / 2
	canvas.blend_rect(resized, Rect2i(Vector2i.ZERO, size), position)


func _rotate_image(source: Image, radians: float) -> Image:
	if is_zero_approx(radians):
		return source.duplicate()
	var diagonal := ceili(Vector2(source.get_size()).length()) + 4
	var result := Image.create(diagonal, diagonal, false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))
	var source_center := Vector2(source.get_size() - Vector2i.ONE) * 0.5
	var result_center := Vector2(result.get_size() - Vector2i.ONE) * 0.5
	var cosine := cos(-radians)
	var sine := sin(-radians)
	for y in diagonal:
		for x in diagonal:
			var delta := Vector2(x, y) - result_center
			var source_position := Vector2(delta.x * cosine - delta.y * sine, delta.x * sine + delta.y * cosine) + source_center
			if source_position.x >= 0.0 and source_position.y >= 0.0 and source_position.x < source.get_width() - 1 and source_position.y < source.get_height() - 1:
				result.set_pixel(x, y, _sample_bilinear(source, source_position))
	return result


func _sample_bilinear(image: Image, position: Vector2) -> Color:
	var x0 := floori(position.x)
	var y0 := floori(position.y)
	var x1 := mini(x0 + 1, image.get_width() - 1)
	var y1 := mini(y0 + 1, image.get_height() - 1)
	var tx := position.x - x0
	var ty := position.y - y0
	var top := image.get_pixel(x0, y0).lerp(image.get_pixel(x1, y0), tx)
	var bottom := image.get_pixel(x0, y1).lerp(image.get_pixel(x1, y1), tx)
	return top.lerp(bottom, ty)
