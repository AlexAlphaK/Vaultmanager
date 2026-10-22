class_name ShopSfx
extends RefCounted
## Shop floor sounds, synthesised like Sfx: the bell on its spring over the door, the
## register's ka-ching, coins clinking on the counter, the service bell, the customers'
## little made-up voices, and the stings for a caught fake, a bad call and a snatch.

const VOWELS := {
	# formant 1, formant 2 (Hz), and how loud the vowel is
	"a": [800.0, 1250.0, 1.0], "e": [450.0, 2000.0, 0.9], "i": [300.0, 2300.0, 0.8],
	"o": [500.0, 850.0, 1.0], "u": [330.0, 800.0, 0.85], "m": [260.0, 1100.0, 0.45],
}
## Each mood is a few syllables: [pitch from, pitch to, vowel, seconds, gap after].
const MOODS := {
	"hello": [[1.0, 1.18, "e", 0.07, 0.02], [1.15, 0.95, "o", 0.11, 0.0]],
	"happy": [[1.0, 1.25, "o", 0.08, 0.03], [1.3, 1.65, "i", 0.13, 0.0]],
	"hmm": [[0.92, 0.88, "m", 0.12, 0.03], [0.95, 1.08, "m", 0.16, 0.0]],
	"grumble": [[0.85, 0.72, "m", 0.12, 0.02], [0.8, 0.6, "u", 0.18, 0.0]],
	"angry": [[1.1, 0.95, "a", 0.07, 0.02], [1.2, 1.0, "a", 0.07, 0.02], [1.05, 0.7, "o", 0.14, 0.0]],
	"gasp": [[1.3, 1.8, "a", 0.13, 0.0]],
}
const BASE_HZ := 185.0

static var _cache := {}


## Renders the sounds a shop day needs up front, so the first customer doesn't stutter.
static func warm_up() -> void:
	door_bell()
	ka_ching()
	service_bell()
	sparkle()
	for take in 3:
		coin_clink(take)


## The bell on its spring over the door: a bright strike, then two smaller jingles as it swings.
static func door_bell() -> AudioStreamWAV:
	return _cached("door", func():
		var buf := _buf(1.2)
		var partials := [[1.0, 1.0, 1.0], [2.32, 0.5, 2.2], [4.25, 0.25, 3.5], [6.63, 0.12, 5.0]]
		for k in 3:
			_strike(buf, k * 0.1 + (0.02 if k == 2 else 0.0), 2350.0 + k * 40.0, partials, 0.8, [1.0, 0.6, 0.35][k], 11.0)
		return _wav(buf, 0.22))


