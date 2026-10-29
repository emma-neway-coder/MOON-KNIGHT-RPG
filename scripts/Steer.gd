extends RefCounted
## 플레이어와 적이 같이 쓰는 이동 도우미.
## move_and_slide()로 미끄러지듯 비켜가고, 나무에 정면으로 막혀 거의 못 움직이면 옆으로 살짝 틀어 다시 움직인다.

static func move(body: CharacterBody3D, desired: Vector3, delta: float) -> void:
	body.velocity = desired
	var start := body.global_position
	body.move_and_slide()
	if desired.length_squared() < 0.0001:
		return
	var moved := body.global_position - start
	moved.y = 0.0
	if moved.length() >= desired.length() * delta * 0.3:
		return
	if body.get_slide_collision_count() == 0:
		return
	var n := body.get_slide_collision(0).get_normal()
	n.y = 0.0
	if n.length_squared() < 0.0001:
		return
	n = n.normalized()
	var side := n.cross(Vector3.UP)
	if side.dot(desired) < 0.0:
		side = -side
	body.velocity = (side * 0.85 + n * 0.15).normalized() * desired.length()
	body.move_and_slide()
