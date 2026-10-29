extends CharacterBody3D
## 적 공통 스크립트: 체력, 상태 머신, 피격, 넉백, 사망.
## 근거리·원거리·덩치는 이 스크립트를 상속해 아래 가상 함수만 덮어쓴다.
##   _can_start_attack(dist)  공격을 시작할 거리인가
##   _chase_velocity(to, dist) 추적 중 이동 속도
##   _on_windup_start() / _on_windup_cancel()  예비 동작 시작·취소
##   _do_attack(to, dist)     예비 동작이 끝나는 순간의 공격

signal died(enemy: Node)

enum State { CHASE, WINDUP, RECOVER, DEAD }

const Steer = preload("res://scripts/Steer.gd")
const KNOCK_TIME := 0.15

@export_group("기본")
@export var max_health: int = 30
@export var move_speed: float = 3.5
@export var body_color: Color = Color(0.85, 0.2, 0.2)
## 예비 동작 중 색
@export var windup_color: Color = Color(1.0, 0.85, 0.2)
@export var body_radius: float = 0.35
@export var bar_height: float = 1.8
@export var knockback_immune: bool = false

@export_group("공격")
@export var attack_range: float = 1.2
## 예비 동작이 끝나는 순간 이 거리 밖이면 빗나간다
@export var hit_range: float = 1.6
@export var windup_time: float = 0.3
@export var attack_interval: float = 1.0
@export var damage: int = 10
@export var recover_time: float = 0.2

var health: int
var state: int = State.CHASE
var player  # Player.gd

var _state_timer := 0.0
var _cooldown := 0.0
var _flash_timer := 0.0
var _knock_velocity := Vector3.ZERO
var _knock_timer := 0.0
var _mat: StandardMaterial3D
var _bar: Node3D
var _bar_front: Sprite3D

@onready var _visual: Node3D = $Visual


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = body_color
	for c in _visual.get_children():
		var mi := c as MeshInstance3D
		if mi:
			mi.material_override = _mat
	_bar = Fx.make_health_bar()
	_bar.position = Vector3(0, bar_height, 0)
	_bar.visible = false  # 첫 피해를 입은 뒤부터 보인다
	add_child(_bar)
	_bar_front = _bar.get_node("Front")
	player = get_tree().get_first_node_in_group("player")


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if _flash_timer > 0.0:
		_flash_timer -= delta
		_update_color()

	# 플레이어가 쓰러지면 공격을 멈추고 제자리에 선다
	if player == null or player.dead:
		velocity = Vector3.ZERO
		if state == State.WINDUP:
			_on_windup_cancel()
		state = State.CHASE
		_update_color()
		return

	if _knock_timer > 0.0:
		_knock_timer -= delta
		Steer.move(self, _knock_velocity, delta)
		global_position.y = 0.0
		return

	var to: Vector3 = player.global_position - global_position
	to.y = 0.0
	var dist := to.length()

	match state:
		State.CHASE:
			if _cooldown <= 0.0 and _can_start_attack(dist):
				_start_windup()
			else:
				var desired := _chase_velocity(to, dist)
				if desired.length_squared() > 0.0:
					_face(desired)
				Steer.move(self, desired, delta)
		State.WINDUP:
			velocity = Vector3.ZERO
			_face(to)
			_state_timer -= delta
			if _state_timer <= 0.0:
				_do_attack(to, dist)
				_cooldown = attack_interval
				state = State.RECOVER
				_state_timer = recover_time
				_update_color()
		State.RECOVER:
			velocity = Vector3.ZERO
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = State.CHASE
	global_position.y = 0.0


# ---------- 가상 함수(종류별 스크립트가 덮어씀) ----------

func _can_start_attack(dist: float) -> bool:
	return dist <= attack_range


func _chase_velocity(to: Vector3, dist: float) -> Vector3:
	if dist <= attack_range * 0.9:
		return Vector3.ZERO
	return to.normalized() * move_speed


func _on_windup_start() -> void:
	pass


func _on_windup_cancel() -> void:
	pass


func _do_attack(_to: Vector3, dist: float) -> void:
	if dist <= hit_range:
		player.take_damage(damage, global_position)


# ---------- 공통 ----------

func _start_windup() -> void:
	state = State.WINDUP
	_state_timer = windup_time
	_update_color()
	_on_windup_start()


func _face(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	rotation.y = atan2(-dir.x, -dir.z)


func _update_color() -> void:
	if _flash_timer > 0.0:
		_mat.albedo_color = Color.WHITE
	elif state == State.WINDUP:
		_mat.albedo_color = windup_color
	else:
		_mat.albedo_color = body_color


func take_damage(amount: int, from_position: Vector3 = Vector3.ZERO, knockback: float = 0.0) -> void:
	if state == State.DEAD:
		return
	health -= amount
	_flash_timer = 0.1
	_bar.visible = true
	var ratio := clampf(float(health) / max_health, 0.0, 1.0)
	_bar_front.region_rect = Rect2(0, 0, 100.0 * ratio, 12.0)
	_bar_front.visible = ratio > 0.0
	if health <= 0:
		_die()
		return
	if knockback > 0.0 and not knockback_immune:
		var dir := global_position - from_position
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			_knock_velocity = dir.normalized() * (knockback / KNOCK_TIME)
			_knock_timer = KNOCK_TIME
			# 넉백으로 밀려나면 하던 예비 동작이 끊기고 추적으로 돌아간다
			if state == State.WINDUP:
				_on_windup_cancel()
			state = State.CHASE
	_update_color()


func _die() -> void:
	if state == State.WINDUP:
		_on_windup_cancel()
	state = State.DEAD
	remove_from_group("enemies")
	velocity = Vector3.ZERO
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	_bar.visible = false
	died.emit(self)
	var t := create_tween()
	t.tween_property(_visual, "scale", Vector3.ONE * 0.05, 0.3)
	t.tween_callback(queue_free)
