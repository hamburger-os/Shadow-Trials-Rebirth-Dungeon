extends Node3D

## Grid-based Wave Function Collapse generator using tile rules.
## Instantiates tile scenes on a 2D grid; scale is controlled by cell_size/tile_base_size.

@export_group("Grid")
@export var grid_width: int = 32
@export var grid_height: int = 32
@export var cell_size: float = 4.0
@export var tile_base_size: float = 4.0

@export_group("Random")
@export var seed_value: int = 12345
@export var randomize_each_run: bool = true
@export var auto_generate: bool = true
@export var max_attempts: int = 5

@export_group("Rules")
@export var rule_set: DungeonRuleSet

@export_group("Snap Actors")
@export var nodes_to_snap: Array[NodePath] = []
@export var spawn_height_offset: float = 0.6

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _tile_variations: Array = []
var _instances: Array[Node] = []
var _grid: Array = []

const DIRS = {
	"n": Vector2i.UP,
	"e": Vector2i.RIGHT,
	"s": Vector2i.DOWN,
	"w": Vector2i.LEFT,
}


func _ready() -> void:
	if auto_generate:
		generate()


func generate(new_seed: int = -1) -> void:
	clear()
	_rng.seed = new_seed if new_seed >= 0 else (Time.get_ticks_usec() if randomize_each_run else seed_value)
	_tile_variations = _build_variations()

	if _tile_variations.is_empty():
		var tiles_count := 0
		if rule_set:
			tiles_count = rule_set.tiles.size()
		var rs_name := "null"
		if rule_set != null:
			rs_name = str(rule_set)
		push_warning("WFC: no tile variations available; generation skipped. rule_set=" + rs_name + " tiles=" + str(tiles_count))
		return

	var success := false
	var attempt := 0
	while not success and attempt < max_attempts:
		attempt += 1
		var result = _run_wfc()
		if result != null and result.size() > 0:
			_grid = result
			_build_geometry()
			_snap_nodes()
			success = true
		else:
			_rng.seed = Time.get_ticks_usec()  # re-roll

	if not success:
		push_warning("WFC: generation failed after attempts; map remains empty.")


func clear() -> void:
	for inst in _instances:
		if is_instance_valid(inst):
			inst.queue_free()
	_instances.clear()
	_grid.clear()


func _build_variations() -> Array:
	var variations: Array = []
	if rule_set == null:
		push_warning("WFC: rule_set is null; no tiles to build.")
		return variations

	for tile in rule_set.tiles:
		if tile == null:
			continue
		if not tile.has_method("get"):
			continue

		var scene = tile.get("scene")
		if scene == null:
			continue
		var sockets = tile.get("sockets")
		if sockets == null:
			continue

		var weight: float = 1.0
		if tile.get("weight") != null:
			weight = float(tile.get("weight"))

		var height: int = 0
		if tile.get("height") != null:
			height = int(tile.get("height"))

		var allow_rotation: bool = false
		if tile.get("allow_rotation") != null:
			allow_rotation = bool(tile.get("allow_rotation"))

		var rotations := [0]
		if allow_rotation:
			rotations = [0, 90, 180, 270]

		for rot in rotations:
			var rotated_sockets = _rotate_sockets(sockets, rot)
			variations.append({
				"scene": scene,
				"sockets": rotated_sockets,
				"weight": weight,
				"rotation": rot,
				"height": height,
			})
	return variations


func _rotate_sockets(sockets: Dictionary, degrees: int) -> Dictionary:
	if degrees % 360 == 0:
		return sockets.duplicate()
	var result := {}
	var steps := int(float(degrees) / 90.0) % 4
	var src := sockets.duplicate()
	for i in range(steps):
		var rotated := {}
		rotated["N"] = src.get("W", "open")
		rotated["E"] = src.get("N", "open")
		rotated["S"] = src.get("E", "open")
		rotated["W"] = src.get("S", "open")
		src = rotated
	result = src
	return result


func _run_wfc():
	if _tile_variations.is_empty():
		return null

	var candidates: Array = []
	for y in range(grid_height):
		var row: Array = []
		for x in range(grid_width):
			row.append(_tile_variations.duplicate(true))
		candidates.append(row)

	var max_iters := grid_width * grid_height * 10
	var iter := 0

	while iter < max_iters:
		iter += 1
		var pos = _pick_lowest_entropy(candidates)
		if pos == null:
			return _bake_grid_from_candidates(candidates)

		var cands: Array = candidates[pos.y][pos.x]
		if cands.is_empty():
			return null
		var choice = _weighted_pick(cands)
		candidates[pos.y][pos.x] = [choice]

		if not _propagate_from(pos, candidates):
			return null

	return _bake_grid_from_candidates(candidates)


