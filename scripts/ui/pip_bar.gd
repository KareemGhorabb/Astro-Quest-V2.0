extends Control
## Draws power-cell pips (squares) or rank stars without relying on font glyphs.

var total := 4:
	set(value):
		total = value
		_resize()
var filled := 0:
	set(value):
		filled = value
		queue_redraw()
var pip_size := 14.0:
	set(value):
		pip_size = value
		_resize()
var gap := 5.0
var color := Color("ffd23f")
var empty_color := Color(1, 1, 1, 0.35)
var star := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resize()


func _resize() -> void:
	custom_minimum_size = Vector2(total * pip_size + maxi(0, total - 1) * gap, pip_size)
	queue_redraw()


func _draw() -> void:
	for i: int in total:
		var origin := Vector2(i * (pip_size + gap), 0)
		var on := i < filled
		if star:
			_draw_star(origin + Vector2(pip_size, pip_size) * 0.5, pip_size * 0.5, on)
		else:
			var rect := Rect2(origin, Vector2(pip_size, pip_size))
			if on:
				draw_rect(rect, color)
				draw_rect(Rect2(origin + Vector2(2, 2), Vector2(pip_size - 4, 3)), color.lightened(0.45))
			draw_rect(rect, color if on else empty_color, false, 2.0)


func _draw_star(center: Vector2, radius: float, on: bool) -> void:
	var points := PackedVector2Array()
	for k: int in 10:
		var r := radius if k % 2 == 0 else radius * 0.45
		var angle := -PI / 2.0 + k * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	if on:
		draw_colored_polygon(points, color)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, color if on else empty_color, 2.0)
