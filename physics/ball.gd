extends RigidBody2D

const ALPHA = 0.1
const EPSILON = 0.0005
const STATE_EXPIRATION_TIME = 1.0 / 20.0

var state = null
var state_timer = 0


# Called when the node enters the scene tree for the first time.
func _ready():
	set_can_sleep(false)


func _integrate_forces(s):
	if (state != null and state_timer < STATE_EXPIRATION_TIME):
		state_timer += s.get_step()

		# Lerp
		var rot = slerp_rot(transform.get_rotation(), state.rotation, ALPHA)
		var pos = lerp_pos(transform.get_origin(), state.position, 1.0 - ALPHA)

		# Transforms
		var transform = s.get_transform().rotated(rot - get_rotation())
		transform.origin = pos
		s.set_transform(transform)

		# Forces
		s.set_linear_velocity(state.linear_velocity)
		s.set_angular_velocity(state.angular_velocity)


func set_state(p_state):
	self.state = p_state
	self.state_timer = 0


# Lerp vector
func lerp_pos(v1, v2, alpha):
	return v1 * alpha + v2 * (1.0 - alpha)


# Spherically linear interpolation of rotation
func slerp_rot(r1, r2, alpha):
	var v1 = Vector2(cos(r1), sin(r1))
	var v2 = Vector2(cos(r2), sin(r2))
	var v = slerp(v1, v2, alpha)
	return atan2(v.y, v.x)


# Spherical linear interpolation of two 2D vectors
func slerp(v1, v2, alpha):
	var cos_angle = clamp(v1.dot(v2), -1.0, 1.0)

	if (cos_angle > 1.0 - EPSILON):
		return lerp_pos(v1, v2, alpha).normalized()

	var angle = acos(cos_angle)
	var angle_alpha = angle * alpha
	var v3 = (v2 - (cos_angle * v1)).normalized()
	return v1 * cos(angle_alpha) + v3 * sin(angle_alpha)
