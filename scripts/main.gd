extends Control
## Astro Quest: Junior Astronaut Mission Trainer.
## Owns screens and input; the simulation rules live in scripts/sim/.

const OpenSourceLicenses = preload("res://scripts/manus/open_source_licenses.gd")
const ProceduralSfx = preload("res://scripts/manus/procedural_sfx.gd")
const Kit = preload("res://scripts/ui/kit.gd")
const OutpostSim = preload("res://scripts/sim/outpost_sim.gd")
const EventDeck = preload("res://scripts/sim/event_deck.gd")
const NasaData = preload("res://scripts/sim/nasa_data.gd")
const LiveDonki = preload("res://scripts/net/live_donki.gd")
const OutpostView = preload("res://scripts/ui/outpost_view.gd")
const PipBar = preload("res://scripts/ui/pip_bar.gd")

const SYSTEM_INFO := {
	"air": {"name": "AIR MAKER", "icon": "res://assets/game/icons/air.png", "help": "+6 air per cell", "color": Kit.AIR_C},
	"food": {"name": "GREENHOUSE", "icon": "res://assets/game/icons/food.png", "help": "+5 food per cell", "color": Kit.FOOD_C},
	"lab": {"name": "SCIENCE LAB", "icon": "res://assets/game/icons/science.png", "help": "+1 science per cell", "color": Kit.PURPLE},
	"shield": {"name": "SHIELD BUILDER", "icon": "res://assets/game/icons/radiation.png", "help": "+8% shield per cell", "color": Kit.SHIELD_C},
	"radio": {"name": "EARTH RADIO", "icon": "res://assets/game/events/earth.png", "help": "Hear NASA storm warnings", "color": Kit.BLUE},
}
const METER_INFO := {
	"air": {"name": "AIR", "icon": "res://assets/game/icons/air.png", "color": Kit.AIR_C, "help": "Oxygen for the crew to breathe. The 2 astronauts use 12 air every day. At 0 the mission must end."},
	"food": {"name": "FOOD", "icon": "res://assets/game/icons/food.png", "color": Kit.FOOD_C, "help": "Food from the greenhouse. The crew eats 9 food every day."},
	"battery": {"name": "BATTERY", "icon": "res://assets/game/icons/power.png", "color": Kit.POWER_C, "help": "Stored power. Unused solar cells charge it. Every night the heaters use 2 cells to keep the crew warm."},
	"shield": {"name": "SHIELD", "icon": "res://assets/game/icons/radiation.png", "color": Kit.SHIELD_C, "help": "How strong the walls are against radiation. A strong shield blocks most of a solar storm."},
	"dose": {"name": "DOSE", "icon": "res://assets/game/icons/radiation.png", "color": Kit.DOSE_C, "help": "Radiation dose: invisible space energy the crew has soaked up. It never goes down. At 100 the crew must fly home."},
	"science": {"name": "SCIENCE", "icon": "res://assets/game/icons/science.png", "color": Kit.PURPLE, "help": "Discoveries made in the lab. More science gives a higher mission rank."},
}
const ART := {
	"lander": "res://assets/game/scene/lander.png",
	"flare": "res://assets/game/events/flare.png",
	"meteor": "res://assets/game/events/meteor.png",
	"rock": "res://assets/game/events/rock.png",
	"earth": "res://assets/game/events/earth.png",
	"plants": "res://assets/game/buildings/greenhouse.png",
	"crew": "res://assets/game/crew/astronaut_walk.png",
	"shadow": "res://assets/game/buildings/panel_closed.png",
	"dust": "res://assets/game/events/dust.png",
}

var sim: RefCounted
var donki: Node
var _screen := "title"
var _paused := false
var _fast := false
var _first_mission := false
var _rng := RandomNumberGenerator.new()

var _view: Control
var _hud: Control
var _meters := {}
var _day_label: Label
var _sun_bar: ProgressBar
var _phase_label: Label
var _data_chip: PanelContainer
var _data_chip_label: Label
var _pause_button: Button

var _plan_panel: PanelContainer
var _plan_header: Label
var _plan_sub: Label
var _rows := {}
var _forecast_label: RichTextLabel
var _clean_button: Button
var _start_button: Button
var _fast_button: Button
var _plan_box: VBoxContainer
var _running_box: VBoxContainer
var _running_label: Label

var _modal_layer: Control
var _event: Dictionary = {}
var _event_time_left := 0.0
var _event_time_total := 10.0
var _event_timer_bar: ProgressBar
var _event_timer_label: Label
var _event_choice_buttons: Array[Button] = []
var _event_resolved := false
var _event_queue: Array[Dictionary] = []
var _transmission_left := 0.0

var _title_screen: Control
var _title_status: Label
var _nasa_screen: Control
var _howto_screen: Control
var _pause_screen: Control
var _result_screen: Control
var _toast: PanelContainer
var _toast_label: Label
var _toast_time := 0.0
var _coach: PanelContainer
var _coach_label: Label
var _coach_frame: Panel
var _coach_step := -1
var _night_time := -1.0
var _pending_report: Dictionary = {}
var _pop_clock := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = Kit.make_theme()
	Kit.full_rect(self)
	_rng.randomize()
	sim = OutpostSim.new()
	donki = LiveDonki.new()
	donki.name = "LiveDonki"
	add_child(donki)
	donki.finished.connect(_on_donki_finished)
	_register_audio()
	_view = OutpostView.new()
	add_child(_view)
	_build_hud()
	_build_plan_panel()
	_modal_layer = Control.new()
	Kit.full_rect(_modal_layer)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_layer)
	_build_coach()
	_build_toast()
	_build_title()
	TuningStore.value_changed.connect(_on_tuning_changed)
	_apply_motion_setting()
	_show_title()
	if DisplayServer.get_name() != "headless":
		donki.fetch()


func _register_audio() -> void:
	AudioDirector.register_stream("ui.confirm", ProceduralSfx.tone(660.0, 0.07, 0.16, 880.0))
	AudioDirector.register_stream("ui.cancel", ProceduralSfx.tone(440.0, 0.08, 0.14, 300.0))
	AudioDirector.register_stream("player.action", ProceduralSfx.tone(520.0, 0.05, 0.14, 700.0))
	AudioDirector.register_stream("enemy.impact", ProceduralSfx.tone(880.0, 0.22, 0.2, 440.0))
	AudioDirector.register_stream("score.reward", ProceduralSfx.tone(700.0, 0.16, 0.18, 1200.0))
	AudioDirector.register_stream("game.pause", ProceduralSfx.tone(500.0, 0.06, 0.12, 400.0))
	AudioDirector.register_stream("game.victory", ProceduralSfx.tone(520.0, 0.6, 0.2, 1040.0))
	AudioDirector.register_stream("game.defeat", ProceduralSfx.tone(400.0, 0.6, 0.18, 160.0))


func _register_buttons(root: Node) -> void:
	for node: Node in root.find_children("*", "Button", true, false):
		AudioDirector.register_button(node as Button)


# ======================================================================= HUD

func _build_hud() -> void:
	_hud = Control.new()
	Kit.full_rect(_hud)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", Kit.box(Color(0.04, 0.06, 0.15, 0.92), Kit.WHITE, 3, 0, 6))
	bar.position = Vector2(6, 6)
	bar.size = Vector2(1268, 84)
	bar.custom_minimum_size = Vector2(1268, 84)
	_hud.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	var day_box := VBoxContainer.new()
	day_box.custom_minimum_size = Vector2(150, 0)
	day_box.add_theme_constant_override("separation", 2)
	row.add_child(day_box)
	_day_label = Kit.label("DAY 1 / 10", 24, Kit.ORANGE, true)
	day_box.add_child(_day_label)
	_sun_bar = _make_bar(Kit.WARN, 12)
	day_box.add_child(_sun_bar)
	_phase_label = Kit.label("Planning", 14, Kit.MUTED, true)
	day_box.add_child(_phase_label)
	for id: String in ["air", "food", "battery", "shield", "dose", "science"]:
		row.add_child(_make_meter(id))
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	_pause_button = Kit.button("II", "secondary", 20)
	_pause_button.custom_minimum_size = Vector2(56, 44)
	_pause_button.tooltip_text = "Pause (Esc)"
	_pause_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_pause_button.pressed.connect(_open_pause)
	right.add_child(_pause_button)
	_data_chip = Kit.chip("ARCHIVED", "real")
	_data_chip_label = _data_chip.get_child(0) as Label
	_data_chip_label.add_theme_font_size_override("font_size", 12)
	_data_chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(_data_chip)
	AudioDirector.register_button(_pause_button)


