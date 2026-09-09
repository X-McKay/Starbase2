extends RefCounted
## Bounded cosmetic response to actual travel and visual turning, never input intent.
const LIMIT := 0.10
var angles := Vector2.ZERO
var velocity := Vector2.ZERO
var previous_speed := 0.0

func reset() -> void:
	angles=Vector2.ZERO
	velocity=Vector2.ZERO
	previous_speed=0.0

func step(displacement:Vector3, turn:float, delta:float, reduced:bool) -> Quaternion:
	if reduced or delta<=0.0 or delta>0.25 or displacement.length()>0.5:
		reset()
		return Quaternion.IDENTITY
	var speed := minf(displacement.length()/delta,6.0)
	var acceleration := clampf((speed-previous_speed)/delta,-20.0,20.0)
	previous_speed=speed
	var target := Vector2(clampf(-speed*0.009-acceleration*0.001,-0.075,0.035),clampf(-turn/delta*0.012,-0.085,0.085))
	var remaining := delta
	while remaining>0.000001:
		var dt := minf(remaining,1.0/120.0)
		velocity+=(target-angles)*90.0*dt-velocity*18.0*dt
		angles+=velocity*dt
		angles=angles.limit_length(LIMIT)
		remaining-=dt
	return Quaternion(Vector3.RIGHT,angles.x)*Quaternion(Vector3.FORWARD,angles.y)
