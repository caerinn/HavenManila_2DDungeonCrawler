extends CharacterBody2D

# =====================================================================================
#  PLAYER  --  the "game feel" core of the platformer.
#
#  A platformer lives or dies by how the jump feels. Almost everything in here exists
#  to make the controls forgiving and the character feel weighty-but-responsive:
#
#    * Acceleration & friction       - the player ramps up to speed instead of snapping
#    * Coyote time                   - you can still jump for a moment after a ledge
#    * Jump buffering                - a jump pressed just before landing still fires
#    * Variable jump height          - tap = small hop, hold = full jump
#    * Asymmetric gravity            - you fall faster than you rise (less floaty)
#    * Double jump                   - an extra mid-air jump for expression & recovery
#    * Squash & stretch              - the sprite deforms on jump / land / bounce
#    * Dust, sounds, screen shake    - feedback on every action
#    * Stomp                         - land on an enemy to bounce off and squash it
#
#  Tunable numbers live up top so they're easy to feel out.
# =====================================================================================

# --- Horizontal movement ---
const SPEED            = 130.0    # top running speed
const ACCELERATION     = 1300.0   # how fast we reach top speed on the ground
const FRICTION         = 1600.0   # how fast we stop on the ground
const AIR_ACCELERATION = 900.0    # weaker control in the air...
const AIR_FRICTION     = 350.0    # ...and we keep momentum longer in the air

# --- Jumping ---
const JUMP_VELOCITY        = -300.0  # initial jump impulse
const DOUBLE_JUMP_VELOCITY = -260.0  # the second (air) jump, a touch weaker
const JUMP_CUT             = 0.45    # velocity kept when you release jump early (variable height)
const STOMP_BOUNCE         = -260.0  # upward kick when you stomp an enemy
const MAX_FALL_SPEED       = 400.0   # terminal velocity so falls stay controllable
const MAX_AIR_JUMPS        = 1       # extra jumps after leaving the ground

# --- Forgiveness windows (seconds) ---
const COYOTE_TIME  = 0.10  # grace period to jump after walking off an edge
const JUMP_BUFFER  = 0.10  # remember a jump press this long before landing

# Corner correction: if you clip a ceiling tile by just a few pixels on the way
# up, nudge sideways past the corner instead of bonking your head and dropping.
const CORNER_CORRECTION_PIXELS = 4

# --- Gravity feel ---
# Pulled from project settings, then scaled differently going up vs. down.
# Falling faster than you rise is the single biggest "this feels good" trick.
var base_gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
const RISE_GRAVITY_MULT = 0.9    # a little floaty on the way up
const FALL_GRAVITY_MULT = 1.5    # snappier on the way down
# Apex hang time: near the top of the arc gravity eases off for a graceful beat
# of "hang" that makes the peak readable. (See GMTK / Celeste on jump feel.)
const APEX_SPEED_THRESHOLD = 45.0  # |vertical speed| under this = "near the apex"
const APEX_GRAVITY_MULT    = 0.55  # extra-light gravity inside the hang window

# --- Runtime state ---
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var air_jumps_left := 0
var was_on_floor := false
var is_dead := false
var dust_cooldown := 0.0

# Squash & stretch spring state (see _update_squash). squash > 0 = squashed
# (wide & short), squash < 0 = stretched (tall & thin); it springs back to 0.
var squash := 0.0
var squash_vel := 0.0
var base_sprite_y := 0.0

# --- Camera feel: shake, look-ahead, zoom punch ---
var shake_strength := 0.0
const SHAKE_DECAY = 28.0   # higher = shake settles back faster

# Look-ahead: the camera leads slightly in the direction you're running so you
# can see what you're moving into. The camera is a character too.
var look_ahead_x := 0.0
const LOOK_AHEAD       = 16.0   # how far the camera leads, in pixels
const LOOK_AHEAD_SPEED = 4.0    # how quickly it eases to the lead position

# Zoom "punch": a quick push-in on big impacts that springs back to normal.
var base_zoom := Vector2.ONE
var zoom_punch := 0.0
const ZOOM_PUNCH_DECAY = 5.0

