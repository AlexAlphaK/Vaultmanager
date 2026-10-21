class_name BarSfx
extends RefCounted
## Bench sounds for the bar test, synthesised like Sfx: couplant gel, the ultrasound
## flaw detector's pulse, and the XRF gun's tube hum and photon counter.

static var _cache := {}


## A squeeze of couplant gel: a short wet squelch.
static func gel() -> AudioStreamWAV:
	return _cached("gel", func():
		var rng := RandomNumberGenerator.new()
		rng.seed = 12
		var seconds := 0.32
		var data := PackedByteArray()
		data.resize(int(seconds * Sfx.RATE) * 2)
		var low := 0.0
		var phase := 0.0
		for n in int(seconds * Sfx.RATE):
			var t := n / float(Sfx.RATE)
			low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.08)
			phase += TAU * lerpf(220.0, 90.0, t / seconds) / Sfx.RATE
			var env := minf(t / 0.02, 1.0) * exp(-t * 9.0)
			data.encode_s16(n * 2, int(clampf((low * 1.4 + sin(phase) * 0.5) * env * 0.4, -1.0, 1.0) * 32767.0))
		return _wav(data))


## The detector's pulse and its echoes: a tick for the pulse, then one soft blip per
## echo. A clean bar answers with one even train; a hidden core adds a stray blip.
static func ping(clean: bool) -> AudioStreamWAV:
	return _cached("ping%s" % clean, func():
		var notes := [[3400.0, 0.0, 0.03]]
		var times := [0.09, 0.18, 0.27] if clean else [0.06, 0.1, 0.19, 0.24]
		for k in times.size():
			notes.append([2600.0 if clean else 2100.0 + k * 230.0, times[k], 0.05])
		return Sfx._tone(notes, 0.16))


## The X-ray tube's hum with photons clicking on the detector, `seconds` long.
static func xrf(seconds: float) -> AudioStreamWAV:
	return _cached("xrf%.1f" % seconds, func():
		var rng := RandomNumberGenerator.new()
		rng.seed = 31
		var data := PackedByteArray()
		data.resize(int(seconds * Sfx.RATE) * 2)
		var click := 0.0
		for n in int(seconds * Sfx.RATE):
			var t := n / float(Sfx.RATE)
			if rng.randf() < 0.012:
				click = rng.randf_range(0.5, 1.0)
			click *= 0.6
			var env := minf(t / 0.15, 1.0) * minf((seconds - t) / 0.1, 1.0)
			var hum := sin(TAU * 120.0 * t) * 0.3 + sin(TAU * 240.0 * t) * 0.15 + sin(TAU * 7800.0 * t) * 0.03
			data.encode_s16(n * 2, int(clampf((hum * env + click) * 0.3, -1.0, 1.0) * 32767.0))
		return _wav(data))


## The analyzer finishing a reading.
static func xrf_done() -> AudioStreamWAV:
	return _cached("xrf_done", func(): return Sfx._tone([[1760.0, 0.0, 0.09], [2349.0, 0.1, 0.18]], 0.2))


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