func _bake_grid_from_candidates(candidates: Array) -> Array:
	var result: Array = []
	for y in range(grid_height):
		var row: Array = []
		for x in range(grid_width):
			var cell: Array = candidates[y][x]
			if cell.is_empty():
				row.append(null)
			else:
				row.append(cell[0])
		result.append(row)
	return result


func _pick_lowest_entropy(candidates: Array) -> Variant:
	var best_count := 999999
	var best_cells: Array = []
	for y in range(grid_height):
		for x in range(grid_width):
			var count = candidates[y][x].size()
			if count == 1:
				continue
			if count < best_count:
				best_count = count
				best_cells = [Vector2i(x, y)]
			elif count == best_count:
				best_cells.append(Vector2i(x, y))

	if best_cells.is_empty():
		return null
	return best_cells[_rng.randi_range(0, best_cells.size() - 1)]


func _propagate_from(start: Vector2i, candidates: Array) -> bool:
	var stack: Array = [start]
	while not stack.is_empty():
		var pos: Vector2i = stack.pop_back()
		var opts: Array = candidates[pos.y][pos.x]
		for dir_key in DIRS.keys():
			var dir_vec: Vector2i = DIRS[dir_key]
			var npos := pos + dir_vec
			if npos.x < 0 or npos.x >= grid_width or npos.y < 0 or npos.y >= grid_height:
				continue
			var n_opts: Array = candidates[npos.y][npos.x]
			var filtered := _filter_options(opts, n_opts, dir_key)
			if filtered.size() < n_opts.size():
				if filtered.is_empty():
					return false
				candidates[npos.y][npos.x] = filtered
				stack.append(npos)
	return true


func _filter_options(src_opts: Array, target_opts: Array, dir_key: String) -> Array:
	var opposite_map := {"n": "S", "s": "N", "e": "W", "w": "E"}
	var opposite: String = opposite_map[dir_key]
	var keep: Array = []
	for option in target_opts:
		var compatible := false
		for chosen in src_opts:
			var s1 = chosen["sockets"].get(dir_key.to_upper(), "open")
			var s2 = option["sockets"].get(opposite, "open")
			if _sockets_compatible(s1, s2):
				compatible = true
				break
		if compatible:
			keep.append(option)
	return keep


func _sockets_compatible(s1: String, s2: String) -> bool:
	# Compatibility rules: open <-> open/door, door <-> open/door, wall <-> wall.
	if s1 == "wall" or s2 == "wall":
		return s1 == "wall" and s2 == "wall"
	if s1 == "door" or s2 == "door":
		return (s1 == "door" and s2 == "door") or (s1 == "door" and s2 == "open") or (s1 == "open" and s2 == "door")
	# default open/other: require equality
	return s1 == s2


func _build_geometry() -> void:
	if _grid.is_empty():
		return

	var scale_factor: float = cell_size / max(0.01, tile_base_size)

	for y in range(grid_height):
		for x in range(grid_width):
			var tile = _grid[y][x]
			if tile == null:
				continue
			var scene: PackedScene = tile["scene"]
			if scene == null:
				continue
			var inst := scene.instantiate()
			inst.scale *= Vector3.ONE * scale_factor
			inst.rotation.y = deg_to_rad(float(tile["rotation"]))
			inst.position = Vector3(x * cell_size, 0, y * cell_size)
			add_child(inst)
			_instances.append(inst)


func _snap_nodes() -> void:
	if nodes_to_snap.is_empty():
		return
	if _grid.is_empty():
		return

	var first_pos: Vector3 = Vector3.ZERO
	var found := false
	for y in range(_grid.size()):
		var row: Array = _grid[y]
		for x in range(row.size()):
			if row[x] != null:
				first_pos = Vector3(x * cell_size, spawn_height_offset, y * cell_size)
				found = true
				break
		if found:
			break
	if not found:
		return

	for i in range(nodes_to_snap.size()):
		var node := get_node_or_null(nodes_to_snap[i])
		if node and node is Node3D:
			node.global_position = first_pos


func _weighted_pick(options: Array):
	var total := 0.0
	for opt in options:
		var w = 1.0
		if opt.has("weight"):
			w = opt["weight"]
		total += w
	var r := _rng.randf() * total
	for opt in options:
		var w = 1.0
		if opt.has("weight"):
			w = opt["weight"]
		r -= w
		if r <= 0:
			return opt
	return options.back()
