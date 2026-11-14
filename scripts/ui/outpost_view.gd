extends Control
## Visual presentation of the outpost. Reads simulation state; never changes it.

const Kit = preload("res://scripts/ui/kit.gd")

const BUILDINGS := {
	"panels": {"path": "res://assets/game/buildings/panel_open.png", "x": 105.0, "base": 640.0, "w": 175.0, "h": 135.0, "name": "SOLAR PANELS", "system": ""},
	"habitat": {"path": "res://assets/game/buildings/habitat.png", "x": 315.0, "base": 645.0, "w": 225.0, "h": 135.0, "name": "AIR MAKER", "system": "air"},
	"greenhouse": {"path": "res://assets/game/buildings/greenhouse.png", "x": 560.0, "base": 645.0, "w": 215.0, "h": 135.0, "name": "GREENHOUSE", "system": "food"},
	"lab": {"path": "res://assets/game/buildings/lab.png", "x": 420.0, "base": 498.0, "w": 190.0, "h": 145.0, "name": "LAB + RADIO", "system": "lab"},
	"shelter": {"path": "res://assets/game/buildings/shelter.png", "x": 700.0, "base": 498.0, "w": 200.0, "h": 105.0, "name": "SHELTER", "system": "shield"},
}

var _sprites := {}
var _tags := {}
var _tag_labels := {}
var _crew: Array[TextureRect] = []
var _crew_targets: Array[Vector2] = []
var _crew_hidden := false
var _crew_cheer := false
var _tex_idle: Texture2D
var _tex_walk: Texture2D
var _tex_cheer: Texture2D
var _tex_panel_open: Texture2D
var _tex_panel_closed: Texture2D
var _storm_rect: ColorRect
var _night_rect: ColorRect
var _storm_particles: CPUParticles2D
var _dust_particles: CPUParticles2D
var _lander: TextureRect
var _fx_layer: Control
var _shield_level := 0.2
var _running := false
var _time := 0.0
var _storm_on := false
var reduced_motion := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Kit.full_rect(self)
	_tex_idle = load("res://assets/game/crew/astronaut_idle.png")
	_tex_walk = load("res://assets/game/crew/astronaut_walk.png")
	_tex_cheer = load("res://assets/game/crew/astronaut_cheer.png")
	_tex_panel_open = load("res://assets/game/buildings/panel_open.png")
	_tex_panel_closed = load("res://assets/game/buildings/panel_closed.png")
	var bg := Kit.texture_rect("res://assets/game/scene/bg_outpost.png", Vector2(1280, 720), false)
	bg.position = Vector2.ZERO
	add_child(bg)
	var order: Array[String] = ["lab", "shelter", "panels", "habitat", "greenhouse"]
	for id: String in order:
		var spec: Dictionary = BUILDINGS[id]
		var sprite := Kit.texture_rect(str(spec.path), Vector2(float(spec.w), float(spec.h)))
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.position = Vector2(float(spec.x) - float(spec.w) / 2.0, float(spec.base) - float(spec.h))
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(sprite)
		_sprites[id] = sprite
	for id: String in order:
		var spec: Dictionary = BUILDINGS[id]
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", Kit.box(Color(0.04, 0.06, 0.15, 0.82), Kit.MUTED, 2, 0, 4))
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var text := Kit.label(str(spec.name), 14, Kit.WHITE, true)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_child(text)
		add_child(tag)
		tag.position = Vector2(float(spec.x) - 70.0, float(spec.base) - float(spec.h) - 26.0)
		tag.custom_minimum_size = Vector2(140, 0)
		_tags[id] = tag
		_tag_labels[id] = text
	_lander = Kit.texture_rect("res://assets/game/scene/lander.png", Vector2(150, 156))
	_lander.position = Vector2(770, -260)
	_lander.visible = false
	add_child(_lander)
	for index: int in 2:
		var astronaut := Kit.texture_rect("res://assets/game/crew/astronaut_idle.png", Vector2(58, 92))
		astronaut.position = Vector2(780 + index * 60, 560)
		add_child(astronaut)
		_crew.append(astronaut)
		_crew_targets.append(astronaut.position)
	_fx_layer = Control.new()
	Kit.full_rect(_fx_layer)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)
	_dust_particles = _make_dust()
	add_child(_dust_particles)
	_storm_rect = ColorRect.new()
	Kit.full_rect(_storm_rect)
	_storm_rect.color = Color(0.7, 0.2, 0.9, 0.0)
	_storm_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_storm_rect)
	_storm_particles = _make_storm()
	add_child(_storm_particles)
	_night_rect = ColorRect.new()
	Kit.full_rect(_night_rect)
	_night_rect.color = Color(0.02, 0.03, 0.12, 0.0)
	_night_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_night_rect)


