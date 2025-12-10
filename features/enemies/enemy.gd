extends CharacterBody3D

@export var enemy_data: EnemyData
@export var stats: CharacterStats
@export_node_path("Node3D") var target_path: NodePath
@export var move_speed: float = 3.2
@export var chase_range: float = 20.0
@export var attack_range: float = 1.6
@export var turn_speed: float = 8.0
@export var hit_recover_time: float = 0.5
@export var anim_name_idle: StringName = "Skeletons_Idle"
@export var anim_name_walk: StringName = "Skeletons_Walking"
@export var anim_name_attack: StringName = "Skeletons_Taunt"
@export var anim_name_spawn: StringName = "Skeletons_Spawn_Ground"
@export var anim_name_hit: StringName = "Skeletons_Awaken_Standing"
@export var anim_name_die: StringName = "Skeletons_Death"
@export_node_path("AudioStreamPlayer3D") var attack_sfx_path: NodePath = NodePath("SfxAttack")
@export_node_path("AudioStreamPlayer3D") var hit_sfx_path: NodePath = NodePath("SfxHit")
@export_node_path("AudioStreamPlayer3D") var death_sfx_path: NodePath = NodePath("SfxDie")

@onready var visual_root: Node3D = $VisualRoot
@onready var anim_tree: AnimationTree = $AnimationTree
var anim_player: AnimationPlayer
var anim_state: AnimationNodeStateMachinePlayback
var model_instance: Node3D

var target: Node3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _current_state: StringName = ""
var _attack_cooldown: float = 0.0
var _attack_anim_remaining: float = 0.0
var _hit_recover_remaining: float = 0.0
var _spawn_time_remaining: float = 0.0
var _death_time_remaining: float = 0.0
var _spawn_min_time: float = 0.8
var _is_dead: bool = false
var _sfx_attack: AudioStreamPlayer3D
var _sfx_hit: AudioStreamPlayer3D
var _sfx_die: AudioStreamPlayer3D


func _ready() -> void:
	if not _apply_enemy_data():
		queue_free()
		return
	if not _validate_visual_root():
		queue_free()
		return
	_setup_animation_tree()
	_refresh_target()
	_play_spawn_animation()
	_setup_audio()


func _physics_process(delta: float) -> void:
	var vel: Vector3 = velocity
	if not is_on_floor():
		vel.y -= gravity * delta
	else:
		vel.y = 0.0

	if _is_dead:
		vel.x = 0.0
		vel.z = 0.0
		if _death_time_remaining > 0.0:
			_death_time_remaining -= delta
			if _death_time_remaining <= 0.0:
				queue_free()
				return
		velocity = vel
		move_and_slide()
		return

	if _spawn_time_remaining > 0.0:
		_spawn_time_remaining -= delta
		_set_state("Spawn")
		velocity = vel
		move_and_slide()
		return

	if _attack_cooldown > 0.0:
		_attack_cooldown = max(_attack_cooldown - delta, 0.0)
	if _attack_anim_remaining > 0.0:
		_attack_anim_remaining = max(_attack_anim_remaining - delta, 0.0)
	if _hit_recover_remaining > 0.0:
		_hit_recover_remaining = max(_hit_recover_remaining - delta, 0.0)

	_refresh_target()

	var chase_dir: Vector3 = Vector3.ZERO
	var distance_to_target: float = INF

	if target and is_instance_valid(target):
		var to_target: Vector3 = target.global_transform.origin - global_transform.origin
		distance_to_target = to_target.length()
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			chase_dir = to_target.normalized()
			_turn_toward(chase_dir, delta)

	var is_attacking: bool = false
	if distance_to_target <= attack_range and _attack_cooldown <= 0.0 and _hit_recover_remaining <= 0.0:
		_perform_attack()
		is_attacking = true

	if _hit_recover_remaining > 0.0:
		_set_state("Hit")
		vel.x = move_toward(vel.x, 0.0, move_speed)
		vel.z = move_toward(vel.z, 0.0, move_speed)
	elif is_attacking or _attack_anim_remaining > 0.0:
		_set_state("Attack")
		vel.x = move_toward(vel.x, 0.0, move_speed)
		vel.z = move_toward(vel.z, 0.0, move_speed)
	elif chase_dir != Vector3.ZERO and distance_to_target <= chase_range:
		vel.x = chase_dir.x * move_speed
		vel.z = chase_dir.z * move_speed
		_set_state("Walk")
	else:
		vel.x = move_toward(vel.x, 0.0, move_speed)
		vel.z = move_toward(vel.z, 0.0, move_speed)
		_set_state("Idle")

	velocity = vel
	move_and_slide()


