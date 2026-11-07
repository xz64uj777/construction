extends Node3D

# WreckWorks Godot prototype: crawler crane + animated wrecking ball.
# Mobile controls: visible dual touch joysticks, one-finger orbit, two-finger pinch zoom.
# Wall panels are individual physics bodies; impacts remove panels and throw rubble.

const WALL_W := 8.8
const WALL_H := 5.0
const WALL_D := 3.4
const WALL_COLS := 11
const WALL_ROWS := 5
const BOOM_LEN := 7.2

var camera: Camera3D
var camera_target := Vector3(0.2, 2.0, -0.8)
var camera_yaw := 0.0
var camera_pitch := 0.28
var camera_distance := 21.0
var camera_dragging := false
var last_camera_pointer := Vector2.ZERO
var touch_points: Dictionary = {}
var pinch_start_distance := 0.0
var pinch_start_zoom := 21.0
var crane_root: Node3D
var upper: Node3D
var boom_pivot: Node3D
var boom: Node3D
var ball_rig: Node3D
var ball: RigidBody3D
var cable: MeshInstance3D
var wall_panels: Array[Node3D] = []
var total_panel_count := 0
var rubble_count := 0
var swing_angle := 0.0
var swing_velocity := 0.0
var rope_length := 3.6
var turn_input := 0.0
var drive_input := 0.0
var winch_input := 0.0
var swing_boost := false
var boom_joystick_x := 0.0
var boom_joystick_y := 0.0
var toast_time := 0.0
var damage_label: Label
var damage_bar: ProgressBar
var rubble_label: Label
var toast_label: Label
var mobile_controls: Control
var initial_crane_position := Vector3(5.1, 0, 3.1)

class TouchJoystick extends Control:
	signal changed(value: Vector2)
	var knob := Vector2.ZERO
	var held := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		queue_redraw()
	func _draw() -> void:
		var radius := minf(size.x, size.y) * 0.46
		var center := size * 0.5
		draw_circle(center, radius, Color(0.04, 0.08, 0.1, 0.78))
		draw_arc(center, radius, 0.0, TAU, 48, Color("#c5d0d4"), 2.0, true)
		draw_line(center - Vector2(0, radius * 0.65), center + Vector2(0, radius * 0.65), Color(1, 1, 1, 0.2), 1.0)
		draw_line(center - Vector2(radius * 0.65, 0), center + Vector2(radius * 0.65, 0), Color(1, 1, 1, 0.2), 1.0)
		draw_circle(center + knob * radius * 0.62, radius * 0.36, Color("#e4a72a"))
		draw_arc(center + knob * radius * 0.62, radius * 0.36, 0.0, TAU, 32, Color("#fff0c2"), 2.0, true)
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch or event is InputEventMouseButton:
			if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
				return
			held = event.pressed
			_update_knob(event.position)
			accept_event()
		elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and held:
			_update_knob(event.position)
			accept_event()
	func _update_knob(pos: Vector2) -> void:
		if not held:
			knob = Vector2.ZERO
			changed.emit(Vector2.ZERO)
		else:
			knob = (pos - size * 0.5) / maxf(1.0, minf(size.x, size.y) * 0.30)
			if knob.length() > 1.0:
				knob = knob.normalized()
			changed.emit(Vector2(knob.x, -knob.y))
		queue_redraw()

func _ready() -> void:
	_build_world()
	total_panel_count = wall_panels.size()
	_build_crane()
	_build_ui()
	_update_stats()
	set_process(true)

func _build_world() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	var ground := _static_box(Vector3(0, -0.25, 0), Vector3(100, 0.5, 100), Color(0.34, 0.35, 0.32))
	ground.name = "Dusty demolition yard"
	_static_box(Vector3(0, -0.02, 1.1), Vector3(34, 0.08, 16), Color(0.22, 0.24, 0.24))
	_add_fence()

	camera = Camera3D.new()
	camera.fov = 48
	camera.position = Vector3(10.8, 9.4, 16.4)
	camera_target = Vector3(0.2, 2.0, -0.8)
	camera_distance = camera.position.distance_to(camera_target)
	camera_yaw = atan2(camera.position.x - camera_target.x, camera.position.z - camera_target.z)
	camera_pitch = asin(clampf((camera.position.y - camera_target.y) / camera_distance, -0.9, 0.9))
	camera.look_at(camera_target, Vector3.UP)
	add_child(camera)
	camera.current = true

	_build_building()
	_add_site_details()