func _make_bar(color: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.min_value = 0
	bar.max_value = 100
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.1)
	bg.border_color = Color(1, 1, 1, 0.5)
	bg.set_border_width_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


func _make_meter(id: String) -> Control:
	var info: Dictionary = METER_INFO[id]
	var button := Button.new()
	button.flat = true
	button.custom_minimum_size = Vector2(152, 70)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = str(info.help)
	button.mouse_default_cursor_shape = Control.CURSOR_HELP
	var empty := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, empty)
	button.pressed.connect(func() -> void: _show_toast(str(info.name) + ": " + str(info.help), 5.0))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Kit.full_rect(hb)
	button.add_child(hb)
	var icon := Kit.texture_rect(str(info.icon), Vector2(32, 34))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if id == "dose":
		icon.modulate = Kit.DOSE_C
	hb.add_child(icon)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(top)
	var name_label := Kit.label(str(info.name), 15, info.color, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var value_label := Kit.label("0", 20, Kit.WHITE, true)
	top.add_child(value_label)
	var bar := _make_bar(info.color, 14)
	vb.add_child(bar)
	var delta_label := Kit.label("", 13, Kit.MUTED, true)
	vb.add_child(delta_label)
	_meters[id] = {"value": value_label, "bar": bar, "delta": delta_label, "button": button}
	return button


func _refresh_hud() -> void:
	_day_label.text = "DAY %d / %d" % [sim.day, sim.days_total]
	_sun_bar.value = sim.day_progress * 100.0
	match str(sim.phase):
		"plan":
			_phase_label.text = "Morning: plan power"
		"day":
			_phase_label.text = "Daytime work" + ("  x2" if _fast else "")
		"night":
			_phase_label.text = "Night: heaters on"
		_:
			_phase_label.text = "Mission over"
	var values := {
		"air": [sim.air, 100.0, "%d" % roundi(sim.air)],
		"food": [sim.food, 100.0, "%d" % roundi(sim.food)],
		"battery": [float(sim.battery), float(sim.BATTERY_MAX), "%d/%d" % [sim.battery, sim.BATTERY_MAX]],
		"shield": [sim.shield, 100.0, "%d%%" % roundi(sim.shield)],
		"dose": [sim.dose, sim.DOSE_LIMIT, "%d" % roundi(sim.dose)],
		"science": [minf(sim.science, sim.days_total * 2.0), sim.days_total * 2.0, "%d" % floori(sim.science)],
	}
	var forecast: Dictionary = sim.forecast()
	var blink := int(Time.get_ticks_msec() / 400) % 2 == 0
	for id: String in values:
		var meter: Dictionary = _meters[id]
		var data: Array = values[id]
		(meter.bar as ProgressBar).max_value = float(data[1])
		(meter.bar as ProgressBar).value = float(data[0])
		(meter.value as Label).text = str(data[2])
		var delta := ""
		var color := Kit.MUTED
		if sim.phase == "plan" and forecast.has(id):
			var v := float(forecast[id])
			if id == "battery":
				delta = "tonight %s%d" % ["+" if v >= 0 else "", roundi(v)]
				color = Kit.GOOD if v >= 0 else Kit.BAD
			elif id == "dose":
				delta = "+%.1f / day" % v
			else:
				delta = "%s%d / day" % ["+" if v >= 0 else "", roundi(v)]
				color = Kit.GOOD if v > 0 else (Kit.BAD if v < 0 else Kit.MUTED)
		(meter.delta as Label).text = delta
		(meter.delta as Label).add_theme_color_override("font_color", color)
		var low := false
		if id in ["air", "food"]:
			low = float(data[0]) < 25.0
		elif id == "dose":
			low = float(data[0]) > 70.0
		(meter.value as Label).add_theme_color_override("font_color", Kit.BAD if (low and blink) else Kit.WHITE)


# ================================================================ plan panel

func _build_plan_panel() -> void:
	_plan_panel = PanelContainer.new()
	_plan_panel.add_theme_stylebox_override("panel", Kit.box(Color(0.05, 0.07, 0.17, 0.94), Kit.WHITE, 3, 6, 10))
	_plan_panel.position = Vector2(918, 98)
	_plan_panel.custom_minimum_size = Vector2(356, 614)
	_plan_panel.size = Vector2(356, 614)
	_hud.add_child(_plan_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_plan_panel.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	head.add_child(Kit.texture_rect("res://assets/game/icons/power.png", Vector2(30, 40)))
	var head_text := VBoxContainer.new()
	head_text.add_theme_constant_override("separation", 0)
	head.add_child(head_text)
	_plan_header = Kit.label("POWER PLAN", 24, Kit.POWER_C, true)
	head_text.add_child(_plan_header)
	_plan_sub = Kit.label("", 15, Kit.WHITE, true, true)
	_plan_sub.custom_minimum_size = Vector2(290, 0)
	head_text.add_child(_plan_sub)
	_plan_box = VBoxContainer.new()
	_plan_box.add_theme_constant_override("separation", 4)
	outer.add_child(_plan_box)
	for id: String in sim.SYSTEMS:
		_plan_box.add_child(_make_system_row(id))
	_clean_button = Kit.button("CLEAN DUSTY PANELS", "secondary", 15)
	_clean_button.custom_minimum_size = Vector2(0, 40)
	_clean_button.pressed.connect(_on_clean)
	_plan_box.add_child(_clean_button)
	_forecast_label = RichTextLabel.new()
	_forecast_label.bbcode_enabled = true
	_forecast_label.fit_content = true
	_forecast_label.scroll_active = false
	_forecast_label.custom_minimum_size = Vector2(320, 40)
	_forecast_label.add_theme_font_size_override("normal_font_size", 15)
	_forecast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plan_box.add_child(_forecast_label)
	_start_button = Kit.button("START DAY  >", "primary", 26)
	_start_button.name = "StartDayButton"
	_start_button.custom_minimum_size = Vector2(0, 58)
	_start_button.pressed.connect(_on_start_day)
	_plan_box.add_child(_start_button)
	_running_box = VBoxContainer.new()
	_running_box.add_theme_constant_override("separation", 10)
	_running_box.visible = false
	outer.add_child(_running_box)
	_running_label = Kit.label("", 18, Kit.WHITE, false, true)
	_running_label.custom_minimum_size = Vector2(320, 0)
	_running_box.add_child(_running_label)
	_fast_button = Kit.button(">> FASTER", "secondary", 18)
	_fast_button.custom_minimum_size = Vector2(0, 48)
	_fast_button.pressed.connect(func() -> void:
		_fast = not _fast
		_fast_button.text = "> NORMAL SPEED" if _fast else ">> FASTER"
	)
	_running_box.add_child(_fast_button)
	_register_buttons(_plan_panel)


func _make_system_row(id: String) -> Control:
	var info: Dictionary = SYSTEM_INFO[id]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.05), Color(info.color).darkened(0.3), 2, 0, 5))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	panel.add_child(hb)
	var icon := Kit.texture_rect(str(info.icon), Vector2(34, 34))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(icon)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	vb.add_child(name_row)
	var name_label := Kit.label(str(info.name), 16, info.color, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	var pips := PipBar.new()
	pips.total = int(sim.MAX_CELLS[id])
	pips.pip_size = 12.0
	pips.gap = 4.0
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(pips)
	vb.add_child(Kit.label(str(info.help), 13, Kit.MUTED))
	var minus := Kit.button("-", "small", 24)
	minus.name = "Minus_" + id
	minus.custom_minimum_size = Vector2(46, 46)
	minus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	minus.tooltip_text = "Take a power cell away"
	minus.pressed.connect(_on_cell.bind(id, -1))
	hb.add_child(minus)
	var plus := Kit.button("+", "primary", 24)
	plus.name = "Plus_" + id
	plus.custom_minimum_size = Vector2(46, 46)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plus.tooltip_text = "Give a power cell"
	plus.pressed.connect(_on_cell.bind(id, 1))
	hb.add_child(plus)
	_rows[id] = {"panel": panel, "pips": pips, "minus": minus, "plus": plus}
	return panel


func _refresh_plan() -> void:
	var planning: bool = sim.phase == "plan"
	_plan_box.visible = planning
	_running_box.visible = sim.phase == "day"
	if planning:
		_plan_header.text = "POWER PLAN"
		var left: int = sim.leftover_cells()
		var from_battery: int = sim.battery_used_by_plan()
		var extra := ("Using %d from battery!" % from_battery) if from_battery > 0 else ("%d unused: charge battery" % left)
		_plan_sub.text = "Sun gives %d cells today. %s" % [sim.cells_today, extra]
		for id: String in sim.SYSTEMS:
			var row: Dictionary = _rows[id]
			row.pips.filled = int(sim.alloc[id])
			(row.minus as Button).disabled = not sim.can_remove(id)
			(row.plus as Button).disabled = not sim.can_add(id)
		_clean_button.visible = sim.dust > 0.05 and not sim.cleaned_today
		_clean_button.text = "CLEAN DUSTY PANELS (+%d dose)" % int(sim.CLEAN_DOSE)
		var f: Dictionary = sim.forecast()
		var lines: Array[String] = []
		if float(f.air) < 0:
			lines.append("[color=#ff5d5d]Air will DROP %d today.[/color]" % roundi(-float(f.air)))
		if float(f.food) < 0:
			lines.append("[color=#ff5d5d]Food will DROP %d today.[/color]" % roundi(-float(f.food)))
		var tonight: int = sim.forecast_battery_tonight()
		if tonight < 0:
			lines.append("[color=#ff5d5d]Battery too low for tonight's heaters![/color]")
		else:
			lines.append("[color=#ffd23f]Battery after tonight: %d[/color]" % tonight)
		if sim.dust > 0.05:
			lines.append("[color=#c9b9a0]Panels are %d%% dusty.[/color]" % roundi(sim.dust * 100.0))
		_forecast_label.text = "\n".join(lines)
	else:
		_plan_header.text = "DAY %d" % sim.day
		_plan_sub.text = "The crew is working!"
		var parts: Array[String] = []
		for id: String in sim.SYSTEMS:
			if int(sim.alloc[id]) > 0:
				parts.append("%s: %d" % [str(SYSTEM_INFO[id].name), int(sim.alloc[id])])
		_running_label.text = "Power sent to:\n" + "\n".join(parts) + "\n\nWatch out for surprises!"
	_view.sync(sim)


func _on_cell(id: String, amount: int) -> void:
	var changed: bool = sim.add_cell(id) if amount > 0 else sim.remove_cell(id)
	if changed:
		AudioDirector.play_cue("player.action", 1.0 + 0.04 * int(sim.alloc[id]))
		if _coach_step == 1 and id == "lab" and amount > 0:
			_coach_next()
	_refresh_plan()
	_refresh_hud()


func _on_clean() -> void:
	if sim.clean_panels():
		_view.pop("Clean!", "panels", Kit.WHITE)
		_show_toast("The crew wiped moon dust off the panels. Moonwalks add a little radiation dose.", 4.0)
	_refresh_plan()
	_refresh_hud()


func _on_start_day() -> void:
	if sim.phase != "plan" or _screen != "game":
		return
	if sim.forecast_battery_tonight() < 0:
		_show_toast("Careful, commander! The battery may run out tonight.", 3.0)
	TuningStore.apply_boundary("NEXT_STAGE")
	sim.air_use = float(TuningStore.get_value("environment.crew.air_use", 12.0))
	if _coach_step >= 0:
		_end_coach()
	sim.begin_day()
	_view.set_running(true)
	AudioDirector.play_cue("score.reward")
	_refresh_plan()
	_refresh_hud()


# ======================================================================= loop

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.visible = _toast_time > 0.0
	if _screen != "game" or _paused:
		return
	if not _event.is_empty():
		if _transmission_left > 0.0:
			_transmission_left -= delta
			if _transmission_left <= 0.0:
				_open_event_card()
		else:
			_process_event(delta)
	elif not _event_queue.is_empty():
		_begin_event(_event_queue.pop_front())
	elif _night_time >= 0.0:
		_process_night(delta)
	elif sim.phase == "day":
		var day_length := float(TuningStore.get_value("gameplay.day.length", 14.0))
		var due: Dictionary = sim.tick(delta * (2.0 if _fast else 1.0) / maxf(1.0, day_length))
		if sim.outcome != "":
			_finish_mission()
			return
		if not due.is_empty():
			_event_queue.append(due)
		elif sim.day_finished():
			_start_night()
		_spawn_ambient_pops(delta)
	_refresh_hud()


func _spawn_ambient_pops(delta: float) -> void:
	_pop_clock += delta * (2.0 if _fast else 1.0)
	if _pop_clock < 1.4:
		return
	_pop_clock = 0.0
	var choices: Array = []
	if int(sim.alloc.air) > 0:
		choices.append(["+O2", "habitat", Kit.AIR_C])
	if int(sim.alloc.food) > 0:
		choices.append(["+food", "greenhouse", Kit.FOOD_C])
	if int(sim.alloc.lab) > 0:
		choices.append(["+science", "lab", Kit.PURPLE])
	if int(sim.alloc.shield) > 0:
		choices.append(["+shield", "shelter", Kit.SHIELD_C])
	if choices.is_empty():
		return
	var pick: Array = choices[_rng.randi_range(0, choices.size() - 1)]
	_view.pop(str(pick[0]), str(pick[1]), pick[2])


func _start_night() -> void:
	_night_time = 0.0
	_view.set_running(false)


func _process_night(delta: float) -> void:
	_night_time += delta
	_view.set_night(minf(0.6, _night_time * 0.6))
	if _night_time >= 1.2 and _pending_report.is_empty():
		_pending_report = sim.run_night()
		_refresh_hud()
		if sim.outcome != "" and sim.outcome != "win":
			_night_time = -1.0
			_view.set_night(0.0)
			_finish_mission()
			return
		_refresh_plan()
		_show_night_report(_pending_report)


# ===================================================================== events

func _begin_event(entry: Dictionary) -> void:
	TuningStore.apply_boundary("NEXT_ACTION")
	var built: Dictionary = EventDeck.build(sim, entry)
	if built.is_empty():
		return
	_event = built
	_event_resolved = false
	_event_timer_bar = null
	_view.set_running(false)
	AudioDirector.play_cue("enemy.impact")
	if str(built.id) in ["radiation_storm", "cme_arrival"]:
		_view.set_storm(true)
	if str(built.id) == "lander_dust":
		_view.lander_arrive()
	if bool(built.get("from_earth", false)):
		_transmission_left = 1.3
		_show_transmission()
		return
	_open_event_card()


func _show_transmission() -> void:
	_clear_modal()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Kit.box(Color(0.04, 0.06, 0.15, 0.95), Kit.BLUE, 3, 6, 18))
	panel.position = Vector2(230, 300)
	panel.custom_minimum_size = Vector2(460, 0)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	vb.add_child(Kit.label("INCOMING MESSAGE FROM EARTH...", 22, Kit.BLUE, true))
	vb.add_child(Kit.label("Radio waves need about 1.3 seconds to cross 384,400 km of space.", 16, Kit.WHITE, false, true))
	_modal_layer.add_child(panel)


