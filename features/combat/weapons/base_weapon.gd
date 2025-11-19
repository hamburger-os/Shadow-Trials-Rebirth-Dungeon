extends Node3D

@export var weapon_data: WeaponData

@onready var hitbox: Area3D = $Hitbox
@onready var collision_shape: CollisionShape3D = $Hitbox/CollisionShape3D
@onready var mesh_instance: MeshInstance3D = $Mesh

var _owner_player: CharacterBody3D


func _ready() -> void:
	_owner_player = _find_owner_player()
	_apply_weapon_data()


func _find_owner_player() -> CharacterBody3D:
	var node: Node = self
	while node:
		if node is CharacterBody3D:
			return node as CharacterBody3D
		node = node.get_parent()
	return null


func _apply_weapon_data() -> void:
	if not weapon_data:
		return

	if mesh_instance and weapon_data.weapon_mesh:
		mesh_instance.mesh = weapon_data.weapon_mesh

	if collision_shape and weapon_data.hitbox_shape:
		collision_shape.shape = weapon_data.hitbox_shape


func _on_hitbox_body_entered(body: Node3D) -> void:
	if _owner_player and _owner_player.has_method("_on_hitbox_body_entered"):
		_owner_player.call("_on_hitbox_body_entered", body)


func _on_hitbox_body_exited(body: Node3D) -> void:
	if _owner_player and _owner_player.has_method("_on_hitbox_body_exited"):
		_owner_player.call("_on_hitbox_body_exited", body)
