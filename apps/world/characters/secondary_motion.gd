extends RefCounted
## Cosmetic inertia from real displacement; no input intent or task authority.
## The default 0.10 rad preserves the existing audited upper-strand envelope.
const LIMIT := 0.10
var strength := 1.0
var angle_limit := LIMIT

func configure(response_strength: float, maximum_angle: float) -> void:
	assert(is_finite(response_strength) and response_strength>=0.0)
	assert(is_finite(maximum_angle) and maximum_angle>=0.0 and maximum_angle<=PI/2)
	strength=response_strength
	angle_limit=maximum_angle
	reset()

var angles := Vector2.ZERO
var velocity := Vector2.ZERO
var previous_speed := 0.0
var travelled := 0.0

func reset() -> void:
	angles=Vector2.ZERO
	velocity=Vector2.ZERO
	previous_speed=0.0
	travelled=0.0

func step(displacement:Vector3, turn:float, delta:float, reduced:bool, gait_phase:float=-1.0) -> Quaternion:
	if reduced or strength==0.0 or angle_limit==0.0 or delta<=0.0 or delta>0.25 or displacement.length()>0.5 or not displacement.is_finite() or not is_finite(turn):
		reset()
		return Quaternion.IDENTITY
	var distance:=Vector2(displacement.x,displacement.z).length()
	var speed:=minf(distance/delta,6.0)
	var acceleration:=clampf((speed-previous_speed)/delta,-20.0,20.0)
	previous_speed=speed
	travelled+=distance
	# No displacement means no new gait forcing; the spring settles after a stop.
	var phase:=gait_phase*TAU if gait_phase>=0.0 else travelled/3.2*TAU
	var gait_strength:=clampf(speed/6.0,0.0,1.0)
	var target:=Vector2(
		clampf(-speed*0.006-acceleration*0.0015+sin(phase*2.0)*0.020*gait_strength,-0.080,0.040),
		clampf(-turn/delta*0.014+sin(phase)*0.028*gait_strength,-0.085,0.085))
	target*=strength
	# Substeps keep the underdamped response stable at 30/60/120 Hz and hitches.
	var remaining:=delta
	while remaining>0.000001:
		var dt:=minf(remaining,1.0/120.0)
		velocity+=((target-angles)*105.0-velocity*11.0)*dt
		angles+=velocity*dt
		if angles.length()>angle_limit:
			angles=angles.limit_length(angle_limit)
			var outward:=velocity.dot(angles.normalized())
			if outward>0.0: velocity-=angles.normalized()*outward
		remaining-=dt
	return Quaternion(Vector3.RIGHT,angles.x)*Quaternion(Vector3.FORWARD,angles.y)
