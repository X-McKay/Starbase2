extends RefCounted
## One displacement clock owns frames and foot contacts; no wall-clock walking.
var phase := 0.0
var moving := false
var contacts := 0

func reset() -> void:
	phase=0.0; moving=false; contacts=0

func advance(distance: float, stride: float, teleported: bool = false) -> void:
	contacts=0
	if teleported:
		reset(); return
	moving=distance>0.001 # Ignore sub-millimeter collision recovery jitter.
	if not moving: return
	var next:=phase+distance/maxf(stride,0.01)
	contacts=int(floor(next*2))-int(floor(phase*2))
	phase=fposmod(next,1.0)
