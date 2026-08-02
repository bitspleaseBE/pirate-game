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
	var checked := 0
	var ids := {}

	for value: Variant in _expand_assets(catalog):
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

		var tile_mode := String(asset.get("tile_mode", ""))
		if tile_mode.contains("x") and not _has_matching_x_edges(image):
			push_error("%s does not have matching horizontal tile edges" % asset_id)
			failures += 1
		if tile_mode.contains("y") and not _has_matching_y_edges(image):
			push_error("%s does not have matching vertical tile edges" % asset_id)
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


func _has_matching_x_edges(image: Image) -> bool:
	for y in image.get_height():
		if image.get_pixel(0, y) != image.get_pixel(image.get_width() - 1, y):
			return false
	return true


func _has_matching_y_edges(image: Image) -> bool:
	for x in image.get_width():
		if image.get_pixel(x, 0) != image.get_pixel(x, image.get_height() - 1):
			return false
	return true


func _repo_path(path: String) -> String:
	return _repo_root.path_join(path.trim_prefix("res://"))


func _load_catalog() -> Dictionary:
	var main_path := _repo_root.path_join("assets_src/catalog.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(main_path))
	if not parsed is Dictionary:
		push_error("Catalog is not valid JSON")
		return {}
	var catalog: Dictionary = parsed
	var assets: Array = catalog.get("assets", []).duplicate(true)
	var sequences: Array = catalog.get("sequences", []).duplicate(true)
	for include_path: Variant in catalog.get("includes", []):
		var included: Variant = JSON.parse_string(FileAccess.get_file_as_string(_repo_path(str(include_path))))
		if not included is Dictionary:
			push_error("Included catalog is invalid: %s" % include_path)
			return {}
		assets.append_array(included.get("assets", []))
		sequences.append_array(included.get("sequences", []))
	catalog["assets"] = assets
	catalog["sequences"] = sequences
	return catalog


func _expand_assets(catalog: Dictionary) -> Array:
	var expanded: Array = catalog.get("assets", []).duplicate(true)
	for value: Variant in catalog.get("sequences", []):
		if not value is Dictionary:
			continue
		var sequence: Dictionary = value
		var common: Dictionary = sequence.get("common", {})
		var frames: Array = sequence.get("frames", [])
		for index in frames.size():
			var entry: Dictionary = common.duplicate(true)
			entry["id"] = str(sequence.get("id_pattern", "frame_{frame}")).replace("{frame}", str(index))
			entry["output"] = str(sequence.get("output_pattern", "")).replace("{frame}", str(index))
			if frames[index] is Dictionary:
				entry.merge(frames[index], true)
			expanded.append(entry)
	return expanded
