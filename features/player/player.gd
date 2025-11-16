extends CharacterBody3D

# ===== 可在 Inspector 中调整的参数 =====
@export var speed: float = 5.0                 # 水平移动速度
@export var rotate_to_movement: bool = true    # 是否自动朝向移动方向
@export var turn_speed: float = 10.0           # 朝向插值速度（越大转身越快）
@export var stats: character_stats             # 玩家角色的属性数据卡
@export var dash_speed: float = 15.0           # 冲刺时的水平速度
@export var dash_duration: float = 0.2         # 冲刺持续时间（秒）
@export var dash_cooldown: float = 0.5         # 冲刺冷却时间（秒）

# 摄像机吊臂（上面挂着 Camera3D，用来确定“前后左右”）
@onready var spring_arm: SpringArm3D = $SpringArm3D
@export_node_path("Camera3D") var camera_path: NodePath
@onready var camera: Camera3D = get_node_or_null(camera_path) as Camera3D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var visual_root: Node3D = $VisualRoot

# 使用项目设置中的 3D 默认重力
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var dash_time_remaining: float = 0.0
var dash_cooldown_remaining: float = 0.0

var attack_cooldown_remaining: float = 0.0
var overlapping_bodies: Array[Node3D] = []


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
	if stats:
		damage = stats.attack_power
		interval = stats.attack_interval

	var dealt_damage: bool = false
	for i in range(overlapping_bodies.size()):
		var body := overlapping_bodies[i]
		if not is_instance_valid(body):
			continue
		if not body.has_method("take_damage"):
			continue

		body.call("take_damage", damage)
		dealt_damage = true

	if dealt_damage:
		attack_cooldown_remaining = max(interval, 0.05)
		if animation_player:
			animation_player.play(&"attack")


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
