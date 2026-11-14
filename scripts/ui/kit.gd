extends RefCounted
## Shared retro pixel-art UI building blocks for Astro Quest.

const NAVY := Color("0b1026")
const PANEL := Color("141c3a")
const PANEL_2 := Color("1f2a55")
const ORANGE := Color("e8601c")
const ORANGE_HI := Color("ff7a35")
const BLUE := Color("17a6e0")
const WHITE := Color("f4f1ea")
const MUTED := Color("a9b8d8")
const GOOD := Color("62d26f")
const BAD := Color("ff5d5d")
const WARN := Color("ffc845")
const PURPLE := Color("b77bff")
const AIR_C := Color("5cc8ff")
const FOOD_C := Color("6fdc5a")
const POWER_C := Color("ffd23f")
const DOSE_C := Color("ff6bd5")
const SHIELD_C := Color("8f9dff")

const PIXEL_FONT_PATH := "res://assets/game/fonts/PixelifySans-VF.ttf"
const BODY_FONT_PATH := "res://assets/template/fonts/ui_medium.tres"
const BODY_BOLD_PATH := "res://assets/template/fonts/ui_bold.tres"

static var _pixel_cache := {}


static func pixel_font(weight: int = 600) -> Font:
	if _pixel_cache.has(weight):
		return _pixel_cache[weight]
	var base := load(PIXEL_FONT_PATH) as Font
	var variation := FontVariation.new()
	variation.base_font = base
	variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	var body := load(BODY_FONT_PATH) as Font
	if body != null:
		variation.fallbacks = [body]
	_pixel_cache[weight] = variation
	return variation


static func body_font(bold: bool = false) -> Font:
	return load(BODY_BOLD_PATH if bold else BODY_FONT_PATH) as Font


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = body_font()
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", WHITE)
	theme.set_color("default_color", "RichTextLabel", WHITE)
	theme.set_stylebox("panel", "PanelContainer", box(PANEL, WHITE, 3))
	var scroll := StyleBoxFlat.new()
	scroll.bg_color = Color(1, 1, 1, 0.08)
	theme.set_stylebox("scroll", "VScrollBar", scroll)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = ORANGE
	theme.set_stylebox("grabber", "VScrollBar", grabber)
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	return theme


static func box(bg: Color, border: Color = WHITE, border_width: int = 3, shadow: int = 6, pad: int = 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 0
	style.shadow_offset = Vector2(shadow, shadow)
	if shadow > 0:
		style.shadow_size = 1
	style.content_margin_left = pad
	style.content_margin_right = pad
	style.content_margin_top = pad
	style.content_margin_bottom = pad
	style.anti_aliasing = false
	return style


static func label(text: String, size: int = 18, color: Color = WHITE, pixel: bool = false, wrap: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if pixel:
		node.add_theme_font_override("font", pixel_font())
	if wrap:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func outline(node: Label, size: int = 6, color: Color = Color(0, 0, 0, 0.85)) -> Label:
	node.add_theme_constant_override("outline_size", size)
	node.add_theme_color_override("font_outline_color", color)
	return node


static func button(text: String, kind: String = "primary", font_size: int = 22) -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_ALL
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.add_theme_font_override("font", pixel_font(700))
	node.add_theme_font_size_override("font_size", font_size)
	style_button(node, kind)
	return node


static func style_button(node: Button, kind: String) -> void:
	var base := ORANGE
	var hover := ORANGE_HI
	var border := WHITE
	var text := Color.WHITE
	match kind:
		"secondary":
			base = PANEL_2
			hover = Color("2c3b75")
		"ghost":
			base = Color(0.04, 0.06, 0.15, 0.75)
			hover = PANEL_2
			border = MUTED
		"blue":
			base = Color("0f6f9a")
			hover = BLUE
		"small":
			base = PANEL_2
			hover = Color("2c3b75")
	var pad := 8 if kind == "small" else 14
	node.add_theme_stylebox_override("normal", box(base, border, 3, 5, pad))
	node.add_theme_stylebox_override("hover", box(hover, border, 3, 5, pad))
	node.add_theme_stylebox_override("pressed", box(base.darkened(0.25), border, 3, 2, pad))
	node.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), BLUE, 4, 0, pad))
	node.add_theme_stylebox_override("disabled", box(Color("2a2f45"), Color("5c6380"), 3, 0, pad))
	node.add_theme_color_override("font_color", text)
	node.add_theme_color_override("font_hover_color", text)
	node.add_theme_color_override("font_pressed_color", text)
	node.add_theme_color_override("font_focus_color", text)
	node.add_theme_color_override("font_disabled_color", Color("8890aa"))


static func chip(text: String, kind: String) -> PanelContainer:
	var colors := {"good": GOOD, "bad": BAD, "info": MUTED, "live": WARN, "real": BLUE}
	var c: Color = colors.get(kind, MUTED)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box(c.darkened(0.72), c, 2, 0, 5))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text_label := label(text, 15, c.lightened(0.25), true)
	panel.add_child(text_label)
	return panel


static func texture_rect(path: String, size: Vector2, keep: bool = true) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = load(path) as Texture2D
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if keep else TextureRect.STRETCH_SCALE
	rect.custom_minimum_size = size
	rect.size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func full_rect(node: Control) -> Control:
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0
	return node


static func dimmer(alpha: float = 0.62) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(0.02, 0.03, 0.09, alpha)
	full_rect(rect)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return rect