# --- Motion trail (after-images) ---
# A short streak of fading ghost-sprites left behind by the flashy moves
# (double jump, stomp bounce) to make them read as fast and powerful.
var trail_timer := 0.0
var afterimage_cooldown := 0.0
const TRAIL_DURATION      = 0.35
const AFTERIMAGE_INTERVAL = 0.05
const TRAIL_COLOR = Color(0.6, 0.8, 1.0, 0.5)

# --- Squash & stretch (Mario-style spring) ---
const SQUASH_STIFFNESS = 360.0  # spring strength — higher = snappier recovery
const SQUASH_DAMPING   = 16.0   # higher = calmer; lower = more bounce/wobble
const AIR_STRETCH_MAX  = 0.10   # subtle tall-stretch that grows with air speed
const SQUASH_PIVOT     = 16.0   # keeps the feet planted while squashing
const LAND_SQUASH_MIN  = 0.14   # squash from the softest landing
const LAND_SQUASH_MAX  = 0.36   # squash from a full-speed slam
const JUMP_STRETCH     = 0.22   # stretch on take-off
const BOUNCE_SQUASH    = 0.28   # squash kick when stomping an enemy
const SPAWN_SQUASH     = 0.22   # the pop-in at level start

@onready var animated_sprite = $AnimatedSprite2D
@onready var camera           = get_node_or_null("Camera2D")


func _ready():
	var size := get_viewport_rect().size
	
	add_to_group("player")
	#if camera:
	#	base_zoom = camera.zoom   # remember the resting zoom so punches settle back
	base_sprite_y = animated_sprite.position.y
	_squash_impulse(SPAWN_SQUASH)  # a little pop-in so the level starts with energy


func _physics_process(delta):
	if is_dead:
		return

	#_apply_gravity(delta)
	_handle_jump(delta)
	_handle_horizontal(delta)
	_update_animation()

	# Slip past ceiling corners you *almost* cleared, just before we move.
	_corner_correction()

	# Leave a fading after-image streak during the flashy moves.
	_update_trail(delta)

	# Remember floor state + fall speed, run, then react to having just landed.
	# (move_and_slide zeroes velocity.y on impact, so we must read it first.)
	was_on_floor = is_on_floor()
	var fall_speed = velocity.y
	move_and_slide()
	_check_landing(fall_speed)


# Camera craft lives in _process so it keeps animating smoothly even during the
# death freeze-frame (when physics is paused). It layers three effects onto the
# camera: a directional look-ahead, a decaying shake, and a settling zoom punch.
func _process(delta):
	_update_squash(delta)   # drive the squash/stretch spring every frame

	if camera == null:
		return

	# Look-ahead: ease the camera toward a lead offset in the move direction.
	var target_lead := 0.0
	if not is_dead and absf(velocity.x) > 20.0:
		target_lead = signf(velocity.x) * LOOK_AHEAD
	look_ahead_x = lerp(look_ahead_x, target_lead, 1.0 - exp(-LOOK_AHEAD_SPEED * delta))

	# Decaying random shake, added on top of the look-ahead.
	var shake_vec := Vector2.ZERO
	if shake_strength > 0.0:
		shake_strength = move_toward(shake_strength, 0.0, SHAKE_DECAY * delta)
		shake_vec = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_strength

	camera.offset = Vector2(look_ahead_x, 0.0) + shake_vec

	# Zoom punch: push in on impact, then spring back to the resting zoom.
	if zoom_punch > 0.0:
		zoom_punch = move_toward(zoom_punch, 0.0, ZOOM_PUNCH_DECAY * delta)
	camera.zoom = base_zoom * (1.0 + zoom_punch)


# ---------------------------------------------------------------------------
#  MOVEMENT
# ---------------------------------------------------------------------------
func _apply_gravity(delta):
	if not is_on_floor():
		# Heavier gravity while falling than while rising = a satisfying arc.
		var mult = RISE_GRAVITY_MULT if velocity.y < 0.0 else FALL_GRAVITY_MULT
		# Apex hang: ease gravity right at the top of the arc for a beat of float.
		if absf(velocity.y) < APEX_SPEED_THRESHOLD:
			mult *= APEX_GRAVITY_MULT
		velocity.y += base_gravity * mult * delta
		velocity.y = min(velocity.y, MAX_FALL_SPEED)


