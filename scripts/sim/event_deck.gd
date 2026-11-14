extends RefCounted
## Builds the timed decision cards and resolves the chosen option against the
## simulation. Every option has a cost; waiting too long is also a choice.

const NasaData = preload("res://scripts/sim/nasa_data.gd")


static func build(sim: RefCounted, entry: Dictionary) -> Dictionary:
	var id := str(entry.get("id", ""))
	var data: Dictionary = entry.get("data", {})
	var event: Dictionary
	match id:
		"lander_dust":
			event = _lander_dust(sim)
		"radiation_storm":
			event = _radiation_storm(sim, data, false)
		"cme_warning":
			event = _cme_warning(sim, data)
		"cme_arrival":
			event = _radiation_storm(sim, data, true)
		"meteor":
			event = _meteor(sim)
		"ice":
			event = _ice(sim)
		"plants":
			event = _plants(sim)
		"muscle":
			event = _muscle(sim)
		"earth_call":
			event = _earth_call(sim)
		"shadow":
			event = _shadow(sim)
		_:
			return {}
	event["id"] = id
	event["data"] = data
	if not event.has("from_earth"):
		event["from_earth"] = false
	return event


## Apply the option (or the timeout option when index < 0). Returns the result text.
static func resolve(sim: RefCounted, event: Dictionary, index: int) -> String:
	var timed_out := index < 0
	var choices: Array = event.get("choices", [])
	var chosen: Dictionary = event.get("timeout", {}) if timed_out else choices[clampi(index, 0, choices.size() - 1)]
	var effects: Dictionary = (chosen.get("effects", {}) as Dictionary).duplicate()
	var result := str(chosen.get("result", ""))
	var special := str(chosen.get("special", ""))
	if special == "panel_risk":
		if sim.rng.randf() < 0.3:
			effects["panel_damage"] = 1
			result += " Ouch! Flying rocks cracked one panel: you make 1 less power cell every day now."
		else:
			result += " Lucky: no panels were broken, but they are covered in dust."
	if bool(chosen.get("shelter", false)):
		sim.shelter_uses += 1
	if str(event.get("id", "")) in ["radiation_storm", "cme_arrival"]:
		sim.storms_survived += 1
	sim.apply_effects(effects)
	var label := "No order given (time ran out)" if timed_out else str(chosen.get("label", ""))
	if timed_out:
		result = "Time ran out! " + result
	sim.log_decision(event, label, result)
	return result


## Turn an effects dictionary into readable chips: [text, "good"|"bad"|"info"].
static func chips(effects: Dictionary, extra: Array = []) -> Array:
	var out: Array = []
	var names := {"air": "Air", "food": "Food", "battery": "Battery", "shield": "Shield", "science": "Science"}
	for key: String in ["air", "food", "battery", "shield", "science"]:
		if effects.has(key) and absf(float(effects[key])) >= 0.5:
			var v := float(effects[key])
			out.append(["%s%d %s" % ["+" if v > 0 else "", roundi(v), names[key]], "good" if v > 0 else "bad"])
	if effects.has("dose") and float(effects.dose) >= 0.5:
		out.append(["+%d Dose" % roundi(float(effects.dose)), "bad"])
	if effects.has("dust") and float(effects.dust) > 0.0:
		out.append(["Dusty panels", "bad"])
	if effects.has("lab_mult"):
		out.append(["Lab stops" if float(effects.lab_mult) <= 0.01 else "Lab slows down", "bad"])
	if effects.has("food_mult"):
		out.append(["Plants grow slower", "bad"])
	if bool(effects.get("tired", false)):
		out.append(["Weaker crew tomorrow", "bad"])
	for item: Variant in extra:
		out.append(item)
	if out.is_empty():
		out.append(["Nothing changes now", "info"])
	return out


static func _choice(label: String, effects: Dictionary, result: String, extra_chips: Array = [], special: String = "") -> Dictionary:
	return {"label": label, "effects": effects, "result": result, "chips": chips(effects, extra_chips), "special": special}


# ---------------------------------------------------------------- events

static func _lander_dust(_sim: RefCounted) -> Dictionary:
	var fold := _choice("Fold the solar panels", {"battery": -3, "food": 12},
		"Panels folded and stayed clean, but no sunlight power this afternoon (-3 battery). The lander brought fresh food (+12).")
	var keep := _choice("Keep the panels open", {"dust": 0.5, "food": 12},
		"Panels kept charging, but the rocket blast sprayed them with sharp moon dust. Dusty panels make less power until cleaned. The lander brought fresh food (+12).",
		[["30% chance: broken panel", "bad"]], "panel_risk")
	var timeout := keep.duplicate(true)
	return {
		"title": "Cargo lander incoming!",
		"art": "lander",
		"text": "A supply rocket is landing next to the base. Its engine will blast moon dust everywhere, faster than a bullet! Fold your solar panels to protect them, or keep them open to keep making power?",
		"term": NasaData.TERMS.regolith,
		"fact": NasaData.FACTS.apollo_dust + " " + NasaData.FACTS.no_wind,
		"source": "Based on Apollo 12 & Surveyor 3 (NASA)",
		"choices": [fold, keep],
		"timeout": timeout,
		"timer_bonus": 0,
	}


