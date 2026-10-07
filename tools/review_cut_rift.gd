extends SceneTree
var stage: Node
var capture_at := 0.43
var output_name := "cut_rift_peak"
var captured := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: capture_at = float(args[0])
	if args.size() > 1: output_name = args[1]
	stage = load("res://vfx/MouseCutFullPreview.tscn").instantiate()
	stage.speed_scale = 1.0
	stage.auto_loop = false
	root.add_child(stage)
	root.size = Vector2i(1280, 720)

func _process(_delta: float) -> bool:
	if captured: return false
	stage.camera.global_position = Vector3(10.0, 3.8, 7.0)
	stage.camera.fov = 48.0
	stage.canvas.visible = false
	stage.dummy_label.visible = false
	stage.camera.look_at(Vector3(2.8, 1.6, 0.0))
	if stage.elapsed >= capture_at:
		captured = true
		stage.paused = true
		Engine.time_scale = 0.0
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://recordings/%s.png" % output_name)
		quit()
	return false
