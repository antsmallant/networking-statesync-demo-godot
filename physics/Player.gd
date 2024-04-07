extends RigidBody2D

const HIT_FORCE : float = 10.0
var screen_size
var enable_control = true

func _ready():
	screen_size = get_viewport_rect().size
	
	
func _physics_process(delta):
	pass


func _process(delta):
	pass
#	if enable_control:
#		var velocity = Vector2.ZERO
#		if Input.is_action_pressed("move_right"):
#			velocity.x += 1
#		if Input.is_action_pressed("move_left"):
#			velocity.x -= 1
#		if Input.is_action_pressed("move_down"):
#			velocity.y += 1
#		if Input.is_action_pressed("move_up"):
#			velocity.y -= 1
#
#		if velocity.length() > 0:
#			apply_impulse(Vector2(0, 0), velocity.normalized() * HIT_FORCE)		
	

func apply_input(dir):
	if dir.length() > 0:
		apply_impulse(Vector2(0, 0), dir.normalized() * HIT_FORCE)	
		
		
		
