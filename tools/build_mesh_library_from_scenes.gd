@tool
extends EditorScript

@export var tiles_dir := "res://features/procedural_generation/room_templates/tiles/KayKit_DungeonRemastered"
@export var output_path := "res://assets/environments/KayKit_DungeonRemastered_1.1_FREE.tres"
@export var overwrite_existing := true
@export var generate_previews := false # 若为 true，构建时生成缩略图

func _run() -> void:
	if not tiles_dir.begins_with("res://") or not output_path.begins_with("res://"):
		push_error("Paths must start with res:// (tiles_dir: %s, output_path: %s)" % [tiles_dir, output_path])
		return

	if ResourceLoader.exists(output_path) and not overwrite_existing:
		push_warning("Output exists, set overwrite_existing=true to regenerate: %s" % output_path)
		return

	var dir := DirAccess.open(tiles_dir)
	if dir == null:
		push_error("Cannot open tiles_dir: %s" % tiles_dir)
		return

	var files: Array[String] = []
	dir.list_dir_begin()
	while true:
		var f := dir.get_next()
		if f.is_empty():
			break
		if dir.current_is_dir():
			continue
		if f.to_lower().ends_with(".tscn"):
			files.append(f)
	dir.list_dir_end()
	files.sort()

	if files.is_empty():
		push_warning("No .tscn found under %s" % tiles_dir)
		return

	var lib := MeshLibrary.new()
	var next_id := 0
	for file in files:
		var path: String = "%s/%s" % [tiles_dir, file]
		var base: String = String(file).trim_suffix(".tscn")
		var packed := ResourceLoader.load(path)
		if packed == null or not (packed is PackedScene):
			push_warning("Skip (not a PackedScene): %s" % path)
			continue

		var inst := (packed as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		if inst == null or not (inst is Node3D):
			push_warning("Skip (root not Node3D): %s" % path)
			continue

		var mesh_instance := _find_first_mesh(inst)
		if mesh_instance == null or mesh_instance.mesh == null:
			push_warning("Skip (no mesh): %s" % path)
			continue
		if mesh_instance.mesh.get_surface_count() == 0:
			push_warning("Skip (mesh has 0 surfaces): %s" % path)
			continue

		var shapes := _collect_shapes(inst as Node3D)

		lib.create_item(next_id)
		lib.set_item_name(next_id, base)
		lib.set_item_mesh(next_id, mesh_instance.mesh)
		lib.set_item_mesh_transform(next_id, _to_root_transform(mesh_instance, inst))
		lib.set_item_shapes(next_id, shapes)
		if generate_previews:
			var preview := await _generate_preview(mesh_instance.mesh)
			if preview:
				lib.set_item_preview(next_id, preview)

		next_id += 1
		# 释放临时实例，避免在编辑器关闭时残留 RID
		inst.free()

	var err := ResourceSaver.save(lib, output_path)
	if err != OK:
		push_error("Failed to save mesh library (%d): %s" % [err, output_path])
	else:
		print("MeshLibrary saved with %d items -> %s" % [next_id, output_path])
		_validate_mesh_library(lib)


func _find_first_mesh(root: Node3D) -> MeshInstance3D:
	for child in root.get_children():
		if child is MeshInstance3D:
			return child
		if child is Node3D:
			var found := _find_first_mesh(child)
			if found:
				return found
	return null


func _collect_shapes(root: Node3D) -> Array:
	var shapes: Array = []
	_add_shapes_recursive(root, root, shapes)
	return shapes


func _add_shapes_recursive(node: Node, root: Node3D, shapes: Array) -> void:
	for child in node.get_children():
		if child is CollisionShape3D:
			var cs := child as CollisionShape3D
			if cs.shape != null:
				shapes.append(cs.shape)
				shapes.append(_to_root_transform(cs, root))
		if child is Node:
			_add_shapes_recursive(child, root, shapes)


func _to_root_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xform := node.transform
	var current := node.get_parent()
	while current != null and current is Node3D and current != root:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


func _validate_mesh_library(lib: MeshLibrary) -> void:
	var errors := 0
	var warnings := 0
	for id in lib.get_item_list():
		if lib.get_item_mesh(id) == null:
			push_error("Item %s has no mesh" % id)
			errors += 1

		var shapes := lib.get_item_shapes(id)
		if shapes.size() % 2 != 0:
			push_error("Item %s shapes count is not even (expected pairs of shape + Transform3D)" % id)
			errors += 1
		else:
			for i in range(0, shapes.size(), 2):
				var shape = shapes[i]
				var xform = shapes[i + 1]
				if shape == null:
					push_warning("Item %s shape at %d is null" % [id, i])
					warnings += 1
				if typeof(xform) != TYPE_TRANSFORM3D:
					push_warning("Item %s transform at %d is not Transform3D" % [id, i + 1])
					warnings += 1

	if errors == 0 and warnings == 0:
		print("MeshLibrary validation passed (%d items)" % lib.get_item_list().size())
	else:
		print("MeshLibrary validation finished: %d errors, %d warnings" % [errors, warnings])


func _generate_preview(mesh: Mesh) -> Texture2D:
	if mesh == null:
		return null
	var tree := _get_tree()
	if tree == null:
		push_warning("Cannot generate preview (no tree available)")
		return null

	var viewport := SubViewport.new()
	viewport.name = "TmpMeshPreview"
	viewport.disable_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.msaa_3d = SubViewport.MSAA_2X
	viewport.size = Vector2i(256, 256)

	var root := Node3D.new()
	viewport.add_child(root)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 35, 0)
	light.light_energy = 1.2
	root.add_child(light)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	root.add_child(mesh_instance)

	var aabb := mesh.get_aabb()
	var center := aabb.position + aabb.size * 0.5
	var radius: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	if radius <= 0.0:
		radius = 1.0

	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.05
	cam.far = radius * 6.0
	var cam_dir := Vector3(1, 1.2, 1).normalized()
	var cam_pos := center + cam_dir * (radius * 2.5)
	# 使用 look_at_from_position 避免未在树中时报错
	cam.look_at_from_position(cam_pos, center, Vector3.UP)
	root.add_child(cam)

	tree.root.add_child(viewport)
	await tree.process_frame
	await tree.process_frame

	var tex: Texture2D = null
	var image := viewport.get_texture().get_image()
	if image:
		tex = ImageTexture.create_from_image(image)

	viewport.queue_free()
	return tex


func _get_tree() -> SceneTree:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return loop
	return null