## The register drawer sliding out, its bell, and coins dropping into the tray.
static func ka_ching() -> AudioStreamWAV:
	return _cached("ka_ching", func():
		var buf := _buf(0.9)
		_noise(buf, 0.0, 0.1, 0.5, 0.25, 7)
		_clink(buf, 0.0, 1300.0, 0.4)
		_strike(buf, 0.06, 2093.0, [[1.0, 1.0, 1.0], [2.0, 0.35, 2.0], [3.01, 0.2, 3.0], [4.2, 0.1, 4.0]], 0.7, 1.0, 0.0)
		_strike(buf, 0.1, 2637.0, [[1.0, 1.0, 1.0], [2.0, 0.3, 2.0]], 0.6, 0.6, 0.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for k in 3:
			_clink(buf, 0.12 + k * 0.05 + rng.randf() * 0.02, rng.randf_range(4200.0, 6200.0), 0.35)
		return _wav(buf, 0.24))


## A small handful of coins set down on the counter. Three takes, so piles don't all sound alike.
static func coin_clink(take := 0) -> AudioStreamWAV:
	take = posmod(take, 3)
	return _cached("clink%d" % take, func():
		var rng := RandomNumberGenerator.new()
		rng.seed = 21 + take
		var buf := _buf(0.45)
		var at := 0.0
		for k in 4 + take:
			_clink(buf, at, rng.randf_range(3600.0, 6800.0), rng.randf_range(0.5, 1.0))
			at += rng.randf_range(0.025, 0.07)
		return _wav(buf, 0.22))


## The brass service bell on the counter, struck once.
static func service_bell() -> AudioStreamWAV:
	return _cached("service", func():
		var buf := _buf(1.1)
		_clink(buf, 0.0, 2400.0, 0.3)
		_strike(buf, 0.0, 2960.0, [[1.0, 1.0, 1.0], [2.41, 0.4, 2.0], [4.1, 0.2, 3.2], [5.9, 0.08, 4.5]], 1.0, 1.0, 5.0)
		return _wav(buf, 0.2))


## A twinkling run of bells: a fake caught, a robber stopped.
static func sparkle() -> AudioStreamWAV:
	return _cached("sparkle", func():
		var buf := _buf(0.9)
		var notes := [2637.0, 3136.0, 3951.0, 5274.0, 6272.0]
		for k in notes.size():
			_strike(buf, k * 0.055, notes[k], [[1.0, 1.0, 1.0], [2.0, 0.2, 2.5]], 0.45, 1.0 - k * 0.12, 0.0)
		return _wav(buf, 0.18))


## A low two-note "wah-wah": a bad call, or the assay lab finding a fake you bought.
static func wrong() -> AudioStreamWAV:
	return _cached("wrong", func():
		var buf := _buf(0.6)
		var phase := 0.0
		for n in buf.size():
			var t := n / float(Sfx.RATE)
			var hz := 233.0 if t < 0.2 else lerpf(196.0, 165.0, (t - 0.2) / 0.4)
			phase += hz / Sfx.RATE
			# two notes with a breath between them, the second sagging and fading
			var env := minf(t / 0.01, 1.0) * (1.0 - smoothstep(0.16, 0.18, t) + smoothstep(0.2, 0.22, t)) * exp(-maxf(t - 0.2, 0.0) * 4.0)
			var x := fmod(phase, 1.0)
			# a soft square: the first few odd harmonics
			var v := sin(TAU * x) + sin(TAU * x * 3.0) / 3.0 + sin(TAU * x * 5.0) / 6.0
			buf[n] += v * env
		return _wav(buf, 0.22))


## A quick rush of air: a hand over the counter, someone running for the door.
static func whoosh() -> AudioStreamWAV:
	return _cached("whoosh", func():
		var buf := _buf(0.4)
		var rng := RandomNumberGenerator.new()
		rng.seed = 31
		var y1 := 0.0
		var y2 := 0.0
		for n in buf.size():
			var t := n / float(Sfx.RATE)
			var f := t / 0.4
			var hz := lerpf(500.0, 2200.0, sin(f * PI))
			var r := 0.94
			var b1 := 2.0 * r * cos(TAU * hz / Sfx.RATE)
			var y := (1.0 - r) * rng.randf_range(-1.0, 1.0) + b1 * y1 - r * r * y2
			y2 = y1
			y1 = y
			buf[n] = y * sin(f * PI) * 6.0
		return _wav(buf, 0.12))


## A customer's made-up voice for `mood` (see MOODS) at their own pitch (about 0.75-1.35).
static func voice(mood: String, pitch: float) -> AudioStreamWAV:
	var bucket := clampi(roundi((pitch - 0.75) / 0.15), 0, 4)
	return _cached("voice_%s_%d" % [mood, bucket], func(): return _speak(MOODS.get(mood, MOODS.hmm), 0.75 + bucket * 0.15, mood == "gasp"))


## The pitch that suits customer seed `seed`, so each person keeps their voice.
static func pitch_for(seed: int) -> float:
	return 0.75 + float(posmod(seed, 97)) / 97.0 * 0.6


## Syllables through two formant resonators on a sawtooth, like a tiny cartoon mumble.
static func _speak(syllables: Array, pitch: float, breathy: bool) -> AudioStreamWAV:
	var total := 0.05
	for s in syllables:
		total += s[3] + s[4]
	var buf := _buf(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var phase := 0.0
	var at := 0.0
	var res := [0.0, 0.0, 0.0, 0.0] # two resonators, two taps each
	for s in syllables:
		var vowel: Array = VOWELS[s[2]]
		var start := int(at * Sfx.RATE)
		var count := int(s[3] * Sfx.RATE)
		for k in count:
			var f := k / float(count)
			var t := k / float(Sfx.RATE)
			var hz: float = BASE_HZ * pitch * lerpf(s[0], s[1], f) * (1.0 + 0.012 * sin(TAU * 6.0 * t))
			phase = fmod(phase + hz / Sfx.RATE, 1.0)
			var src := 2.0 * phase - 1.0
			if breathy:
				src = src * 0.4 + rng.randf_range(-1.0, 1.0) * 0.8
			var env := minf(t / 0.012, 1.0) * minf((s[3] - t) / 0.03, 1.0)
			var v := 0.0
			for r in 2:
				var rr := 0.985 - r * 0.01
				var b1 := 2.0 * rr * cos(TAU * vowel[r] / Sfx.RATE)
				var y: float = (1.0 - rr) * src + b1 * res[r * 2] - rr * rr * res[r * 2 + 1]
				res[r * 2 + 1] = res[r * 2]
				res[r * 2] = y
				v += y * (1.0 if r == 0 else 0.7)
			if start + k < buf.size():
				buf[start + k] += v * env * vowel[2]
		at += s[3] + s[4]
	# normalise, so every mood and pitch comes out about as loud
	var peak := 0.0001
	for n in buf.size():
		peak = maxf(peak, absf(buf[n]))
	for n in buf.size():
		buf[n] /= peak
	return _wav(buf, 0.3)


## A struck bell: partials [ratio, loudness, decay speed] fading over about `seconds`.
## `wobble` (Hz) shakes the loudness, like a bell still swinging on its spring.
static func _strike(buf: PackedFloat32Array, at: float, hz: float, partials: Array, seconds: float, amp: float, wobble: float) -> void:
	var start := int(at * Sfx.RATE)
	var count := buf.size() - start
	var ring := PackedFloat32Array()
	ring.resize(count)
	# each partial as a decaying phasor: rotate and shrink one step per sample, no sin() or exp()
	for p in partials:
		var w: float = TAU * hz * p[0] / Sfx.RATE
		if w >= PI:
			continue # above what the sample rate can carry
		var step_c := cos(w)
		var step_s := sin(w)
		var shrink := exp(-p[2] * 3.0 / seconds / Sfx.RATE)
		var re: float = p[1]
		var im := 0.0
		for n in count:
			ring[n] += im
			var r2 := (re * step_c - im * step_s) * shrink
			im = (re * step_s + im * step_c) * shrink
			re = r2
	var attack := int(0.002 * Sfx.RATE)
	for n in count:
		var env := amp * minf(float(n) / attack, 1.0)
		if wobble > 0.0:
			env *= 1.0 - 0.3 * (0.5 + 0.5 * sin(TAU * wobble * n / Sfx.RATE))
		buf[start + n] += ring[n] * env


## One coin tapping another: a short metallic tick with a click at the start.
static func _clink(buf: PackedFloat32Array, at: float, hz: float, amp: float) -> void:
	var start := int(at * Sfx.RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hz)
	for n in range(start, mini(buf.size(), start + int(0.15 * Sfx.RATE))):
		var t := (n - start) / float(Sfx.RATE)
		var v := sin(TAU * hz * t) * exp(-t * 40.0) + sin(TAU * hz * 2.76 * t) * 0.5 * exp(-t * 70.0) + sin(TAU * hz * 5.4 * t) * 0.25 * exp(-t * 110.0)
		if t < 0.004:
			v += rng.randf_range(-1.0, 1.0) * (1.0 - t / 0.004)
		buf[n] += v * amp


## Smoothed noise, fading out over `length` seconds: drawers, rattles.
static func _noise(buf: PackedFloat32Array, at: float, length: float, amp: float, smooth: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var start := int(at * Sfx.RATE)
	var low := 0.0
	for n in range(start, mini(buf.size(), start + int(length * Sfx.RATE))):
		var t := (n - start) / float(Sfx.RATE)
		low = lerpf(low, rng.randf_range(-1.0, 1.0), smooth)
		buf[n] += low * amp * (1.0 - t / length) * (0.6 + 0.4 * sin(TAU * 60.0 * t))


static func _buf(seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(seconds * Sfx.RATE))
	return buf


static func _wav(buf: PackedFloat32Array, gain: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	var fade := mini(buf.size(), int(0.01 * Sfx.RATE)) # no click at the very end
	for n in buf.size():
		var v := buf[n] * gain
		if n >= buf.size() - fade:
			v *= float(buf.size() - n) / fade
		data.encode_s16(n * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	return Sfx._wav(data)


static func _cached(key: String, make: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]
