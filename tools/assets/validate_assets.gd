extends SceneTree

var _repo_root: String


func _initialize() -> void:
	_repo_root = ProjectSettings.globalize_path("res://../..").simplify_path()
	var text := FileAccess.get_file_as_string(_repo_root.path_join("assets_src/catalog.json"))
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("Catalog is not valid JSON")
		quit(1)
		return

	var catalog: Dictionary = parsed
	var render_scale := int(catalog.get("render_scale", 2))
	var failures := 0
	var checked := 0
	var ids := {}

	for value: Variant in catalog.get("assets", []):
		if not value is Dictionary:
			failures += 1
			continue
		var asset: Dictionary = value
		var asset_id: String = asset.get("id", "")
		if asset_id.is_empty() or ids.has(asset_id):
			push_error("Missing or duplicate asset id: %s" % asset_id)
			failures += 1
			continue
		ids[asset_id] = true

		var output: String = asset.get("output", "")
		var image := Image.new()
		var error := image.load(_repo_path(output))
		if error != OK:
			push_error("Cannot load %s output %s" % [asset_id, output])
			failures += 1
			continue

		var nominal: Array = asset.get("nominal", [])
		var expected := Vector2i(int(nominal[0]) * render_scale, int(nominal[1]) * render_scale)
		if image.get_size() != expected:
			push_error("%s is %s, expected %s" % [asset_id, image.get_size(), expected])
			failures += 1

		if expected.x > 2048 or expected.y > 2048:
			push_error("%s exceeds the 2048 px safety floor" % asset_id)
			failures += 1

		if bool(asset.get("padding", true)) and not _has_transparent_border(image):
			push_error("%s does not have a fully transparent outer border" % asset_id)
			failures += 1

		checked += 1

	print("Asset validation complete: %d checked, %d failure(s)" % [checked, failures])
	quit(1 if failures > 0 else 0)


func _has_transparent_border(image: Image) -> bool:
	var width := image.get_width()
	var height := image.get_height()
	for x in width:
		if image.get_pixel(x, 0).a > 0.01 or image.get_pixel(x, height - 1).a > 0.01:
			return false
	for y in height:
		if image.get_pixel(0, y).a > 0.01 or image.get_pixel(width - 1, y).a > 0.01:
			return false
	return true


func _repo_path(path: String) -> String:
	return _repo_root.path_join(path.trim_prefix("res://"))
