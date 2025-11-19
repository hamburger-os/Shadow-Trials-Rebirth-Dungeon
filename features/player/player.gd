extends CharacterBody3D

# ===== 可在 Inspector 中调整的参数 =====
@export var speed: float = 5.0                 # 水平移动速度
@export var rotate_to_movement: bool = true    # 是否自动朝向移动方向
@export var turn_speed: float = 10.0           # 朝向插值速度（越大转身越快）
@export var stats: CharacterStats             # 玩家角色的属性数据卡
@export var dash_speed: float = 15.0           # 冲刺时的水平速度
@export var dash_duration: float = 0.2         # 冲刺持续时间（秒）
@export var dash_cooldown: float = 0.5         # 冲刺冷却时间（秒）
@export var anim_name_idle: StringName = "Idle_A"
@export var anim_name_run: StringName = "Walking_A"
@export var anim_name_dash: StringName = "Running_A"
@export var anim_name_attack: StringName = "Melee_1H_Attack_Slice_Diagonal"
@export var weapon_scene: PackedScene
@export var weapon_data: WeaponData

# 摄像机吊臂（上面挂着 Camera3D，用来确定“前后左右”）
@onready var spring_arm: SpringArm3D = $SpringArm3D
@export_node_path("Camera3D") var camera_path: NodePath
@onready var camera: Camera3D = get_node_or_null(camera_path) as Camera3D
@onready var visual_root: Node3D = $VisualRoot
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var anim_player: AnimationPlayer = $VisualRoot/Barbarian/AnimationPlayer
var anim_state: AnimationNodeStateMachinePlayback

# 使用项目设置中的 3D 默认重力
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var dash_time_remaining: float = 0.0
var dash_cooldown_remaining: float = 0.0

var attack_cooldown_remaining: float = 0.0
var overlapping_bodies: Array[Node3D] = []
var _current_move_state: StringName = ""
var attack_anim_time_remaining: float = 0.0
var _attack_anim_index: int = 0
var _attack_anim_node: AnimationNodeAnimation


func _ready() -> void:
	_update_attack_anim_from_weapon()
	_setup_animation_tree()
	_equip_weapon()


func _physics_process(delta: float) -> void:
	# 当前速度，从 CharacterBody3D 自带的 velocity 拷贝一份出来修改
	var vel: Vector3 = velocity

	# 1. 重力：不在地面上时持续向下加速度
	if not is_on_floor():
		vel.y -= gravity * delta

	# 更新 dash 与攻击冷却计时
	if dash_cooldown_remaining > 0.0:
		dash_cooldown_remaining -= delta
		if dash_cooldown_remaining < 0.0:
			dash_cooldown_remaining = 0.0

	if dash_time_remaining > 0.0:
		dash_time_remaining -= delta
		if dash_time_remaining < 0.0:
			dash_time_remaining = 0.0

	if attack_cooldown_remaining > 0.0:
		attack_cooldown_remaining -= delta
		if attack_cooldown_remaining < 0.0:
			attack_cooldown_remaining = 0.0

	if attack_anim_time_remaining > 0.0:
		attack_anim_time_remaining -= delta
		if attack_anim_time_remaining <= 0.0:
			attack_anim_time_remaining = 0.0
			# 攻击结束后清空当前状态字符串，
			# 确保后续一次移动更新能强制刷新状态机。
			_current_move_state = ""
			# 立即根据当前速度恢复到 Idle / Run 动画
			_update_move_animation(velocity)

	# 2. 获取输入（键盘方向键 / 手柄左摇杆）
	# 使用自定义 move_*
	# Input.get_vector: x = right - left, y = down - up
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var has_manual_input: bool = input_dir.length_squared() > 0.2

	# 3. 基于摄像机朝向计算“前/后/左/右”的 3D 方向
	var forward: Vector3 = -spring_arm.global_transform.basis.z  # 摄像机朝向的前方
	var right: Vector3 = spring_arm.global_transform.basis.x     # 摄像机右方

	# 忽略 Y 分量，只在 XZ 平面移动
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	var direction: Vector3 = Vector3.ZERO

	if has_manual_input:
		# Input.get_vector 的 y 向下为正，所以这里取反：
		#   上键：input_dir.y = -1 → 向前
		#   下键：input_dir.y =  1 → 向后
		direction = forward * -input_dir.y + right * input_dir.x

	# Dash 触发：优先使用当前移动方向；若没有输入，则沿摄像机前方冲刺
	if dash_time_remaining <= 0.0 and dash_cooldown_remaining <= 0.0 and Input.is_action_just_pressed("dash"):
		var dash_dir: Vector3 = direction
		if dash_dir == Vector3.ZERO:
			dash_dir = forward

		dash_dir.y = 0.0
		if dash_dir.length_squared() > 0.0001:
			dash_dir = dash_dir.normalized()
			dash_time_remaining = dash_duration
			dash_cooldown_remaining = dash_cooldown
			# 在 dash 开始瞬间立即更新朝向
			if rotate_to_movement and visual_root:
				var dash_yaw: float = atan2(dash_dir.x, dash_dir.z)
				visual_root.rotation.y = dash_yaw
			# 直接设置当前水平速度用于本帧
			vel.x = dash_dir.x * dash_speed
			vel.z = dash_dir.z * dash_speed

	# 4. 根据输入设置水平速度；没有输入时做简单减速
	if dash_time_remaining > 0.0:
		# 冲刺期间锁定在 dash 方向，由前面设置的 vel 保持
		pass
	elif direction != Vector3.ZERO:
		direction = direction.normalized()
		vel.x = direction.x * speed
		vel.z = direction.z * speed
	else:
		vel.x = move_toward(vel.x, 0.0, speed)
		vel.z = move_toward(vel.z, 0.0, speed)

	# 6. 自动攻击尝试：根据当前重叠的敌人和冷却时间进行一次攻击 tick
	_try_attack()

	# 7. 更新角色朝向：优先朝向最近的敌人，否则朝向移动方向
	_update_facing(direction, delta)

	# 8. 把计算好的速度写回并执行移动与碰撞
	velocity = vel
	_update_move_animation(vel)
	move_and_slide()


