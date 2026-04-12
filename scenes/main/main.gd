extends Node2D

@onready var orion = $orion
@onready var earth = $earth
@onready var moon = $moon
@onready var camera = $Camera2D
@onready var hud_panel: PanelContainer = $UI/PanelContainer
@onready var main_menu: PanelContainer = $UI/MainMenu
@onready var start_button: Button = $UI/MainMenu/VBoxContainer/StartButton
@onready var quit_menu_button: Button = $UI/MainMenu/VBoxContainer/QuitButton
@onready var end_screen: PanelContainer = $UI/EndScreen
@onready var final_time_label: Label = $UI/EndScreen/VBoxContainer/FinalTimeLabel
@onready var end_menu_button: Button = $UI/EndScreen/VBoxContainer/MenuButton
@onready var quit_end_button: Button = $UI/EndScreen/VBoxContainer/QuitButton
@onready var time_scale_slider: HSlider = $UI/PanelContainer/VBoxContainer/TimeScaleRow/TimeScaleSlider
@onready var time_scale_value_label: Label = $UI/PanelContainer/VBoxContainer/TimeScaleRow/TimeScaleValueLabel
@onready var moon_distance_label: Label = $UI/PanelContainer/VBoxContainer/MoonDistanceLabel
@onready var speed_label: Label = $UI/PanelContainer/VBoxContainer/SpeedLabel
@onready var runtime_label: Label = $UI/PanelContainer/VBoxContainer/RuntimeLabel
@onready var thrust_label: Label = $UI/PanelContainer/VBoxContainer/Thrust
@onready var milestone_label: Label = $UI/PanelContainer/VBoxContainer/Milestone
@export var zoom_speed := 0.5
@export var min_zoom := 0.2
@export var max_zoom := 1.0
@export var simulation_time_scale := 1.0
@export var goal_distance := 10.0
var elapsed_play_time := 0.0
var run_started_msec: int = 0
var min_milestone = 3000
var game_started := false
var game_finished := false

# Die Gravitationskonstante. 
# Im echten Universum ist sie winzig (6.6743e-11).
# Für ein Spiel skaliert man diesen Wert meistens stark nach oben (z.B. 1.0, 100.0 etc.), 
# damit man keine astronomischen Massen wie 10^24 kg eingeben muss (das sprengt Godots Kommazahlen).
#var G: float = 6.6743e-11 
var G: float = 1000.0

func _ready() -> void:
	# orioin in den Orbit der Erde einfügen:
	orion.speed = create_perfect_orbit(earth.global_position, orion.global_position, earth.mass)
	moon.speed = create_perfect_orbit(earth.global_position, moon.global_position, earth.mass)
	start_button.pressed.connect(_on_start_pressed)
	quit_menu_button.pressed.connect(_on_quit_pressed)
	end_menu_button.pressed.connect(_on_back_to_menu_pressed)
	quit_end_button.pressed.connect(_on_quit_pressed)
	time_scale_slider.value_changed.connect(_on_time_scale_slider_value_changed)
	_on_time_scale_slider_value_changed(time_scale_slider.value)
	set_moon_distance(null)
	set_current_speed(null)
	runtime_label.text = "GameTime: 00:00:00"
	_show_main_menu()
	


func create_perfect_orbit(first_pos: Vector2, second_pos: Vector2, first_mass: float) -> Vector2:
	# 1. Distanz zwischen Planet und Satellit berechnen (das 'r' in der Formel)
	var distance: float = first_pos.distance_to(second_pos)
	
	# 2. Die PERFEKTE Geschwindigkeit für einen Kreisorbit berechnen
	var perfect_speed: float = sqrt((G * first_mass) / distance)
	print("Für einen perfekten Orbit brauchst du eine Geschwindigkeit von: ", perfect_speed)
	
	# 3. Den Satelliten exakt im 90 Grad Winkel zum Planeten ausrichten (Tangente)
	var direction_to_planet: Vector2 = (first_pos - second_pos).normalized()
	# Einen 90 Grad gedrehten Vektor erstellen (Orthogonal)
	var orbit_direction: Vector2 = Vector2(-direction_to_planet.y, direction_to_planet.x)
	
	# 4. Dem Satelliten die perfekte Geschwindigkeit und Richtung geben
	return orbit_direction * perfect_speed
	

