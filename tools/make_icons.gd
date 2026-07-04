extends SceneTree

# Dev tool: renders assets/logo.svg to PNGs for preview + ICO packing.
# Run: godot --headless --path <project> --script res://tools/make_icons.gd

func _init() -> void:
	var svg := FileAccess.get_file_as_bytes("res://assets/logo.svg")
	if svg.is_empty():
		push_error("logo.svg not found")
		quit(1)
		return
	for size in [16, 32, 48, 64, 128, 256]:
		var img := Image.new()
		var err := img.load_svg_from_buffer(svg, float(size) / 512.0)
		if err != OK:
			push_error("SVG load failed: %d" % err)
			quit(1)
			return
		if img.get_width() != size or img.get_height() != size:
			img.resize(size, size, Image.INTERPOLATE_LANCZOS)
		img.save_png("res://assets/icon_%d.png" % size)
	print("icons written")
	quit(0)
