extends Node
## 이펙트 모음(오토로드 이름: Fx).
## 메시·머티리얼은 한 번만 만들어 재사용하고, 사라지는 효과는 인스턴스별 transparency로 준다.

const CLICK_COLOR := Color(1.0, 1.0, 1.0, 0.8)
const FAN_COLOR := Color(0.75, 0.9, 1.0, 0.45)
const TELEPORT_COLOR := Color(0.3, 0.6, 1.0, 0.8)
const WARNING_BASE_COLOR := Color(1.0, 0.1, 0.1, 0.22)
const WARNING_FILL_COLOR := Color(1.0, 0.1, 0.1, 0.5)

var _ring_mesh: TorusMesh
var _disc_mesh: CylinderMesh
var _puff_mesh: SphereMesh
var _fan_meshes := {}
var _mats := {}
var _bar_tex: ImageTexture


func _ready() -> void:
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.8
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 32
	_ring_mesh.ring_segments = 6
	_disc_mesh = CylinderMesh.new()
	_disc_mesh.top_radius = 1.0
	_disc_mesh.bottom_radius = 1.0
	_disc_mesh.height = 0.02
	_disc_mesh.radial_segments = 48
	_disc_mesh.rings = 1
	_puff_mesh = SphereMesh.new()
	_puff_mesh.radius = 0.5
	_puff_mesh.height = 1.0
	_puff_mesh.radial_segments = 12
	_puff_mesh.rings = 6
	var img := Image.create_empty(100, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_bar_tex = ImageTexture.create_from_image(img)


# ---------- 공개 함수 ----------

## 좌클릭한 바닥에 작은 원(0.3초)
func click(pos: Vector3) -> void:
	var mi := _spawn(_ring_mesh, CLICK_COLOR, pos + Vector3(0, 0.03, 0), Vector3.ONE * 0.3)
	_fade_out(mi, 0.3, Vector3.ONE * 0.15)


## 순간이동 출발·도착점 같은 원. size는 반지름(m)
func ring(pos: Vector3, color: Color = TELEPORT_COLOR, size: float = 0.7) -> void:
	var mi := _spawn(_ring_mesh, color, pos + Vector3(0, 0.05, 0), Vector3.ONE * size)
	_fade_out(mi, 0.3, Vector3.ONE * size * 1.6)


## 근접 공격 부채꼴(0.1초)
func fan(pos: Vector3, dir: Vector3, reach: float, angle_deg: float) -> void:
	var mi := _spawn(_get_fan(angle_deg), FAN_COLOR, pos + Vector3(0, 0.06, 0), Vector3(reach, 1.0, reach))
	mi.rotation.y = atan2(-dir.x, -dir.z)
	_fade_out(mi, 0.1, Vector3(reach, 1.0, reach) * 1.05)


## 맞았을 때 작게 퍼지는 구
func puff(pos: Vector3, color: Color) -> void:
	var mi := _spawn(_puff_mesh, color, pos, Vector3.ONE * 0.2)
	_fade_out(mi, 0.2, Vector3.ONE * 0.7)


## 덩치의 내려찍기 경고 원. 바깥 원은 옅게 깔리고 안쪽 원이 time 동안 차오른다.
## 돌려받은 노드는 공격이 끝나거나 취소될 때 호출한 쪽이 지운다.
func warning(pos: Vector3, radius: float, time: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos + Vector3(0, 0.04, 0)
	_scene_root().add_child(root)
	root.reset_physics_interpolation()
	var base := _make_instance(_disc_mesh, WARNING_BASE_COLOR)
	base.scale = Vector3(radius, 1.0, radius)
	root.add_child(base)
	var fill := _make_instance(_disc_mesh, WARNING_FILL_COLOR)
	fill.position.y = 0.01
	fill.scale = Vector3(0.01, 1.0, 0.01)
	root.add_child(fill)
	var t := fill.create_tween()
	t.tween_property(fill, "scale", Vector3(radius, 1.0, radius), time)
	return root


## 적 머리 위 체력 바. 빌보드 Sprite3D 두 장이 텍스처 하나를 같이 쓴다.
## 앞 장(이름 "Front")의 region_rect 폭으로 남은 체력을 보여준다.
func make_health_bar() -> Node3D:
	var bar := Node3D.new()
	bar.name = "HealthBar"
	var back := _bar_sprite(Color(0.08, 0.08, 0.08, 0.9), 0)
	back.name = "Back"
	var front := _bar_sprite(Color(0.9, 0.15, 0.15, 1.0), 1)
	front.name = "Front"
	bar.add_child(back)
	bar.add_child(front)
	return bar


## 첫 사용 때 셰이더 컴파일로 화면이 멈추지 않게, 시작할 때 바닥 아래(안 보이는 곳)에 한 번씩 그려 둔다.
func prewarm(at: Vector3) -> void:
	var p := at + Vector3(0, -3.0, 0)
	var mi := _spawn(_ring_mesh, CLICK_COLOR, p, Vector3.ONE)
	_fade_out(mi, 0.5, Vector3.ONE)
	var mi2 := _spawn(_get_fan(90.0), FAN_COLOR, p, Vector3.ONE)
	_fade_out(mi2, 0.5, Vector3.ONE)
	var bar := make_health_bar()
	bar.position = p
	_scene_root().add_child(bar)
	get_tree().create_timer(0.5).timeout.connect(bar.queue_free)
	for path in ["res://scenes/MagicMissile.tscn", "res://scenes/EnemyArrow.tscn"]:
		var scene: PackedScene = load(path)
		if scene == null:
			continue
		var n = scene.instantiate()
		n.process_mode = Node.PROCESS_MODE_DISABLED
		n.position = p
		_scene_root().add_child(n)
		get_tree().create_timer(0.5).timeout.connect(n.queue_free)


# ---------- 내부 ----------

func _scene_root() -> Node:
	var s := get_tree().current_scene
	if s == null:
		return get_tree().root
	return s


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	_mats[key] = m
	return m


func _make_instance(mesh: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _spawn(mesh: Mesh, color: Color, pos: Vector3, start_scale: Vector3) -> MeshInstance3D:
	var mi := _make_instance(mesh, color)
	mi.position = pos  # 씬 루트가 원점이라 position = 월드 위치
	mi.scale = start_scale
	_scene_root().add_child(mi)
	mi.reset_physics_interpolation()
	return mi


func _fade_out(mi: MeshInstance3D, time: float, end_scale: Vector3) -> void:
	var t := mi.create_tween()
	t.set_parallel(true)
	t.tween_property(mi, "transparency", 1.0, time)
	t.tween_property(mi, "scale", end_scale, time)
	t.chain().tween_callback(mi.queue_free)


func _get_fan(angle_deg: float) -> ArrayMesh:
	var key := snappedf(angle_deg, 0.1)
	if _fan_meshes.has(key):
		return _fan_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 16
	var half := deg_to_rad(angle_deg) * 0.5
	for i in seg:
		var a0 := -half + 2.0 * half * float(i) / seg
		var a1 := -half + 2.0 * half * float(i + 1) / seg
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a0), 0.0, -cos(a0)))
		st.add_vertex(Vector3(sin(a1), 0.0, -cos(a1)))
	var mesh := st.commit()
	_fan_meshes[key] = mesh
	return mesh


func _bar_sprite(color: Color, priority: int) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = _bar_tex
	s.pixel_size = 0.01  # 100px → 1 m
	s.centered = false
	s.offset = Vector2(-50, -6)
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, 100, 12)
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.shaded = false
	s.modulate = color
	s.render_priority = priority
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s
