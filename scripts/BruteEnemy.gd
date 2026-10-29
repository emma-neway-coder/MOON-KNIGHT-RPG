extends "res://scripts/Enemy.gd"
## 덩치: 느리게 쫓아와 2 m 안에 들면 0.8초 동안 바닥 경고 원을 보여준 뒤 반경 2.5 m 내려찍기.
## 넉백을 받지 않는다(knockback_immune). 원 밖에 있으면 맞지 않는다.

@export_group("덩치")
@export var slam_radius: float = 2.5

var _warning: Node3D


func _on_windup_start() -> void:
	_clear_warning()
	_warning = Fx.warning(global_position, slam_radius, windup_time)


func _on_windup_cancel() -> void:
	_clear_warning()


func _do_attack(_to: Vector3, dist: float) -> void:
	_clear_warning()
	Fx.ring(global_position, Color(1.0, 0.3, 0.3, 0.7), slam_radius)
	if dist <= slam_radius:
		player.take_damage(damage, global_position)


func _clear_warning() -> void:
	if is_instance_valid(_warning):
		_warning.queue_free()
	_warning = null


func _exit_tree() -> void:
	_clear_warning()
