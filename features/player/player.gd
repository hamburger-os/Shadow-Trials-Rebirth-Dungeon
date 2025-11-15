extends CharacterBody3D

# ===== 可在 Inspector 中调整的参数 =====
@export var speed: float = 5.0                 # 水平移动速度
@export var jump_velocity: float = 7.5         # 起跳时给予的向上速度
@export var rotate_to_movement: bool = true    # 是否自动朝向移动方向
@export var turn_speed: float = 10.0           # 朝向插值速度（越大转身越快）
@export var click_ray_length: float = 1000.0   # 鼠标点击射线长度
@export var ai_arrive_tolerance: float = 0.25  # AI 导航到达判定半径
@export var click_effect_scene: PackedScene    # 点击地面时播放的特效
@export var stats: character_stats             # 玩家角色的属性数据卡

# 摄像机吊臂（上面挂着 Camera3D，用来确定“前后左右”）
@onready var spring_arm: SpringArm3D = $SpringArm3D
@export_node_path("Camera3D") var camera_path: NodePath
@onready var camera: Camera3D = get_node_or_null(camera_path) as Camera3D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var visual_root: Node3D = $VisualRoot

# 使用项目设置中的 3D 默认重力
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var ai_has_target: bool = false
var ai_target_position: Vector3 = Vector3.ZERO
var is_attacking: bool = false


func _input(event: InputEvent) -> void:
	if is_attacking:
		return

	# 鼠标右键点击，发射一条从摄像机出发的射线，命中点作为 AI 导航目标
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if Input.is_action_just_pressed("player_attack"): # 鼠标默认左键
			_handle_attack_click(mouse_event.position)
		elif Input.is_action_just_pressed("move"): # 鼠标默认右键
			_handle_mouse_click(mouse_event.position)


func _handle_mouse_click(screen_pos: Vector2) -> void:
	var cam: Camera3D = camera
	if cam == null:
		cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var to: Vector3 = from + cam.project_ray_normal(screen_pos) * click_ray_length

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return

	var hit_position: Vector3 = result.position
	var to_target: Vector3 = hit_position - global_transform.origin
	to_target.y = 0.0

	if to_target.length_squared() > 0.0001:
		var target_yaw: float = atan2(to_target.x, to_target.z)
		if visual_root:
			visual_root.rotation.y = target_yaw

	ai_target_position = hit_position
	ai_has_target = true

	_spawn_click_effect(ai_target_position)


func _handle_attack_click(screen_pos: Vector2) -> void:
	if is_attacking:
		return

	var cam: Camera3D = camera
	if cam == null:
		cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var to: Vector3 = from + cam.project_ray_normal(screen_pos) * click_ray_length

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return

	var hit_position: Vector3 = result.position
	var to_target: Vector3 = hit_position - global_transform.origin
	to_target.y = 0.0

	if to_target.length_squared() > 0.0001:
		var target_yaw: float = atan2(to_target.x, to_target.z)
		if visual_root:
			visual_root.rotation.y = target_yaw

	ai_has_target = false
	velocity.x = 0.0
	velocity.z = 0.0

	is_attacking = true
	if animation_player:
		animation_player.play(&"attack")


func _spawn_click_effect(world_position: Vector3) -> void:
	if click_effect_scene == null:
		return

	var effect_instance := click_effect_scene.instantiate() as Node3D
	if effect_instance == null:
		return

	var root := get_tree().current_scene
	if root == null:
		return

	root.add_child(effect_instance)
	effect_instance.global_position = world_position

	var anim_player := effect_instance.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim_player:
		anim_player.play(&"spawn_and_fade")


func _physics_process(delta: float) -> void:
	# 当前速度，从 CharacterBody3D 自带的 velocity 拷贝一份出来修改
	var vel: Vector3 = velocity

	# 1. 重力：不在地面上时持续向下加速度
	if not is_on_floor():
		vel.y -= gravity * delta

	# 攻击时锁定水平移动，但仍应用重力
	if is_attacking:
		vel.x = move_toward(vel.x, 0.0, speed)
		vel.z = move_toward(vel.z, 0.0, speed)
		velocity = vel
		move_and_slide()
		return

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
		# 有键盘/手柄输入时，优先使用玩家输入，并打断 AI 导航
		ai_has_target = false
		# Input.get_vector 的 y 向下为正，所以这里取反：
		#   上键：input_dir.y = -1 → 向前
		#   下键：input_dir.y =  1 → 向后
		direction = forward * -input_dir.y + right * input_dir.x
	elif ai_has_target:
		# 没有键盘/手柄输入时，使用 AI 导航方向（朝向目标点）
		var to_target: Vector3 = ai_target_position - global_transform.origin
		to_target.y = 0.0
		if to_target.length_squared() > ai_arrive_tolerance * ai_arrive_tolerance:
			direction = to_target.normalized()
		else:
			ai_has_target = false

	# 4. 根据输入设置水平速度；没有输入时做简单减速
	if direction != Vector3.ZERO:
		direction = direction.normalized()
		vel.x = direction.x * speed
		vel.z = direction.z * speed

		# 可选：让角色缓慢转向当前移动方向
		if rotate_to_movement:
			var target_yaw: float = atan2(direction.x, direction.z)
			if visual_root:
				visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw, turn_speed * delta)
	else:
		vel.x = move_toward(vel.x, 0.0, speed)
		vel.z = move_toward(vel.z, 0.0, speed)

	# 5. 跳跃：角色在地面上并按下 move_jump（键盘默认空格 / 手柄默认 A / ✕）
	if is_on_floor() and Input.is_action_just_pressed("move_jump"):
		vel.y = jump_velocity

	# 6. 把计算好的速度写回并执行移动与碰撞
	velocity = vel
	move_and_slide()


func _on_hitbox_body_entered(body: Node3D) -> void:
	if not is_attacking:
		return

	if body and body.has_method("take_damage"):
		body.call("take_damage", 20)


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"attack":
		is_attacking = false
