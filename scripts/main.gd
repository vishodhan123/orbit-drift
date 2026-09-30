extends Node2D

enum State { TITLE, PLAYING, GAME_OVER }

const SAVE_PATH := "user://orbit_drift_save.cfg"
const CYAN := Color(0.0, 1.0, 0.94)
const MAGENTA := Color(1.0, 0.1, 0.7)
const PURPLE := Color(0.55, 0.2, 1.0)
const ORANGE := Color(1.0, 0.55, 0.15)
const WHITE_GLOW := Color(0.9, 0.95, 1.0)

var state: State = State.TITLE
var score: int = 0
var score_accum: float = 0.0
var high_score: int = 0
var combo: int = 0
var combo_timer: float = 0.0
var score_pops: Array = []  # {pos, text, life, col}
var difficulty: float = 1.0
var elapsed: float = 0.0
var shake: float = 0.0
var flash: float = 0.0
var title_pulse: float = 0.0

var player_pos: Vector2
var player_vel: Vector2 = Vector2.ZERO
var target_pos: Vector2
var dragging: bool = false
var trail: Array = []  # Array of {pos, life}

var asteroids: Array = []
var orbs: Array = []
var particles: Array = []
var stars: Array = []
var spawn_timer: float = 0.0
var orb_timer: float = 1.5

var screen_size: Vector2
var btn_play_rect: Rect2
var btn_restart_rect: Rect2

func _ready() -> void:
	screen_size = get_viewport_rect().size
	player_pos = Vector2(screen_size.x * 0.5, screen_size.y * 0.72)
	target_pos = player_pos
	_load_high_score()
	_init_stars()
	_layout_buttons()

func _layout_buttons() -> void:
	var cx := screen_size.x * 0.5
	btn_play_rect = Rect2(cx - 140, screen_size.y * 0.62, 280, 72)
	btn_restart_rect = Rect2(cx - 140, screen_size.y * 0.58, 280, 72)

func _init_stars() -> void:
	stars.clear()
	for i in range(90):
		stars.append({
			"pos": Vector2(randf() * screen_size.x, randf() * screen_size.y),
			"speed": 20.0 + randf() * 80.0,
			"size": 1.0 + randf() * 2.2,
			"bright": 0.3 + randf() * 0.7,
			"twinkle": randf() * TAU
		})

func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = int(cfg.get_value("scores", "high", 0))

func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "high", high_score)
	cfg.save(SAVE_PATH)

func _start_game() -> void:
	state = State.PLAYING
	score = 0
	score_accum = 0.0
	combo = 0
	combo_timer = 0.0
	score_pops.clear()
	difficulty = 1.0
	elapsed = 0.0
	shake = 0.0
	flash = 0.0
	asteroids.clear()
	orbs.clear()
	particles.clear()
	trail.clear()
	spawn_timer = 0.4
	orb_timer = 1.2
	player_pos = Vector2(screen_size.x * 0.5, screen_size.y * 0.72)
	target_pos = player_pos
	player_vel = Vector2.ZERO

func _game_over() -> void:
	state = State.GAME_OVER
	shake = 18.0
	flash = 0.8
	if score > high_score:
		high_score = score
		_save_high_score()
	_burst(player_pos, MAGENTA, 40)

func _process(delta: float) -> void:
	title_pulse += delta
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 40.0)
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 2.2)

	_update_stars(delta)

	match state:
		State.TITLE:
			pass
		State.PLAYING:
			_update_playing(delta)
		State.GAME_OVER:
			_update_particles(delta)
			_update_trail(delta)
			_update_score_pops(delta)

	queue_redraw()

func _update_stars(delta: float) -> void:
	var scroll := 40.0
	if state == State.PLAYING:
		scroll = 60.0 + difficulty * 50.0
	for s in stars:
		s.pos.y += s.speed * (scroll / 60.0) * delta * 0.35
		s.twinkle += delta * 3.0
		if s.pos.y > screen_size.y + 4.0:
			s.pos.y = -4.0
			s.pos.x = randf() * screen_size.x

