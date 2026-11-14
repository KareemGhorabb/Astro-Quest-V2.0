extends Node
## Astro Quest checks: simulation rules, events, data labeling, tuning, boot.

const OutpostSim = preload("res://scripts/sim/outpost_sim.gd")
const EventDeck = preload("res://scripts/sim/event_deck.gd")
const NasaData = preload("res://scripts/sim/nasa_data.gd")
const LiveDonki = preload("res://scripts/net/live_donki.gd")

var _failures := PackedStringArray()
var _checks := 0
var _saved_save: Variant = null


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_saved_save = FileAccess.get_file_as_bytes(SaveStore.SAVE_PATH) if FileAccess.file_exists(SaveStore.SAVE_PATH) else null
	SaveStore.set("_data", SaveStore.call("_default_data"))
	_test_power_budget()
	_test_day_and_night()
	_test_failures()
	_test_schedule_and_events()
	_test_data_labels()
	_test_tuning()
	_test_assets()
	await _test_runtime_scene()
	_restore()
	if _failures.is_empty():
		print("[game-generic-tests] PASS: %d checks" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[game-generic-tests] " + failure)
	print("[game-generic-tests] FAIL: %d failures across %d checks" % [_failures.size(), _checks])
	get_tree().quit(1)


func _restore() -> void:
	if _saved_save == null:
		if FileAccess.file_exists(SaveStore.SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.SAVE_PATH))
	else:
		var file := FileAccess.open(SaveStore.SAVE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_saved_save)
			file.close()


