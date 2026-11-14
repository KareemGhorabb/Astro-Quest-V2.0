extends RefCounted
## Authoritative Moon-outpost simulation. UI only reads state and calls the
## public methods below; every rule and number lives here.

const NasaData = preload("res://scripts/sim/nasa_data.gd")

const SYSTEMS: Array[String] = ["air", "food", "lab", "shield", "radio"]
const MAX_CELLS := {"air": 4, "food": 4, "lab": 4, "shield": 3, "radio": 1}
const BATTERY_MAX := 12
const NIGHT_HEAT := 2
const AIR_PER_CELL := 6.0
const FOOD_PER_CELL := 5.0
const FOOD_USE := 9.0
const SHIELD_PER_CELL := 8.0
const LAB_PER_CELL := 1.0
const BG_DOSE := 2.0
const CLEAN_DOSE := 2.0
const DOSE_LIMIT := 100.0
const NIGHT_SHORTFALL_AIR := 6.0
const NIGHT_SHORTFALL_FOOD := 3.0

const FILLER_EVENTS: Array[String] = ["meteor", "ice", "plants", "muscle", "earth_call", "shadow"]

var rng := RandomNumberGenerator.new()
var seed_value := 0
var days_total := 10
var solar_max := 8
var air_use := 12.0

var day := 1
var phase := "plan" # plan, day, night, ended
var air := 70.0
var food := 60.0
var battery := 6
var dose := 0.0
var shield := 20.0
var science := 0.0
var dust := 0.0
var panel_damage := 0
var cleaned_today := false
var alloc := {"air": 2, "food": 2, "lab": 0, "shield": 0, "radio": 0}
var cells_today := 0
var day_progress := 0.0
var mods := {}
var crew_tired := false
var crew_tired_next := false
var sheltered := false
var schedule := {}
var pending_cme := {}
var mission_log: Array[Dictionary] = []
var outcome := ""
var live_flare := {}
var day_start := {}
var day_notes: Array[String] = []
var storms_survived := 0
var shelter_uses := 0


func start(new_seed: int = 0, options: Dictionary = {}) -> void:
	seed_value = new_seed if new_seed != 0 else int(Time.get_ticks_usec() % 2147483647) + 1
	rng.seed = seed_value
	days_total = int(options.get("days", 10))
	solar_max = int(options.get("solar_max", 8))
	air_use = float(options.get("air_use", 12.0))
	live_flare = options.get("live_flare", {})
	day = 1
	phase = "plan"
	air = 70.0
	food = 60.0
	battery = 6
	dose = 0.0
	shield = 20.0
	science = 0.0
	dust = 0.0
	panel_damage = 0
	crew_tired = false
	crew_tired_next = false
	pending_cme = {}
	mission_log.clear()
	outcome = ""
	storms_survived = 0
	shelter_uses = 0
	alloc = {"air": 2, "food": 2, "lab": 0, "shield": 0, "radio": 0}
	_build_schedule()
	_begin_plan()


# ---------------------------------------------------------------- planning

func _begin_plan() -> void:
	phase = "plan"
	cleaned_today = false
	sheltered = false
	day_progress = 0.0
	mods = {"power_mult": 1.0, "lab_mult": 1.0, "food_mult": 1.0, "charge_mult": 1.0}
	crew_tired = crew_tired_next
	crew_tired_next = false
	cells_today = solar_cells()
	_clamp_alloc_to_budget()


func solar_cells() -> int:
	var healthy := maxi(0, solar_max - panel_damage)
	return maxi(0, roundi(healthy * (1.0 - 0.6 * dust)))


func allocated_total() -> int:
	var total := 0
	for key: String in SYSTEMS:
		total += int(alloc[key])
	return total


func available_cells() -> int:
	return cells_today + battery


func can_add(system: String) -> bool:
	return phase == "plan" and int(alloc[system]) < int(MAX_CELLS[system]) and allocated_total() < available_cells()


func can_remove(system: String) -> bool:
	return phase == "plan" and int(alloc[system]) > 0


func add_cell(system: String) -> bool:
	if not can_add(system):
		return false
	alloc[system] = int(alloc[system]) + 1
	return true


func remove_cell(system: String) -> bool:
	if not can_remove(system):
		return false
	alloc[system] = int(alloc[system]) - 1
	return true


func battery_used_by_plan() -> int:
	return maxi(0, allocated_total() - cells_today)


func leftover_cells() -> int:
	return maxi(0, cells_today - allocated_total())


func forecast_battery_tonight() -> int:
	return mini(BATTERY_MAX, battery - battery_used_by_plan() + leftover_cells()) - NIGHT_HEAT


