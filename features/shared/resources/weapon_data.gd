extends Resource
class_name WeaponData

@export var weapon_name: String = "Unnamed Weapon"
@export var damage: float = 10.0
@export var attack_speed: float = 1.0
@export var attack_range: float = 1.5

@export var weapon_mesh: Mesh # 武器的模型
@export var attack_animation_name: StringName = "attack" # 默认攻击动画名
@export var attack_animation_names: Array[StringName] = [] # 可选：多个攻击动作轮流播放
@export var hitbox_shape: Shape3D # 后面会用到的Hitbox形状
@export var hit_sound: AudioStream # 攻击命中时的音效
