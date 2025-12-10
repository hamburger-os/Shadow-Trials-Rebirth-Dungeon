@tool
extends EditorScript

# 把 KayKit Rig_Medium 的多个 GLB 动作合并成一个 AnimationLibrary 资源。
# 使用方式：在 Godot 编辑器中打开项目，执行“文件 > 运行…”选择本脚本，或在脚本编辑器点击“运行”。

const SOURCE_DIR := "res://assets/animations/KayKit_Character_Animations_1.0/Animations/gltf/Rig_Medium"
const OUTPUT_PATH := "res://assets/animations/KayKit_Character_Animations_Rig_Medium.tres"
const LOOP_ANIMS := [
	"Idle_A", "Idle_B", "Jump_Idle", "Lie_Idle",
	"Melee_2H_Idle", "Melee_Unarmed_Idle",
	"Ranged_Bow_Aiming_Idle", "Ranged_Bow_Idle",
	"Running_A", "Running_B", "Running_HoldingBow", "Running_HoldingRifle",
	"Running_Strafe_Left", "Running_Strafe_Right",
	"Skeletons_Idle", "Skeletons_Walking",
	"Walking_A", "Walking_B", "Walking_Backwards", "Walking_C",
	"Sit_Chair_Idle", "Sit_Floor_Idle"
]

func _run() -> void:
	var lib := AnimationLibrary.new()
	var dir := DirAccess.open(SOURCE_DIR)
	if dir == null:
		push_error("无法打开目录: %s" % SOURCE_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	var added := 0
	while file_name != "":
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".glb"):
			var scene_path := "%s/%s" % [SOURCE_DIR, file_name]
			_add_animations_from_scene(scene_path, lib)
		file_name = dir.get_next()
	dir.list_dir_end()

	var err := ResourceSaver.save(lib, OUTPUT_PATH)
	if err != OK:
		push_error("保存 AnimationLibrary 失败: %s" % err)
	else:
		print("生成完成，写入: %s" % OUTPUT_PATH)


func _add_animations_from_scene(scene_path: String, lib: AnimationLibrary) -> void:
	var packed := load(scene_path) as PackedScene
	if not packed:
		push_warning("无法加载场景: %s" % scene_path)
		return

	var inst := packed.instantiate()
	if not inst:
		push_warning("无法实例化: %s" % scene_path)
		return

	var players := inst.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_warning("未找到 AnimationPlayer: %s" % scene_path)
		return

	for player in players:
		player = player as AnimationPlayer
		for anim_name in player.get_animation_list():
			if anim_name == "" or anim_name == "T-Pose":
				continue
			var new_name: String = anim_name
			# 如果重名，则加上文件名前缀避免覆盖
			if lib.has_animation(new_name):
				var prefix: String = scene_path.get_file().get_basename()
				new_name = "%s/%s" % [prefix, anim_name]
			var anim: Animation = player.get_animation(anim_name)
			if anim:
				if LOOP_ANIMS.has(new_name):
					anim.loop_mode = Animation.LOOP_LINEAR
					anim.loop = true
				lib.add_animation(new_name, anim.duplicate())