func _open_event_card() -> void:
	_clear_modal()
	_transmission_left = 0.0
	_modal_layer.add_child(Kit.dimmer(0.45))
	var storm := bool(_event.get("storm", false))
	var panel := PanelContainer.new()
	panel.name = "EventCard"
	panel.add_theme_stylebox_override("panel", Kit.box(Color(0.06, 0.08, 0.2, 0.98), Kit.ORANGE if storm else Kit.WHITE, 4, 8, 16))
	panel.position = Vector2(24, 100)
	panel.custom_minimum_size = Vector2(880, 0)
	_modal_layer.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	root.add_child(top)
	top.add_child(Kit.texture_rect(str(ART.get(str(_event.get("art", "")), ART.flare)), Vector2(150, 130)))
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 6)
	top.add_child(text_box)
	text_box.add_child(Kit.label("DAY %d: %s" % [sim.day, str(_event.title).to_upper()], 28, Kit.ORANGE, true))
	var body := Kit.label(str(_event.text), 19, Kit.WHITE, false, true)
	body.custom_minimum_size = Vector2(660, 0)
	text_box.add_child(body)
	var source_row := HBoxContainer.new()
	source_row.add_theme_constant_override("separation", 8)
	text_box.add_child(source_row)
	var is_live := bool(_event.get("live", false))
	var chip_text := "LIVE" if is_live else ("REAL NASA DATA" if bool(_event.get("real", false)) else "NASA SCIENCE")
	source_row.add_child(Kit.chip(chip_text, "live" if is_live else "real"))
	var src := Kit.label(str(_event.get("source", "")), 14, Kit.BLUE, false, true)
	src.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_row.add_child(src)
	var term := PanelContainer.new()
	term.add_theme_stylebox_override("panel", Kit.box(Color(0.09, 0.4, 0.55, 0.25), Kit.BLUE, 2, 0, 8))
	var term_text := "WORD HELP:  " + str(_event.get("term", ""))
	if _event.has("term2"):
		term_text += "\n" + str(_event.term2)
	var term_label := Kit.label(term_text, 15, Color("cfefff"), false, true)
	term_label.custom_minimum_size = Vector2(820, 0)
	term.add_child(term_label)
	root.add_child(term)
	var notice_only := bool(_event.get("notice_only", false))
	var timer_row := HBoxContainer.new()
	timer_row.add_theme_constant_override("separation", 10)
	timer_row.visible = not notice_only
	root.add_child(timer_row)
	timer_row.add_child(Kit.label("DECIDE!", 18, Kit.WARN, true))
	_event_timer_bar = _make_bar(Kit.WARN, 18)
	_event_timer_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_event_timer_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	timer_row.add_child(_event_timer_bar)
	_event_timer_label = Kit.label("10", 26, Kit.WARN, true)
	_event_timer_label.custom_minimum_size = Vector2(44, 0)
	timer_row.add_child(_event_timer_label)
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 12)
	root.add_child(choices)
	_event_choice_buttons.clear()
	var list: Array = _event.choices
	for index: int in list.size():
		var choice: Dictionary = list[index]
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 6)
		choices.add_child(col)
		var label := ("%d  %s" % [index + 1, str(choice.label)]) if list.size() > 1 else str(choice.label)
		var kind := "primary" if index == 0 else ("blue" if index == 1 else "secondary")
		var button := Kit.button(label, kind, 19)
		button.name = "Choice%d" % index
		button.custom_minimum_size = Vector2(0, 62)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_on_event_choice.bind(index))
		col.add_child(button)
		_event_choice_buttons.append(button)
		if not notice_only:
			var chip_row := HFlowContainer.new()
			chip_row.add_theme_constant_override("h_separation", 6)
			chip_row.add_theme_constant_override("v_separation", 4)
			col.add_child(chip_row)
			for item: Variant in choice.chips:
				chip_row.add_child(Kit.chip(str(item[0]), str(item[1])))
	_register_buttons(panel)
	_event_time_total = float(TuningStore.get_value("gameplay.event.timer", 10.0)) + float(_event.get("timer_bonus", 0))
	if _first_mission:
		_event_time_total += 5.0
	_event_time_left = _event_time_total
	if not notice_only and int(_event.get("timer_bonus", 0)) > 0:
		_show_toast("Your radio heard NASA's warning early: +%d seconds to decide!" % int(_event.timer_bonus), 3.5)
	if not _event_choice_buttons.is_empty():
		_event_choice_buttons[0].grab_focus()