func _make_storm() -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.emitting = false
	particles.amount = 70
	particles.lifetime = 1.1
	particles.position = Vector2(-40, -40)
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(700, 20)
	particles.direction = Vector2(0.55, 1.0)
	particles.spread = 6.0
	particles.initial_velocity_min = 700.0
	particles.initial_velocity_max = 950.0
	particles.gravity = Vector2.ZERO
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = Color(1.0, 0.55, 1.0, 0.85)
	return particles


func _make_dust() -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 90
	particles.lifetime = 1.6
	particles.explosiveness = 0.85
	particles.position = Vector2(845, 640)
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(60, 8)
	particles.direction = Vector2(-1, -0.25)
	particles.spread = 35.0
	particles.initial_velocity_min = 380.0
	particles.initial_velocity_max = 900.0
	particles.gravity = Vector2(0, 160)
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 7.0
	particles.color = Color(0.72, 0.72, 0.76, 0.9)
	return particles


func sync(sim: RefCounted) -> void:
	var alloc: Dictionary = sim.alloc
	for id: String in BUILDINGS:
		var spec: Dictionary = BUILDINGS[id]
		var system := str(spec.system)
		var label: Label = _tag_labels[id]
		var sprite: TextureRect = _sprites[id]
		if system.is_empty():
			var folded: bool = float(sim.mods.get("charge_mult", 1.0)) < 0.99 and sim.phase == "day"
			sprite.texture = _tex_panel_closed if folded else _tex_panel_open
			label.text = "SOLAR  %d CELLS" % int(sim.cells_today)
			var dirt := clampf(float(sim.dust), 0.0, 1.0)
			sprite.modulate = Color.WHITE.lerp(Color(0.55, 0.5, 0.45), dirt)
			continue
		var cells := int(alloc.get(system, 0))
		var pips := "%d/%d" % [cells, int(sim.MAX_CELLS[system])]
		var name := str(spec.name)
		if id == "lab":
			name = "LAB" + ("+RADIO" if int(alloc.radio) > 0 else "")
		label.text = "%s %s" % [name, pips]
		sprite.modulate = Color.WHITE if cells > 0 or (id == "lab" and int(alloc.radio) > 0) else Color(0.62, 0.62, 0.7)
	_shield_level = float(sim.shield) / 100.0
	queue_redraw()


func _draw() -> void:
	# Shield dome over the shelter grows with shielding.
	var spec: Dictionary = BUILDINGS.shelter
	var center := Vector2(float(spec.x), float(spec.base) - 10.0)
	var radius := 70.0 + 50.0 * _shield_level
	var alpha := 0.15 + 0.35 * _shield_level
	var points := PackedVector2Array()
	for i: int in 25:
		var angle := PI + PI * float(i) / 24.0
		points.append(center + Vector2(cos(angle) * radius * 1.25, sin(angle) * radius))
	draw_polyline(points, Color(0.55, 0.65, 1.0, alpha + 0.2), 4.0)
	var fill := points.duplicate()
	fill.append(center)
	draw_colored_polygon(fill, Color(0.45, 0.55, 1.0, alpha * 0.35))


func set_running(running: bool) -> void:
	_running = running
	if running:
		_crew_cheer = false
		_pick_targets()


func set_crew_hidden(hidden: bool) -> void:
	_crew_hidden = hidden
	var spec: Dictionary = BUILDINGS.shelter
	for index: int in _crew.size():
		if hidden:
			_crew_targets[index] = Vector2(float(spec.x) - 30.0 + index * 10.0, float(spec.base) - 80.0)
		else:
			_pick_targets()


