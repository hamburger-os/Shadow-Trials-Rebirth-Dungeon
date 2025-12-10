extends Resource
class_name CharacterData

@export var model_scene: PackedScene
@export var animation_player_path: NodePath = NodePath("")
@export var weapon_socket_path: NodePath = NodePath("")
@export var visual_transform: Transform3D = Transform3D.IDENTITY

@export var stats: CharacterStats
@export var move_speed: float = 5.0
@export var rotate_to_movement: bool = true
@export var turn_speed: float = 10.0
@export var dash_speed: float = 15.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 0.5
@export var respawn_delay: float = 0.5

# 动画名
@export var anim_idle: StringName = "default/Idle_A"
@export var anim_run: StringName = "default/Walking_A"
@export var anim_dash: StringName = "default/Running_A"
@export var anim_attack: StringName = "default/Melee_Unarmed_Attack_Punch_A"
@export var anim_die: StringName = "default/Death_A"
@export var anim_spawn: StringName = "" # 敌人常用
@export var anim_hit: StringName = "default/Hit_B"   # 敌人常用
@export var attack_animation_sequence: Array[StringName] = []

# 音效
@export var sfx_attack: AudioStream
@export var sfx_hurt: AudioStream
@export var sfx_die: AudioStream

# 武器
@export var weapon_scene: PackedScene
@export var weapon_data: WeaponData
