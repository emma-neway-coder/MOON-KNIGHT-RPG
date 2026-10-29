extends Node
## 웨이브 진행. 구성표대로 스폰 지점에서 적을 0.5초 간격으로 하나씩 내보내고,
## 전멸하면 3초 쉬고 다음 웨이브, 마지막 웨이브를 넘기면 all_waves_cleared.

signal wave_started(wave: int, total: int)
signal remaining_changed(remaining: int)
signal all_waves_cleared

enum Phase { WAITING, SPAWNING, FIGHTING, RESTING, DONE }

## 웨이브 구성표: x = 근거리, y = 원거리, z = 덩치 마릿수
@export var waves: Array[Vector3i] = [Vector3i(6, 0, 0), Vector3i(6, 3, 0), Vector3i(6, 4, 2)]
@export var melee_scene: PackedScene
@export var ranged_scene: PackedScene
@export var brute_scene: PackedScene
@export var spawn_points_path: NodePath
@export var enemies_path: NodePath
@export var first_delay: float = 1.0
@export var spawn_interval: float = 0.5
@export var rest_time: float = 3.0
@export var min_spawn_distance: float = 10.0

var phase: int = Phase.WAITING
var current_wave := 0
## 남은 적 = 아직 안 나온 적 + 살아 있는 적
var remaining := 0
var kills := 0
var elapsed := 0.0

var _timer := 0.0
var _queue: Array[PackedScene] = []
var _player


func _ready() -> void:
	add_to_group("wave_manager")
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.died.connect(_on_player_died)
	_timer = first_delay


func _physics_process(delta: float) -> void:
	if phase == Phase.DONE:
		return
	elapsed += delta
	match phase:
		Phase.WAITING, Phase.RESTING:
			_timer -= delta
			if _timer <= 0.0:
				_start_wave(current_wave + 1)
		Phase.SPAWNING:
			_timer -= delta
			if _timer <= 0.0:
				_spawn(_queue.pop_front())
				_timer = spawn_interval
				if _queue.is_empty():
					phase = Phase.FIGHTING


func _start_wave(n: int) -> void:
	current_wave = n
	var w := waves[n - 1]
	_queue.clear()
	for i in w.x:
		_queue.append(melee_scene)
	for i in w.y:
		_queue.append(ranged_scene)
	for i in w.z:
		_queue.append(brute_scene)
	_queue.shuffle()  # 종류를 섞어서 내보낸다
	remaining = _queue.size()
	phase = Phase.SPAWNING
	_timer = 0.0
	wave_started.emit(n, waves.size())
	remaining_changed.emit(remaining)
	if remaining == 0:
		_on_wave_cleared()


func _spawn(scene: PackedScene) -> void:
	if scene == null:
		_count_down()
		return
	var e = scene.instantiate()
	e.position = _pick_spawn_point()  # Enemies 노드가 원점이라 position = 월드 위치
	get_node(enemies_path).add_child(e)
	e.reset_physics_interpolation()
	e.died.connect(_on_enemy_died)


## 플레이어와 10 m 이상 떨어진 스폰 지점 중 무작위. 없으면 가장 먼 곳.
func _pick_spawn_point() -> Vector3:
	var far_enough: Array[Vector3] = []
	var best := Vector3.ZERO
	var best_dist := -1.0
	var player_pos := Vector3.ZERO
	if _player:
		player_pos = _player.global_position
	for child in get_node(spawn_points_path).get_children():
		var m := child as Node3D
		if m == null:
			continue
		var d := m.global_position.distance_to(player_pos)
		if d >= min_spawn_distance:
			far_enough.append(m.global_position)
		if d > best_dist:
			best_dist = d
			best = m.global_position
	if far_enough.is_empty():
		return best
	return far_enough.pick_random()


func _on_enemy_died(_enemy: Node) -> void:
	kills += 1
	_count_down()


func _count_down() -> void:
	remaining = maxi(0, remaining - 1)
	remaining_changed.emit(remaining)
	if remaining == 0 and _queue.is_empty() and phase != Phase.DONE:
		_on_wave_cleared()


func _on_wave_cleared() -> void:
	if current_wave >= waves.size():
		phase = Phase.DONE
		all_waves_cleared.emit()
	else:
		phase = Phase.RESTING
		_timer = rest_time


func _on_player_died() -> void:
	phase = Phase.DONE
