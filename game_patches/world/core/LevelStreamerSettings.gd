extends Node

export (float) var min_inner_margin: float = 5.0
export (float) var min_mid_margin: float = 7.0
export (float) var min_outer_margin: float = 9.0
export (float) var max_inner_margin: float = 14.0
export (float) var max_mid_margin: float = 18.0
export (float) var max_outer_margin: float = 28.0

func _ready():
	update_settings()
	UserSettings.connect("settings_changed", self, "update_settings")

func update_settings():
	if get_parent() is LevelStreamer:
		var use_max = UserSettings.graphics_world_streaming > 0
		
		get_parent().inner_margin = max_inner_margin if use_max else min_inner_margin
		get_parent().mid_margin = max_mid_margin if use_max else min_mid_margin
		get_parent().outer_margin = max_outer_margin if use_max else min_outer_margin