func _handle_jump(delta):
	# Tick down the two forgiveness timers.
	if is_on_floor():
		coyote_timer = COYOTE_TIME
		air_jumps_left = MAX_AIR_JUMPS
	else:
		coyote_timer = max(coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = JUMP_BUFFER
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0.0)

	# A buffered press + coyote grace = a ground jump.
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		_do_jump(JUMP_VELOCITY)
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
	# Otherwise spend an air jump (double jump) with its own pop of feedback.
	elif jump_buffer_timer > 0.0 and air_jumps_left > 0:
		_do_jump(DOUBLE_JUMP_VELOCITY)
		trail_timer = TRAIL_DURATION   # streak out of the double jump
		air_jumps_left -= 1
		jump_buffer_timer = 0.0

	# Variable jump height: let go early and the jump is cut short.
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT


func _do_jump(jump_force: float):
	velocity.y = jump_force
	_squash_impulse(-JUMP_STRETCH)   # stretch tall on take-off


func _handle_horizontal(delta):
	var direction = Input.get_axis("move_left", "move_right")

	if direction != 0.0:
		var accel = ACCELERATION if is_on_floor() else AIR_ACCELERATION
		velocity.x = move_toward(velocity.x, direction * SPEED, accel * delta)
		animated_sprite.flip_h = direction < 0.0
	else:
		var fric = FRICTION if is_on_floor() else AIR_FRICTION
		velocity.x = move_toward(velocity.x, 0.0, fric * delta)

	# Kick up dust while running on the ground.
	if is_on_floor() and abs(velocity.x) > 40.0:
		dust_cooldown -= delta
		if dust_cooldown <= 0.0:
			dust_cooldown = 0.2


# ---------------------------------------------------------------------------
#  LANDING & STOMPING
# ---------------------------------------------------------------------------
func _check_landing(fall_speed: float):
	# Just touched down this frame.
	if is_on_floor() and not was_on_floor:
		var impact = max(fall_speed, 0.0)  # downward speed at the moment of impact
		# Squish the player on impact — harder falls flatten more, but even a soft
		# hop gets a clear squish. The spring then bounces it back through a stretch.
		var squish = clamp(impact / 320.0, LAND_SQUASH_MIN, LAND_SQUASH_MAX)
		_squash_impulse(squish)
		# Only real falls shake the screen — a normal hop barely registers.
		add_shake(clamp((impact - 120.0) / 220.0, 0.0, 2.0))
		add_zoom_punch(clamp(impact / 1400.0, 0.0, 0.05))


# Called by an enemy when we land on its head: pop upward, refresh the air jump,
# and pile on the feedback (a freeze-frame, a shake, a squash) to sell the hit.
# Enemies are Area2D-based, so they detect the stomp and call this on us.
func bounce(amount: float = STOMP_BOUNCE):
	velocity.y = amount
	air_jumps_left = MAX_AIR_JUMPS
	add_shake(2.5)
	add_zoom_punch(0.10)         # snappy push-in sells the stomp
	trail_timer = TRAIL_DURATION # streak off the bounce
	_squash_impulse(BOUNCE_SQUASH)


# ---------------------------------------------------------------------------
#  DEATH
# ---------------------------------------------------------------------------
# Called by the killzone (falling off the map) and by enemies (touching them).
func die():
	if is_dead:
		return
	is_dead = true

	add_shake(7.0)
	add_zoom_punch(0.18)
	velocity = Vector2.ZERO
	set_physics_process(false)
	$CollisionShape2D.set_deferred("disabled", true)

	# Dramatic slow-mo, then restart.
	Engine.time_scale = 0.4
	await get_tree().create_timer(0.8, true, false, true).timeout
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
#  FEEDBACK HELPERS
# ---------------------------------------------------------------------------
func add_shake(amount: float):
	shake_strength = max(shake_strength, amount)