func _process_event(delta: float) -> void:
	if _event_resolved or bool(_event.get("notice_only", false)) or _event_timer_bar == null:
		return
	_event_time_left -= delta
	_event_timer_bar.max_value = _event_time_total
	_event_timer_bar.value = maxf(0.0, _event_time_left)
	_event_timer_label.text = "%d" % ceili(maxf(0.0, _event_time_left))
	_event_timer_label.add_theme_color_override("font_color", Kit.BAD if _event_time_left < 4.0 else Kit.WARN)
	if _event_time_left <= 0.0:
		_resolve_event(-1)


func _on_event_choice(index: int) -> void:
	if _event_resolved or _event.is_empty() or _transmission_left > 0.0:
		return
	_resolve_event(index)


func _resolve_event(index: int) -> void:
	_event_resolved = true
	var shelter := false
	if index >= 0:
		shelter = bool((_event.choices[index] as Dictionary).get("shelter", false))
	var result := EventDeck.resolve(sim, _event, index)
	if shelter:
		_view.set_crew_hidden(true)
	if str(_event.id) == "lander_dust":
		if index != 0:
			_view.dust_burst()
		_view.lander_leave()
	AudioDirector.play_cue("ui.cancel" if index < 0 else "score.reward")
	_refresh_hud()
	_refresh_plan()
	_show_event_result(result)


func _show_event_result(result: String) -> void:
	_clear_modal()
	_modal_layer.add_child(Kit.dimmer(0.45))
	var panel := PanelContainer.new()
	panel.name = "ResultCard"
	panel.add_theme_stylebox_override("panel", Kit.box(Color(0.06, 0.08, 0.2, 0.98), Kit.WHITE, 4, 8, 18))
	panel.position = Vector2(84, 150)
	panel.custom_minimum_size = Vector2(760, 0)
	_modal_layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(Kit.label("WHAT HAPPENED", 24, Kit.ORANGE, true))
	var res := Kit.label(result, 20, Kit.WHITE, false, true)
	res.custom_minimum_size = Vector2(720, 0)
	vb.add_child(res)
	var fact := PanelContainer.new()
	fact.add_theme_stylebox_override("panel", Kit.box(Color(0.09, 0.4, 0.55, 0.25), Kit.BLUE, 2, 0, 10))
	var fact_box := VBoxContainer.new()
	fact.add_child(fact_box)
	fact_box.add_child(Kit.label("REAL SPACE FACT", 16, Kit.BLUE, true))
	var fact_text := Kit.label(str(_event.get("fact", "")), 16, Color("cfefff"), false, true)
	fact_text.custom_minimum_size = Vector2(690, 0)
	fact_box.add_child(fact_text)
	fact_box.add_child(Kit.label(str(_event.get("source", "")), 13, Kit.MUTED, false, true))
	vb.add_child(fact)
	var ok := Kit.button("CONTINUE  >", "primary", 22)
	ok.name = "ContinueButton"
	ok.custom_minimum_size = Vector2(260, 56)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(_close_event)
	vb.add_child(ok)
	_register_buttons(panel)
	ok.grab_focus()


