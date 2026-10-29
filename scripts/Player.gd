extends CharacterBody3D
## 플레이어(마법사). 좌클릭·WASD 이동, 우클릭 근접 공격, Q 매직 미사일, Space 순간이동.
## 공격은 모두 마우스 커서 방향으로 나가고, 마나 없이 쿨다운으로만 제한한다.

signal died
signal health_changed(current: int, maximum: int)

const Steer = preload("res://scripts/Steer.gd")

@export_group("이동")
@export var move_speed: float = 5.0
@export var stop_distance: float = 0.2
## 맵 반 폭(벽 안쪽 20 m에서 몸 두께만큼 뺀 값)
@export var map_half_size: float = 19.5

@export_group("체력")
@export var max_health: int = 100
@export var hit_invuln_time: float = 0.5

@export_group("근접 공격")
@export var melee_damage: int = 20
@export var melee_range: float = 1.8
@export var melee_angle: float = 90.0
@export var melee_knockback: float = 1.0
@export var melee_cooldown: float = 0.4

@export_group("매직 미사일")
@export var missile_scene: PackedScene
@export var missile_cooldown: float = 0.6
@export var missile_forward: float = 0.5
@export var missile_height: float = 1.0

@export_group("순간이동")
@export var teleport_distance: float = 4.0
@export var teleport_invuln: float = 0.3
@export var teleport_cooldown: float = 3.0

@export_group("공격 중 정지")
@export var attack_pause: float = 0.15

var health: int
var dead := false
var cooldowns := {"melee": 0.0, "missile": 0.0, "teleport": 0.0}

var _target := Vector3.ZERO
var _has_target := false
var _wait_new_click := false
var _pause_timer := 0.0
var _invuln_timer := 0.0
var _blink_timer := 0.0

@onready var _visual: Node3D = $Visual
@onready var _shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group("player")
	health = max_health
	health_changed.emit(health, max_health)
	Fx.prewarm.call_deferred(global_position)


func get_cooldown(skill: String) -> float:
	return cooldowns[skill]


func get_cooldown_max(skill: String) -> float:
	match skill:
		"melee":
			return melee_cooldown
		"missile":
			return missile_cooldown
	return teleport_cooldown


func _physics_process(delta: float) -> void:
	for k in cooldowns.keys():
		cooldowns[k] = maxf(0.0, cooldowns[k] - delta)
	_invuln_timer = maxf(0.0, _invuln_timer - delta)
	if _blink_timer > 0.0:
		_blink_timer -= delta
		_visual.visible = _blink_timer <= 0.0 or int(_blink_timer * 20.0) % 2 == 0
	if dead:
		velocity = Vector3.ZERO
		return
	var cursor = _cursor_point()  # Vector3, 커서가 바닥 밖이면 null
	_handle_actions(cursor)
	_handle_move(cursor, delta)


# ---------- 입력 ----------

## 카메라에서 마우스 위치로 광선을 쏴 바닥 평면(y = 0)과 만나는 점
func _cursor_point() -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)


func _handle_actions(cursor: Variant) -> void:
	if cursor == null:
		return
	var aim: Vector3 = cursor - global_position
	aim.y = 0.0
	if aim.length_squared() < 0.0001:
		aim = -global_basis.z
		aim.y = 0.0
	aim = aim.normalized()
	if Input.is_action_pressed("attack_melee") and cooldowns["melee"] <= 0.0:
		_melee(aim)
	if Input.is_action_pressed("cast_missile") and cooldowns["missile"] <= 0.0:
		_cast_missile(aim)
	if Input.is_action_just_pressed("teleport") and cooldowns["teleport"] <= 0.0:
		_teleport(cursor)