static func _radiation_storm(sim: RefCounted, data: Dictionary, from_cme: bool) -> Dictionary:
	var power := float(data.get("power", 26))
	var hide_dose: float = sim.storm_dose(power, true)
	var work_dose: float = sim.storm_dose(power, false)
	var hide := _choice("Everyone into the storm shelter", {"dose": hide_dose, "lab_mult": 0.0, "food_mult": 0.5, "shelter": true},
		"The crew hid behind thick walls. Only +%d dose, but no experiments and less plant care today." % roundi(hide_dose))
	hide["shelter"] = true
	var work := _choice("Keep working outside", {"dose": work_dose, "science": 1},
		"The crew finished their experiment (+1 science) but soaked up +%d radiation dose." % roundi(work_dose))
	var timeout := _choice("", {"dose": work_dose}, "Nobody gave the order to take cover. The crew got +%d dose." % roundi(work_dose))
	var is_live := bool(data.get("live", false))
	var warned: bool = sim.radio_on()
	var title := "Radiation storm!"
	var text := ""
	if from_cme:
		title = "The CME has arrived!"
		text = "The giant cloud of solar gas is here. Its shock wave is pushing fast particles at the base. Take cover, or keep working?"
	else:
		text = "The Sun just fired a %s. Fast particles are racing toward the Moon and will arrive in minutes! Take cover, or keep working?" % str(data.get("headline", "huge solar flare")).to_lower()
	if warned:
		text += " Your radio got an early warning from NASA forecasters, so you have extra time."
	var label := "%s - %s" % [str(data.get("date", "")), str(data.get("headline", ""))]
	return {
		"title": title,
		"art": "flare",
		"text": text,
		"term": NasaData.TERMS.cme if from_cme else NasaData.TERMS.sep,
		"term2": NasaData.TERMS.dose,
		"fact": str(data.get("detail", "")) + " " + NasaData.FACTS.artemis_shelter,
		"source": ("LIVE NASA DONKI: " if is_live else "Real event from NASA DONKI (archived): ") + label,
		"live": is_live,
		"real": true,
		"choices": [hide, work],
		"timeout": timeout,
		"timer_bonus": 5 if warned else 0,
		"storm": true,
	}


static func _cme_warning(sim: RefCounted, data: Dictionary) -> Dictionary:
	var label := "%s - %s" % [str(data.get("date", "")), str(data.get("headline", ""))]
	if not sim.radio_on():
		return {
			"title": "Radio silence...",
			"art": "earth",
			"text": "NASA forecasters on Earth spotted something big leaving the Sun and tried to call you. But your radio had no power today, so the warning never arrived. You will not have time to prepare.",
			"term": NasaData.TERMS.delay,
			"fact": NasaData.FACTS.light_delay,
			"source": "Real event from NASA DONKI (archived): " + label,
			"real": true,
			"from_earth": true,
			"notice_only": true,
			"choices": [_choice("Oh no. Continue", {}, "You missed NASA's warning because the radio was off.")],
			"timeout": _choice("", {}, "You missed NASA's warning because the radio was off."),
			"timer_bonus": 0,
		}
	var water := _choice("Fill the water walls", {"shield": 20, "air": -10},
		"Water pumped into the walls (+20 shield). That water can't be split into oxygen now (-10 air).")
	var dirt := _choice("Pile moon dirt with the rover", {"shield": 14, "battery": -3},
		"The rover piled regolith on the shelter (+14 shield) and used -3 battery.")
	var wait := _choice("Save resources and wait", {}, "You saved your supplies, but the shelter is no stronger for tomorrow.",
		[["Risky tomorrow", "bad"]])
	return {
		"title": "Warning: CME on the way!",
		"art": "earth",
		"text": "Message from NASA Mission Control: \"A CME left the Sun and will reach the Moon tomorrow!\" How will you get the base ready?",
		"term": NasaData.TERMS.cme,
		"term2": NasaData.TERMS.shield,
		"fact": str(data.get("detail", "")) + " " + NasaData.FACTS.water_shield,
		"source": "Real event from NASA DONKI (archived): " + label,
		"real": true,
		"from_earth": true,
		"choices": [water, dirt, wait],
		"timeout": wait,
		"timer_bonus": 5,
	}


static func _meteor(_sim: RefCounted) -> Dictionary:
	var patch := _choice("Spacewalk to patch it", {"dose": 3, "battery": -1, "air": -3},
		"Two astronauts sealed the hole outside (+3 dose, -1 battery). Only a little air escaped (-3).")
	var seal := _choice("Seal off the lab module", {"air": -8, "lab_mult": 0.5},
		"You closed the hatch. Some air was lost (-8) and the lab only works at half speed today.")
	var timeout := _choice("", {"air": -15}, "The leak kept hissing until the alarm closed the hatch (-15 air).")
	return {
		"title": "Air leak! A space rock hit!",
		"art": "meteor",
		"text": "A tiny micrometeorite, smaller than a pea, punched a hole in the habitat. Air is leaking out! Fix it outside, or close off that part of the base?",
		"term": "Micrometeorite: a speck of space rock moving faster than a rifle bullet.",
		"fact": NasaData.FACTS.micrometeoroid,
		"source": "Based on NASA micrometeoroid research",
		"choices": [patch, seal],
		"timeout": timeout,
		"timer_bonus": 0,
	}


