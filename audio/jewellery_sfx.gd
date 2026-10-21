class_name JewellerySfx
extends RefCounted
## Bench sounds for the jewellery appraisal, synthesised like Sfx: rubbing a piece on
## the touchstone, acid drops and fizzing, and the thermal diamond tester.

static var _cache := {}


## Metal dragged across slate: band-limited scratchy noise.
static func rub() -> AudioStreamWAV:
	return _cached("rub", func():
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var seconds := 0.7
		var data := PackedByteArray()
		data.resize(int(seconds * Sfx.RATE) * 2)
		var low := 0.0
		for n in int(seconds * Sfx.RATE):
			var t := n / float(Sfx.RATE)
			low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.35)
			var strokes := 0.55 + 0.45 * sin(TAU * 5.0 * t) # three strokes back and forth
			var env := minf(t / 0.02, 1.0) * minf((seconds - t) / 0.08, 1.0)
			data.encode_s16(n * 2, int(clampf(low * strokes * env * 0.35, -1.0, 1.0) * 32767.0))
		return _wav(data))


## A single drop from a dropper bottle.
static func drip() -> AudioStreamWAV:
	return _cached("drip", func():
		var seconds := 0.12
		var data := PackedByteArray()
		data.resize(int(seconds * Sfx.RATE) * 2)
		var phase := 0.0
		for n in int(seconds * Sfx.RATE):
			var t := n / float(Sfx.RATE)
			phase += TAU * lerpf(1400.0, 600.0, t / seconds) / Sfx.RATE
			var v := sin(phase) * exp(-t * 30.0)
			data.encode_s16(n * 2, int(clampf(v * 0.3, -1.0, 1.0) * 32767.0))
		return _wav(data))


## Acid eating base metal: a crackle of tiny bubbles that dies away.
static func fizz() -> AudioStreamWAV:
	return _cached("fizz", func():
		var rng := RandomNumberGenerator.new()
		rng.seed = 9
		var seconds := 1.4
		var data := PackedByteArray()
		data.resize(int(seconds * Sfx.RATE) * 2)
		var pop := 0.0
		for n in int(seconds * Sfx.RATE):
			var t := n / float(Sfx.RATE)
			if rng.randf() < 0.004 * exp(-t * 1.5):
				pop = rng.randf_range(0.4, 1.0)
			pop *= 0.93
			var v := rng.randf_range(-1.0, 1.0) * (pop + 0.04 * exp(-t * 2.0))
			data.encode_s16(n * 2, int(clampf(v * 0.4, -1.0, 1.0) * 32767.0))
		return _wav(data))


## The tester's verdict: a rising run of beeps, held long on a diamond.
static func tester(leds: int) -> AudioStreamWAV:
	return _cached("tester%d" % leds, func():
		var notes := []
		for k in leds:
			notes.append([1200.0 + k * 140.0, k * 0.07, 0.06])
		if leds >= 10:
			notes.append([2700.0, leds * 0.07, 0.6])
		else:
			notes.append([380.0, leds * 0.07 + 0.05, 0.25])
		return Sfx._tone(notes, 0.18))


static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = Sfx.RATE
	w.stereo = false
	w.data = data
	return w


static func _cached(key: String, make: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]
