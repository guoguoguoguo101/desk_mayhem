extends SceneTree

var stage: Node
var frames := 0
var capture_at := 0.19
var output_name := "cut_vfx_review"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: capture_at = float(args[0])
	if args.size() > 1: output_name = args[1]
	stage = load("res://vfx/MouseCutDashPreview.tscn").instantiate()
	stage.speed_scale = 1.0
	root.add_child(stage)
	root.size = Vector2i(1280, 720)

func _process(_delta: float) -> bool:
	frames += 1
	stage.camera.position = Vector3(0.0, 2.6, 8.0)
	stage.camera.look_at(Vector3(0.0, 0.6, 0.0))
	if stage.elapsed >= capture_at and frames < 10000:
		stage.paused = true
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://recordings/%s.png" % output_name)
		quit()
	return false
