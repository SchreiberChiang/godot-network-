extends SceneTree
## Presentation checks use exact production snapshot names; no race mutation.
const HUD = preload("res://practice_hud.gd")
var failed := 0
var passed := 0
var resets := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
 if ok: passed += 1
 else:
  failed += 1
  print("HUD_FAILED ", label)
func _run() -> void:
 var hud = HUD.new()
 root.add_child(hud)
 for item in [[0,"00:00.000"],[59999,"00:59.999"],[60000,"01:00.000"],[3600001,"60:00.001"],[-1,"—"],[604800001,"—"]]: check(HUD.format_ms(item[0]) == item[1], "millisecond format " + str(item[0]))
 for phase in ["countdown","ready","running","finished","invalid"]:
  hud.set_state({"phase":phase,"countdown_remaining_ms":2001,"elapsed_ms":83427,"lap":0,"target_laps":1,"passed_checkpoints":3,"checkpoint_count":12,"next_physical_gate":4,"error":"DISCONTINUITY"})
  check(hud.state.phase == phase, "actual phase " + phase)
  check(hud.detail.text.contains("3 / 12"), "progress " + phase)
  check(not hud.detail.text.contains("最佳"), "no unmeasured best " + phase)
  if phase in ["running","finished"]: check(hud.clock_label.text.contains("01:23.427"), "actual elapsed " + phase)
  if phase == "countdown": check(hud.notice.text.contains("3"), "countdown ceil from milliseconds")
  if phase == "ready": check(hud.notice.text.contains("起跑线") and not hud.clock_label.text.contains("00:00.000"), "ready is not already timed")
  if phase == "invalid": check(hud.notice.text.contains("DISCONTINUITY"), "invalid reason retained")
 hud.reset_requested.connect(func(): resets += 1)
 var before: Dictionary = hud.state.duplicate()
 hud.restart_button.pressed.emit()
 check(resets == 1 and hud.state == before, "reset signal delegates all state policy")
 hud.set_state({"phase":"running","elapsed_ms":"bad","alien":7})
 check(hud.clock_label.text.contains("—") and not hud.state.has("alien"), "wrong time remains unknown")
 hud.set_state({"phase":"running","elapsed_ms":0,"checkpoint_count":12,"passed_checkpoints":0})
 check(hud.clock_label.text.contains("00:00.000") and hud.detail.text.contains("0 / 12"), "observed zeros preserved")
 hud.set_state({"phase":"running","passed_checkpoints":100,"checkpoint_count":12})
 check(hud.state.passed_checkpoints == -1 and not hud.detail.text.contains("12 / 12"), "invalid progress never becomes full")
 hud.set_state({"elapsed_ms":-8,"checkpoint_count":true,"lap":9,"target_laps":1,"next_physical_gate":44})
 check(hud.state.elapsed_ms == -1 and hud.state.checkpoint_count == -1 and hud.state.lap == -1 and hud.state.next_physical_gate == -1, "negative boolean and inconsistent observations unknown")
 hud.set_state({})
 check(hud.state == HUD.DEFAULTS, "new complete snapshot clears stale display")
 for size in [Vector2i(1280,720),Vector2i(844,390),Vector2i(640,360)]:
  root.size = size
  for phase in ["running","finished","invalid"]:
   hud.set_state({"phase":phase,"elapsed_ms":604800000,"target_laps":1,"lap":1,"passed_checkpoints":12,"checkpoint_count":12,"next_physical_gate":0,"error":"LONG_ERROR_REASON_".repeat(30)})
   hud.driving_label.text = "108 km/h · 氮气 3.0/3 · 漂移"
   hud._layout()
   await process_frame
   await process_frame
   check(hud.card.get_rect().end.y <= size.y - 174, "no nitro overlap " + str(size) + phase)
   check(hud.card.get_rect().end.x <= size.x - 16, "width bounded " + str(size) + phase)
   check(hud.restart_button.get_rect().size.y >= 44, "reset hit area " + str(size) + phase)
   check(hud.notice.size.y >= hud.notice.get_theme_font("font").get_height(hud.notice.get_theme_font_size("font_size")), "status notice has visible text height " + str(size) + phase)
 hud.queue_free()
 await process_frame
 print("RACING_HUD_RESULT passed=",passed," failed=",failed)
 quit(0 if failed == 0 else 1)
