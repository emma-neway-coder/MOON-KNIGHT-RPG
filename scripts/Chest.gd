extends Node3D
## 보물상자. 플레이어가 TriggerArea(반경 2 m)에 들어오면 open 애니메이션을 한 번만 재생한다.
## 모델(export/chest.glb)은 Blender에서 만들었고, 뚜껑 원점이 경첩 자리라 그 축으로 열린다.

signal opened

@export var anim_name: StringName = &"open"

var is_open := false
var _anim: AnimationPlayer

@onready var _area: Area3D = $TriggerArea


func _ready() -> void:
	# glb 인스턴스 안의 노드는 이 씬이 소유하지 않으므로 owned = false로 찾는다
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		push_warning("Chest: AnimationPlayer를 찾지 못했습니다.")
	_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if is_open or not body.is_in_group("player"):
		return
	is_open = true
	if _anim and _anim.has_animation(anim_name):
		_anim.play(anim_name)
	else:
		push_warning("Chest: '%s' 애니메이션이 없습니다." % anim_name)
	opened.emit()
	# 한 번 열린 뒤에는 더 감지하지 않는다
	_area.set_deferred("monitoring", false)
