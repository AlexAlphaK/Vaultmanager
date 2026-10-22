class_name SmelterSfx
extends RefCounted
## Workshop sounds for the Smelter, synthesised like Sfx: the burner's roar (a seamless
## loop, played louder with more gas), borax fizzing on the melt, the hiss of metal
## pouring, the quench and the hallmark punch.

static var _cache := {}


## One second of the burner: low rumbling noise with a breathy hiss on top. Loops.
static func roar() -> AudioStreamWAV:
	return _cached("roar", func():
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var count := Sfx.RATE
		var data := PackedByteArray()
		data.resize(count * 2)
		var low := 0.0
		var mid := 0.0
		var samples := PackedFloat32Array()
		samples.resize(count)
		for n in count:
			var white := rng.randf_range(-1.0, 1.0)
			low = lerpf(low, white, 0.02)
			mid = lerpf(mid, white, 0.25)
			samples[n] = low * 2.2 + (mid - low) * 0.35 + white * 0.04
		# crossfade the tail into the head so the loop has no click
		var fade := 2000
		for n in fade:
			var t := float(n) / fade
			samples[n] = lerpf(samples[count - fade + n], samples[n], t)
		for n in count:
			data.encode_s16(n * 2, int(clampf(samples[n] * 0.45, -1.0, 1.0) * 32767.0))
		var w := _wav(data)
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = fade
		w.loop_end = count
		return w)


## Borax hitting the melt: a short crackling fizz.
static func fizz() -> AudioStreamWAV:
	return _cached("fizz", func(): return _noise_burst(0.5, 0.35, 0.6, 21, 30.0))


## Metal running out of the crucible into the mould: a soft hiss with spits.
static func pour() -> AudioStreamWAV:
	return _cached("pour", func(): return _noise_burst(0.9, 0.3, 0.45, 8, 0.0))


## The bar going into the quench bucket: a long steamy sizzle.
static func quench() -> AudioStreamWAV:
	return _cached("quench", func(): return _noise_burst(1.4, 0.45, 0.8, 13, 0.0))


## The hallmark punch: a hammer on a steel letter punch.
static func punch() -> AudioStreamWAV:
	return _cached("punch", func(): return Sfx._tone([[880.0, 0.0, 0.05], [1320.0, 0.0, 0.04], [220.0, 0.0, 0.08]], 0.4))


## `seconds` of filtered noise fading out; `bright` mixes in high hiss, `crackle` is how
## many pops a second ride on it.
static func _noise_burst(seconds: float, gain: float, bright: float, seed: int, crackle: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var count := int(seconds * Sfx.RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var low := 0.0
	var pop := 0.0
	for n in count:
		var t := n / float(Sfx.RATE)
		var white := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.15)
		if crackle > 0.0 and rng.randf() < crackle / Sfx.RATE:
			pop = rng.randf_range(0.5, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		pop *= 0.9
		var env := minf(t / 0.03, 1.0) * exp(-t * 2.5 / seconds)
		var v := (low * (1.0 - bright) * 2.0 + white * bright) * env + pop
		data.encode_s16(n * 2, int(clampf(v * gain, -1.0, 1.0) * 32767.0))
	return _wav(data)


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
