extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_verify")


func _verify() -> void:
	_check(ProjectSettings.get_setting("application/config/name") == "Astro Quest", "exported identity")
	for path: String in [
		"scene/bg_outpost.png", "scene/bg_title.png", "scene/lander.png", "ui/logo.png",
		"buildings/habitat.png", "buildings/greenhouse.png", "buildings/lab.png", "buildings/shelter.png",
		"buildings/panel_open.png", "buildings/panel_closed.png",
		"crew/astronaut_idle.png", "crew/astronaut_walk.png", "crew/astronaut_cheer.png",
		"icons/air.png", "icons/food.png", "icons/power.png", "icons/radiation.png", "icons/science.png",
		"events/flare.png", "events/meteor.png", "events/rock.png", "events/earth.png",
		"fonts/PixelifySans-VF.ttf",
	]:
		_check(ResourceLoader.exists("res://assets/game/" + path), "pack resource: " + path)
	_check(not ResourceLoader.exists("res://test/test_suite.tscn"), "test scene excluded")
	_check(not ResourceLoader.exists("res://tools/capture_native.gd"), "native capture tool excluded")
	_check(not ResourceLoader.exists("res://scripts/ui/tuning_panel.gd"), "release tuning panel excluded")
	_check(FileAccess.file_exists("res://localization/en.json"), "exported locale")
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "exported main scene")
	if packed != null:
		var main := packed.instantiate()
		root.add_child(main)
		await process_frame
		await process_frame
		_check(bool((main.get("_title_screen") as Control).visible), "pack boots to title")
		main.call("_start_mission")
		await process_frame
		_check(str(main.get("_screen")) == "game", "pack starts gameplay")
		main.queue_free()
		await process_frame
	if _failures.is_empty():
		print("[exported-pack] PASS: identity, resources, exclusions, boot, gameplay")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("[exported-pack] " + failure)
		quit(1)


func _check(condition: bool, context: String) -> void:
	if not condition and context not in _failures:
		_failures.append(context)
