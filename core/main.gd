extends Node3D

@export_node_path("CharacterBody3D") var player_path: NodePath
@export var enemy_scene: PackedScene
@export var spawn_interval: float = 4.0
@export var min_spawn_per_wave: int = 2
@export var max_spawn_per_wave: int = 4
@export var spawn_radius_min: float = 6.0
@export var spawn_radius_max: float = 10.0
@export var min_spawn_distance_from_player: float = 4.0
@export var max_enemies: int = 12
@export var auto_spawn_on_ready: bool = true
@export var initial_spawn_delay: float = 0.25
@export var enemy_datas: Array[EnemyData] = []

var _player: CharacterBody3D
var _spawn_timer: Timer
var _enemies: Array[Node3D] = []
var _has_started: bool = false


func _ready() -> void:
	randomize()

	if min_spawn_per_wave > max_spawn_per_wave:
		var tmp: int = min_spawn_per_wave
		min_spawn_per_wave = max_spawn_per_wave
		max_spawn_per_wave = tmp
	if spawn_radius_min > spawn_radius_max:
		var tmp_radius: float = spawn_radius_min
		spawn_radius_min = spawn_radius_max
		spawn_radius_max = tmp_radius

	if player_path != NodePath(""):
		_player = get_node_or_null(player_path) as CharacterBody3D
	if not _player:
		_player = get_node_or_null("主角") as CharacterBody3D

	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.one_shot = false
	_spawn_timer.autostart = false
	_spawn_timer.timeout.connect(_on_spawn_timeout)
	add_child(_spawn_timer)

	if auto_spawn_on_ready:
		_schedule_initial_spawn()


func start_spawning() -> void:
	_schedule_initial_spawn()


func _on_spawn_timeout() -> void:
	_spawn_wave()


func _schedule_initial_spawn() -> void:
	if _has_started:
		return
	# 等一帧让场景内的对齐/定位逻辑先跑完，再按最终坐标生成敌人
	await get_tree().process_frame
	if initial_spawn_delay > 0.0:
		await get_tree().create_timer(initial_spawn_delay).timeout
	_begin_spawning()


func _begin_spawning() -> void:
	if _has_started:
		return
	_has_started = true
	_spawn_wave()
	_spawn_timer.start()


func _spawn_wave() -> void:
	if not enemy_scene or not _player:
		return

	_cleanup_dead()
	if max_enemies > 0 and _enemies.size() >= max_enemies:
		return

	var spawn_count: int = randi_range(min_spawn_per_wave, max_spawn_per_wave)
	for i in range(spawn_count):
		if max_enemies > 0 and _enemies.size() >= max_enemies:
			break

		var enemy := enemy_scene.instantiate() as Node3D
		if not enemy:
			continue

		if enemy_datas.size() > 0:
			var data_index := randi_range(0, enemy_datas.size() - 1)
			var selected_data: EnemyData = enemy_datas[data_index]
			if selected_data:
				enemy.set("enemy_data", selected_data)

		add_child(enemy)
		if _player:
			enemy.set("target", _player)
			enemy.set("target_path", _player.get_path())

		var spawn_position: Vector3 = _get_spawn_position()
		enemy.global_transform.origin = spawn_position

		_enemies.append(enemy)
		enemy.tree_exited.connect(_on_enemy_tree_exited.bind(enemy))


func _get_spawn_position() -> Vector3:
	if not _player:
		return Vector3.ZERO

	var base: Vector3 = _player.global_transform.origin
	var min_radius: float = max(spawn_radius_min, min_spawn_distance_from_player)
	var max_radius: float = max(spawn_radius_max, min_radius)

	var tries := 6
	for i in range(tries):
		var radius: float = randf_range(min_radius, max_radius)
		var angle: float = randf() * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		if offset.length() >= min_spawn_distance_from_player:
			return _project_to_ground(base + offset)

	# 兜底：如果随机多次仍未满足，直接放在最小安全距离正前方
	return _project_to_ground(base + Vector3(min_radius, 0.0, 0.0))


func _cleanup_dead() -> void:
	_enemies = _enemies.filter(func(e): return is_instance_valid(e))


func _on_enemy_tree_exited(enemy: Node) -> void:
	_enemies.erase(enemy)


func _project_to_ground(pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if not space:
		return pos

	var from := pos + Vector3.UP * 5.0
	var to := pos + Vector3.DOWN * 50.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.exclude = [_player]

	var result := space.intersect_ray(query)
	if result.has("position"):
		pos.y = result.position.y
	return pos