func _check(condition: bool, context: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(context)


func _new_sim(seed_value: int = 1234) -> RefCounted:
	var sim: RefCounted = OutpostSim.new()
	sim.start(seed_value, {"days": 10, "solar_max": 8, "air_use": 12.0})
	return sim


func _empty_schedule(sim: RefCounted) -> void:
	sim.schedule = {}
	for d: int in range(1, 11):
		sim.schedule[d] = []


func _test_power_budget() -> void:
	var sim := _new_sim()
	_check(sim.phase == "plan", "mission starts in planning")
	_check(sim.cells_today == 8, "clean panels give 8 cells")
	_check(sim.allocated_total() == 4, "default plan uses 4 cells")
	_check(sim.available_cells() == 8 + 6, "budget includes battery")
	for i: int in 10:
		sim.add_cell("air")
	_check(int(sim.alloc.air) == 4, "air maker capped at 4 cells")
	for i: int in 10:
		sim.add_cell("food")
		sim.add_cell("lab")
		sim.add_cell("shield")
		sim.add_cell("radio")
	_check(sim.allocated_total() <= sim.available_cells(), "allocation never exceeds budget")
	_check(sim.battery_used_by_plan() == sim.allocated_total() - 8, "overspend comes from battery")
	var dusty := _new_sim()
	dusty.dust = 0.5
	_check(dusty.solar_cells() == 6, "50% dust costs about 30% of power (8 -> 6)")
	var dose_before: float = dusty.dose
	_check(dusty.clean_panels(), "cleaning works when dusty")
	_check(dusty.dust == 0.0 and dusty.dose > dose_before, "cleaning trades dose for power")
	_check(not dusty.clean_panels(), "only one cleaning per day")


func _run_day(sim: RefCounted) -> Dictionary:
	sim.begin_day()
	var guard := 0
	while not sim.day_finished() and guard < 200 and sim.outcome == "":
		var due: Dictionary = sim.tick(0.05)
		if not due.is_empty():
			var event: Dictionary = EventDeck.build(sim, due)
			if not event.is_empty():
				EventDeck.resolve(sim, event, 0)
		guard += 1
	if sim.outcome != "":
		return {}
	return sim.run_night()


func _test_day_and_night() -> void:
	var sim := _new_sim(42)
	_empty_schedule(sim)
	var air_before: float = sim.air
	var report := _run_day(sim)
	_check(not report.is_empty(), "day produces a report")
	_check(absf(sim.air - air_before) < 0.01, "2 air cells exactly balance crew breathing")
	_check(sim.day == 2 and sim.phase == "plan", "next morning starts")
	_check(int(report.charge) == 4, "4 unused cells charge the battery")
	_check(sim.battery == 6 + 4 - 2, "night heaters use 2 cells")
	_check(sim.dose > 0.0, "cosmic rays add background dose")
	var poor := _new_sim(7)
	_empty_schedule(poor)
	poor.battery = 0
	poor.alloc = {"air": 4, "food": 4, "lab": 0, "shield": 0, "radio": 0}
	poor.cells_today = 8
	var report2 := _run_day(poor)
	_check(poor.battery == 0, "battery cannot go negative")
	_check(int(report2.get("shortfall", 0)) == 2, "empty battery at night is a shortfall")


func _test_failures() -> void:
	var sim := _new_sim(5)
	_empty_schedule(sim)
	var guard := 0
	while sim.outcome == "" and guard < 20:
		sim.alloc.air = 0
		_run_day(sim)
		guard += 1
	_check(sim.outcome == "air", "no air maker power ends the mission by air")
	var dose_sim := _new_sim(9)
	dose_sim.apply_effects({"dose": 150})
	_check(dose_sim.outcome == "dose" and dose_sim.phase == "ended", "dose limit ends mission")
	var win := _new_sim(11)
	_empty_schedule(win)
	for d: int in 10:
		_run_day(win)
	_check(win.outcome == "win", "balanced plan survives all 10 days")
	_check(int(win.rank().stars) >= 1, "winning gives at least one star")


func _test_schedule_and_events() -> void:
	var seen := {}
	for seed_value: int in range(1, 30):
		var sim := _new_sim(seed_value)
		var storms := 0
		var lander := 0
		for d: Variant in sim.schedule:
			for entry: Dictionary in sim.schedule[d]:
				seen[str(entry.id)] = true
				if str(entry.id) in ["radiation_storm", "cme_arrival"]:
					storms += 1
				if str(entry.id) == "lander_dust":
					lander += 1
					_check(int(d) <= 2, "dust dilemma happens early")
				var built: Dictionary = EventDeck.build(sim, entry)
				_check(not built.is_empty(), "event builds: " + str(entry.id))
				_check(built.has("timeout"), "event has a timeout outcome: " + str(entry.id))
				if not bool(built.get("notice_only", false)):
					_check((built.choices as Array).size() >= 2, "decision has at least 2 options: " + str(entry.id))
		_check(storms >= 2, "each mission has real space weather (seed %d)" % seed_value)
		_check(lander == 1, "exactly one lander dust dilemma")
	for id: String in ["lander_dust", "radiation_storm", "meteor", "ice", "plants", "muscle", "earth_call", "shadow"]:
		_check(seen.has(id), "event appears across seeds: " + id)
	var a := _new_sim(100)
	var b := _new_sim(200)
	_check(JSON.stringify(a.schedule) != JSON.stringify(b.schedule), "different seeds give different missions")
	var sim := _new_sim(3)
	var storm := {"id": "radiation_storm", "data": NasaData.SPACE_WEATHER_ARCHIVE[0], "at": 0.5}
	var event: Dictionary = EventDeck.build(sim, storm)
	var hide_dose := float((event.choices[0] as Dictionary).effects.dose)
	var work_dose := float((event.choices[1] as Dictionary).effects.dose)
	_check(hide_dose < work_dose, "shelter blocks most storm dose")
	sim.begin_day()
	EventDeck.resolve(sim, event, -1)
	_check(sim.dose >= work_dose - 0.01, "timeout means crew stayed outside")
	_check(sim.mission_log.size() == 1 and str(sim.mission_log[0].choice).to_lower().contains("time ran out"), "timeout recorded in log")
	for seed_value: int in range(1, 6):
		var s := _new_sim(seed_value)
		for d: Variant in s.schedule:
			for entry: Dictionary in s.schedule[d]:
				var built: Dictionary = EventDeck.build(s, entry)
				if bool(built.get("notice_only", false)):
					continue
				for choice: Dictionary in built.choices:
					var has_cost := false
					for chip: Variant in choice.chips:
						if str(chip[1]) == "bad":
							has_cost = true
					_check(has_cost, "no free choice: %s / %s" % [str(entry.id), str(choice.label)])


func _test_data_labels() -> void:
	_check(NasaData.SPACE_WEATHER_ARCHIVE.size() >= 6, "archive has real events")
	for event: Dictionary in NasaData.SPACE_WEATHER_ARCHIVE:
		_check(str(event.date).length() >= 8 and str(event["class"]) != "", "archive event dated: " + str(event.id))
		_check(not bool(event.get("live", false)), "archive events are never live")
		var sim := _new_sim(1)
		var built: Dictionary = EventDeck.build(sim, {"id": "radiation_storm", "data": event, "at": 0.5})
		_check(str(built.source).contains("archived"), "archived label shown: " + str(event.id))
	var donki: Node = LiveDonki.new()
	_check(donki.live_event().is_empty(), "no live event before a successful fetch")
	_check(not donki.summary_text().begins_with("LIVE"), "not labeled live before fetch")
	donki.status = "live"
	donki.strongest = {"class": "X1.5", "date": "2026-11-01", "id": "t"}
	donki.flare_count = 3
	var live: Dictionary = donki.live_event()
	_check(bool(live.get("live", false)) and int(live.power) >= 20, "successful fetch creates live event")
	var sim2 := _new_sim(1)
	var built2: Dictionary = EventDeck.build(sim2, {"id": "radiation_storm", "data": live, "at": 0.5})
	_check(str(built2.source).begins_with("LIVE"), "live event labeled live")
	donki.free()
	_check(NasaData.SOURCES.size() >= 4, "attribution list exists")


func _test_tuning() -> void:
	for id: String in ["gameplay.mission.days", "gameplay.event.timer", "gameplay.day.length", "environment.solar.max_cells", "environment.crew.air_use", "audio.master.volume_db", "ui.reduced_motion"]:
		var setting: Dictionary = TuningStore.get_setting(id)
		_check(not setting.is_empty(), "tuning setting exists: " + id)
		_check(I18n.t(str(setting.get("label_key", ""))) != str(setting.get("label_key", "")), "tuning label localized: " + id)
	_check(float(TuningStore.get_value("gameplay.event.timer", 0)) == 10.0, "default countdown is 10 seconds")


func _test_assets() -> void:
	for path: String in [
		"res://assets/game/scene/bg_outpost.png", "res://assets/game/scene/bg_title.png", "res://assets/game/ui/logo.png",
		"res://assets/game/buildings/habitat.png", "res://assets/game/buildings/greenhouse.png", "res://assets/game/buildings/lab.png",
		"res://assets/game/buildings/shelter.png", "res://assets/game/buildings/panel_open.png", "res://assets/game/buildings/panel_closed.png",
		"res://assets/game/crew/astronaut_idle.png", "res://assets/game/crew/astronaut_walk.png", "res://assets/game/crew/astronaut_cheer.png",
		"res://assets/game/icons/air.png", "res://assets/game/icons/food.png", "res://assets/game/icons/power.png",
		"res://assets/game/icons/radiation.png", "res://assets/game/icons/science.png", "res://assets/game/events/flare.png",
		"res://assets/game/fonts/PixelifySans-VF.ttf",
	]:
		_check(ResourceLoader.exists(path), "asset exists: " + path)


func _test_runtime_scene() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main := packed.instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_check((main.get("_title_screen") as Control).visible, "boots to title")
	main.call("_start_mission")
	await get_tree().process_frame
	_check(str(main.get("_screen")) == "game", "start mission enters game")
	var sim: RefCounted = main.get("sim")
	_check(sim.phase == "plan", "first morning is planning")
	main.call("_end_coach")
	main.call("_on_cell", "lab", 1)
	_check(int(sim.alloc.lab) == 1, "plus button adds a lab cell")
	main.call("_on_start_day")
	_check(sim.phase == "day", "start day runs the day")
	main.call("_begin_event", {"id": "meteor", "data": {}, "at": 0.5})
	await get_tree().process_frame
	_check(not (main.get("_event") as Dictionary).is_empty(), "event card opens")
	main.call("_open_pause")
	_check(bool(main.get("_paused")), "pause works")
	var left := float(main.get("_event_time_left"))
	main.call("_process", 1.0)
	_check(is_equal_approx(float(main.get("_event_time_left")), left), "countdown frozen while paused")
	main.call("_close_pause")
	main.call("_on_event_choice", 1)
	_check(bool(main.get("_event_resolved")), "choice resolves the event")
	main.call("_close_event")
	_check((main.get("_event") as Dictionary).is_empty(), "event closes")
	sim.apply_effects({"air": -200})
	main.call("_finish_mission")
	await get_tree().process_frame
	_check(str(main.get("_screen")) == "result", "result screen after failure")
	_check(main.get("_result_screen") != null, "result screen built")
	main.call("_show_title")
	await get_tree().process_frame
	_check((main.get("_title_screen") as Control).visible, "back to title")
	main.call("_show_nasa")
	await get_tree().process_frame
	_check(main.get("_nasa_screen") != null, "NASA data screen opens")
	main.queue_free()
	await get_tree().process_frame