func _close_event() -> void:
	if _event.is_empty():
		return
	var was_storm := bool(_event.get("storm", false))
	_event = {}
	_event_timer_bar = null
	_clear_modal()
	if was_storm:
		_view.set_storm(false)
		_view.set_crew_hidden(false)
	_view.set_running(sim.phase == "day")
	if sim.outcome != "" and sim.outcome != "win":
		_finish_mission()


# =============================================================== night report

func _show_night_report(report: Dictionary) -> void:
	_clear_modal()
	_modal_layer.add_child(Kit.dimmer(0.35))
	var panel := PanelContainer.new()
	panel.name = "NightReport"
	panel.add_theme_stylebox_override("panel", Kit.box(Color(0.05, 0.07, 0.18, 0.98), Kit.WHITE, 4, 8, 18))
	panel.position = Vector2(84, 110)
	panel.custom_minimum_size = Vector2(760, 0)
	_modal_layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(Kit.label("DAY %d REPORT" % int(report.day), 28, Kit.ORANGE, true))
	var start: Dictionary = report.start
	var finish: Dictionary = report.end
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	for id: String in ["air", "food", "battery", "shield", "dose", "science"]:
		var info: Dictionary = METER_INFO[id]
		var a := float(start.get(id, 0.0))
		var b := float(finish.get(id, 0.0))
		var diff := b - a
		var good := diff >= -0.5 if id != "dose" else diff <= 2.5
		var arrow := "same" if absf(diff) < 0.5 else (("+%d" % roundi(diff)) if diff > 0 else ("%d" % roundi(diff)))
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(220, 0)
		cell.add_child(Kit.label(str(info.name), 18, info.color, true))
		cell.add_child(Kit.label("  %d  (%s)" % [roundi(b) if id != "science" else floori(b), arrow], 18, Kit.GOOD if good else Kit.BAD, true))
		grid.add_child(cell)
	var charge := int(report.get("charge", 0))
	vb.add_child(Kit.label("Night: unused sunlight charged the battery +%d. Heaters used -%d." % [charge, int(sim.NIGHT_HEAT)], 16, Kit.POWER_C, false, true))
	var notes: Array = report.get("notes", [])
	for note: Variant in notes.slice(maxi(0, notes.size() - 3)):
		var n := Kit.label("• " + str(note), 15, Kit.MUTED, false, true)
		n.custom_minimum_size = Vector2(720, 0)
		vb.add_child(n)
	var tip_panel := PanelContainer.new()
	tip_panel.add_theme_stylebox_override("panel", Kit.box(Color(0.9, 0.38, 0.11, 0.18), Kit.ORANGE, 2, 0, 10))
	var tip_label := Kit.label("MISSION CONTROL TIP: " + _commander_tip(), 17, Color("ffd9c2"), false, true)
	tip_label.custom_minimum_size = Vector2(700, 0)
	tip_panel.add_child(tip_label)
	vb.add_child(tip_panel)
	var label := "FINISH MISSION  >" if sim.outcome == "win" else ("PLAN DAY %d  >" % sim.day)
	var ok := Kit.button(label, "primary", 22)
	ok.name = "ContinueButton"
	ok.custom_minimum_size = Vector2(280, 56)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(_close_night_report)
	vb.add_child(ok)
	_register_buttons(panel)
	ok.grab_focus()


func _commander_tip() -> String:
	var f: Dictionary = sim.forecast()
	if sim.outcome == "win":
		return "You did it! Your crew made it through every day."
	if sim.air < 35.0:
		return "Air is low! Each Air Maker cell makes 6 air. The crew needs 12 a day, so use at least 2 cells, or 3 to catch up."
	if sim.food < 30.0:
		return "Food is running low. Give the greenhouse 2 or more cells."
	if sim.battery <= 2:
		return "Your battery is almost empty. Leave some sunlight cells unused so they charge the battery for the night."
	if sim.dose > 60.0:
		return "The crew's radiation dose is high. Build shielding and use the storm shelter in the next solar storm."
	if sim.dust > 0.35:
		return "Dusty panels make less power. Cleaning costs a little dose, but gives power back."
	if sim.shield < 30.0 and sim.day < sim.days_total - 1:
		return "Solar storms are coming. Shielding blocks radiation for the rest of the mission."
	if int(sim.alloc.radio) == 0:
		return "Power the Earth Radio to hear NASA's storm warnings early and get more time to decide."
	if float(f.get("science", 0.0)) < 1.0:
		return "Everything looks steady. Send spare cells to the lab to earn science and a higher rank!"
	return "Great balance, commander! Keep an eye on the Sun."


func _close_night_report() -> void:
	if _pending_report.is_empty():
		return
	_clear_modal()
	_pending_report = {}
	_night_time = -1.0
	_view.set_night(0.0)
	if sim.outcome == "win":
		_finish_mission()
		return
	_refresh_plan()
	_refresh_hud()
	_start_button.grab_focus()


# ===================================================================== mission

func _start_mission() -> void:
	_close_overlays()
	_clear_modal()
	TuningStore.begin_run(false)
	_first_mission = not SaveStore.is_tutorial_completed()
	var options := {
		"days": int(TuningStore.get_value("gameplay.mission.days", 10.0)),
		"solar_max": int(TuningStore.get_value("environment.solar.max_cells", 8.0)),
		"air_use": float(TuningStore.get_value("environment.crew.air_use", 12.0)),
		"live_flare": donki.live_event(),
	}
	sim.start(0, options)
	_event = {}
	_event_queue.clear()
	_pending_report = {}
	_night_time = -1.0
	_transmission_left = 0.0
	_fast = false
	_fast_button.text = ">> FASTER"
	_paused = false
	_screen = "game"
	_hud.visible = true
	_view.visible = true
	_view.set_night(0.0)
	_view.set_storm(false)
	_view.set_crew_hidden(false)
	_view.set_running(false)
	_update_data_chip()
	_refresh_plan()
	_refresh_hud()
	if _first_mission:
		_coach_step = 0
		_show_coach()
	else:
		_coach_step = -1
		_coach.visible = false
		_coach_frame.visible = false
		_show_toast("Day 1: share out today's solar power, then press START DAY.", 4.0)
	_start_button.grab_focus()


func _finish_mission() -> void:
	if _screen != "game":
		return
	_screen = "result"
	_clear_modal()
	_event = {}
	_coach.visible = false
	_coach_frame.visible = false
	_view.set_storm(false)
	_view.set_running(false)
	_view.set_night(0.0)
	TuningStore.end_run()
	SaveStore.set_tutorial_completed(true)
	var win: bool = sim.outcome == "win"
	AudioDirector.play_cue("game.victory" if win else "game.defeat")
	if win:
		_view.cheer()
	_build_result(win)


func _failure_lesson() -> Dictionary:
	match str(sim.outcome):
		"air":
			return {
				"title": "The air ran out",
				"why": "The Air Maker did not get enough power. Two astronauts breathe 12 air every day, and one cell only makes 6.",
				"fix": "Next time: keep at least 2 cells on the Air Maker every day. Save battery for the night so the heaters don't steal life-support power.",
				"fact": NasaData.FACTS.oxygen_iss,
			}
		"food":
			return {
				"title": "The food ran out",
				"why": "The greenhouse did not get enough light and power to feed the crew. They eat 9 food a day.",
				"fix": "Next time: give the greenhouse 2 cells most days, and give the plants extra light when they are in trouble.",
				"fact": NasaData.FACTS.veggie,
			}
		"dose":
			return {
				"title": "Too much radiation",
				"why": "The crew's radiation dose reached the safe limit. Solar storms add a lot of dose if the crew stays outside, and cosmic rays add a little every day.",
				"fix": "Next time: build shielding early, power the radio to get storm warnings, and use the storm shelter.",
				"fact": NasaData.FACTS.artemis_mare + " " + NasaData.FACTS.gcr_hard,
			}
	return {"title": "Mission ended", "why": "", "fix": "", "fact": ""}


