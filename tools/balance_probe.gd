extends SceneTree
## Headless balance probe: plays many missions with simple strategies.

const OutpostSim = preload("res://scripts/sim/outpost_sim.gd")
const EventDeck = preload("res://scripts/sim/event_deck.gd")


func _initialize() -> void:
	for policy: String in ["default_first", "careful", "greedy_science", "random", "timeout"]:
		var wins := 0
		var outcomes := {}
		var science := 0.0
		var dose := 0.0
		for seed_value: int in range(1, 201):
			var sim: RefCounted = OutpostSim.new()
			sim.start(seed_value, {"days": 10, "solar_max": 8, "air_use": 12.0})
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			while sim.outcome == "":
				_plan(sim, policy, rng)
				sim.begin_day()
				while not sim.day_finished() and sim.outcome == "":
					var due: Dictionary = sim.tick(0.05)
					if not due.is_empty():
						var event: Dictionary = EventDeck.build(sim, due)
						EventDeck.resolve(sim, event, _choose(event, policy, rng, sim))
				if sim.outcome == "":
					sim.run_night()
			outcomes[sim.outcome] = int(outcomes.get(sim.outcome, 0)) + 1
			if sim.outcome == "win":
				wins += 1
				science += sim.science
			dose += sim.dose
		print("%s: wins %d/200 outcomes %s avg science(win) %.1f avg dose %.1f" % [policy, wins, str(outcomes), science / maxf(1, wins), dose / 200.0])
	quit(0)


func _plan(sim: RefCounted, policy: String, rng: RandomNumberGenerator) -> void:
	for key: String in sim.SYSTEMS:
		sim.alloc[key] = 0
	match policy:
		"default_first", "timeout":
			sim.alloc.air = 2
			sim.alloc.food = 2
		"careful":
			if sim.dust > 0.3:
				sim.clean_panels()
			sim.alloc.air = 3 if sim.air < 50 else 2
			sim.alloc.food = 3 if sim.food < 40 else 2
			sim.alloc.radio = 1
			if sim.shield < 60:
				sim.alloc.shield = 1
			while sim.forecast_battery_tonight() > 3 and sim.can_add("lab"):
				sim.add_cell("lab")
		"greedy_science":
			sim.alloc.air = 2
			sim.alloc.food = 2
			while sim.can_add("lab"):
				sim.add_cell("lab")
		"random":
			for i: int in rng.randi_range(3, 9):
				sim.add_cell(sim.SYSTEMS[rng.randi_range(0, 4)])
	sim._clamp_alloc_to_budget()


func _choose(event: Dictionary, policy: String, rng: RandomNumberGenerator, _sim: RefCounted) -> int:
	var count := (event.choices as Array).size()
	match policy:
		"timeout":
			return -1
		"random":
			return rng.randi_range(0, count - 1)
		"careful":
			return 0
		_:
			return 0
