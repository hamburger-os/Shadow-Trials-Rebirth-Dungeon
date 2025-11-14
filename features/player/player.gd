extends CharacterBody3D

# 导出变量，会显示在检查器中，方便调整
@export var speed: float = 5.0
@export var jump_velocity: float = 7.5

# 从项目设置中获取默认重力
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _physics_process(delta):
    # 获取当前的 'velocity' 向量（CharacterBody3D 的内置属性）
    var vel = velocity

    # 1. 应用重力
    # 检查是否在地面上
    if not is_on_floor():
        vel.y -= gravity * delta

    # 2. 获取键盘输入（方向键，对应 ui_left/right/up/down）
    # 这会返回一个 2D 向量，例如按上键是 (0, -1)，按左键是 (-1, 0)
    var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

    # 3. 计算 3D 移动方向
    # 我们将 2D 输入的 x 和 y 映射到 3D 空间的 x 和 z
    var direction = Vector3(input_dir.x, 0, input_dir.y).normalized()

    # 4. 跳跃逻辑 + 应用速度
    if direction:
        # 如果有输入，设置水平速度
        vel.x = direction.x * speed
        vel.z = direction.z * speed

        # 额外加分：让角色转向移动方向
        # 使用 atan2 (反正切) 计算 Y 轴的旋转角度
        rotation.y = atan2(direction.x, direction.z)

    else:
        # 如果没有输入，慢慢停下（模拟摩擦力）
        vel.x = move_toward(vel.x, 0, speed)
        vel.z = move_toward(vel.z, 0, speed)

    # 5. 跳跃：在地面上且按下 ui_accept（默认空格）
    if is_on_floor() and Input.is_action_just_pressed("ui_accept"):
        vel.y = jump_velocity

    # 6. 执行移动
    # 将计算好的速度设置回 CharacterBody3D
    set_velocity(vel)
    # 调用 move_and_slide() 来实际移动并处理碰撞
    move_and_slide()
    
