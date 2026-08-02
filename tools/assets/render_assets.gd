extends SceneTree

var _repo_root: String


func _initialize() -> void:
	_repo_root = ProjectSettings.globalize_path("res://../..").simplify_path()
	var catalog := _load_catalog()
	if catalog.is_empty():
		quit(1)
		return

	var render_scale := int(catalog.get("render_scale", 2))
	var failures := 0
	for value: Variant in catalog.get("assets", []):
		if not value is Dictionary:
			push_error("Catalog asset entry is not an object")
			failures += 1
			continue
		var asset: Dictionary = value
		var asset_id: String = asset.get("id", "unnamed")
		var nominal: Array = asset.get("nominal", [])
		if nominal.size() != 2:
			push_error("Missing nominal dimensions for %s" % asset_id)
			failures += 1
			continue
		var expected := Vector2i(int(nominal[0]) * render_scale, int(nominal[1]) * render_scale)
		var image := _render_asset(asset, expected, render_scale)
		if image.is_empty():
			failures += 1
			continue

		var output: String = asset.get("output", "")
		var output_absolute := _repo_path(output)
		DirAccess.make_dir_recursive_absolute(output_absolute.get_base_dir())
		var error := image.save_png(output_absolute)
		if error != OK:
			push_error("PNG save failed for %s: %s" % [asset_id, error_string(error)])
			failures += 1
		else:
			print("Rendered %-28s %4dx%-4d -> %s" % [asset_id, expected.x, expected.y, output])

	print("Asset render complete: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _render_asset(asset: Dictionary, expected: Vector2i, render_scale: int) -> Image:
	var source: String = asset.get("source", "")
	var asset_id: String = asset.get("id", source)
	var source_absolute := _repo_path(source)
	if asset.get("source_type", "svg") == "raster":
		var source_image := Image.new()
		var error := source_image.load(source_absolute)
		if error != OK:
			push_error("Raster load failed for %s: %s" % [asset_id, source])
			return Image.new()
		match String(asset.get("process", "fit")):
			"fit":
				return _fit_raster(source_image, expected, int(asset.get("padding_pixels", 2)))
			"accent_recolor":
				var recolored := _fit_raster(source_image, expected, int(asset.get("padding_pixels", 2)))
				_recolor_accents(recolored, Color.from_string(asset.get("target_color", "#3F78B8"), Color.WHITE))
				return recolored
			"accent_mask":
				var mask := _fit_raster(source_image, expected, int(asset.get("padding_pixels", 2)))
				_make_accent_mask(mask)
				return mask
			"mirror_tile":
				return _make_mirror_tile(source_image, expected)
			"mirror_x":
				return _make_mirror_x(source_image, expected)
			"muzzle_variant":
				return _make_muzzle_variant(source_image, expected, float(asset.get("content_scale", 1.0)), float(asset.get("alpha", 1.0)))
			"cannon_icon":
				return _make_cannon_icon(source_image, expected)
			_:
				push_error("Unknown raster process for %s" % asset_id)
				return Image.new()

	var svg_text := FileAccess.get_file_as_string(source_absolute)
	if svg_text.is_empty():
		push_error("Missing or empty SVG for %s: %s" % [asset_id, source])
		return Image.new()
	var replacements: Dictionary = asset.get("replacements", {})
	for key: Variant in replacements:
		svg_text = svg_text.replace(str(key), str(replacements[key]))
	var image := Image.new()
	var error := image.load_svg_from_buffer(svg_text.to_utf8_buffer(), render_scale)
	if error != OK:
		push_error("SVG render failed for %s: %s" % [asset_id, error_string(error)])
		return Image.new()
	if image.get_size() != expected:
		image.resize(expected.x, expected.y, Image.INTERPOLATE_LANCZOS)
	return image


func _fit_raster(source: Image, expected: Vector2i, padding: int) -> Image:
	var used := source.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return Image.create(expected.x, expected.y, false, Image.FORMAT_RGBA8)
	var cropped := source.get_region(used)
	var available := Vector2i(maxi(1, expected.x - padding * 2), maxi(1, expected.y - padding * 2))
	var scale := minf(float(available.x) / cropped.get_width(), float(available.y) / cropped.get_height())
	var fitted_size := Vector2i(maxi(1, roundi(cropped.get_width() * scale)), maxi(1, roundi(cropped.get_height() * scale)))
	cropped.resize(fitted_size.x, fitted_size.y, Image.INTERPOLATE_LANCZOS)
	var result := Image.create(expected.x, expected.y, false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))
	result.blend_rect(cropped, Rect2i(Vector2i.ZERO, fitted_size), (expected - fitted_size) / 2)
	return result


func _is_accent(color: Color) -> bool:
	# The master uses oxblood paint for faction trim. Keep warm timber (hue ~0.08-0.11)
	# out of the mask so faction variants never recolor the deck or hull material.
	return color.a > 0.08 and color.v > 0.08 and color.s > 0.30 and (color.h < 0.045 or color.h > 0.985) and color.r > color.g * 1.15