func _update_playing(delta: float) -> void:
	elapsed += delta
	difficulty = 1.0 + elapsed * 0.08
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0

	# Smooth follow toward touch target
	var follow := 14.0
	player_pos = player_pos.lerp(target_pos, 1.0 - exp(-follow * delta))
	player_pos.x = clampf(player_pos.x, 36.0, screen_size.x - 36.0)
	player_pos.y = clampf(player_pos.y, screen_size.y * 0.35, screen_size.y - 80.0)

	# Trail
	trail.append({"pos": player_pos + Vector2(0, 18), "life": 0.45})
	_update_trail(delta)

	# Spawns
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_asteroid()
		spawn_timer = maxf(0.28, 1.1 / difficulty) * (0.7 + randf() * 0.6)

	orb_timer -= delta
	if orb_timer <= 0.0:
		_spawn_orb()
		orb_timer = maxf(0.7, 2.2 / (0.7 + difficulty * 0.4)) * (0.8 + randf() * 0.5)

	_update_asteroids(delta)
	_update_orbs(delta)
	_update_particles(delta)
	_update_score_pops(delta)

	# Passive survival score (float accum — int(delta*rate) was always 0)
	score_accum += 18.0 * delta * difficulty
	var add := int(score_accum)
	if add > 0:
		score += add
		score_accum -= float(add)

func _update_trail(delta: float) -> void:
	var keep: Array = []
	for t in trail:
		t.life -= delta
		if t.life > 0.0:
			keep.append(t)
	trail = keep

func _spawn_asteroid() -> void:
	var lane := randi() % 5
	var x := 60.0 + lane * ((screen_size.x - 120.0) / 4.0) + randf_range(-28, 28)
	var kind := randi() % 3
	var r := 18.0 + randf() * 22.0
	if kind == 2:
		r = 12.0 + randf() * 10.0
	asteroids.append({
		"pos": Vector2(x, -40.0 - randf() * 60.0),
		"vel": Vector2(randf_range(-20, 20), 140.0 + difficulty * 90.0 + randf() * 60.0),
		"r": r,
		"rot": randf() * TAU,
		"spin": randf_range(-2.5, 2.5),
		"sides": 5 + randi() % 4,
		"kind": kind,
		"hue": Color(0.7 + randf() * 0.3, 0.2 + randf() * 0.2, 0.85 + randf() * 0.15) if kind == 1 else Color(0.45, 0.5, 0.7)
	})

func _spawn_orb() -> void:
	orbs.append({
		"pos": Vector2(randf_range(50, screen_size.x - 50), -30.0),
		"vel": Vector2(0, 100.0 + difficulty * 40.0),
		"pulse": randf() * TAU,
		"r": 12.0
	})

func _update_asteroids(delta: float) -> void:
	var keep: Array = []
	for a in asteroids:
		a.pos += a.vel * delta
		a.rot += a.spin * delta
		# Collision with player
		if a.pos.distance_to(player_pos) < a.r + 16.0:
			_game_over()
			return
		if a.pos.y < screen_size.y + 80.0:
			keep.append(a)
	asteroids = keep

func _update_orbs(delta: float) -> void:
	var keep: Array = []
	for o in orbs:
		o.pos += o.vel * delta
		o.pulse += delta * 6.0
		if o.pos.distance_to(player_pos) < o.r + 22.0:
			combo += 1
			combo_timer = 2.5
			var mult := mini(combo, 8)
			var pts := 50 * mult
			score += pts
			_add_score_pop(o.pos, "+%d" % pts, CYAN if mult < 3 else MAGENTA)
			_burst(o.pos, CYAN, 18)
			flash = maxf(flash, 0.25)
			continue
		if o.pos.y < screen_size.y + 40.0:
			keep.append(o)
	orbs = keep

func _update_particles(delta: float) -> void:
	var keep: Array = []
	for p in particles:
		p.life -= delta
		p.pos += p.vel * delta
		p.vel *= 0.96
		if p.life > 0.0:
			keep.append(p)
	particles = keep


func _add_score_pop(pos: Vector2, text: String, col: Color) -> void:
	score_pops.append({"pos": pos + Vector2(0, -20), "text": text, "life": 0.9, "col": col})

func _update_score_pops(delta: float) -> void:
	var keep: Array = []
	for p in score_pops:
		p.life -= delta
		p.pos.y -= 40.0 * delta
		if p.life > 0.0:
			keep.append(p)
	score_pops = keep