static func _ice(_sim: RefCounted) -> Dictionary:
	var study := _choice("Study it in the lab", {"battery": -2, "science": 3},
		"Amazing data about ancient Moon water (+3 science). The rover trip used -2 battery.")
	var melt := _choice("Melt it for air", {"battery": -2, "air": 14},
		"You melted the ice and split the water into oxygen (+14 air). That used -2 battery.")
	var timeout := _choice("", {"battery": -1}, "The rover waited too long in the cold and drove home empty (-1 battery).")
	return {
		"title": "The rover found ice!",
		"art": "rock",
		"text": "In a dark crater that never sees sunlight, the rover found a rock with frozen water! Bringing it back costs power. What will you use it for?",
		"term": NasaData.TERMS.electrolysis,
		"fact": NasaData.FACTS.lcross,
		"source": "Based on NASA LCROSS (2009)",
		"choices": [study, melt],
		"timeout": timeout,
		"timer_bonus": 0,
	}


static func _plants(_sim: RefCounted) -> Dictionary:
	var light := _choice("Give plants extra light", {"battery": -2},
		"Grow lights on full power (-2 battery). The lettuce perked right up!")
	var rest := _choice("Let the plants rest", {"food": -6, "food_mult": 0.5},
		"Some leaves wilted (-6 food) and plants grow slower today.")
	return {
		"title": "Greenhouse trouble!",
		"art": "plants",
		"text": "The greenhouse got too cold and the lettuce is drooping. Plants need light and warmth, and both cost power.",
		"term": "Greenhouse: a glass room where plants get light, water and warm air.",
		"fact": NasaData.FACTS.veggie + " " + NasaData.FACTS.zinnia,
		"source": "Based on NASA Veggie on the Space Station",
		"choices": [light, rest],
		"timeout": rest,
		"timer_bonus": 0,
	}


static func _muscle(_sim: RefCounted) -> Dictionary:
	var gym := _choice("Exercise on the treadmill", {"battery": -1, "food": -4},
		"A hard workout kept muscles strong. The treadmill used -1 battery and hungry astronauts ate -4 extra food.")
	var skip := _choice("Skip exercise today", {"tired": true},
		"The crew rested, but tomorrow their weak muscles will make lab work slower.")
	return {
		"title": "Wobbly legs!",
		"art": "crew",
		"text": "Astronaut Nour says her legs feel weak. In low gravity, muscles don't have to work hard, so they shrink. Exercise takes energy and makes you hungry.",
		"term": NasaData.TERMS.microgravity,
		"fact": NasaData.FACTS.osdr_muscle + " " + NasaData.FACTS.exercise,
		"source": "Based on NASA OSDR research",
		"real": true,
		"choices": [gym, skip],
		"timeout": skip,
		"timer_bonus": 0,
	}


static func _earth_call(_sim: RefCounted) -> Dictionary:
	var answer := _choice("Send the science data now", {"battery": -2, "science": 2},
		"Your data reached Earth 1.3 seconds later. Scientists cheered (+2 science)! The big upload used -2 battery.")
	var later := _choice("Save power for tonight", {}, "You kept your battery, but the scientists will have to wait for your data.",
		[["Miss +2 Science", "bad"]])
	return {
		"title": "Call from Earth!",
		"art": "earth",
		"text": "Mission Control and a class of students in Cairo want your latest results. Sending lots of data uses the big radio dish, and that costs power.",
		"term": NasaData.TERMS.delay,
		"fact": NasaData.FACTS.light_delay,
		"source": "Real physics: Earth-Moon light delay",
		"from_earth": true,
		"choices": [answer, later],
		"timeout": later,
		"timer_bonus": 0,
	}


static func _shadow(_sim: RefCounted) -> Dictionary:
	var battery := _choice("Run everything on battery", {"battery": -3},
		"Machines kept humming on stored power (-3 battery).")
	var power_down := _choice("Switch off the lab and grow lights", {"lab_mult": 0.0, "food_mult": 0.5},
		"You saved the battery, but the lab stopped and the plants grew slower.")
	return {
		"title": "Long shadows!",
		"art": "shadow",
		"text": "At the Moon's South Pole the Sun stays very low. This afternoon a mountain shadow is covering your solar panels. Use the battery, or turn some machines off?",
		"term": "South Pole: the bottom of the Moon, where Artemis astronauts plan to land.",
		"fact": NasaData.FACTS.south_pole,
		"source": "Based on NASA Lunar Reconnaissance Orbiter maps",
		"choices": [battery, power_down],
		"timeout": power_down,
		"timer_bonus": 0,
	}