func set_target(new_target: Node3D) -> void:
	target = new_target
	if target:
		target_path = target.get_path()


func take_damage(damage_amount: int) -> void:
	if _is_dead:
		return
	if not stats:
		return

	stats.current_health -= damage_amount
	if stats.current_health <= 0:
		die()
		return

	_play_sfx(_sfx_hit)
	_hit_recover_remaining = hit_recover_time
	_attack_anim_remaining = 0.0
	_attack_cooldown = max(_attack_cooldown, hit_recover_time)
	_set_state("Hit", true)


func die() -> void:
	if _is_dead:
		return

	_is_dead = true
	_death_time_remaining = max(_get_anim_length(anim_name_die), 0.8)
	_set_state("Die", true)
	_play_sfx(_sfx_die)


func _perform_attack() -> void:
	_set_state("Attack", true)
	_attack_anim_remaining = max(_get_anim_length(anim_name_attack), 0.4)
	var interval: float = _get_attack_interval()
	_attack_cooldown = max(interval, _attack_anim_remaining)
	_play_sfx(_sfx_attack)

	if target and is_instance_valid(target) and target.has_method("take_damage"):
		target.call("take_damage", stats.attack_power if stats else 10)


func _turn_toward(dir: Vector3, delta: float) -> void:
	if not visual_root or dir == Vector3.ZERO:
		return
	var target_yaw: float = atan2(dir.x, dir.z)
	visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw, turn_speed * delta)


func _setup_animation_tree() -> void:
	if not anim_tree:
		return

	var state_machine := AnimationNodeStateMachine.new()
	_add_anim_state(state_machine, "Idle", anim_name_idle)
	_add_anim_state(state_machine, "Walk", anim_name_walk)
	_add_anim_state(state_machine, "Attack", anim_name_attack)
	_add_anim_state(state_machine, "Spawn", anim_name_spawn)
	_add_anim_state(state_machine, "Hit", anim_name_hit)
	_add_anim_state(state_machine, "Die", anim_name_die)

	anim_tree.tree_root = state_machine
	anim_tree.active = true

	anim_state = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if anim_state:
		_current_state = "Idle"
		anim_state.start(_current_state)


func _add_anim_state(machine: AnimationNodeStateMachine, state_name: StringName, anim_name: StringName) -> void:
	var node := AnimationNodeAnimation.new()
	node.animation = anim_name
	machine.add_node(state_name, node)


func _set_state(state: StringName, force_restart: bool = false) -> void:
	if not anim_state:
		return
	if _current_state == state and not force_restart:
		return

	_current_state = state
	anim_state.start(state)


func _setup_audio() -> void:
	_sfx_attack = get_node_or_null(attack_sfx_path) as AudioStreamPlayer3D
	_sfx_hit = get_node_or_null(hit_sfx_path) as AudioStreamPlayer3D
	_sfx_die = get_node_or_null(death_sfx_path) as AudioStreamPlayer3D


func _play_sfx(player: AudioStreamPlayer3D) -> void:
	if not player:
		return
	if not player.stream:
		return
	player.stop()
	player.play()


func _get_attack_interval() -> float:
	if stats and stats.attack_interval > 0.0:
		return stats.attack_interval
	return 1.0


func _refresh_target() -> void:
	if target and is_instance_valid(target):
		return
	if target_path != NodePath(""):
		target = get_node_or_null(target_path) as Node3D


func _play_spawn_animation() -> void:
	_spawn_time_remaining = max(_get_anim_length(anim_name_spawn), _spawn_min_time)
	_set_state("Spawn", true)