# ===================================================================== screens

func _build_title() -> void:
	_title_screen = Control.new()
	_title_screen.name = "TitleScreen"
	Kit.full_rect(_title_screen)
	add_child(_title_screen)
	_title_screen.add_child(Kit.texture_rect("res://assets/game/scene/bg_title.png", Vector2(1280, 720), false))
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.1, 0.35)
	Kit.full_rect(shade)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_screen.add_child(shade)
	var logo := Kit.texture_rect("res://assets/game/ui/logo.png", Vector2(470, 311))
	logo.position = Vector2(405, 14)
	_title_screen.add_child(logo)
	var sub := Kit.outline(Kit.label("JUNIOR ASTRONAUT MISSION TRAINER", 26, Kit.WHITE, true), 8)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(240, 334)
	sub.size = Vector2(800, 36)
	_title_screen.add_child(sub)
	var pitch := Kit.outline(Kit.label("Run a real Moon base. Share out the power, survive real solar storms, keep your crew safe!", 18, Color("dbe6ff")), 6)
	pitch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pitch.position = Vector2(140, 372)
	pitch.size = Vector2(1000, 30)
	_title_screen.add_child(pitch)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 12)
	menu.position = Vector2(470, 416)
	menu.custom_minimum_size = Vector2(340, 0)
	_title_screen.add_child(menu)
	var play := Kit.button("START MISSION", "primary", 30)
	play.name = "PlayButton"
	play.custom_minimum_size = Vector2(340, 70)
	play.pressed.connect(_start_mission)
	menu.add_child(play)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	menu.add_child(row)
	var howto := Kit.button("HOW TO PLAY", "secondary", 18)
	howto.custom_minimum_size = Vector2(164, 52)
	howto.pressed.connect(_show_howto)
	row.add_child(howto)
	var data := Kit.button("NASA DATA", "blue", 18)
	data.name = "NasaDataButton"
	data.custom_minimum_size = Vector2(164, 52)
	data.pressed.connect(_show_nasa)
	row.add_child(data)
	var intro := Kit.button("WATCH STORY INTRO", "ghost", 16)
	intro.custom_minimum_size = Vector2(340, 44)
	intro.pressed.connect(_replay_intro)
	intro.visible = OS.has_feature("web")
	menu.add_child(intro)
	_title_status = Kit.outline(Kit.label("", 15, Kit.WARN, false, true), 6)
	_title_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_status.position = Vector2(240, 646)
	_title_status.size = Vector2(800, 30)
	_title_screen.add_child(_title_status)
	var credit := Kit.outline(Kit.label("NASA Space Apps Challenge Cairo 2026  ·  Space data: NASA DONKI, OSDR, Artemis", 13, Kit.MUTED), 5)
	credit.position = Vector2(16, 692)
	_title_screen.add_child(credit)
	var licenses := Kit.button("Licenses", "ghost", 13)
	licenses.name = "OpenSourceLicensesButton"
	licenses.position = Vector2(1170, 672)
	licenses.custom_minimum_size = Vector2(96, 36)
	licenses.pressed.connect(OpenSourceLicenses.open.bind(self))
	_title_screen.add_child(licenses)
	_register_buttons(_title_screen)


func _show_title() -> void:
	_close_overlays()
	_clear_modal()
	_screen = "title"
	_paused = false
	_event = {}
	_hud.visible = false
	_coach.visible = false
	_coach_frame.visible = false
	_title_screen.visible = true
	_update_data_chip()
	var play := _title_screen.find_child("PlayButton", true, false) as Button
	if play != null:
		play.grab_focus()


func _replay_intro() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.astroQuestPlayIntro && window.astroQuestPlayIntro()", true)


func _overlay_screen(title: String) -> Array:
	var screen := Control.new()
	Kit.full_rect(screen)
	add_child(screen)
	screen.add_child(Kit.dimmer(0.8))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Kit.box(Color(0.05, 0.07, 0.18, 0.98), Kit.WHITE, 4, 8, 20))
	panel.position = Vector2(110, 40)
	panel.custom_minimum_size = Vector2(1060, 640)
	panel.size = Vector2(1060, 640)
	screen.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var t := Kit.label(title, 32, Kit.ORANGE, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Kit.button("BACK", "secondary", 18)
	close.name = "BackButton"
	close.custom_minimum_size = Vector2(120, 46)
	close.pressed.connect(func() -> void:
		screen.queue_free()
		var focus_target: Button = null
		if _screen == "title":
			focus_target = _title_screen.find_child("PlayButton", true, false) as Button
		elif _result_screen != null and is_instance_valid(_result_screen):
			focus_target = _result_screen.find_child("AgainButton", true, false) as Button
		if focus_target != null:
			focus_target.grab_focus()
	)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	AudioDirector.register_button(close, true)
	close.grab_focus()
	return [screen, content]


func _show_nasa() -> void:
	var parts := _overlay_screen("NASA DATA USED IN THIS GAME")
	_nasa_screen = parts[0]
	var content: VBoxContainer = parts[1]
	var live: bool = donki.status == "live"
	var status := PanelContainer.new()
	status.add_theme_stylebox_override("panel", Kit.box(Color(0.9, 0.75, 0.2, 0.15) if live else Color(0.09, 0.4, 0.55, 0.2), Kit.WARN if live else Kit.BLUE, 2, 0, 10))
	var status_label := Kit.label(donki.summary_text(), 18, Kit.WARN if live else Color("cfefff"), false, true)
	status_label.custom_minimum_size = Vector2(980, 0)
	status.add_child(status_label)
	content.add_child(status)
	content.add_child(Kit.label("Astro Quest is a game, but its storms and science come from real NASA data. Here is what we used and why:", 18, Kit.WHITE, false, true))
	for source: Dictionary in NasaData.SOURCES:
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.05), Kit.MUTED, 2, 0, 10))
		var v := VBoxContainer.new()
		box.add_child(v)
		v.add_child(Kit.label(str(source.name), 20, Kit.BLUE, true))
		v.add_child(Kit.label(str(source.url), 14, Kit.MUTED))
		var use := Kit.label(str(source.use), 16, Kit.WHITE, false, true)
		use.custom_minimum_size = Vector2(960, 0)
		v.add_child(use)
		content.add_child(box)
	content.add_child(Kit.label("ARCHIVED REAL SOLAR EVENTS (from NASA DONKI records)", 20, Kit.ORANGE, true))
	content.add_child(Kit.label("Each mission picks a few of these at random, so every playthrough is different.", 15, Kit.MUTED, false, true))
	var type_names := {"FLR": "Solar flare", "SEP": "Radiation storm", "CME": "CME"}
	for event: Dictionary in NasaData.SPACE_WEATHER_ARCHIVE:
		var line := Kit.label("%s  ·  %s  ·  %s: %s" % [str(event.date), str(type_names.get(str(event.type), "Event")), str(event["class"]), str(event.detail)], 15, Kit.WHITE, false, true)
		line.custom_minimum_size = Vector2(980, 0)
		content.add_child(line)
	content.add_child(Kit.label("Simplified for play: game numbers like '28 dose' are easy-to-read game points. Real radiation is measured in millisieverts (mSv).", 14, Kit.MUTED, false, true))


