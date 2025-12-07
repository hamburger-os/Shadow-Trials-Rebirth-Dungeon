extends Resource

@export var name: String
@export var scene: PackedScene
@export var sockets: Dictionary = {"N": "open", "E": "open", "S": "open", "W": "open"}
@export var height: int = 0
@export var weight: float = 1.0
@export var allow_rotation: bool = false