func _get_anim_length(anim_name: StringName) -> float:
	if anim_player and anim_player.has_animation(anim_name):
		var anim := anim_player.get_animation(anim_name)
		if anim:
			return anim.length
	return 0.0


func _apply_enemy_data() -> bool:
	if enemy_data:
		if enemy_data.character:
			_apply_character_data(enemy_data.character)
		chase_range = enemy_data.chase_range
		attack_range = enemy_data.attack_range
		hit_recover_time = enemy_data.hit_recover_time
		_spawn_min_time = max(enemy_data.spawn_anim_min_time, 0.0)
		if enemy_data.character and enemy_data.character.anim_spawn != "":
			anim_name_spawn = enemy_data.character.anim_spawn
		if enemy_data.character and enemy_data.character.anim_hit != "":
			anim_name_hit = enemy_data.character.anim_hit
		if enemy_data.attack_interval > 0.0 and stats:
			stats.attack_interval = enemy_data.attack_interval

	if not stats:
		push_error("character %s 没有分配 CharacterStats!" % name)
		return false

	# 确保实例拥有独立的属性资源
	stats = stats.duplicate(true)
	stats.current_health = stats.max_health
	return true


func _apply_character_data(data: CharacterData) -> void:
	if data.stats:
		stats = data.stats.duplicate(true)
		stats.current_health = stats.max_health

	move_speed = data.move_speed
	turn_speed = data.turn_speed
	anim_name_idle = data.anim_idle
	anim_name_walk = data.anim_run
	anim_name_attack = data.anim_attack
	if data.anim_spawn != "":
		anim_name_spawn = data.anim_spawn
	if data.anim_hit != "":
		anim_name_hit = data.anim_hit
	anim_name_die = data.anim_die

	_load_model_from_data(data)
	_assign_sfx_from_data(data)


func _load_model_from_data(data: CharacterData) -> void:
	if not visual_root:
		return

	if data.model_scene:
		for child in visual_root.get_children():
			child.queue_free()
		model_instance = data.model_scene.instantiate() as Node3D
		if model_instance:
			visual_root.add_child(model_instance)
			model_instance.transform = data.visual_transform
			anim_player = model_instance.get_node_or_null(data.animation_player_path) as AnimationPlayer
			if not anim_player:
				anim_player = model_instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if anim_tree:
				anim_tree.root_node = model_instance.get_path()
				if anim_player:
					anim_tree.anim_player = anim_player.get_path()
	elif visual_root.get_child_count() > 0:
		model_instance = visual_root.get_child(0) as Node3D
		if model_instance:
			anim_player = model_instance.get_node_or_null(data.animation_player_path) as AnimationPlayer
			if anim_tree and anim_player:
				anim_tree.root_node = model_instance.get_path()
				anim_tree.anim_player = anim_player.get_path()


func _assign_sfx_from_data(data: CharacterData) -> void:
	if data.sfx_attack and get_node_or_null(attack_sfx_path) is AudioStreamPlayer3D:
		var node := get_node(attack_sfx_path) as AudioStreamPlayer3D
		node.stream = data.sfx_attack
	if data.sfx_hurt and get_node_or_null(hit_sfx_path) is AudioStreamPlayer3D:
		var hurt := get_node(hit_sfx_path) as AudioStreamPlayer3D
		hurt.stream = data.sfx_hurt
	if data.sfx_die and get_node_or_null(death_sfx_path) is AudioStreamPlayer3D:
		var die_node := get_node(death_sfx_path) as AudioStreamPlayer3D
		die_node.stream = data.sfx_die


func _validate_visual_root() -> bool:
	if not visual_root:
		push_error("敌人 %s 缺少 VisualRoot 节点" % name)
		return false
	if visual_root.get_child_count() == 0 and not model_instance:
		push_error("敌人 %s 的 VisualRoot 为空，未能加载模型" % name)
		return false
	if not anim_player:
		push_error("敌人 %s 没有 AnimationPlayer，无法播放动画" % name)
		return false
	return true