func forecast() -> Dictionary:
	return {
		"air": int(alloc.air) * AIR_PER_CELL - air_use,
		"food": int(alloc.food) * FOOD_PER_CELL - FOOD_USE,
		"science": int(alloc.lab) * LAB_PER_CELL * (0.5 if crew_tired else 1.0),
		"shield": minf(100.0 - shield, int(alloc.shield) * SHIELD_PER_CELL),
		"dose": background_dose(),
		"battery": forecast_battery_tonight() - battery,
	}


func clean_panels() -> bool:
	if phase != "plan" or cleaned_today or dust <= 0.05:
		return false
	cleaned_today = true
	dust = 0.0
	dose += CLEAN_DOSE
	cells_today = solar_cells()
	_note("Crew dusted off the solar panels on a moonwalk (+%d dose)." % int(CLEAN_DOSE))
	_check_outcome()
	return true


func _clamp_alloc_to_budget() -> void:
	var order: Array[String] = ["radio", "shield", "lab", "food", "air"]
	while allocated_total() > available_cells():
		var removed := false
		for key: String in order:
			if int(alloc[key]) > 0:
				alloc[key] = int(alloc[key]) - 1
				removed = true
				break
		if not removed:
			break


# ---------------------------------------------------------------- day

func begin_day() -> void:
	if phase != "plan":
		return
	day_start = snapshot()
	day_notes.clear()
	battery -= battery_used_by_plan()
	phase = "day"
	day_progress = 0.0


func radio_on() -> bool:
	return int(alloc.radio) > 0


func background_dose() -> float:
	return BG_DOSE * (1.0 - shield / 100.0 * 0.3)


## Advance the day by `fraction` (0..1 of a full day). Returns a due event or {}.
func tick(fraction: float) -> Dictionary:
	if phase != "day":
		return {}
	var before := day_progress
	var step := minf(fraction, 1.0 - day_progress)
	day_progress += step
	var power := float(mods.power_mult)
	air += (int(alloc.air) * AIR_PER_CELL * power - air_use) * step
	food += (int(alloc.food) * FOOD_PER_CELL * power * float(mods.food_mult) - FOOD_USE) * step
	science += int(alloc.lab) * LAB_PER_CELL * power * float(mods.lab_mult) * (0.5 if crew_tired else 1.0) * step
	shield = minf(100.0, shield + int(alloc.shield) * SHIELD_PER_CELL * power * step)
	dose += background_dose() * step
	_clamp_resources()
	_check_outcome()
	if outcome != "":
		return {}
	for entry: Dictionary in schedule.get(day, []):
		if not bool(entry.get("done", false)) and before < float(entry.at) and day_progress >= float(entry.at):
			entry["done"] = true
			return entry
	return {}


func day_finished() -> bool:
	return phase == "day" and day_progress >= 1.0


## Charge the battery with unused solar cells, then pay for night heaters.
func run_night() -> Dictionary:
	if phase != "day":
		return {}
	phase = "night"
	var charge := roundi(leftover_cells() * float(mods.charge_mult))
	battery = mini(BATTERY_MAX, battery + charge)
	battery -= NIGHT_HEAT
	var shortfall := 0
	if battery < 0:
		shortfall = -battery
		battery = 0
		air -= NIGHT_SHORTFALL_AIR * shortfall
		food -= NIGHT_SHORTFALL_FOOD * shortfall
		_note("Battery ran out at night! Heaters stole power from life support (-%d air, -%d food)." % [int(NIGHT_SHORTFALL_AIR * shortfall), int(NIGHT_SHORTFALL_FOOD * shortfall)])
	dust = minf(1.0, dust + 0.04)
	_clamp_resources()
	_check_outcome()
	var report := {
		"day": day,
		"start": day_start,
		"end": snapshot(),
		"charge": charge,
		"shortfall": shortfall,
		"notes": day_notes.duplicate(),
	}
	if outcome == "":
		if day >= days_total:
			outcome = "win"
			phase = "ended"
		else:
			day += 1
			_begin_plan()
	return report


func snapshot() -> Dictionary:
	return {"air": air, "food": food, "battery": battery, "dose": dose, "shield": shield, "science": science, "dust": dust}


# ---------------------------------------------------------------- events

func storm_dose(power: float, in_shelter: bool) -> float:
	var blocked := 1.0 - 0.8 * shield / 100.0
	return power * blocked * (0.25 if in_shelter else 1.0)


