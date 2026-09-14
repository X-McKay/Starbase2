extends Node
## Optional decorative room tone, unrelated to agent work or operational health.
## Defaults silent. Uses only original deterministic synthesis; no recording/network.
const RATE := 22050
const SECONDS := 5
const FRAMES := RATE * SECONDS
const LEVEL_DB := -29.0
var _player: AudioStreamPlayer
var _cache: Dictionary = {}
var _context := ""
var _enabled := false

func _ready() -> void:
	_ensure_player()

func _ensure_player() -> void:
	if is_instance_valid(_player):
		return
	_player = AudioStreamPlayer.new()
	_player.name = "DecorativeRoomTone"
	_player.autoplay = false
	_player.volume_db = LEVEL_DB
	_player.max_polyphony = 1
	add_child(_player)

func configure(room_id: String, garden: bool, enabled: bool) -> void:
	_ensure_player()
	var next_context := ""
	if garden:
		next_context = "water"
	elif room_id in ["review", "command"]:
		next_context = "vent"
	elif room_id == "habitat":
		next_context = "air"
	elif room_id in ["greenhouse", "botanical"]:
		next_context = "water"
	_enabled = enabled and not next_context.is_empty()
	if not _enabled:
		_player.stop() # Muting is immediate, including during a context transition.
		_context = next_context
		return
	if next_context == _context and _player.playing:
		return
	_player.stop()
	_context = next_context
	if not _cache.has(_context):
		_cache[_context] = _make_stream(_context)
	_player.stream = _cache[_context]
	_player.play()

func _make_stream(kind: String) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(FRAMES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 471093
	var low := 0.0
	var slow := 0.0
	for index in range(FRAMES):
		var time := float(index) / RATE
		# Smoothed deterministic air noise avoids sharp static or hiss.
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.065
		slow += (low - slow) * 0.012
		var value := slow * 0.8
		if kind == "vent":
			value += sin(TAU * 55.0 * time) * 0.075
			value += sin(TAU * 110.0 * time) * 0.018
		elif kind == "water":
			value = low * 0.16 + slow * 0.35
			# Quiet droplets overlap the water bed without a rhythmic alert pattern.
			for offset in [0.18, 0.91, 1.73, 2.02, 3.21, 4.47]:
				var age := fposmod(time - offset, float(SECONDS))
				if age < 0.30:
					var envelope := (1.0 - exp(-age * 140.0)) * exp(-age * 22.0)
					var phase := TAU * (520.0 * age + 85.0 * (1.0 - exp(-age * 18.0)))
					value += sin(phase) * envelope * 0.052
		samples[index] = value
	# Short smooth ramps reach exact zero at the loop seam, preventing a click.
	var ramp := int(RATE * 0.10)
	for index in range(ramp):
		var weight := 0.5 - 0.5 * cos(PI * float(index) / ramp)
		samples[index] *= weight
		samples[FRAMES - 1 - index] *= weight
	var bytes := PackedByteArray()
	bytes.resize(FRAMES * 2)
	for index in range(FRAMES):
		var sample := clampi(roundi(samples[index] * 32767.0), -32768, 32767)
		bytes.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = FRAMES
	return stream

func _exit_tree() -> void:
	if is_instance_valid(_player):
		_player.stop()
		_player.stream = null
	_cache.clear()
