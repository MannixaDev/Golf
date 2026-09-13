## Asserts the synthesised sound bank actually contains sound.
##
## Generated audio fails silently in the most literal sense: a bad envelope or a
## clamped-to-zero buffer produces a stream that loads, plays, and cannot be
## heard. So each effect is measured rather than assumed.
extends SceneTree

var failures := 0


func _initialize() -> void:
	var bank := SoundBank.build()
	print("=== sound bank (%d effects) ===" % bank.size())

	var ids: Array = bank.keys()
	ids.sort()
	for id in ids:
		var stream: AudioStreamWAV = bank[id]
		var samples := _samples(stream)
		var peak := 0.0
		var energy := 0.0
		for value in samples:
			peak = maxf(peak, absf(value))
			energy += value * value
		var rms := sqrt(energy / maxf(samples.size(), 1))
		var length := float(samples.size()) / SoundBank.RATE

		print("  %-11s %5.0f ms   peak %.2f   rms %.3f" % [
			id, length * 1000.0, peak, rms])

		_expect(samples.size() > 0, "%s has no samples" % id)
		_expect(length > 0.02 and length < 2.0,
			"%s is an implausible length" % id)
		# Loud enough to hear, quiet enough not to clip the whole buffer.
		_expect(peak > 0.05, "%s is effectively silent" % id)
		_expect(peak <= 1.0, "%s exceeds full scale" % id)
		_expect(rms > 0.005, "%s carries almost no energy" % id)
		_expect(stream.mix_rate == SoundBank.RATE, "%s has the wrong rate" % id)

	_expect(bank.has(&"drive") and bank.has(&"putt") and bank.has(&"splash"),
		"the bank should cover striking, putting and water")

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


## Decode the 16-bit PCM back to floats so the buffer can be measured.
func _samples(stream: AudioStreamWAV) -> PackedFloat32Array:
	var data := stream.data
	var out := PackedFloat32Array()
	out.resize(data.size() / 2)
	for i in out.size():
		out[i] = float(data.decode_s16(i * 2)) / 32768.0
	return out


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
