extends Area3D
## 직선 투사체. 매직 미사일(MagicMissile.tscn)과 적 화살(EnemyArrow.tscn)이 같이 쓴다.
## 처음 맞은 대상 하나에 피해를 주고 사라진다. 나무·벽에 닿거나 최대 거리를 날면 사라진다.

@export var speed: float = 12.0
@export var damage: int = 15
@export var max_distance: float = 12.0
## 피해를 줄 대상 그룹("enemies" 또는 "player")
@export var target_group: StringName = &"enemies"
@export var hit_color: Color = Color(0.6, 0.9, 1.0, 0.9)

var direction := Vector3.FORWARD
var _travelled := 0.0
var _done := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func launch(dir: Vector3) -> void:
	direction = dir.normalized()
	look_at(global_position + direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	if _done:
		return
	var step := direction * speed * delta
	global_position += step
	_travelled += step.length()
	if _travelled >= max_distance:
		queue_free()


func _on_body_entered(body) -> void:
	if _done:
		return
	if body.is_in_group(target_group):
		body.take_damage(damage, global_position - direction)
	elif not body is StaticBody3D:
		return
	_done = true
	Fx.puff(global_position, hit_color)
	queue_free()