func _on_hitbox_body_entered(body: Node3D) -> void:
	if body and body.has_method("take_damage"):
		if not overlapping_bodies.has(body):
			overlapping_bodies.append(body)
		# 进入时尝试立刻进行一次攻击tick
		_try_attack()


func _on_hitbox_body_exited(body: Node3D) -> void:
	if overlapping_bodies.has(body):
		overlapping_bodies.erase(body)


func _try_attack() -> void:
	if attack_cooldown_remaining > 0.0:
		return

	if overlapping_bodies.is_empty():
		return

	var damage: int = 20
	var interval: float = 0.4
	if weapon_data:
		damage = int(weapon_data.damage)
		if weapon_data.attack_speed > 0.0:
			interval = 1.0 / weapon_data.attack_speed
	elif stats:
		damage = stats.attack_power
		interval = stats.attack_interval

	var dealt_damage: bool = false
	var origin: Vector3 = global_transform.origin
	for i in range(overlapping_bodies.size()):
		var body := overlapping_bodies[i]
		if not is_instance_valid(body):
			continue
		if not body.has_method("take_damage"):
			continue

		if weapon_data and weapon_data.attack_range > 0.0:
			var to_body: Vector3 = body.global_transform.origin - origin
			if to_body.length() > weapon_data.attack_range:
				continue

		body.call("take_damage", damage)
		dealt_damage = true

	if dealt_damage:
		var anim_duration := _play_attack_animation()
		var cd: float = interval
		if anim_duration > 0.0:
			cd = anim_duration
		attack_cooldown_remaining = max(cd, 0.05)


func _update_facing(move_dir: Vector3, delta: float) -> void:
	# 1）若攻击范围内有敌人，则自动朝向最近的敌人
	if not overlapping_bodies.is_empty():
		var closest_dir: Vector3 = Vector3.ZERO
		var closest_dist_sq: float = INF

		for i in range(overlapping_bodies.size()):
			var body := overlapping_bodies[i]
			if not is_instance_valid(body):
				continue

			var to_body: Vector3 = body.global_transform.origin - global_transform.origin
			to_body.y = 0.0
			var dist_sq := to_body.length_squared()
			if dist_sq < 0.0001:
				continue
			if dist_sq < closest_dist_sq:
				closest_dist_sq = dist_sq
				closest_dir = to_body.normalized()

		if closest_dir != Vector3.ZERO and visual_root:
			var target_yaw_enemy: float = atan2(closest_dir.x, closest_dir.z)
			visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw_enemy, turn_speed * delta)
		return

	# 2）否则，按移动方向转身（原先逻辑）
	if rotate_to_movement and move_dir != Vector3.ZERO and visual_root:
		var dir := move_dir.normalized()
		var target_yaw_move: float = atan2(dir.x, dir.z)
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw_move, turn_speed * delta)


