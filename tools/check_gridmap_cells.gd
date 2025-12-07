@tool
extends EditorScript

@export var gridmap_scene_path := "res://features/procedural_generation/room_templates/dungeon_01.tscn"
@export var gridmap_node_path := NodePath("GridMap")

func _run() -> void:
	if not gridmap_scene_path.begins_with("res://"):
		push_error("gridmap_scene_path must start with res://")
		return

	var packed := load(gridmap_scene_path)
	if packed == null or not (packed is PackedScene):
		push_error("Failed to load PackedScene: %s" % gridmap_scene_path)
		return

	var root := (packed as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if root == null or not (root is Node):
		push_error("Root is invalid in: %s" % gridmap_scene_path)
		return

	var gm := root.get_node_or_null(gridmap_node_path) as GridMap
	if gm == null:
		push_error("GridMap not found at path: %s" % gridmap_node_path)
		return

	var lib := gm.mesh_library
	if lib == null:
		push_error("GridMap has no mesh_library assigned.")
		return

	# 统计库中无 surface 的条目（即 mesh.get_surface_count() == 0）
	var zero_surface_items: Array = []
	for id in lib.get_item_list():
		var mesh := lib.get_item_mesh(id)
		if mesh == null or mesh.get_surface_count() == 0:
			zero_surface_items.append(id)

	var bad: Array = []
	for cell in gm.get_used_cells():
		var item_id: int = gm.get_cell_item(cell)
		# MeshLibrary 没有 has_item 方法，直接通过 get_item_mesh 判空即可
		if lib.get_item_mesh(item_id) == null:
			bad.append([cell, item_id])

	if bad.is_empty():
		print("GridMap check passed: all used cells have valid MeshLibrary items. Total cells: %d" % gm.get_used_cells().size())
		if not zero_surface_items.is_empty():
			push_warning("MeshLibrary has %d items with 0 surfaces (they cannot render): %s" % [zero_surface_items.size(), zero_surface_items])
	else:
		push_warning("GridMap found %d invalid cells (missing item or mesh):" % bad.size())
		for entry in bad:
			var cell: Vector3i = entry[0]
			var item_id: int = int(entry[1])
			print(" - cell %s -> item_id %s invalid" % [cell, item_id])

	# 释放临时实例，减少关闭编辑器时的残留资源
	root.free()