func _handle_move(cursor: Variant, delta: float) -> void:
	# 공격 뒤 누르고 있던 좌클릭은 무시하고, 새로 누른 클릭부터 다시 걷는다
	if Input.is_action_just_pressed("move"):
		_wait_new_click = false
		if cursor != null:
			Fx.click(_clamp_to_map(cursor))
	if not Input.is_action_pressed("move"):
		_wait_new_click = false

	if _pause_timer > 0.0:
		_pause_timer -= delta
		velocity = Vector3.ZERO
		return

	if Input.is_action_pressed("move") and not _wait_new_click and cursor != null:
		_target = _clamp_to_map(cursor)
		_has_target = true

	var desired := Vector3.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input.length_squared() > 0.0:
		# WASD는 화면 기준: W = 화면 위쪽, D = 화면 오른쪽
		_has_target = false
		var cam := get_viewport().get_camera_3d()
		var right := cam.global_basis.x
		right.y = 0.0
		var up := -cam.global_basis.z
		up.y = 0.0
		desired = right.normalized() * input.x + up.normalized() * -input.y
		if desired.length() > 1.0:
			desired = desired.normalized()
		desired *= move_speed
	elif _has_target:
		var to := _target - global_position
		to.y = 0.0
		if to.length() <= stop_distance:
			_has_target = false
		else:
			desired = to.normalized() * move_speed

	if desired.length_squared() > 0.0:
		_face(desired)
	Steer.move(self, desired, delta)
	global_position.y = 0.0


func _clamp_to_map(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, -map_half_size, map_half_size), 0.0, clampf(p.z, -map_half_size, map_half_size))


func _face(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	rotation.y = atan2(-dir.x, -dir.z)


# ---------- 동작 ----------

## 근접 공격과 미사일 공통: 멈추고 커서 쪽으로 돌아선 뒤 잠깐 제자리에 선다
func _begin_attack(aim: Vector3) -> void:
	_face(aim)
	_pause_timer = attack_pause
	_has_target = false
	_wait_new_click = true


func _melee(aim: Vector3) -> void:
	_begin_attack(aim)
	cooldowns["melee"] = melee_cooldown
	var half := deg_to_rad(melee_angle) * 0.5
	for node in get_tree().get_nodes_in_group("enemies"):
		var e = node
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var reach: float = melee_range + float(e.body_radius)
		if to.length() > reach:
			continue
		if to.length() > 0.01 and aim.angle_to(to) > half:
			continue
		e.take_damage(melee_damage, global_position, melee_knockback)
	Fx.fan(global_position, aim, melee_range, melee_angle)


func _cast_missile(aim: Vector3) -> void:
	_begin_attack(aim)
	cooldowns["missile"] = missile_cooldown
	if missile_scene == null:
		return
	var m = missile_scene.instantiate()
	var root := get_tree().get_first_node_in_group("projectiles_root")
	if root == null:
		root = get_tree().current_scene
	m.position = global_position + aim * missile_forward + Vector3.UP * missile_height
	root.add_child(m)
	m.launch(aim)
	m.reset_physics_interpolation()


func _teleport(cursor: Vector3) -> void:
	var offset := cursor - global_position
	offset.y = 0.0
	if offset.length() > teleport_distance:
		offset = offset.normalized() * teleport_distance
	var dest := global_position + offset
	dest.y = 0.0
	# 도착점이 맵 밖이거나 나무·벽과 겹치면 발동하지 않고 쿨다운도 쓰지 않는다
	if absf(dest.x) > map_half_size or absf(dest.z) > map_half_size:
		return
	if not _is_free(dest):
		return
	Fx.ring(global_position)
	global_position = dest
	reset_physics_interpolation()
	if offset.length_squared() > 0.0001:
		_face(offset)
	_has_target = false
	_invuln_timer = maxf(_invuln_timer, teleport_invuln)
	cooldowns["teleport"] = teleport_cooldown
	Fx.ring(dest)


## 플레이어 몸(캡슐)을 그 자리에 놓았을 때 world 레이어와 겹치지 않는지
func _is_free(dest: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape.shape
	q.transform = Transform3D(Basis(), dest + _shape.position)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


# ---------- 피격·사망 ----------

func take_damage(amount: int, _from_position: Vector3 = Vector3.ZERO, _knockback: float = 0.0) -> void:
	if dead or _invuln_timer > 0.0:
		return
	health = maxi(0, health - amount)
	_invuln_timer = hit_invuln_time
	_blink_timer = hit_invuln_time
	health_changed.emit(health, max_health)
	if health <= 0:
		_die()


func _die() -> void:
	dead = true
	_blink_timer = 0.0
	_visual.visible = true
	var gray := StandardMaterial3D.new()
	gray.albedo_color = Color(0.5, 0.5, 0.5)
	for c in _visual.get_children():
		var mi := c as MeshInstance3D
		if mi:
			mi.material_override = gray
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_visual, "rotation:z", deg_to_rad(90.0), 0.4)
	t.tween_property(_visual, "position:y", 0.4, 0.4)
	died.emit()