func _show_howto() -> void:
	var parts := _overlay_screen("HOW TO PLAY")
	_howto_screen = parts[0]
	var content: VBoxContainer = parts[1]
	var steps := [
		["res://assets/game/icons/power.png", "1. Share out the sunlight", "Every morning your solar panels give you power cells. Tap + and - to send cells to the Air Maker, Greenhouse, Lab, Shield Builder or Earth Radio. Cells you don't use charge the battery."],
		["res://assets/game/icons/air.png", "2. Keep the crew alive", "Two astronauts need 12 air and 9 food every day. At night the heaters always use 2 battery cells. If the battery is empty, the heaters take power from life support!"],
		["res://assets/game/events/flare.png", "3. Decide fast!", "Surprises happen during the day: real solar storms, dust blasts, air leaks. You have about 10 seconds to choose. Every choice costs something. If time runs out, the base picks for you."],
		["res://assets/game/icons/radiation.png", "4. Watch the radiation dose", "Space radiation adds up and never goes away. Shielding blocks part of it and the storm shelter blocks most of it. Keep the dose under 100."],
		["res://assets/game/icons/science.png", "5. Make discoveries", "Survive all the days to finish the mission. Earn science in the lab to become a Mission Legend!"],
	]
	for step: Array in steps:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.add_child(Kit.texture_rect(str(step[0]), Vector2(64, 64)))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(Kit.label(str(step[1]), 22, Kit.ORANGE, true))
		var d := Kit.label(str(step[2]), 17, Kit.WHITE, false, true)
		d.custom_minimum_size = Vector2(900, 0)
		v.add_child(d)
		row.add_child(v)
		content.add_child(row)
	content.add_child(Kit.label("Controls: mouse or touch. Keyboard: Tab to move, Enter to press, 1/2/3 for choices, Space to start the day, Esc to pause.", 15, Kit.MUTED, false, true))


func _open_pause() -> void:
	if _screen != "game" or _paused:
		return
	_paused = true
	AudioDirector.set_game_paused(true)
	AudioDirector.play_cue("game.pause")
	_pause_screen = Control.new()
	_pause_screen.name = "PauseScreen"
	Kit.full_rect(_pause_screen)
	add_child(_pause_screen)
	_pause_screen.add_child(Kit.dimmer(0.7))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Kit.box(Color(0.05, 0.07, 0.18, 0.98), Kit.WHITE, 4, 8, 24))
	panel.position = Vector2(440, 170)
	panel.custom_minimum_size = Vector2(400, 0)
	_pause_screen.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var t := Kit.label("PAUSED", 34, Kit.ORANGE, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var resume := Kit.button("RESUME", "primary", 24)
	resume.custom_minimum_size = Vector2(0, 58)
	resume.pressed.connect(_close_pause)
	vb.add_child(resume)
	var help := Kit.button("HOW TO PLAY", "secondary", 18)
	help.custom_minimum_size = Vector2(0, 48)
	help.pressed.connect(_show_howto)
	vb.add_child(help)
	var restart := Kit.button("RESTART MISSION", "secondary", 18)
	restart.custom_minimum_size = Vector2(0, 48)
	restart.pressed.connect(func() -> void:
		_close_pause()
		TuningStore.end_run()
		_start_mission()
	)
	vb.add_child(restart)
	var quit := Kit.button("MAIN MENU", "ghost", 18)
	quit.custom_minimum_size = Vector2(0, 48)
	quit.pressed.connect(func() -> void:
		_close_pause()
		TuningStore.end_run()
		_show_title()
	)
	vb.add_child(quit)
	_register_buttons(panel)
	resume.grab_focus()


func _close_pause() -> void:
	if _pause_screen != null and is_instance_valid(_pause_screen):
		_pause_screen.queue_free()
	_pause_screen = null
	if _howto_screen != null and is_instance_valid(_howto_screen):
		_howto_screen.queue_free()
	_howto_screen = null
	_paused = false
	AudioDirector.set_game_paused(false)
	if _event_choice_buttons.size() > 0 and is_instance_valid(_event_choice_buttons[0]) and not _event.is_empty():
		_event_choice_buttons[0].grab_focus()


func _build_result(win: bool) -> void:
	_result_screen = Control.new()
	_result_screen.name = "ResultScreen"
	Kit.full_rect(_result_screen)
	add_child(_result_screen)
	_result_screen.add_child(Kit.dimmer(0.55 if win else 0.72))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Kit.box(Color(0.05, 0.07, 0.18, 0.97), Kit.ORANGE if win else Kit.WHITE, 4, 8, 20))
	panel.position = Vector2(120, 26)
	panel.custom_minimum_size = Vector2(1040, 668)
	panel.size = Vector2(1040, 668)
	_result_screen.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	vb.add_child(top)
	top.add_child(Kit.texture_rect("res://assets/game/ui/logo.png", Vector2(200, 132)))
	var head := VBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(head)
	var rank: Dictionary = sim.rank()
	if win:
		head.add_child(Kit.label("MISSION COMPLETE!", 40, Kit.ORANGE, true))
		var rank_row := HBoxContainer.new()
		rank_row.add_theme_constant_override("separation", 14)
		var stars := PipBar.new()
		stars.star = true
		stars.total = 3
		stars.pip_size = 30.0
		stars.gap = 6.0
		stars.color = Kit.WARN
		stars.filled = int(rank.stars)
		stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rank_row.add_child(stars)
		rank_row.add_child(Kit.label(str(rank.name).to_upper(), 28, Kit.WARN, true))
		head.add_child(rank_row)
		var next_hint := "Earn more science to reach the next rank!" if int(rank.stars) < 3 else "The best rank there is. Amazing!"
		head.add_child(Kit.label("Your crew survived %d days on the Moon. %s" % [sim.days_total, next_hint], 18, Kit.WHITE, false, true))
	else:
		var lesson := _failure_lesson()
		head.add_child(Kit.label("MISSION ENDED ON DAY %d" % sim.day, 34, Kit.ORANGE, true))
		head.add_child(Kit.label(str(lesson.title).to_upper(), 26, Kit.WARN, true))
		head.add_child(Kit.label("The crew flew home safely in the return capsule. Every real astronaut learns from tough days. Let's try again!", 17, Kit.WHITE, false, true))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 16)
	vb.add_child(stats)
	for item: Array in [["SCIENCE", "%d" % floori(sim.science), Kit.PURPLE], ["DOSE", "%d / 100" % roundi(sim.dose), Kit.DOSE_C], ["STORMS FACED", str(sim.storms_survived), Kit.WARN], ["SHELTER USED", str(sim.shelter_uses), Kit.SHIELD_C], ["AIR LEFT", "%d" % roundi(sim.air), Kit.AIR_C], ["FOOD LEFT", "%d" % roundi(sim.food), Kit.FOOD_C]]:
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.05), item[2], 2, 0, 8))
		box.custom_minimum_size = Vector2(150, 0)
		var v := VBoxContainer.new()
		box.add_child(v)
		v.add_child(Kit.label(str(item[0]), 14, item[2], true))
		v.add_child(Kit.label(str(item[1]), 24, Kit.WHITE, true))
		stats.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	if not win:
		var lesson := _failure_lesson()
		var why := PanelContainer.new()
		why.add_theme_stylebox_override("panel", Kit.box(Color(0.9, 0.38, 0.11, 0.15), Kit.ORANGE, 2, 0, 10))
		var wv := VBoxContainer.new()
		why.add_child(wv)
		wv.add_child(Kit.label("WHAT WENT WRONG", 18, Kit.ORANGE, true))
		var w1 := Kit.label(str(lesson.why), 17, Kit.WHITE, false, true)
		w1.custom_minimum_size = Vector2(960, 0)
		wv.add_child(w1)
		var w2 := Kit.label(str(lesson.fix), 17, Color("ffd9c2"), false, true)
		w2.custom_minimum_size = Vector2(960, 0)
		wv.add_child(w2)
		content.add_child(why)
		var fact := Kit.label("REAL SPACE FACT: " + str(lesson.fact), 16, Color("cfefff"), false, true)
		fact.custom_minimum_size = Vector2(980, 0)
		content.add_child(fact)
	content.add_child(Kit.label("YOUR MISSION LOG", 18, Kit.BLUE, true))
	if sim.mission_log.is_empty():
		content.add_child(Kit.label("No big decisions this time.", 15, Kit.MUTED))
	for entry: Dictionary in sim.mission_log:
		var line := Kit.label("Day %d · %s  >  %s" % [int(entry.day), str(entry.title), str(entry.choice)], 15, Kit.WHITE, false, true)
		line.custom_minimum_size = Vector2(980, 0)
		content.add_child(line)
	var real_events: Array[String] = []
	for d: Variant in sim.schedule:
		for e: Dictionary in sim.schedule[d]:
			var data: Dictionary = e.get("data", {})
			if not data.is_empty() and bool(e.get("done", false)):
				var label := "%s %s (%s)" % [str(data.date), str(data.headline), "LIVE NASA DONKI" if bool(data.get("live", false)) else "archived NASA DONKI record"]
				if label not in real_events:
					real_events.append(label)
	if not real_events.is_empty():
		var real := Kit.label("REAL SOLAR EVENTS YOU FACED: " + ";  ".join(real_events), 15, Kit.WARN, false, true)
		real.custom_minimum_size = Vector2(980, 0)
		content.add_child(real)
	var twins := Kit.label(NasaData.FACTS.twins, 14, Kit.MUTED, false, true)
	twins.custom_minimum_size = Vector2(980, 0)
	content.add_child(twins)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(buttons)
	var data_button := Kit.button("NASA DATA", "blue", 18)
	data_button.custom_minimum_size = Vector2(170, 54)
	data_button.pressed.connect(_show_nasa)
	buttons.add_child(data_button)
	var menu := Kit.button("MAIN MENU", "secondary", 18)
	menu.custom_minimum_size = Vector2(170, 54)
	menu.pressed.connect(_show_title)
	buttons.add_child(menu)
	var again := Kit.button("NEW MISSION" if win else "TRY AGAIN", "primary", 24)
	again.name = "AgainButton"
	again.custom_minimum_size = Vector2(240, 58)
	again.pressed.connect(_start_mission)
	buttons.add_child(again)
	_register_buttons(_result_screen)
	again.grab_focus()


