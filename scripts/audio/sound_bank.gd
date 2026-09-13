## Synthesises every sound effect in the game at startup.
##
## The project deliberately ships no binary assets, so rather than skip audio the
## sounds are generated as PCM: a strike is a low sine with a noise transient, a
## splash is filtered noise with a falling pitch, a holed putt is two tones and a
## rattle. It costs a few milliseconds once and keeps the repository text-only.
class_name SoundBank
extends RefCounted

const RATE := 22050


## One-pole low pass, which is all that is needed to turn white noise into
## something that sounds like turf rather than static.
class LowPass:
	var _value := 0.0
	var _amount := 0.5

	func _init(amount: float) -> void:
		_amount = clampf(amount, 0.01, 1.0)

	func apply(sample: float) -> float:
		_value += (sample - _value) * _amount
		return _value


static func build() -> Dictionary:
	return {
		&"drive": _strike(90.0, 9.0, 0.34, 0.9),
		&"iron": _strike(150.0, 14.0, 0.24, 0.75),
		&"chip": _strike(220.0, 20.0, 0.18, 0.6),
		&"putt": _strike(430.0, 34.0, 0.10, 0.5),
		&"land_soft": _landing(0.30, 0.16, 0.45),
		&"land_rough": _landing(0.55, 0.24, 0.5),
		&"land_sand": _landing(0.85, 0.30, 0.55),
		&"splash": _splash(),
		&"holed": _holed(),
		&"card": _click(1250.0, 0.045, 0.32),
		&"select": _click(760.0, 0.055, 0.28),
		&"whoosh": _whoosh(),
	}


# --- Generators -----------------------------------------------------------

## A struck ball: a very short noise transient for the click of the face, over a
## low body tone that decays away.
static func _strike(freq: float, decay: float, length: float,
		volume: float) -> AudioStreamWAV:
	var frames := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq)
	var filter := LowPass.new(0.55)

	for i in frames:
		var t := float(i) / RATE
		var envelope := exp(-t * decay)
		var body := sin(TAU * freq * t) * envelope
		# The transient is what makes it read as a hit rather than a beep.
		var transient := 0.0
		if t < 0.012:
			transient = filter.apply(rng.randf_range(-1.0, 1.0)) * (1.0 - t / 0.012)
		samples[i] = (body * 0.8 + transient * 0.9) * volume
	return _to_stream(samples)


## The ball arriving: a dull thump whose brightness says what it landed on.
static func _landing(brightness: float, length: float,
		volume: float) -> AudioStreamWAV:
	var frames := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(brightness * 1000.0)
	var filter := LowPass.new(clampf(brightness, 0.05, 1.0))

	for i in frames:
		var t := float(i) / RATE
		var envelope := exp(-t * 26.0)
		var noise := filter.apply(rng.randf_range(-1.0, 1.0))
		var thud := sin(TAU * 70.0 * t) * exp(-t * 40.0) * 0.5
		samples[i] = (noise * envelope + thud) * volume
	return _to_stream(samples)


## Water: a bloop that falls in pitch, wrapped in filtered noise.
static func _splash() -> AudioStreamWAV:
	var length := 0.45
	var frames := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var filter := LowPass.new(0.35)
	var phase := 0.0

	for i in frames:
		var t := float(i) / RATE
		var progress := t / length
		# Falling pitch is what makes water read as water.
		var freq: float = lerpf(520.0, 140.0, progress * progress)
		phase += TAU * freq / RATE
		var bloop := sin(phase) * exp(-t * 7.0)
		var spray := filter.apply(rng.randf_range(-1.0, 1.0)) * exp(-t * 12.0)
		samples[i] = (bloop * 0.7 + spray * 0.5) * 0.6
	return _to_stream(samples)


## Holed out: the rattle of the ball against the cup, then a small reward chime.
static func _holed() -> AudioStreamWAV:
	var length := 0.7
	var frames := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var filter := LowPass.new(0.7)

	for i in frames:
		var t := float(i) / RATE
		var value := 0.0
		# Three quick knocks against the plastic.
		for knock in 3:
			var start := 0.02 + knock * 0.055
			if t >= start and t < start + 0.05:
				var local := t - start
				value += filter.apply(rng.randf_range(-1.0, 1.0)) \
					* exp(-local * 70.0) * 0.7
		# Then the chime, a fifth apart, well after the rattle.
		if t > 0.20:
			var chime := t - 0.20
			var decay := exp(-chime * 5.0)
			value += (sin(TAU * 880.0 * chime) * 0.5
				+ sin(TAU * 1320.0 * chime) * 0.32) * decay
		samples[i] = value * 0.55
	return _to_stream(samples)


static func _click(freq: float, length: float, volume: float) -> AudioStreamWAV:
	var frames := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for i in frames:
		var t := float(i) / RATE
		samples[i] = sin(TAU * freq * t) * exp(-t * 60.0) * volume
	return _to_stream(samples)


## Air moving: noise that swells and fades, for a card leaving your hand.
static func _whoosh() -> AudioStreamWAV:
	var length := 0.28
	var frames := int(RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var filter := LowPass.new(0.18)

	for i in frames:
		var progress := float(i) / frames
		var envelope := sin(PI * progress)
		samples[i] = filter.apply(rng.randf_range(-1.0, 1.0)) * envelope * 0.35
	return _to_stream(samples)


# --- Encoding -------------------------------------------------------------

static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var value := clampf(samples[i], -1.0, 1.0)
		data.encode_s16(i * 2, int(value * 32000.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
