extends Control
## Adapted from dot's independent HUD. State is a complete authoritative snapshot.
## This widget never advances clocks, awards laps or directly resets the car.
signal reset_requested
const DEFAULTS := {"phase": "waiting", "countdown_remaining_ms": -1, "lap": -1,
 "target_laps": -1, "elapsed_ms": -1, "passed_checkpoints": -1,
 "checkpoint_count": -1, "next_physical_gate": -1, "error": ""}
var state: Dictionary = DEFAULTS.duplicate()
var card: PanelContainer
var heading: Label
var clock_label: Label
var driving_label: Label
var detail: Label
var notice: Label
var restart_button: Button
var column: VBoxContainer

func _ready() -> void:
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 card = PanelContainer.new()
 card.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(card)
 var style := StyleBoxFlat.new()
 style.bg_color = Color(0.07, 0.14, 0.17, 0.94)
 style.border_color = Color("46ccd2")
 style.border_width_left = 3
 for edge in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: style.set_content_margin(edge, 6)
 style.corner_radius_top_left = 8
 style.corner_radius_top_right = 8
 style.corner_radius_bottom_left = 8
 style.corner_radius_bottom_right = 8
 card.add_theme_stylebox_override("panel", style)
 column = VBoxContainer.new()
 column.add_theme_constant_override("separation", 2)
 column.mouse_filter = Control.MOUSE_FILTER_IGNORE
 card.add_child(column)
 heading = _label(14)
 clock_label = _label(26)
 driving_label = _label(14)
 detail = _label(14)
 notice = _label(14)
 notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 notice.max_lines_visible = 2
 restart_button = Button.new()
 restart_button.text = "重开整场 · R"
 restart_button.custom_minimum_size = Vector2(0, 44)
 restart_button.focus_mode = Control.FOCUS_NONE
 restart_button.pressed.connect(func(): reset_requested.emit())
 column.add_child(restart_button)
 get_viewport().size_changed.connect(_layout)
 _layout()
 _render()

func _label(font_size: int) -> Label:
 var label := Label.new()
 label.mouse_filter = Control.MOUSE_FILTER_IGNORE
 label.clip_text = true
 label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 label.add_theme_font_size_override("font_size", font_size)
 label.add_theme_color_override("font_color", Color("edf6f4"))
 column.add_child(label)
 return label

func _layout() -> void:
 var view := get_viewport().get_visible_rect().size
 var compact := view.y < 500.0
 heading.visible = not compact
 clock_label.add_theme_font_size_override("font_size", 22 if compact else 26)
 for label in [driving_label, detail, notice]: label.add_theme_font_size_override("font_size", 12 if compact else 14)
 # Wrapped, clipped labels do not reliably request a height from VBoxContainer.
 # Reserve readable notice space: a trimmed line on compact screens, two on desktop.
 notice.autowrap_mode = TextServer.AUTOWRAP_OFF if compact else TextServer.AUTOWRAP_WORD_SMART
 notice.max_lines_visible = 1 if compact else 2
 notice.custom_minimum_size = Vector2(0, 18 if compact else 42)
 card.position = Vector2(16, 14)
 card.size = Vector2(minf(420, maxf(1, view.x - 32)), 0)

func set_state(snapshot: Dictionary) -> void:
 state = DEFAULTS.duplicate()
 if snapshot.get("phase") is String and snapshot.phase in ["countdown", "ready", "running", "finished", "invalid"]:
  state.phase = snapshot.phase
 var limits := {"countdown_remaining_ms": 60000, "lap": 999, "target_laps": 999,
  "elapsed_ms": 604800000, "passed_checkpoints": 256, "checkpoint_count": 256, "next_physical_gate": 255}
 for key in limits:
  var value: Variant = snapshot.get(key)
  if typeof(value) == TYPE_INT and value >= 0 and value <= limits[key]: state[key] = value
 if state.target_laps == 0: state.target_laps = -1
 if state.checkpoint_count == 0: state.checkpoint_count = -1
 if state.passed_checkpoints > state.checkpoint_count: state.passed_checkpoints = -1
 if state.next_physical_gate >= state.checkpoint_count: state.next_physical_gate = -1
 if state.lap > state.target_laps: state.lap = -1
 if snapshot.get("error") is String: state.error = snapshot.error.substr(0, 48)
 if is_instance_valid(card): _render()

static func format_ms(milliseconds: int) -> String:
 if milliseconds < 0 or milliseconds > 604800000: return "—"
 var minutes := floori(float(milliseconds) / 60000.0)
 var seconds := floori(float(milliseconds) / 1000.0) % 60
 return "%02d:%02d.%03d" % [minutes, seconds, milliseconds % 1000]

func _number(value: int) -> String:
 return "—" if value < 0 else str(value)

func _render() -> void:
 heading.text = "港区 · 单人练习"
 clock_label.text = "圈速  " + format_ms(int(state.elapsed_ms))
 if state.phase in ["waiting", "countdown", "ready"]: clock_label.text = "过起跑线后计时"
 detail.text = "目标 %s 圈 · 检查点 %s / %s" % [_number(state.target_laps), _number(state.passed_checkpoints), _number(state.checkpoint_count)]
 match state.phase:
  "countdown": notice.text = "准备 · %s" % (str(ceili(float(state.countdown_remaining_ms) / 1000.0)) if state.countdown_remaining_ms >= 0 else "—")
  "ready": notice.text = "穿过起跑线开始这一圈"
  "running": notice.text = "回到起终线完成一圈" if state.next_physical_gate == 0 else "练习进行中 · 下一门 %s" % _number(state.next_physical_gate)
  "finished": notice.text = "练习完成 · 已完成 %s 圈" % _number(state.lap)
  "invalid": notice.text = "本次无效 · 重开整场" + ("（%s）" % state.error if not state.error.is_empty() else "")
  _: notice.text = "等待练习状态"