func _close_overlays() -> void:
	for node: Variant in [_result_screen, _pause_screen, _nasa_screen, _howto_screen]:
		if node != null and is_instance_valid(node):
			(node as Node).queue_free()
	_result_screen = null
	_pause_screen = null
	_nasa_screen = null
	_howto_screen = null
	_title_screen.visible = false


func _clear_modal() -> void:
	for child: Node in _modal_layer.get_children():
		_modal_layer.remove_child(child)
		child.queue_free()


# ======================================================================= coach

func _build_coach() -> void:
	_coach_frame = Panel.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0, 0, 0, 0)
	frame_style.border_color = Kit.WARN
	frame_style.set_border_width_all(5)
	_coach_frame.add_theme_stylebox_override("panel", frame_style)
	_coach_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coach_frame.visible = false
	add_child(_coach_frame)
	_coach = PanelContainer.new()
	_coach.add_theme_stylebox_override("panel", Kit.box(Color("fff4d6"), Kit.ORANGE, 4, 6, 14))
	_coach.custom_minimum_size = Vector2(420, 0)
	_coach.visible = false
	add_child(_coach)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_coach.add_child(vb)
	vb.add_child(Kit.label("TRAINING TIP", 16, Kit.ORANGE, true))
	_coach_label = Kit.label("", 18, Color("1a1f3a"), false, true)
	_coach_label.custom_minimum_size = Vector2(390, 0)
	vb.add_child(_coach_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var skip := Kit.button("SKIP TRAINING", "small", 14)
	skip.custom_minimum_size = Vector2(0, 40)
	skip.pressed.connect(_end_coach)
	row.add_child(skip)
	var next := Kit.button("GOT IT", "primary", 16)
	next.name = "CoachNext"
	next.custom_minimum_size = Vector2(110, 40)
	next.pressed.connect(_coach_next)
	row.add_child(next)
	_register_buttons(_coach)


func _show_coach() -> void:
	var steps := [
		["Welcome, Commander! These meters show your base. Tap any meter to learn what it means. Air and food go down every day.", Rect2(160, 6, 1000, 84), Vector2(380, 110)],
		["The Sun gives you power cells every morning. Tap + to send cells where they are needed. Try giving 1 cell to the SCIENCE LAB.", Rect2(918, 98, 356, 478), Vector2(470, 200)],
		["Cells you don't use charge the battery for tonight's heaters. When you are ready, press START DAY!", Rect2(918, 580, 356, 132), Vector2(470, 440)],
	]
	if _coach_step < 0 or _coach_step >= steps.size():
		_end_coach()
		return
	var step: Array = steps[_coach_step]
	_coach_label.text = str(step[0])
	var rect: Rect2 = step[1]
	_coach_frame.position = rect.position - Vector2(4, 4)
	_coach_frame.size = rect.size + Vector2(8, 8)
	_coach_frame.visible = true
	_coach.position = step[2]
	_coach.visible = true
	(_coach.find_child("CoachNext", true, false) as Button).visible = _coach_step != 2
	move_child(_coach_frame, get_child_count() - 1)
	move_child(_coach, get_child_count() - 1)


func _coach_next() -> void:
	if _coach_step < 0:
		return
	_coach_step += 1
	if _coach_step >= 3:
		_end_coach()
	else:
		_show_coach()


func _end_coach() -> void:
	_coach_step = -1
	_coach.visible = false
	_coach_frame.visible = false
	SaveStore.set_tutorial_completed(true)


# ======================================================================= misc

func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", Kit.box(Color(0.04, 0.06, 0.15, 0.95), Kit.WARN, 3, 5, 10))
	_toast.position = Vector2(30, 640)
	_toast.custom_minimum_size = Vector2(860, 0)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	add_child(_toast)
	_toast_label = Kit.label("", 17, Kit.WHITE, false, true)
	_toast_label.custom_minimum_size = Vector2(830, 0)
	_toast.add_child(_toast_label)


func _show_toast(text: String, seconds: float = 3.0) -> void:
	_toast_label.text = text
	_toast_time = seconds
	_toast.visible = true
	_toast.reset_size()
	_toast.position = Vector2(30, 704 - maxf(44.0, _toast.get_combined_minimum_size().y))
	move_child(_toast, get_child_count() - 1)


func _on_donki_finished(_status: String) -> void:
	_update_data_chip()


func _update_data_chip() -> void:
	var live: bool = donki.status == "live"
	var color := Kit.WARN if live else Kit.BLUE
	_data_chip_label.text = "LIVE + ARCHIVED NASA DATA" if live else "ARCHIVED NASA DATA"
	_data_chip.add_theme_stylebox_override("panel", Kit.box(color.darkened(0.72), color, 2, 0, 4))
	_data_chip_label.add_theme_color_override("font_color", color.lightened(0.25))
	if _title_status != null:
		_title_status.text = donki.summary_text()


func _on_tuning_changed(id: String, _requested: Variant, _active: Variant) -> void:
	if id == "ui.reduced_motion":
		_apply_motion_setting()


func _apply_motion_setting() -> void:
	_view.reduced_motion = bool(TuningStore.get_value("ui.reduced_motion", false))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _screen == "game" and not _paused:
			_open_pause()


func _unhandled_input(event: InputEvent) -> void:
	AudioDirector.unlock_audio()
	if event.is_action_pressed("pause"):
		if _screen == "game":
			if _paused:
				_close_pause()
			else:
				_open_pause()
			get_viewport().set_input_as_handled()
		return
	if _screen != "game" or _paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if not _event.is_empty() and not _event_resolved:
			var index := -1
			match key:
				KEY_1, KEY_KP_1:
					index = 0
				KEY_2, KEY_KP_2:
					index = 1
				KEY_3, KEY_KP_3:
					index = 2
			if index >= 0 and index < (_event.choices as Array).size():
				_on_event_choice(index)
				get_viewport().set_input_as_handled()
		elif key == KEY_SPACE and sim.phase == "plan" and _event.is_empty() and _modal_layer.get_child_count() == 0:
			_on_start_day()
			get_viewport().set_input_as_handled()
