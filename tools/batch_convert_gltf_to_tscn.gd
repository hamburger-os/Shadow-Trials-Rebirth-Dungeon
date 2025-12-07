@tool
extends EditorScript

@export var source_dir := "res://assets/environments/KayKit_DungeonRemastered_1.1_FREE/Assets/gltf"
@export var output_dir := "res://features/procedural_generation/room_templates/tiles/KayKit_DungeonRemastered"
@export var overwrite_existing := false
@export var add_convex_collision := true

const EXTENSIONS := ["gltf"]

func _run() -> void:
	# Batch convert glTF files to TSCN scenes, optionally adding convex collisions.
	if not source_dir.begins_with("res://") or not output_dir.begins_with("res://"):
		push_error("Paths must start with res:// (source: %s, output: %s)." % [source_dir, output_dir])
		return

	var src_dir := DirAccess.open(source_dir)
	if src_dir == null:
		push_error("Cannot open source directory: %s" % source_dir)
		return

	var root_dir := DirAccess.open("res://")
	if root_dir == null:
		push_error("Failed to open project root (res://).")
		return

	var mkdir_err := root_dir.make_dir_recursive(output_dir.trim_prefix("res://"))
	if mkdir_err != OK and mkdir_err != ERR_ALREADY_EXISTS:
		push_error("Failed to ensure destination directory: %s (err %d)." % [output_dir, mkdir_err])
		return

	src_dir.list_dir_begin()
	var created := 0
	var skipped := 0
	var failed := 0
	while true:
		var file := src_dir.get_next()
		if file.is_empty():
			break
		if src_dir.current_is_dir():
			continue
		if not _is_supported(file):
			continue

		var base := _base_name(file)
		var src_path := "%s/%s" % [source_dir, file]
		var dest_path := "%s/%s.tscn" % [output_dir, base]

		if ResourceLoader.exists(dest_path) and not overwrite_existing:
			skipped += 1
			print("Skip existing: ", dest_path)
			continue

		var packed := _build_scene(src_path, base)
		if packed == null:
			failed += 1
			continue

		var save_err := ResourceSaver.save(packed, dest_path)
		if save_err != OK:
			push_error("Failed to save %s (err %d)." % [dest_path, save_err])
			failed += 1
		else:
			created += 1
			print("Saved: ", dest_path)

	src_dir.list_dir_end()
	print("Conversion finished. Created: %d, Skipped: %d, Failed: %d" % [created, skipped, failed])


func _build_scene(src_path: String, base_name: String) -> PackedScene:
	var src_scene := ResourceLoader.load(src_path)
	if src_scene == null or not (src_scene is PackedScene):
		push_error("Load failed or resource is not a PackedScene: %s" % src_path)
		return null

	var instanced := (src_scene as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if instanced == null or not (instanced is Node3D):
		push_error("Instancing failed or root is not Node3D: %s" % src_path)
		return null

	var root := instanced as Node3D
	root.name = base_name # Keep the root name stable (avoid auto-suffixed names).

	if add_convex_collision:
		var static_body := StaticBody3D.new()
		static_body.name = "StaticBody3D"
		root.add_child(static_body)
		root.move_child(static_body, 0)
		static_body.owner = root
		_add_mesh_collisions(root, static_body, root)

	var out := PackedScene.new()
	var pack_err := out.pack(root)
	if pack_err != OK:
		push_error("Packing scene failed for %s (err %d)." % [src_path, pack_err])
		return null

	return out


func _add_mesh_collisions(node: Node, static_body: StaticBody3D, root: Node3D) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			var mesh := mesh_instance.mesh
			if mesh != null:
				var shape := mesh.create_convex_shape()
				if shape != null:
					var collision := CollisionShape3D.new()
					collision.name = "%s_Collision" % mesh_instance.name
					collision.shape = shape
					collision.transform = _to_root_transform(mesh_instance, root)
					static_body.add_child(collision)
					collision.owner = root

		if child is Node:
			_add_mesh_collisions(child, static_body, root)


func _to_root_transform(mesh_instance: Node3D, root: Node3D) -> Transform3D:
	var xform := mesh_instance.transform
	var current := mesh_instance.get_parent()
	while current != null and current is Node3D and current != root:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


func _is_supported(file: String) -> bool:
	for ext in EXTENSIONS:
		if file.to_lower().ends_with(".%s" % ext):
			return true
	return false


func _base_name(file: String) -> String:
	var parts := file.split(".")
	if parts.size() <= 1:
		return file
	parts.remove_at(parts.size() - 1)
	return ".".join(parts)