func _burst(pos: Vector2, col: Color, n: int) -> void:
	for i in range(n):
		var ang := randf() * TAU
		var spd := 40.0 + randf() * 180.0
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": 0.3 + randf() * 0.5,
			"max_life": 0.8,
			"col": col,
			"size": 2.0 + randf() * 3.5
		})

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_on_press(st.position)
		else:
			dragging = false
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if state == State.PLAYING:
			dragging = true
			target_pos = sd.position
			target_pos.y = clampf(target_pos.y, screen_size.y * 0.35, screen_size.y - 80.0)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_press(mb.position)
			else:
				dragging = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if dragging and state == State.PLAYING and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			target_pos = mm.position
			target_pos.y = clampf(target_pos.y, screen_size.y * 0.35, screen_size.y - 80.0)

func _on_press(pos: Vector2) -> void:
	match state:
		State.TITLE:
			if btn_play_rect.has_point(pos):
				_start_game()
		State.PLAYING:
			dragging = true
			target_pos = pos
			target_pos.y = clampf(target_pos.y, screen_size.y * 0.35, screen_size.y - 80.0)
		State.GAME_OVER:
			if btn_restart_rect.has_point(pos):
				_start_game()

func _draw() -> void:
	var offset := Vector2.ZERO
	if shake > 0.0:
		offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	draw_set_transform(offset, 0.0, Vector2.ONE)

	_draw_background()
	_draw_stars()

	match state:
		State.TITLE:
			_draw_title()
		State.PLAYING:
			_draw_game()
			_draw_hud()
		State.GAME_OVER:
			_draw_game()
			_draw_game_over()

	if flash > 0.0:
		draw_rect(Rect2(-20, -20, screen_size.x + 40, screen_size.y + 40), Color(1, 1, 1, flash * 0.35))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_background() -> void:
	# Deep space gradient-ish bands
	draw_rect(Rect2(0, 0, screen_size.x, screen_size.y), Color(0.02, 0.02, 0.07))
	for i in range(6):
		var y := i * screen_size.y / 6.0
		var c := Color(0.04 + i * 0.008, 0.02, 0.1 + i * 0.01, 0.4)
		draw_rect(Rect2(0, y, screen_size.x, screen_size.y / 6.0 + 2), c)
	# Soft nebula blobs
	_draw_glow(Vector2(screen_size.x * 0.2, screen_size.y * 0.3), 120, Color(0.3, 0.0, 0.5, 0.08))
	_draw_glow(Vector2(screen_size.x * 0.8, screen_size.y * 0.55), 140, Color(0.0, 0.25, 0.4, 0.07))

func _draw_stars() -> void:
	for s in stars:
		var a: float = float(s.bright) * (0.6 + 0.4 * sin(float(s.twinkle)))
		draw_circle(s.pos, s.size, Color(0.7, 0.85, 1.0, a))

func _draw_glow(pos: Vector2, radius: float, col: Color) -> void:
	var steps := 5
	for i in range(steps, 0, -1):
		var t := float(i) / float(steps)
		var c := col
		c.a = col.a * t * 0.6
		draw_circle(pos, radius * t, c)

func _draw_title() -> void:
	var cx := screen_size.x * 0.5
	var pulse := 0.5 + 0.5 * sin(title_pulse * 2.5)

	# Orbit rings
	for i in range(3):
		var r := 70.0 + i * 28.0 + pulse * 6.0
		var col := CYAN if i % 2 == 0 else MAGENTA
		col.a = 0.25 + pulse * 0.15
		_draw_ring(Vector2(cx, screen_size.y * 0.28), r, 2.5, col)

	# Mini ship icon
	_draw_ship(Vector2(cx, screen_size.y * 0.28), 1.4, title_pulse)

	# Title text
	_draw_neon_text("ORBIT DRIFT", Vector2(cx, screen_size.y * 0.42), 48, CYAN)
	_draw_neon_text("NEON SPACE DODGE", Vector2(cx, screen_size.y * 0.48), 18, MAGENTA)

	# High score
	_draw_neon_text("HIGH SCORE  %d" % high_score, Vector2(cx, screen_size.y * 0.54), 20, WHITE_GLOW)

	# Play button
	_draw_button(btn_play_rect, "PLAY", CYAN, pulse)

	_draw_neon_text("Drag to steer  ·  Collect orbs  ·  Dodge debris", Vector2(cx, screen_size.y * 0.78), 14, Color(0.6, 0.7, 0.9, 0.7))