func _process(delta: float) -> void:
	if not game_started or game_finished:
		return

	# UI stuff:
	elapsed_play_time = float(Time.get_ticks_msec() - run_started_msec) / 1000.0
	runtime_label.text = "GameTime: %s" % _format_elapsed_time(elapsed_play_time)
	set_thrust(0.0)
	
	Engine.time_scale = time_scale_slider.value
	
	# Kamera zoom out
	var distance = earth.position.distance_to(moon.position)
	# Zoom out as distance increases
	var target_zoom = 1.0 / (distance * 0.005) # Adjust formula to taste
	target_zoom = clamp(target_zoom, min_zoom, max_zoom)
	camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), zoom_speed * delta)
	
	# --- 1. RCS / DREHUNG ---
	# Wenn Links/Rechts gedrückt wird, ändert sich nur der WINKEL, nicht die Flugbahn!
	if Input.is_action_pressed("rotate_left"):
		orion.angle -= orion.turn_speed * delta
	if Input.is_action_pressed("rotate_right"):
		orion.angle += orion.turn_speed * delta
		
	# --- 2. BLICKRICHTUNG BERECHNEN ---
	# In Godot zeigt 0 Radiant immer nach RECHTS (Vector2.RIGHT). 
	# Mit .rotated() drehen wir diesen Vektor in die Richtung unseres Winkels.
	var facing_direction: Vector2 = Vector2.RIGHT.rotated(orion.angle)
	
	# Visuelles Update für deinen Sprite/Node (Wichtig, damit du siehst, wo er hinschaut!)
	orion.rotation = orion.angle
	
	# --- 3. TRIEBWERK (SCHUB IN BLICKRICHTUNG) ---
	if Input.is_action_pressed("thrust"):
		orion.speed = apply_directional_thrust(orion.speed, facing_direction, orion.thrust, delta)
		set_thrust(orion.thrust)
	
	# orion
	var orion_orbit = calculate_orbital_step(earth.mass, earth.speed, earth.global_position, orion.mass, orion.speed, orion.global_position, delta)
	orion.position += orion_orbit["shift_vector"]
	orion.speed = orion_orbit["new_velocity"]
	
	#moon
	var moon_orbit = calculate_orbital_step(earth.mass, earth.speed, earth.global_position, moon.mass, moon.speed, moon.global_position, delta)
	moon.position += moon_orbit["shift_vector"]
	moon.speed = moon_orbit["new_velocity"]

	# Vorbereitet: Diese beiden Methoden koennen spaeter mit den echten Werten versorgt werden.
	# Beispiel:
	var moon_distance = orion.global_position.distance_to(moon.global_position)
	set_moon_distance(moon_distance)
	set_current_speed(orion.speed.length())
	if moon_distance <= goal_distance:
		_show_end_screen()


# Berechnet den Positions-Vektor UND die neue Geschwindigkeit für das kleinere Objekt.
func calculate_orbital_step(
	mass_a: float, vel_a: Vector2, pos_a: Vector2, 
	mass_b: float, vel_b: Vector2, pos_b: Vector2, 
	delta: float) -> Dictionary:
	
	# 1. Bestimmen, welches das kleinere Objekt ist
	var is_a_smaller = mass_a < mass_b
	
	var mass_large = mass_b if is_a_smaller else mass_a
	var pos_small = pos_a if is_a_smaller else pos_b
	var pos_large = pos_b if is_a_smaller else pos_a
	var vel_small = vel_a if is_a_smaller else vel_b

	# 2. Vektor vom kleinen zum großen Objekt (Anziehungsrichtung)
	var direction_to_large: Vector2 = pos_large - pos_small
	var distance_squared: float = direction_to_large.length_squared()
	
	# Schutz vor Division durch Null (falls sie exakt übereinander liegen)
	if distance_squared < 0.0001:
		return {"shift_vector": Vector2.ZERO, "new_velocity": vel_small}
	
	# 3. Newtonsches Gravitationsgesetz (F = G * (m1 * m2) / r^2)
	# Da F = m * a, kürzt sich die Masse des kleinen Objekts heraus!
	# Die Beschleunigung (a) hängt NUR von der Masse des großen Objekts ab.
	var acceleration: float = G * (mass_large / distance_squared)
	
	# Beschleunigungsvektor
	var acceleration_vector: Vector2 = direction_to_large.normalized() * acceleration
	
	# 4. Geschwindigkeit aktualisieren (wichtig für einen Orbit!)
	var new_velocity: Vector2 = vel_small + (acceleration_vector * delta)
	
	# 5. Distanz berechnen, die in diesem Frame zurückgelegt wird
	var shift_vector: Vector2 = new_velocity * delta
	
	# Wir geben ein Dictionary zurück, da du zwingend die neue Geschwindigkeit speichern musst.
	return {
		"shift_vector": shift_vector,
		"new_velocity": new_velocity
	}
	
