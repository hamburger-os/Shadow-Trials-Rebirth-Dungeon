@tool
extends EditorScript

@export var scene_path := "res://features/procedural_generation/room_templates/tiles/KayKit_DungeonRemastered.tscn"
@export var columns := 0 # 0 means auto (ceil(sqrt(n)))
@export var spacing := Vector2(16.0, 16.0) # x = right, y = forward (maps to z)
@export var start_offset := Vector2(0.0, 0.0) # x = start X, y = start Z
@export var sort_by_name := true
@export var flatten_y := false # true to set all children to y = 0

func _run() -> void:
	if not scene_path.begins_with("res://"):
		push_error("scene_path must start with res://")
		return

	var packed := ResourceLoader.load(scene_path)
	if packed == null or not (packed is PackedScene):
		push_error("Failed to load PackedScene: %s" % scene_path)
		return

	var root := (packed as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if root == null or not (root is Node3D):
		push_error("Root is not Node3D in: %s" % scene_path)
		return

	var children: Array[Node3D] = []
	for child in root.get_children():
		if child is Node3D:
			children.append(child)

	if sort_by_name:
		children.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return a.name.naturalnocasecmp_to(b.name) < 0)

	if children.is_empty():
		push_warning("No Node3D children to arrange.")
		return

	var cols := columns
	if cols <= 0:
		cols = int(ceil(sqrt(float(children.size()))))
	cols = max(cols, 1)

	for i in children.size():
		var row := i / cols
		var col := i % cols
		var child := children[i]
		var pos := child.transform.origin
		pos.x = start_offset.x + col * spacing.x
		pos.z = start_offset.y + row * spacing.y
		if flatten_y:
			pos.y = 0.0
		child.transform.origin = pos
		child.owner = root

	var out := PackedScene.new()
	var err := out.pack(root)
	if err != OK:
		push_error("Pack failed (%d) for %s" % [err, scene_path])
		return

	var save_err := ResourceSaver.save(out, scene_path)
	if save_err != OK:
		push_error("Save failed (%d) for %s" % [save_err, scene_path])
		return

	print("Arranged %d nodes into %d columns. Saved: %s" % [children.size(), cols, scene_path])
