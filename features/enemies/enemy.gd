extends CharacterBody3D

# ===== 可在 Inspector 中调整的参数 =====
@export var stats: character_stats             # 玩家角色的属性数据卡

func _ready():
    # 安全检查，确保我们没有忘记在编辑器里分配 Stats
    if not stats:
        push_error("character %s 没有分配 character_stats!" % name)
        return

    # 订阅 "health_changed" 信号，但我们先不实现 UI
    # stats.health_changed.connect(_on_health_changed)


func take_damage(damage_amount: int):
    if not stats:
        return

    print("%s 受到 %s 点伤害" % [name, damage_amount])
    stats.current_health -= damage_amount

    if stats.current_health <= 0:
        die()

func die():
    print("%s 死亡!" % name)
    queue_free() # 节点自毁

