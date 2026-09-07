extends RefCounted
## Stable authored landmarks. Footprints are consumed by physics and routing.
# Shared arrival/utility geometry; scenery never represents operational health.
const LANDING_CENTER := Vector2(-24,19.5)
const LANDING_RADIUS := 6.0
const NATURAL_BLOCKS := [Rect2(48,-39,12,10),Rect2(8,-25,4,4),Rect2(46,26,4,4)]
const UTILITY_BLOCKS := [Rect2(-30,-17.5,14,6),Rect2(-17.5,-28,2,2)]
const RESERVED_PLOTS := [Vector2(3,34.5),Vector2(-7,23)]
const OUTCROPS := [
	{"at":Vector2(-34,-22),"size":Vector3(3.2,1.7,2.8)},
	{"at":Vector2(-24,-23),"size":Vector3(2.2,0.9,2.0)},
	{"at":Vector2(-8,-39),"size":Vector3(3.0,1.2,2.5)},
	{"at":Vector2(16,-26),"size":Vector3(3.0,1.4,2.6)},
	{"at":Vector2(49,-8),"size":Vector3(3.0,1.6,2.6)},
	{"at":Vector2(33,9),"size":Vector3(2.8,0.9,2.4)},
	{"at":Vector2(10,42),"size":Vector3(2.6,1.1,2.2)},
	{"at":Vector2(-32,21),"size":Vector3(2.4,1.1,2.2)},
	{"at":Vector2(-16,16.5),"size":Vector3(2.0,0.8,1.8)},
	{"at":Vector2(10,-12),"size":Vector3(2.8,1.0,2.4)},
	{"at":Vector2(-34.75,-2),"size":Vector3(2.6,0.9,2.2)},
	{"at":Vector2(45,38),"size":Vector3(2.2,1.2,2.0)}
]
const CRATERS := [
	Vector3(-31,2.0,-27),Vector3(-22,1.9,-27),Vector3(0,2.0,-39),
	Vector3(13.5,1.4,-30),Vector3(34,2.0,14),Vector3(4.5,1.8,18),
	Vector3(-15,1.8,22.5),Vector3(-37,2.2,-10),Vector3(-34,2.3,15)
]
static func rock_bounds() -> Array[Rect2]:
	var result: Array[Rect2]=[]
	for item in OUTCROPS:
		var size := Vector2(item.size.x,item.size.z)
		result.append(Rect2(item.at-size/2,size))
	return result
