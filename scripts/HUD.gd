extends CanvasLayer
## HUD: 체력 바, 스킬 쿨다운 3칸, 웨이브 표시, 웨이브 안내, 피격 비네트, 결과 화면.
## 모두 코드로 만든다. 플레이어·웨이브 매니저의 신호를 듣고, 쿨다운만 매 프레임 읽는다.
## R 키 재시작도 여기서 처리한다.

@export var announce_time: float = 1.5
@export var vignette_time: float = 0.2
@export var victory_delay: float = 0.6
@export var defeat_delay: float = 1.0

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	float d = length(UV - vec2(0.5)) * 1.4;
	float v = smoothstep(0.35, 0.95, d);
	COLOR = vec4(0.9, 0.0, 0.0, v * strength);
}
"""

const SKILLS := [
	{"skill": "melee", "key": "우클릭", "name": "근접"},
	{"skill": "missile", "key": "Q", "name": "미사일"},
	{"skill": "teleport", "key": "Space", "name": "순간이동"},
]

var _player
var _waves

var _hp_fill: ColorRect
var _hp_label: Label
var _wave_label: Label
var _announce: Label
var _vignette_mat: ShaderMaterial
var _result: Control
var _result_title: Label
var _result_info: Label
var _slots: Array = []

var _last_health := -1
var _wave := 0
var _wave_total := 0
var _remaining := 0
var _announce_tween: Tween
var _vignette_tween: Tween


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_waves = get_tree().get_first_node_in_group("wave_manager")
	_build()
	if _player:
		_player.health_changed.connect(_on_health_changed)
		_player.died.connect(_on_player_died)
		_on_health_changed(_player.health, _player.max_health)
	if _waves:
		_wave_total = _waves.waves.size()
		_waves.wave_started.connect(_on_wave_started)
		_waves.remaining_changed.connect(_on_remaining_changed)
		_waves.all_waves_cleared.connect(_on_all_cleared)
	_update_wave_label()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
		return
	if _player == null:
		return
	for s in _slots:
		var cd: float = _player.get_cooldown(s["skill"])
		var mx: float = _player.get_cooldown_max(s["skill"])
		var ratio := 0.0
		if mx > 0.0:
			ratio = clampf(cd / mx, 0.0, 1.0)
		var shade: ColorRect = s["shade"]
		shade.anchor_top = 1.0 - ratio
		var label: Label = s["time"]
		label.text = "%.1f" % cd if cd > 0.0 else ""


# ---------- 신호 ----------

func _on_health_changed(current: int, maximum: int) -> void:
	_hp_fill.anchor_right = clampf(float(current) / maxi(1, maximum), 0.0, 1.0)
	_hp_label.text = "%d / %d" % [current, maximum]
	if _last_health >= 0 and current < _last_health:
		_flash_vignette()
	_last_health = current


func _on_wave_started(wave: int, total: int) -> void:
	_wave = wave
	_wave_total = total
	_update_wave_label()
	_show_announce("웨이브 %d" % wave)


func _on_remaining_changed(remaining: int) -> void:
	_remaining = remaining
	_update_wave_label()


func _on_all_cleared() -> void:
	get_tree().create_timer(victory_delay).timeout.connect(_show_result.bind(true))


func _on_player_died() -> void:
	get_tree().create_timer(defeat_delay).timeout.connect(_show_result.bind(false))


# ---------- 표시 ----------

func _update_wave_label() -> void:
	if _wave == 0:
		_wave_label.text = "준비"
	else:
		_wave_label.text = "웨이브 %d / %d · 남은 적 %d" % [_wave, _wave_total, _remaining]


func _show_announce(text: String) -> void:
	_announce.text = text
	_announce.visible = true
	_announce.modulate.a = 1.0
	if _announce_tween:
		_announce_tween.kill()
	_announce_tween = create_tween()
	_announce_tween.tween_interval(announce_time - 0.3)
	_announce_tween.tween_property(_announce, "modulate:a", 0.0, 0.3)
	_announce_tween.tween_callback(_announce.hide)


func _flash_vignette() -> void:
	if _vignette_tween:
		_vignette_tween.kill()
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(_set_vignette, 1.0, 0.0, vignette_time)


func _set_vignette(v: float) -> void:
	_vignette_mat.set_shader_parameter("strength", v)


func _show_result(victory: bool) -> void:
	if _result.visible:
		return
	_result_title.text = "승리!" if victory else "쓰러졌다…"
	var kills := 0
	var elapsed := 0.0
	if _waves:
		kills = _waves.kills
		elapsed = _waves.elapsed
	var sec := int(elapsed)
	_result_info.text = "처치 %d · 걸린 시간 %d:%02d" % [kills, sec / 60, sec % 60]
	_result.visible = true


# ---------- 화면 만들기 ----------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Apple SD Gothic Neo", "AppleGothic", "Noto Sans CJK KR", "Malgun Gothic", "sans-serif"])
	theme.default_font = font
	theme.default_font_size = 16
	root.theme = theme
	add_child(root)

	# 피격 비네트(맨 아래에 깔아 다른 UI를 가리지 않게)
	var vignette := ColorRect.new()
	_vignette_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	_vignette_mat.shader = shader
	vignette.material = _vignette_mat
	_place(vignette, root, 0, 0, 1, 1, 0, 0, 0, 0)

	# 체력 바: 왼쪽 아래
	var hp_bg := _rect(Color(0, 0, 0, 0.6))
	_place(hp_bg, root, 0, 1, 0, 1, 16, -44, 256, -16)
	_hp_fill = _rect(Color(0.85, 0.15, 0.15))
	_place(_hp_fill, hp_bg, 0, 0, 1, 1, 0, 0, 0, 0)
	_hp_label = _label("100 / 100", 16)
	_place(_hp_label, hp_bg, 0, 0, 1, 1, 0, 0, 0, 0)

	# 스킬 칸 3개: 아래 가운데
	var size := 60.0
	var gap := 8.0
	var total := size * SKILLS.size() + gap * (SKILLS.size() - 1)
	for i in SKILLS.size():
		var info: Dictionary = SKILLS[i]
		var left := -total * 0.5 + i * (size + gap)
		var slot := _rect(Color(0.12, 0.14, 0.2, 0.85))
		_place(slot, root, 0.5, 1, 0.5, 1, left, -16 - size, left + size, -16)
		var key := _label(info["key"], 13)
		_place(key, slot, 0, 0, 1, 0, 0, 2, 0, 22)
		var nm := _label(info["name"], 11)
		_place(nm, slot, 0, 1, 1, 1, 0, -20, 0, -2)
		var shade := _rect(Color(0, 0, 0, 0.6))
		_place(shade, slot, 0, 1, 1, 1, 0, 0, 0, 0)
		var time := _label("", 20)
		_place(time, slot, 0, 0, 1, 1, 0, 0, 0, 0)
		_slots.append({"skill": info["skill"], "shade": shade, "time": time})

	# 웨이브 표시: 위 가운데
	_wave_label = _label("", 18)
	_place(_wave_label, root, 0.5, 0, 0.5, 0, -260, 12, 260, 40)

	# 웨이브 안내: 화면 가운데
	_announce = _label("", 44)
	_place(_announce, root, 0.5, 0.5, 0.5, 0.5, -300, -110, 300, -40)
	_announce.visible = false

	# 결과 화면
	_result = Control.new()
	_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_result, root, 0, 0, 1, 1, 0, 0, 0, 0)
	var dim := _rect(Color(0, 0, 0, 0.55))
	_place(dim, _result, 0, 0, 1, 1, 0, 0, 0, 0)
	_result_title = _label("", 48)
	_place(_result_title, _result, 0.5, 0.5, 0.5, 0.5, -300, -100, 300, -30)
	_result_info = _label("", 20)
	_place(_result_info, _result, 0.5, 0.5, 0.5, 0.5, -300, -10, 300, 20)
	var hint := _label("R 키로 다시 시작", 18)
	_place(hint, _result, 0.5, 0.5, 0.5, 0.5, -300, 40, 300, 70)
	_result.visible = false


func _rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return l


## 앵커(0~1)와 여백(px, 기본 뷰포트 1152×648 기준)으로 배치
func _place(c: Control, parent: Node, al: float, at: float, ar: float, ab: float, ol: float, ot: float, o_r: float, ob: float) -> void:
	parent.add_child(c)
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = o_r
	c.offset_bottom = ob
