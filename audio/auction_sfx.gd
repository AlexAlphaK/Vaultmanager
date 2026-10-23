class_name AuctionSfx
extends RefCounted
## Saleroom sounds, synthesised like Sfx: the gavel on its block, a paddle snapping up,
## and the murmur that runs round the room when the bidding gets hot.

static var _cache := {}


## The gavel: a hollow wooden knock with a sharp crack on top.
static func gavel() -> AudioStreamWAV:
	return _cached("gavel", func():
		var data := PackedByteArray()
		var count := int(0.35 * Sfx.RATE)
		data.resize(count * 2)
		var rng := RandomNumberGenerator.new()
		rng.seed = 41
		for n in count:
			var t := n / float(Sfx.RATE)
			var body := sin(TAU * 190.0 * t) * exp(-t * 28.0) + sin(TAU * 410.0 * t) * 0.5 * exp(-t * 40.0)
			var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 400.0) * 0.9
			data.encode_s16(n * 2, int(clampf((body + crack) * 0.55, -1.0, 1.0) * 32767.0))
		return Sfx._wav(data))


## A paddle raised: a quick papery flick.
static func paddle() -> AudioStreamWAV:
	return _cached("paddle", func(): return SmelterSfx._noise_burst(0.08, 0.25, 0.9, 7, 0.0))


## The room murmuring: soft low noise that swells and fades.
static func murmur() -> AudioStreamWAV:
	return _cached("murmur", func():
		var data := PackedByteArray()
		var count := int(1.2 * Sfx.RATE)
		data.resize(count * 2)
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var low := 0.0
		var mid := 0.0
		for n in count:
			var t := n / float(Sfx.RATE)
			var white := rng.randf_range(-1.0, 1.0)
			low = lerpf(low, white, 0.04)
			mid = lerpf(mid, white, 0.12)
			# voices: the noise pulsed at syllable rate
			var syll := 0.6 + 0.4 * sin(TAU * 4.3 * t) * sin(TAU * 2.9 * t + 1.0)
			var env := sin(PI * t / 1.2)
			data.encode_s16(n * 2, int(clampf((low * 1.6 + (mid - low) * 0.8) * syll * env * 0.5, -1.0, 1.0) * 32767.0))
		return Sfx._wav(data))


static func _cached(key: String, make: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]