func _setup_animation_tree() -> void:
	if not anim_tree:
		return

	var state_machine := AnimationNodeStateMachine.new()

	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = anim_name_idle
	state_machine.add_node("Idle", idle_node)

	var run_node := AnimationNodeAnimation.new()
	run_node.animation = anim_name_run
	state_machine.add_node("Run", run_node)

	if anim_name_dash != "":
		var dash_node := AnimationNodeAnimation.new()
		dash_node.animation = anim_name_dash
		state_machine.add_node("Dash", dash_node)

	# 攻击状态交给 AnimationTree 管理
	_attack_anim_node = AnimationNodeAnimation.new()
	_attack_anim_node.animation = anim_name_attack
	state_machine.add_node("Attack", _attack_anim_node)

	anim_tree.tree_root = state_machine
	anim_tree.active = true

	anim_state = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if not anim_state:
		return

	_current_move_state = "Idle"
	anim_state.start(_current_move_state)


func _set_move_state(state: StringName) -> void:
	if not anim_state:
		return
	# 允许攻击状态重复触发，以便每次攻击都能从头播放一段动画
	if _current_move_state == state and state != "Attack":
		return

	_current_move_state = state
	anim_state.travel(state)


func _update_move_animation(vel: Vector3) -> void:
	if not anim_tree or not anim_state:
		return

	var horizontal_speed := Vector2(vel.x, vel.z).length()

	if attack_anim_time_remaining > 0.0:
		# 攻击期间保持在 Attack 状态，不切换移动动画
		return
	elif dash_time_remaining > 0.0 and anim_name_dash != "":
		_set_move_state("Dash")
	elif horizontal_speed > 0.1:
		_set_move_state("Run")
	else:
		_set_move_state("Idle")


func _play_attack_animation() -> float:
	if not anim_tree or not anim_state:
		return 0.0

	var next_anim: StringName = _get_next_attack_anim_name()
	if next_anim == "":
		return 0.0

	var base_length: float = 0.8
	if anim_player:
		var anim: Animation = anim_player.get_animation(next_anim)
		if anim:
			base_length = anim.length

	var attacks_per_second: float = 1.0
	if weapon_data and weapon_data.attack_speed > 0.0:
		attacks_per_second = weapon_data.attack_speed

	var desired_duration: float = 1.0 / attacks_per_second

	if _attack_anim_node:
		_attack_anim_node.animation = next_anim
		# 完全通过 AnimationTree 控制攻击动画速度：
		# 1）开启自定义时间线；
		# 2）让一整段动画被拉伸或压缩到 desired_duration。
		_attack_anim_node.use_custom_timeline = true
		_attack_anim_node.stretch_time_scale = true
		_attack_anim_node.timeline_length = desired_duration

	# 每次攻击都从头开始播放 Attack 状态，
	# 确保挥砍 / 刺击动作可以按顺序反复循环。
	_current_move_state = "Attack"
	anim_state.start("Attack")

	attack_anim_time_remaining = desired_duration
	return desired_duration


func _update_attack_anim_from_weapon() -> void:
	if not weapon_data:
		return

	if weapon_data.attack_animation_names.size() > 0:
		_attack_anim_index = 0
		anim_name_attack = weapon_data.attack_animation_names[_attack_anim_index]
	elif weapon_data.attack_animation_name != "":
		anim_name_attack = weapon_data.attack_animation_name

	_refresh_attack_node_from_anim_name()


func _get_next_attack_anim_name() -> StringName:
	if weapon_data and weapon_data.attack_animation_names.size() > 0:
		if _attack_anim_index >= weapon_data.attack_animation_names.size():
			_attack_anim_index = 0
		var anim_name_local: StringName = weapon_data.attack_animation_names[_attack_anim_index]
		_attack_anim_index += 1
		return anim_name_local
	return anim_name_attack


func _refresh_attack_node_from_anim_name() -> void:
	if _attack_anim_node:
		_attack_anim_node.animation = anim_name_attack


func _equip_weapon() -> void:
	if not weapon_scene:
		return

	var weapon_instance := weapon_scene.instantiate()
	if weapon_instance == null:
		return

	var attach_parent: Node3D = get_node_or_null("VisualRoot/Barbarian/Rig_Medium/Skeleton3D/Barbarian_BoneHandr") as Node3D
	if attach_parent == null:
		attach_parent = visual_root

	attach_parent.add_child(weapon_instance)

	if weapon_data and weapon_instance.has_method("_apply_weapon_data"):
		weapon_instance.set("weapon_data", weapon_data)
		weapon_instance.call("_apply_weapon_data")