# engine_power ist die Stärke der Beschleunigung (z.B. 500.0)
func apply_prograde_thrust(current_velocity: Vector2, engine_power: float, delta: float) -> Vector2:
	# Verhindern, dass wir durch 0 teilen, falls der Satellit exakt stillsteht
	if current_velocity.length_squared() > 0.001:
		# 1. Flugrichtung ermitteln (Geschwindigkeitsvektor auf Länge 1 bringen)
		var flight_direction: Vector2 = current_velocity.normalized()
		
		# 2. Schub berechnen (Kraft * Zeit)
		var thrust_vector: Vector2 = flight_direction * engine_power * delta
		
		# 3. Den Schub zur aktuellen Geschwindigkeit addieren
		return current_velocity + thrust_vector
		
	return current_velocity
	
# Wendet Schub in die Richtung an, in die das Objekt gerade schaut.
func apply_directional_thrust(current_velocity: Vector2, facing_direction: Vector2, engine_power: float, delta: float) -> Vector2:
	# Schub-Vektor berechnen (Richtung * Kraft * Zeit)
	var thrust_vector: Vector2 = facing_direction * engine_power * delta
	
	# Schub zur aktuellen Geschwindigkeit addieren
	return current_velocity + thrust_vector

func _on_time_scale_slider_value_changed(value: float) -> void:
	simulation_time_scale = value
	time_scale_value_label.text = "%.2fx" % value

func set_moon_distance(distance: Variant) -> void:
	if distance == null:
		moon_distance_label.text = "Distance to moon: --"
		return
	var res = float(distance)
	moon_distance_label.text = "Distance to moon: %.2f" % res
	if res < 10:
		change_milestones(0)
		return
	if res < 100:
		change_milestones(100)
		return
	if res < 500:
		change_milestones(500)
		return
	if res < 1000:
		change_milestones(1000)
		return
	if res < 2000:
		change_milestones(2000)

func set_current_speed(speed: Variant) -> void:
	if speed == null:
		speed_label.text = "Velocity: --"
		return
	speed_label.text = "Velocity: %.2f" % float(speed)
	
func set_thrust(thrust: Variant) -> void:
	if thrust == null:
		thrust_label.text = "Thrust: 0.0 m/s"
		return
	thrust_label.text = "Thrust: %.2f m/s" % float(thrust)

func _format_elapsed_time(total_seconds: float) -> String:
	var full_seconds: int = int(total_seconds)
	var hours: int = full_seconds / 3600
	var minutes: int = (full_seconds % 3600) / 60
	var seconds: int = full_seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]

func change_milestones(new: int) -> void:
	if new < min_milestone:
		min_milestone = new
		milestone_label.text = "Milestone: Distance < " + str(min_milestone)
		return

func _show_main_menu() -> void:
	hud_panel.visible = false
	end_screen.visible = false
	main_menu.visible = true
	start_button.grab_focus()
	Engine.time_scale = 1.0

func _on_start_pressed() -> void:
	main_menu.visible = false
	end_screen.visible = false
	hud_panel.visible = true
	game_started = true
	game_finished = false
	run_started_msec = Time.get_ticks_msec()
	elapsed_play_time = 0.0
	runtime_label.text = "GameTime: 00:00:00"
	time_scale_slider.grab_focus()

func _show_end_screen() -> void:
	if game_finished:
		return
	game_finished = true
	game_started = false
	hud_panel.visible = false
	main_menu.visible = false
	end_screen.visible = true
	final_time_label.text = "Zeit bis Ziel: %s" % _format_elapsed_time(elapsed_play_time)
	end_menu_button.grab_focus()
	Engine.time_scale = 1.0

func _on_back_to_menu_pressed() -> void:
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	get_tree().quit()
	
