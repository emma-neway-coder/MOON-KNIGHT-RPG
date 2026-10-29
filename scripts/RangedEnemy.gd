extends "res://scripts/Enemy.gd"
## 원거리(궁수): 플레이어와 7~9 m 거리를 유지하며 0.5초 조준 후 화살 한 발.
## 6 m(min_distance − 1)보다 가까우면 쏘지 않고 먼저 물러난다.

@export_group("원거리")
@export var arrow_scene: PackedScene
@export var min_distance: float = 7.0
@export var max_distance: float = 9.0
@export var arrow_forward: float = 0.5
@export var arrow_height: float = 0.8


func _can_start_attack(dist: float) -> bool:
	return dist >= min_distance - 1.0 and dist <= max_distance + 1.0


func _chase_velocity(to: Vector3, dist: float) -> Vector3:
	if dist < min_distance:
		return -to.normalized() * move_speed
	if dist > max_distance:
		return to.normalized() * move_speed
	return Vector3.ZERO


## 조준이 끝나는 순간의 플레이어 방향으로 직선 발사
func _do_attack(to: Vector3, _dist: float) -> void:
	if arrow_scene == null or to.length_squared() < 0.0001:
		return
	var dir := to.normalized()
	var a = arrow_scene.instantiate()
	a.damage = damage
	var root := get_tree().get_first_node_in_group("projectiles_root")
	if root == null:
		root = get_tree().current_scene
	a.position = global_position + dir * arrow_forward + Vector3.UP * arrow_height
	root.add_child(a)
	a.launch(dir)
	a.reset_physics_interpolation()
