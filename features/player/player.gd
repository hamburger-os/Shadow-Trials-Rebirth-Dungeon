extends CharacterBody3D

# ===== 可在 Inspector 中调整的参数 =====
@export var speed: float = 5.0                 # 水平移动速度
@export var jump_velocity: float = 7.5         # 起跳时给予的向上速度
@export var rotate_to_movement: bool = false   # 是否自动朝向移动方向
@export var turn_speed: float = 10.0           # 朝向插值速度（越大转身越快）

# 摄像机吊臂（上面挂着 Camera3D，用来确定“前后左右”）
@onready var spring_arm: SpringArm3D = $SpringArm3D

# 使用项目设置中的 3D 默认重力
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _physics_process(delta: float) -> void:
    # 当前速度，从 CharacterBody3D 自带的 velocity 拷贝一份出来修改
    var vel: Vector3 = velocity

    # 1. 重力：不在地面上时持续向下加速度
    if not is_on_floor():
        vel.y -= gravity * delta

    # 2. 获取输入（键盘方向键 / 手柄左摇杆）
    # Input.get_vector: x = right - left, y = down - up
    var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

    # 3. 基于摄像机朝向计算“前/后/左/右”的 3D 方向
    var forward: Vector3 = -spring_arm.global_transform.basis.z  # 摄像机朝向的前方
    var right: Vector3 = spring_arm.global_transform.basis.x     # 摄像机右方

    # 忽略 Y 分量，只在 XZ 平面移动
    forward.y = 0.0
    right.y = 0.0
    forward = forward.normalized()
    right = right.normalized()

    # Input.get_vector 的 y 向下为正，所以这里取反：
    #   上键：input_dir.y = -1 → 向前
    #   下键：input_dir.y =  1 → 向后
    var direction: Vector3 = forward * -input_dir.y + right * input_dir.x

    # 4. 根据输入设置水平速度；没有输入时做简单减速
    if direction != Vector3.ZERO:
        direction = direction.normalized()
        vel.x = direction.x * speed
        vel.z = direction.z * speed

        # 可选：让角色缓慢转向当前移动方向
        if rotate_to_movement:
            var target_yaw: float = atan2(direction.x, direction.z)
            rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)
    else:
        vel.x = move_toward(vel.x, 0.0, speed)
        vel.z = move_toward(vel.z, 0.0, speed)

    # 5. 跳跃：角色在地面上并按下 ui_accept（键盘默认空格 / 手柄默认 A / ✕）
    if is_on_floor() and Input.is_action_just_pressed("ui_accept"):
        vel.y = jump_velocity

    # 6. 把计算好的速度写回并执行移动与碰撞
    velocity = vel
    move_and_slide()