func _draw_game() -> void:
	# Trail
	for t in trail:
		var a: float = float(t.life) / 0.45
		_draw_glow(t.pos, 8.0 * a, Color(CYAN.r, CYAN.g, CYAN.b, 0.25 * a))
		draw_circle(t.pos, 3.0 * a, Color(CYAN.r, CYAN.g, CYAN.b, 0.5 * a))

	# Orbs
	for o in orbs:
		var p: float = 0.7 + 0.3 * sin(float(o.pulse))
		_draw_glow(o.pos, 22.0 * p, Color(CYAN.r, MAGENTA.g, 1.0, 0.2))
		_draw_glow(o.pos, 12.0, Color(0.3, 1.0, 1.0, 0.35))
		draw_circle(o.pos, o.r * p, CYAN)
		draw_circle(o.pos, o.r * 0.45, Color(1, 1, 1, 0.85))

	# Asteroids
	for a in asteroids:
		_draw_asteroid(a)

	# Particles
	for p in particles:
		var a: float = float(p.life) / maxf(0.01, float(p.get("max_life", 0.8)))
		var c: Color = p.col
		c.a = a
		draw_circle(p.pos, p.size * a, c)

	# Player
	if state == State.PLAYING or state == State.GAME_OVER:
		_draw_ship(player_pos, 1.0, elapsed * 8.0)

func _draw_asteroid(a: Dictionary) -> void:
	var pts := PackedVector2Array()
	var n: int = a.sides
	for i in range(n):
		var ang: float = float(a.rot) + float(i) / float(n) * TAU
		var jagged: float = float(a.r) * (0.75 + 0.25 * sin(float(i) * 2.7 + float(a.rot)))
		pts.append(a.pos + Vector2(cos(ang), sin(ang)) * jagged)
	var fill: Color = a.hue
	fill.a = 0.55
	draw_colored_polygon(pts, fill)
	var outline := MAGENTA if a.kind == 1 else Color(0.6, 0.75, 1.0)
	outline.a = 0.9
	for i in range(n):
		draw_line(pts[i], pts[(i + 1) % n], outline, 2.0)
	_draw_glow(a.pos, a.r * 1.4, Color(outline.r, outline.g, outline.b, 0.12))

func _draw_ship(pos: Vector2, scale: float, t: float) -> void:
	# Engine glow
	var flame: float = 10.0 + 4.0 * abs(sin(t * 2.0))
	_draw_glow(pos + Vector2(0, 22 * scale), 18 * scale, Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.35))
	draw_circle(pos + Vector2(0, 20 * scale), flame * 0.35 * scale, Color(1.0, 0.6, 0.2, 0.8))

	# Wings
	var wing_col := Color(CYAN.r, CYAN.g, CYAN.b, 0.85)
	var left := PackedVector2Array([
		pos + Vector2(-6, 4) * scale,
		pos + Vector2(-28, 14) * scale,
		pos + Vector2(-8, 10) * scale
	])
	var right := PackedVector2Array([
		pos + Vector2(6, 4) * scale,
		pos + Vector2(28, 14) * scale,
		pos + Vector2(8, 10) * scale
	])
	draw_colored_polygon(left, wing_col)
	draw_colored_polygon(right, wing_col)

	# Body
	var body := PackedVector2Array([
		pos + Vector2(0, -22) * scale,
		pos + Vector2(14, 16) * scale,
		pos + Vector2(0, 10) * scale,
		pos + Vector2(-14, 16) * scale
	])
	draw_colored_polygon(body, Color(0.85, 0.95, 1.0, 0.95))
	# Neon edge
	for i in range(4):
		draw_line(body[i], body[(i + 1) % 4], CYAN, 2.0 * scale)
	# Cockpit
	draw_circle(pos + Vector2(0, -4) * scale, 5.0 * scale, MAGENTA)
	draw_circle(pos + Vector2(0, -4) * scale, 2.5 * scale, Color(1, 1, 1, 0.9))
	_draw_glow(pos, 30 * scale, Color(CYAN.r, CYAN.g, CYAN.b, 0.12))