func _static_box(pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color, 0.88)
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body

func _material(color: Color, roughness := 0.82, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m

func _mesh_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, roughness := 0.82, metallic := 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = _material(color, roughness, metallic)
	parent.add_child(mesh)
	return mesh

func _build_building() -> void:
	var building := Node3D.new()
	building.name = "Condemned brick workshop"
	building.position = Vector3(-1.3, 0, -3.2)
	add_child(building)
	var colors: Array[Color] = [Color("#955642"), Color("#b16a51"), Color("#7b7771"), Color("#a75d49")]
	for face in [1, -1]:
		for row in range(WALL_ROWS):
			for col in range(WALL_COLS):
				if row < 2 and col >= 4 and col <= 6:
					continue
				var x := -WALL_W / 2.0 + (col + 0.5) * WALL_W / WALL_COLS
				var y := (row + 0.5) * WALL_H / WALL_ROWS
				var z: float = float(face) * WALL_D / 2.0
				var panel := _make_panel(building, Vector3(x, y, z), Vector3(WALL_W / WALL_COLS - 0.04, WALL_H / WALL_ROWS - 0.04, 0.22), colors[(row + col) % colors.size()])
				wall_panels.append(panel)
	for side in [-1, 1]:
		for row in range(WALL_ROWS):
			for col in range(4):
				var pos: Vector3 = Vector3(float(side) * WALL_W / 2.0, (row + 0.5) * WALL_H / WALL_ROWS, -WALL_D / 2.0 + (col + 0.5) * WALL_D / 4.0)
				var panel := _make_panel(building, pos, Vector3(0.22, WALL_H / WALL_ROWS - 0.04, WALL_D / 4.0 - 0.04), colors[(row + col + 1) % colors.size()])
				wall_panels.append(panel)
	for col in range(4):
		var panel := _make_panel(building, Vector3(-WALL_W / 2.0 + (col + 0.5) * WALL_W / 4.0, WALL_H + 0.12, 0), Vector3(WALL_W / 4.0 - 0.06, 0.24, WALL_D), Color("#777873"))
		wall_panels.append(panel)
	_mesh_box(building, Vector3(0, 3.65, WALL_D / 2.0 + 0.14), Vector3(2.8, 0.42, 0.25), Color("#d8a12e"))
	_mesh_box(building, Vector3(0, 3.65, WALL_D / 2.0 + 0.29), Vector3(2.25, 0.14, 0.04), Color("#22272a"))
	for x in range(-4, 5):
		_mesh_box(building, Vector3(x * 0.85, 2.1, WALL_D / 2.0 + 0.13), Vector3(0.045, 4.2, 0.045), Color("#51595a"), 0.45, 0.6)

func _make_panel(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.position = pos
	body.mass = maxf(0.8, size.x * size.y * size.z * 2.5)
	body.gravity_scale = 1.0
	body.freeze = true
	body.collision_layer = 2
	body.collision_mask = 1
	body.set_meta("breakable", true)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	parent.add_child(body)
	return body

func _build_crane() -> void:
	crane_root = Node3D.new()
	crane_root.position = initial_crane_position
	crane_root.name = "Crawler crane"
	add_child(crane_root)
	var dark := Color("#202629")
	var yellow := Color("#e4a72a")
	var steel := Color("#626f74")
	for z in [-0.76, 0.76]:
		_mesh_box(crane_root, Vector3(0, 0.34, z), Vector3(2.8, 0.44, 0.48), dark)
		for i in range(10):
			_mesh_box(crane_root, Vector3(-1.18 + i * 0.26, 0.12, z), Vector3(0.14, 0.12, 0.54), steel)
	upper = Node3D.new()
	upper.position.y = 0.68
	crane_root.add_child(upper)
	_mesh_box(upper, Vector3(0, 0.08, 0), Vector3(2.2, 0.38, 1.45), yellow)
	_mesh_box(upper, Vector3(-0.58, 0.5, -0.12), Vector3(0.85, 0.55, 0.88), dark)
	_mesh_box(upper, Vector3(-0.58, 0.87, -0.12), Vector3(0.55, 0.55, 0.58), Color("#28434d"), 0.28, 0.2)
	_mesh_box(upper, Vector3(-0.58, 1.17, -0.12), Vector3(0.65, 0.12, 0.66), yellow)
	boom_pivot = Node3D.new()
	boom_pivot.position = Vector3(-0.15, 0.48, 0)
	boom_pivot.rotation.z = -0.43
	upper.add_child(boom_pivot)
	boom = Node3D.new()
	boom_pivot.add_child(boom)
	# Industrial lattice boom: paired rails and repeated cross-bracing.
	for z in [-0.32, 0.32]:
		_add_beam(boom, Vector3(0, 0, z), Vector3(0, BOOM_LEN, z), 0.12, yellow)
		for i in range(10):
			var y0 := i * BOOM_LEN / 10.0
			var y1 := (i + 1) * BOOM_LEN / 10.0
			_add_beam(boom, Vector3(-0.2, y0, z), Vector3(0.2, y1, z), 0.045, steel)
			_add_beam(boom, Vector3(0.2, y0, z), Vector3(-0.2, y1, z), 0.045, steel)
	for i in range(11):
		var y := i * BOOM_LEN / 10.0
		_add_beam(boom, Vector3(-0.2, y, -0.32), Vector3(0.2, y, -0.32), 0.04, steel)
		_add_beam(boom, Vector3(-0.2, y, 0.32), Vector3(0.2, y, 0.32), 0.04, steel)
	cable = MeshInstance3D.new()
	var cable_mesh := CylinderMesh.new()
	cable_mesh.top_radius = 0.025
	cable_mesh.bottom_radius = 0.025
	cable_mesh.height = 1.0
	cable.mesh = cable_mesh
	cable.material_override = _material(Color("#202629"), 0.4, 0.7)
	boom.add_child(cable)
	ball_rig = Node3D.new()
	boom.add_child(ball_rig)
	ball = RigidBody3D.new()
	ball.mass = 420.0
	ball.gravity_scale = 0.0
	ball.freeze = true
	ball.collision_layer = 4
	ball.collision_mask = 2
	ball_rig.add_child(ball)
	var sphere := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.62
	sphere_mesh.height = 1.24
	sphere.mesh = sphere_mesh
	sphere.material_override = _material(Color("#68777b"), 0.34, 0.82)
	ball.add_child(sphere)
	_mesh_box(ball, Vector3(0, 0.65, 0), Vector3(0.3, 0.35, 0.3), dark)
	var collision := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.62
	collision.shape = sphere_shape
	ball.add_child(collision)
	for i in range(3):
		var band := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.57
		torus.outer_radius = 0.62
		band.mesh = torus
		band.position.y = (i - 1) * 0.25
		band.material_override = _material(Color("#252b2e"), 0.38, 0.7)
		ball.add_child(band)

func _add_beam(parent: Node3D, a: Vector3, b: Vector3, thickness: float, color: Color) -> void:
	var beam_mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = thickness
	cylinder.bottom_radius = thickness
	cylinder.height = a.distance_to(b)
	beam_mesh.mesh = cylinder
	beam_mesh.position = (a + b) * 0.5
	beam_mesh.look_at_from_position(beam_mesh.position, b, Vector3.FORWARD)
	beam_mesh.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	beam_mesh.material_override = _material(color, 0.42, 0.55)
	parent.add_child(beam_mesh)

func _add_fence() -> void:
	for x in range(-12, 13, 2):
		_mesh_box(self, Vector3(x, 0.36, -8), Vector3(0.09, 0.72, 0.09), Color("#e4dfd2"))
		_mesh_box(self, Vector3(x, 0.36, 8), Vector3(0.09, 0.72, 0.09), Color("#e4dfd2"))

func _add_site_details() -> void:
	for i in range(7):
		var pile := _mesh_box(self, Vector3(-8.0 + i * 0.4, 0.12, 4.4), Vector3(0.55, 0.2 + (i % 3) * 0.08, 0.45), Color("#8c8274"))
		pile.rotation.y = i * 0.3
	# Work lights on simple poles
	for x in [-11.0, 11.0]:
		_mesh_box(self, Vector3(x, 2.3, -5.5), Vector3(0.12, 4.6, 0.12), Color("#4a5355"), 0.45, 0.5)
		_mesh_box(self, Vector3(x, 4.55, -5.5), Vector3(0.7, 0.22, 0.3), Color("#e9dfb0"), 0.35)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var title := Label.new()
	title.text = "WRECKWORKS  /  WRECKING BALL"
	title.position = Vector2(18, 14)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#fff4dc"))
	root.add_child(title)
	var job := Label.new()
	job.text = "JOB 01  ·  OLD BRICK WORKS"
	job.position = Vector2(18, 43)
	job.add_theme_font_size_override("font_size", 12)
	job.add_theme_color_override("font_color", Color("#ffc04e"))
	root.add_child(job)
	damage_label = Label.new()
	damage_label.position = Vector2(18, 72)
	damage_label.add_theme_font_size_override("font_size", 15)
	root.add_child(damage_label)
	damage_bar = ProgressBar.new()
	damage_bar.position = Vector2(18, 99)
	damage_bar.size = Vector2(190, 12)
	damage_bar.show_percentage = false
	root.add_child(damage_bar)
	rubble_label = Label.new()
	rubble_label.position = Vector2(18, 118)
	rubble_label.add_theme_font_size_override("font_size", 12)
	root.add_child(rubble_label)
	toast_label = Label.new()
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.position = Vector2(-190, -104)
	toast_label.size = Vector2(380, 34)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 15)
	toast_label.add_theme_color_override("font_color", Color("#ffe0a0"))
	root.add_child(toast_label)
	mobile_controls = Control.new()
	mobile_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mobile_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mobile_controls)
	var drive_stick := TouchJoystick.new()
	drive_stick.name = "DriveJoystick"
	drive_stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE, 0)
	drive_stick.position = Vector2(18, -124)
	drive_stick.size = Vector2(112, 112)
	drive_stick.z_index = 50
	drive_stick.visible = true
	drive_stick.changed.connect(func(v: Vector2):
		turn_input = v.x
		drive_input = v.y
	)
	mobile_controls.add_child(drive_stick)
	var drive_label := Label.new()
	drive_label.text = "DRIVE / TURN"
	drive_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	drive_label.position = Vector2(18, -146)
	drive_label.add_theme_font_size_override("font_size", 10)
	mobile_controls.add_child(drive_label)
	var swing_stick := TouchJoystick.new()
	swing_stick.name = "BallSwingJoystick"
	swing_stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 0)
	swing_stick.position = Vector2(-134, -124)
	swing_stick.size = Vector2(112, 112)
	swing_stick.name = "BoomJoystick"
	swing_stick.changed.connect(func(v: Vector2):
		boom_joystick_x = v.x
		boom_joystick_y = v.y
	)
	mobile_controls.add_child(swing_stick)
	var swing_label := Label.new()
	swing_label.text = "BOOM CONTROL"
	swing_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	swing_label.position = Vector2(-122, -146)
	swing_label.add_theme_font_size_override("font_size", 10)
	mobile_controls.add_child(swing_label)
	_add_button(mobile_controls, "HOIST", Vector2(-202, -184), Vector2(88, 48), func(): winch_input = -1.0, func(): winch_input = 0.0, false)
	_add_button(mobile_controls, "LOWER", Vector2(-108, -184), Vector2(88, 48), func(): winch_input = 1.0, func(): winch_input = 0.0, false)
	var reset := Button.new()
	reset.text = "RESET ↻"
	reset.position = Vector2(-112, 18)
	reset.size = Vector2(94, 34)
	reset.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	reset.pressed.connect(_reset_job)
	root.add_child(reset)
	# Mobile-only buttons are still usable on desktop; keyboard controls are also enabled.

