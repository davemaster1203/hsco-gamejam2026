extends Node2D

@onready var orion = $orion
@onready var earth = $earth
@onready var moon = $moon
@onready var camera = $Camera2D
@export var zoom_speed := 0.5
@export var min_zoom := 0.2
@export var max_zoom := 1.0

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
	
	var distance = earth.position.distance_to(moon.position)
	# Zoom out as distance increases
	var target_zoom = 1.0 / (distance * 0.005) # Adjust formula to taste
	target_zoom = clamp(target_zoom, min_zoom, max_zoom)
	camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), zoom_speed * delta)
	
	
	# --- 1. RCS / DREHUNG ---
	# Wenn Links/Rechts gedrückt wird, ändert sich nur der WINKEL, nicht die Flugbahn!
	if Input.is_action_pressed("ui_left"):
		orion.angle -= orion.turn_speed * delta
	if Input.is_action_pressed("ui_right"):
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
	
	# orion
	var orion_orbit = calculate_orbital_step(earth.mass, earth.speed, earth.global_position, orion.mass, orion.speed, orion.global_position, delta)
	orion.position += orion_orbit["shift_vector"]
	orion.speed = orion_orbit["new_velocity"]
	
	#moon
	var moon_orbit = calculate_orbital_step(earth.mass, earth.speed, earth.global_position, moon.mass, moon.speed, moon.global_position, delta)
	moon.position += moon_orbit["shift_vector"]
	moon.speed = moon_orbit["new_velocity"]


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