func _recolor_accents(image: Image, target: Color) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if _is_accent(color):
				var value := color.v
				var saturation := clampf(color.s * 0.82, 0.18, 0.72)
				var replacement := Color.from_hsv(target.h, saturation, clampf(value * target.v, 0.05, 1.0), color.a)
				image.set_pixel(x, y, replacement)


func _make_accent_mask(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(1, 1, 1, color.a if _is_accent(color) else 0.0))


func _make_mirror_tile(source: Image, expected: Vector2i) -> Image:
	var quarter := source.duplicate()
	quarter.convert(Image.FORMAT_RGBA8)
	quarter.resize(maxi(1, expected.x / 2), maxi(1, expected.y / 2), Image.INTERPOLATE_LANCZOS)
	var flip_x := quarter.duplicate()
	flip_x.flip_x()
	var flip_y := quarter.duplicate()
	flip_y.flip_y()
	var flip_xy := flip_x.duplicate()
	flip_xy.flip_y()
	var result := Image.create(expected.x, expected.y, false, Image.FORMAT_RGBA8)
	result.blit_rect(quarter, Rect2i(Vector2i.ZERO, quarter.get_size()), Vector2i.ZERO)
	result.blit_rect(flip_x, Rect2i(Vector2i.ZERO, flip_x.get_size()), Vector2i(expected.x / 2, 0))
	result.blit_rect(flip_y, Rect2i(Vector2i.ZERO, flip_y.get_size()), Vector2i(0, expected.y / 2))
	result.blit_rect(flip_xy, Rect2i(Vector2i.ZERO, flip_xy.get_size()), Vector2i(expected.x / 2, expected.y / 2))
	return result


func _make_mirror_x(source: Image, expected: Vector2i) -> Image:
	var half := source.duplicate()
	half.convert(Image.FORMAT_RGBA8)
	half.resize(maxi(1, expected.x / 2), expected.y, Image.INTERPOLATE_LANCZOS)
	var reflected := half.duplicate()
	reflected.flip_x()
	var result := Image.create(expected.x, expected.y, false, Image.FORMAT_RGBA8)
	result.blit_rect(half, Rect2i(Vector2i.ZERO, half.get_size()), Vector2i.ZERO)
	result.blit_rect(reflected, Rect2i(Vector2i.ZERO, reflected.get_size()), Vector2i(expected.x / 2, 0))
	return result


func _make_muzzle_variant(source: Image, expected: Vector2i, content_scale: float, alpha_multiplier: float) -> Image:
	var fitted := _fit_raster(source, expected, 3)
	if not is_equal_approx(content_scale, 1.0):
		var size := Vector2i(maxi(1, roundi(expected.x * content_scale)), maxi(1, roundi(expected.y * content_scale)))
		fitted.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		var centered := Image.create(expected.x, expected.y, false, Image.FORMAT_RGBA8)
		centered.fill(Color(0, 0, 0, 0))
		centered.blend_rect(fitted, Rect2i(Vector2i.ZERO, size), (expected - size) / 2)
		fitted = centered
	if alpha_multiplier < 0.999:
		for y in fitted.get_height():
			for x in fitted.get_width():
				var color := fitted.get_pixel(x, y)
				color.a *= alpha_multiplier
				fitted.set_pixel(x, y, color)
	return fitted


func _make_cannon_icon(source: Image, expected: Vector2i) -> Image:
	var result := Image.create(expected.x, expected.y, false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))
	var center := Vector2(expected) * 0.5
	var outer_radius := minf(expected.x, expected.y) * 0.47
	var inner_radius := outer_radius - maxf(3.0, expected.x * 0.045)
	for y in expected.y:
		for x in expected.x:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if distance <= outer_radius:
				var vignette := clampf(distance / outer_radius, 0.0, 1.0)
				if distance > inner_radius:
					result.set_pixel(x, y, Color("#201C18").lerp(Color("#68523A"), 1.0 - vignette))
				else:
					result.set_pixel(x, y, Color("#D6C49C").lerp(Color("#8A7653"), vignette * 0.38))
	var cannon_size := Vector2i(roundi(expected.x * 0.72), roundi(expected.y * 0.45))
	var cannon := _fit_raster(source, cannon_size, 1)
	result.blend_rect(cannon, Rect2i(Vector2i.ZERO, cannon.get_size()), (expected - cannon_size) / 2)
	return result


func _load_catalog() -> Dictionary:
	var catalog_path := _repo_root.path_join("assets_src/catalog.json")
	var text := FileAccess.get_file_as_string(catalog_path)
	if text.is_empty():
		push_error("Unable to read %s" % catalog_path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("Catalog is not valid JSON")
		return {}
	return parsed


func _repo_path(path: String) -> String:
	return _repo_root.path_join(path.trim_prefix("res://"))
