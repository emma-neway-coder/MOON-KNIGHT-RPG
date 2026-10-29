extends Node3D
## 쿼터뷰 카메라 받침대. 플레이어 위치를 부드럽게 따라간다(물리 보간 때문에 _physics_process에서 움직인다).

@export var target_path: NodePath
@export var follow_speed: float = 6.0

var _target: Node3D


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target:
		global_position = _target.global_position
		reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var w := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(_target.global_position, w)