func _draw_hud() -> void:
	draw_rect(Rect2(0, 0, screen_size.x, 96), Color(0.02, 0.02, 0.1, 0.5))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(20, 36), "BEST  %d" % high_score, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.75, 0.85, 1.0, 0.9))
	_draw_neon_text("SCORE", Vector2(screen_size.x * 0.5, 26), 14, Color(0.55, 0.75, 0.95, 0.9))
	_draw_neon_text("%d" % score, Vector2(screen_size.x * 0.5, 60), 42, CYAN)
	if combo > 1:
		var ccol := MAGENTA
		ccol.a = 0.55 + 0.45 * minf(1.0, combo_timer)
		_draw_neon_text("COMBO x%d" % mini(combo, 8), Vector2(screen_size.x * 0.5, 100), 22, ccol)
	for p in score_pops:
		var a: float = clampf(float(p.life) / 0.9, 0.0, 1.0)
		var c: Color = p.col
		c.a = a
		_draw_neon_text(str(p.text), p.pos, 22, c)

func _draw_game_over() -> void:
	draw_rect(Rect2(0, 0, screen_size.x, screen_size.y), Color(0, 0, 0, 0.55))
	var cx := screen_size.x * 0.5
	_draw_neon_text("SIGNAL LOST", Vector2(cx, screen_size.y * 0.32), 42, MAGENTA)
	_draw_neon_text("SCORE  %d" % score, Vector2(cx, screen_size.y * 0.42), 32, CYAN)
	var best_label := "NEW HIGH SCORE!" if score >= high_score and score > 0 else "HIGH SCORE  %d" % high_score
	_draw_neon_text(best_label, Vector2(cx, screen_size.y * 0.49), 20, ORANGE if score >= high_score else WHITE_GLOW)
	_draw_button(btn_restart_rect, "RETRY", MAGENTA, 0.5 + 0.5 * sin(title_pulse * 3.0))

func _draw_button(rect: Rect2, label: String, accent: Color, pulse: float) -> void:
	var bg := Color(0.05, 0.08, 0.18, 0.85)
	draw_rect(rect, bg)
	var border := accent
	border.a = 0.55 + 0.45 * pulse
	# Border lines
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), border, 2.5)
	draw_line(rect.position + Vector2(0, rect.size.y), rect.position + rect.size, border, 2.5)
	draw_line(rect.position, rect.position + Vector2(0, rect.size.y), border, 2.5)
	draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + rect.size, border, 2.5)
	# Corner accents
	var c := 16.0
	draw_line(rect.position, rect.position + Vector2(c, 0), accent, 3.5)
	draw_line(rect.position, rect.position + Vector2(0, c), accent, 3.5)
	draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + Vector2(rect.size.x - c, 0), accent, 3.5)
	draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + Vector2(rect.size.x, c), accent, 3.5)
	_draw_neon_text(label, rect.get_center(), 28, accent)

func _draw_ring(center: Vector2, radius: float, width: float, col: Color) -> void:
	var pts := 48
	for i in range(pts):
		var a0 := float(i) / float(pts) * TAU
		var a1 := float(i + 1) / float(pts) * TAU
		draw_line(center + Vector2(cos(a0), sin(a0)) * radius, center + Vector2(cos(a1), sin(a1)) * radius, col, width)

func _draw_neon_text(text: String, pos: Vector2, size: int, col: Color, right_align: bool = false) -> void:
	var font := ThemeDB.fallback_font
	var fs := size
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var draw_pos := pos
	if right_align:
		draw_pos.x -= tw
	else:
		draw_pos.x -= tw * 0.5
	draw_pos.y += fs * 0.35
	# Glow layers
	var glow := col
	glow.a = col.a * 0.25
	draw_string(font, draw_pos + Vector2(2, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, glow)
	draw_string(font, draw_pos + Vector2(-1, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, glow)
	draw_string(font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