## Apply a dictionary of effects. Keys: air, food, battery, dose, shield,
## science, dust, panel_damage, power_mult, lab_mult, food_mult, charge_mult.
func apply_effects(effects: Dictionary) -> void:
	for key: String in effects:
		var value: Variant = effects[key]
		match key:
			"air":
				air += float(value)
			"food":
				food += float(value)
			"dose":
				dose += float(value)
			"shield":
				shield = clampf(shield + float(value), 0.0, 100.0)
			"science":
				science = maxf(0.0, science + float(value))
			"dust":
				dust = clampf(dust + float(value), 0.0, 1.0)
			"panel_damage":
				panel_damage = mini(solar_max - 2, panel_damage + int(value))
			"battery":
				_spend_battery(int(value))
			"power_mult", "lab_mult", "food_mult", "charge_mult":
				mods[key] = float(mods.get(key, 1.0)) * float(value)
			"tired":
				crew_tired_next = bool(value)
			"shelter":
				sheltered = bool(value)
	_clamp_resources()
	_check_outcome()


## Negative amounts drain the battery; any shortfall slows today's machines.
func _spend_battery(amount: int) -> void:
	if amount >= 0:
		battery = mini(BATTERY_MAX, battery + amount)
		return
	var need := -amount
	var paid := mini(need, battery)
	battery -= paid
	var missing := need - paid
	if missing > 0:
		mods["power_mult"] = float(mods.power_mult) * maxf(0.2, 1.0 - missing / 6.0)
		_note("Battery was empty, so machines ran slower for the rest of the day.")


func log_decision(event: Dictionary, choice_label: String, result: String) -> void:
	mission_log.append({"day": day, "title": str(event.get("title", "")), "choice": choice_label, "result": result})
	_note(result)


func _note(text: String) -> void:
	day_notes.append(text)


func _clamp_resources() -> void:
	air = clampf(air, 0.0, 100.0)
	food = clampf(food, 0.0, 100.0)
	dose = clampf(dose, 0.0, DOSE_LIMIT)
	battery = clampi(battery, 0, BATTERY_MAX)


func _check_outcome() -> void:
	if outcome != "":
		return
	if dose >= DOSE_LIMIT:
		outcome = "dose"
	elif air <= 0.0:
		outcome = "air"
	elif food <= 0.0:
		outcome = "food"
	if outcome != "":
		phase = "ended"


func rank() -> Dictionary:
	if outcome != "win":
		return {"id": "trainee", "name": "Brave Trainee", "stars": 0}
	if science >= days_total * 1.6:
		return {"id": "legend", "name": "Mission Legend", "stars": 3}
	if science >= days_total * 1.0:
		return {"id": "commander", "name": "Outpost Commander", "stars": 2}
	return {"id": "survivor", "name": "Survival Expert", "stars": 1}


# ---------------------------------------------------------------- schedule

func _build_schedule() -> void:
	schedule = {}
	for d: int in range(1, days_total + 1):
		schedule[d] = []
	if days_total < 2:
		return
	# The signature lander-dust dilemma happens early in every mission.
	_add_event(rng.randi_range(1, mini(2, days_total)), "lander_dust", {})
	# Real archived space weather, spread over the mission.
	var storm_count := clampi(int(days_total / 3.0), 1, 4)
	var storms := NasaData.pick_archive_events(rng, storm_count)
	if not live_flare.is_empty() and storms.size() > 0:
		storms[0] = live_flare
	var span := float(days_total - 2) / float(storm_count)
	for index: int in storms.size():
		var lo := 3 + int(index * span)
		var hi := mini(days_total, 3 + int((index + 1) * span) - 1)
		var storm_day := clampi(rng.randi_range(lo, maxi(lo, hi)), 2, days_total)
		var data: Dictionary = storms[index]
		if str(data.get("type", "")) == "CME" and storm_day > 2:
			_add_event(storm_day - 1, "cme_warning", data, 0.55)
			_add_event(storm_day, "cme_arrival", data, 0.3)
		else:
			_add_event(storm_day, "radiation_storm", data, 0.45)
	# Everyday outpost surprises fill the remaining days.
	var fillers: Array[String] = FILLER_EVENTS.duplicate()
	_shuffle(fillers)
	var filler_index := 0
	for d: int in range(2, days_total + 1):
		var todays: Array = schedule[d]
		var wants := 1 if todays.is_empty() else 0
		if d >= 4 and todays.size() < 2 and rng.randf() < 0.45:
			wants += 1
		for _i: int in wants:
			_add_event(d, fillers[filler_index % fillers.size()], {})
			filler_index += 1
	for d: int in schedule:
		var entries: Array = schedule[d]
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.at) < float(b.at))
		# Keep events comfortably apart inside one day.
		for i: int in range(1, entries.size()):
			if float(entries[i].at) - float(entries[i - 1].at) < 0.25:
				entries[i]["at"] = minf(0.9, float(entries[i - 1].at) + 0.3)


func _add_event(on_day: int, id: String, data: Dictionary, at: float = -1.0) -> void:
	if not schedule.has(on_day):
		return
	var when := at if at >= 0.0 else rng.randf_range(0.25, 0.8)
	(schedule[on_day] as Array).append({"id": id, "data": data, "at": when, "done": false})


func _shuffle(items: Array) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