# A quick camera push-in that springs back (see _process). Bigger = punchier.
func add_zoom_punch(amount: float):
	zoom_punch = max(zoom_punch, amount)


# While the trail timer is active, drop a fading ghost on a fixed cadence.
func _update_trail(delta: float):
	if trail_timer <= 0.0:
		return
	trail_timer -= delta
	afterimage_cooldown -= delta
	if afterimage_cooldown <= 0.0:
		afterimage_cooldown = AFTERIMAGE_INTERVAL
		_spawn_afterimage()


# Snapshots the current sprite frame as a static ghost that fades out in place.
func _spawn_afterimage():
	var frames: SpriteFrames = animated_sprite.sprite_frames
	if frames == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = frames.get_frame_texture(animated_sprite.animation, animated_sprite.frame)
	ghost.global_position = animated_sprite.global_position
	ghost.flip_h = animated_sprite.flip_h
	ghost.scale = animated_sprite.scale
	ghost.modulate = TRAIL_COLOR
	ghost.z_index = 4   # behind the player (z_index 5)

	var scene := get_tree().current_scene
	if scene == null:
		return
	scene.add_child(ghost)

	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.25)
	tween.tween_callback(ghost.queue_free)


# Plays a sound with a little random pitch so repeated actions never sound
# identical — the cheapest way to kill "repetition fatigue" in the SFX.
func _play_varied(sound: AudioStreamPlayer, low := 0.92, high := 1.09):
	sound.pitch_scale = randf_range(low, high)
	sound.play()


# Ceiling corner correction: while rising, if the head is blocked but a tiny
# sideways nudge would clear the corner, take it. Turns cheap head-bonks into
# smooth slips past tile edges. No-op when there's nothing above you.
func _corner_correction():
	if velocity.y >= 0.0:
		return
	var motion := Vector2(0.0, velocity.y) * get_physics_process_delta_time()
	if not test_move(global_transform, motion):
		return  # clear path up — nothing to correct
	for offset in range(1, CORNER_CORRECTION_PIXELS + 1):
		for dir in [1, -1]:
			var shift := Vector2(dir * offset, 0.0)
			# The nudge itself must be unobstructed, and must clear the ceiling.
			if test_move(global_transform, shift):
				continue
			if not test_move(global_transform.translated(shift), motion):
				global_position.x += dir * offset
				return

# Squash & stretch, Mario-style. A single damped spring (_update_squash) drives
# the sprite's scale; this just "kicks" it. Positive = squash (wide & short, for
# impacts); negative = stretch (tall & thin, for take-offs). The spring then
# carries it back past neutral with a lively overshoot, so a squash flows into a
# little stretch and settles — that bounce is what makes it feel good.
func _squash_impulse(amount: float):
	squash = amount
	squash_vel = 0.0


# Integrates the squash spring every frame and applies it to the sprite. While
# airborne the rest pose is a slight tall-stretch that grows with vertical speed
# (extra "Mario" juice); on the ground it rests at neutral. We also slide the
# sprite down as it squashes so the feet stay planted instead of floating up.
func _update_squash(delta: float):
	if animated_sprite == null:
		return
	var d = minf(delta, 0.033)   # guard the spring against frame-time spikes
	var rest := 0.0
	if not is_on_floor() and not is_dead:
		rest = -clampf(absf(velocity.y) / 650.0, 0.0, AIR_STRETCH_MAX)
	var force = -SQUASH_STIFFNESS * (squash - rest) - SQUASH_DAMPING * squash_vel
	squash_vel += force * d
	squash += squash_vel * d
	animated_sprite.scale = Vector2(1.0 + squash, 1.0 - squash)
	animated_sprite.position.y = base_sprite_y + SQUASH_PIVOT * squash


# ---------------------------------------------------------------------------
#  ANIMATION
# ---------------------------------------------------------------------------
func _update_animation():
	if not is_on_floor():
		animated_sprite.play("action")
	elif abs(velocity.x) > 10.0:
		animated_sprite.play("run")
	else:
		animated_sprite.play("walking_idle")
