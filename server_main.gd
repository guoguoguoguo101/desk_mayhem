extends Node3D

func _enter_tree() -> void:
	set_meta("dedicated_server", true)

func _ready() -> void:
	if "--server-smoke" in OS.get_cmdline_user_args():
		get_tree().create_timer(0.4).timeout.connect(get_tree().quit)