func _add_button(parent: Control, text_value: String, offset: Vector2, size: Vector2, pressed: Callable, released: Callable, bottom_left: bool, danger := false) -> void:
	var button := Button.new()
	button.text = text_value
	button.size = size
	if bottom_left:
		button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		button.position = Vector2(offset.x, offset.y)
	else:
		button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		button.position = Vector2(offset.x, offset.y)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("#201e18") if danger else Color("#fff8e9"))
	button.add_theme_stylebox_override("normal", _button_style(Color("#bd492b") if danger else Color("#27343a")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("#e4a72a")))
	button.button_down.connect(pressed)
	button.button_up.connect(released)
	parent.add_child(button)

func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 3
	style.border_color = Color("#829097")
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 8
	style.content_margin_right = 8
	return style

func _release_ball() -> void:
	swing_velocity += 2.8 if absf(swing_angle) < 0.05 else signf(swing_angle) * 1.8
	_show_toast("HOIST RELEASED · BALL IN MOTION")

func _reset_job() -> void:
	for panel in wall_panels:
		if is_instance_valid(panel):
			panel.queue_free()
	wall_panels.clear()
	for child in get_children():
		if child is RigidBody3D and child.get_meta("rubble", false):
			child.queue_free()
	for child in get_children():
		if child.name == "Condemned brick workshop":
			child.queue_free()
	_build_building()
	total_panel_count = wall_panels.size()
	crane_root.position = initial_crane_position
	upper.rotation = Vector3.ZERO
	boom_pivot.rotation.z = -0.43
	rope_length = 3.6
	swing_angle = 0.0
	swing_velocity = 0.0
	rubble_count = 0
	_update_stats()
	_show_toast("Fresh demolition contract")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_points[event.index] = event.position
			if touch_points.size() == 2:
				var points: Array = touch_points.values()
				pinch_start_distance = points[0].distance_to(points[1])
				pinch_start_zoom = camera_distance
				camera_dragging = false
			elif touch_points.size() == 1:
				last_camera_pointer = event.position
				camera_dragging = true
		else:
			touch_points.erase(event.index)
			if touch_points.size() < 2:
				pinch_start_distance = 0.0
			camera_dragging = false
	elif event is InputEventScreenDrag:
		touch_points[event.index] = event.position
		if touch_points.size() >= 2:
			var points: Array = touch_points.values()
			var distance: float = points[0].distance_to(points[1])
			if pinch_start_distance > 0.0:
				camera_distance = clampf(pinch_start_zoom * pinch_start_distance / maxf(distance, 1.0), 7.0, 38.0)
		elif camera_dragging:
			var delta_pos: Vector2 = event.position - last_camera_pointer
			camera_yaw -= delta_pos.x * 0.008
			camera_pitch = clampf(camera_pitch + delta_pos.y * 0.006, -0.12, 1.12)
			last_camera_pointer = event.position
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			camera_dragging = event.pressed
			last_camera_pointer = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = clampf(camera_distance - 1.5, 7.0, 38.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = clampf(camera_distance + 1.5, 7.0, 38.0)
	elif event is InputEventMouseMotion and camera_dragging and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var delta_pos: Vector2 = event.position - last_camera_pointer
		camera_yaw -= delta_pos.x * 0.008
		camera_pitch = clampf(camera_pitch + delta_pos.y * 0.006, -0.12, 1.12)
		last_camera_pointer = event.position

func _process(delta: float) -> void:
	var dt := minf(delta, 0.035)
	var cp := cos(camera_pitch)
	var camera_offset := Vector3(sin(camera_yaw) * cp, sin(camera_pitch), cos(camera_yaw) * cp) * camera_distance
	camera.position = camera.position.lerp(camera_target + camera_offset, minf(1.0, dt * 10.0))
	camera.look_at(camera_target, Vector3.UP)
	if Input.is_key_pressed(KEY_A):
		turn_input = -1.0
	elif Input.is_key_pressed(KEY_D):
		turn_input = 1.0
	if Input.is_key_pressed(KEY_W):
		winch_input = -1.0
	elif Input.is_key_pressed(KEY_S):
		winch_input = 1.0
	else:
		winch_input = 0.0
	if Input.is_key_pressed(KEY_SPACE):
		if not swing_boost:
			_release_ball()
		swing_boost = true
	else:
		swing_boost = false
	if Input.is_key_pressed(KEY_R):
		pass
	upper.rotation.y += turn_input * dt * 0.48
	upper.rotation.y += boom_joystick_x * dt * 0.75
	boom_pivot.rotation.z = clampf(boom_pivot.rotation.z - boom_joystick_y * dt * 0.65, -1.05, -0.12)
	crane_root.position.x += drive_input * cos(upper.rotation.y) * dt * 0.9
	crane_root.position.z -= drive_input * sin(upper.rotation.y) * dt * 0.9
	rope_length = clampf(rope_length + winch_input * dt * 1.3, 1.8, 6.2)
	if swing_boost:
		swing_velocity += dt * 1.25
	swing_velocity += (-sin(swing_angle) * 2.0 - swing_velocity * 0.32) * dt
	swing_angle += swing_velocity * dt
	if absf(swing_angle) > 1.1:
		swing_angle = signf(swing_angle) * 1.1
		swing_velocity *= -0.4
	_update_ball_position()
	if absf(swing_angle) > 0.25 and absf(swing_velocity) > 0.4:
		_check_impact()
	if toast_time > 0:
		toast_time -= dt
		if toast_time <= 0:
			toast_label.text = ""

func _update_ball_position() -> void:
	var tip := Vector3(0, BOOM_LEN, 0)
	tip = boom.to_global(tip)
	var swing := Vector3(sin(swing_angle) * rope_length, -cos(swing_angle) * rope_length, 0)
	var target := tip + swing
	ball.global_position = target
	ball.rotation = Vector3.ZERO
	var mid := (tip + target) * 0.5
	cable.global_position = mid
	cable.look_at(target, Vector3.FORWARD)
	cable.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var cylinder := cable.mesh as CylinderMesh
	cylinder.height = tip.distance_to(target)

func _check_impact() -> void:
	var ball_pos := ball.global_position
	for panel in wall_panels:
		if not is_instance_valid(panel) or panel.is_queued_for_deletion():
			continue
		if panel.global_position.distance_to(ball_pos) < 1.15:
			var p := panel.global_position
			panel.queue_free()
			wall_panels.erase(panel)
			_spawn_rubble(p, 5)
			_update_stats()
			_show_toast("WRECKING BALL IMPACT · WALL PANEL BROKEN")
			swing_velocity *= 0.62
			return

func _spawn_rubble(pos: Vector3, count: int) -> void:
	for i in range(count):
		var body := RigidBody3D.new()
		body.position = pos + Vector3(randf_range(-0.25, 0.25), randf_range(0.0, 0.35), randf_range(-0.25, 0.25))
		body.mass = randf_range(0.5, 2.2)
		body.set_meta("rubble", true)
		var size := Vector3(randf_range(0.12, 0.3), randf_range(0.12, 0.28), randf_range(0.12, 0.3))
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = size
		mesh.mesh = cube
		mesh.material_override = _material([Color("#955642"), Color("#b16a51"), Color("#8b8981")][randi_range(0, 2)])
		body.add_child(mesh)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
		body.apply_central_impulse(Vector3(randf_range(-2.4, 2.4), randf_range(1.2, 3.5), randf_range(-2.4, 2.4)))
		rubble_count += 1

func _update_stats() -> void:
	var total := 0
	for panel in wall_panels:
		if is_instance_valid(panel):
			total += 1
	# Remaining panels are tracked directly; a hit removes a panel from this list.
	var destroyed := maxi(0, total_panel_count - total)
	var percent := clampf(float(destroyed) / maxf(1.0, float(total_panel_count)), 0.0, 1.0)
	if damage_label:
		damage_label.text = "BUILDING DAMAGE  %d%%" % roundi(percent * 100.0)
		damage_bar.value = percent * 100.0
		rubble_label.text = "MASONRY REMOVED  %d  ·  RUBBLE CHUNKS %d" % [destroyed, rubble_count]
		if percent >= 0.98:
			_show_toast("BUILDING DOWN · CONTRACT COMPLETE")

func _show_toast(message: String) -> void:
	if toast_label:
		toast_label.text = message
		toast_time = 2.4