func cheer() -> void:
	_crew_cheer = true
	_running = false
	_crew_hidden = false
	for index: int in _crew.size():
		_crew[index].modulate.a = 1.0
		_crew[index].texture = _tex_cheer
		_crew_targets[index] = Vector2(560 + index * 120, 560)


func _pick_targets() -> void:
	if _crew_hidden:
		return
	var spots: Array[Vector2] = [Vector2(90, 645), Vector2(290, 650), Vector2(530, 650), Vector2(760, 640), Vector2(840, 630), Vector2(170, 650), Vector2(400, 520), Vector2(680, 515)]
	for index: int in _crew.size():
		_crew_targets[index] = spots[randi() % spots.size()] - Vector2(29, 92)


func _process(delta: float) -> void:
	_time += delta
	for index: int in _crew.size():
		var astronaut := _crew[index]
		var target := _crew_targets[index]
		var logical: Vector2 = astronaut.get_meta("logical", astronaut.position)
		var to := target - logical
		var moving := to.length() > 4.0 and (_running or _crew_hidden or _crew_cheer)
		if moving:
			var speed := 110.0
			logical += to.normalized() * minf(speed * delta, to.length())
			astronaut.flip_h = to.x < 0.0
			if not _crew_cheer:
				astronaut.texture = _tex_walk
		elif _running and not _crew_hidden and randf() < delta * 0.35:
			_pick_targets()
		elif not _crew_cheer:
			astronaut.texture = _tex_idle
		var bob := 0.0
		if not reduced_motion and (moving or _crew_cheer):
			bob = absf(sin(_time * 7.0 + index)) * -8.0
		astronaut.set_meta("logical", logical)
		astronaut.position = logical + Vector2(0, bob)
		astronaut.modulate.a = move_toward(astronaut.modulate.a, 0.0 if (_crew_hidden and not moving) else 1.0, delta * 3.0)
	if _storm_on:
		var pulse := 0.16 + (0.0 if reduced_motion else 0.07 * sin(_time * 4.0))
		_storm_rect.color.a = move_toward(_storm_rect.color.a, pulse, delta)
	else:
		_storm_rect.color.a = move_toward(_storm_rect.color.a, 0.0, delta * 0.6)


func set_storm(on: bool) -> void:
	_storm_on = on
	_storm_particles.emitting = on and not reduced_motion


func set_night(amount: float) -> void:
	_night_rect.color.a = clampf(amount, 0.0, 0.7)


func lander_arrive() -> void:
	_lander.visible = true
	_lander.position = Vector2(770, -220)
	var tween := create_tween()
	tween.tween_property(_lander, "position", Vector2(770, 495), 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(dust_burst)


func lander_leave() -> void:
	if not _lander.visible:
		return
	var tween := create_tween()
	tween.tween_interval(0.4)
	tween.tween_property(_lander, "position", Vector2(770, -260), 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: _lander.visible = false)


func dust_burst() -> void:
	_dust_particles.restart()
	_dust_particles.emitting = true


## Floating feedback text such as "+O2" rising from a building.
func pop(text: String, building: String, color: Color) -> void:
	if not BUILDINGS.has(building):
		return
	var spec: Dictionary = BUILDINGS[building]
	var node := Kit.outline(Kit.label(text, 20, color, true), 6)
	node.position = Vector2(float(spec.x) - 30.0 + randf_range(-20, 20), float(spec.base) - float(spec.h) - 10.0)
	_fx_layer.add_child(node)
	var tween := node.create_tween()
	var rise := 0.0 if reduced_motion else -46.0
	tween.set_parallel(true)
	tween.tween_property(node, "position:y", node.position.y + rise, 1.3)
	tween.tween_property(node, "modulate:a", 0.0, 1.3).set_delay(0.3)
	tween.chain().tween_callback(node.queue_free)


func building_rect(id: String) -> Rect2:
	if not _sprites.has(id):
		return Rect2()
	var sprite: TextureRect = _sprites[id]
	return Rect2(sprite.position, sprite.size)
