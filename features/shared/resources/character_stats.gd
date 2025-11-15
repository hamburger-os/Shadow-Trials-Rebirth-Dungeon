@tool # 这个 @tool 关键字能让它在 Godot 编辑器中实时显示数据
extends Resource
class_name character_stats

# 信号：当血量变化时发出（比如用于更新 UI 血条）
signal health_changed(current_health, max_health)

# --- 基础属性 ---
@export var max_health: int = 100:
    set(value):
        max_health = value
        # 确保当前血量不会超过新的最大血量
        if current_health > max_health:
            current_health = max_health
        emit_signal("health_changed", current_health, max_health)

@export var attack_power: int = 10

# --- 运行时变量 ---
var current_health: int:
    set(value):
        # "clamp" 函数确保血量不会低于 0 或高于 max_health
        current_health = clamp(value, 0, max_health)
        emit_signal("health_changed", current_health, max_health)


# 当这个资源被创建时，自动设置满血量
func _init():
    current_health = max_health

