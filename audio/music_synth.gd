class_name MusicSynth
extends RefCounted
## Renders the game's music at runtime into seamless loops, so the game ships without
## audio files. Each track is a chord progression played by a few simple voices:
## electric piano, pad, bass, a music-box bell and soft drums.
## Rendering takes a second or two, so the Music autoload runs it on a thread.

const RATE := 22050
const TRACKS := ["title", "shop"]

## Chords as [bass note, [voicing]] in MIDI numbers, one per bar.
const SHOP_CHORDS := [
	[43, [58, 62, 65, 69]], [48, [58, 64, 67, 74]], [41, [57, 60, 64, 67]], [38, [53, 57, 60, 64]],
	[46, [57, 60, 62, 65]], [45, [55, 60, 64, 67]], [43, [58, 62, 65, 69]], [48, [58, 61, 64, 67]],
]
const TITLE_CHORDS := [
	[41, [57, 60, 64, 67]], [45, [55, 60, 64, 67]], [46, [57, 62, 65, 69]], [48, [55, 60, 65, 67]],
	[38, [57, 60, 62, 65]], [46, [57, 62, 65, 69]], [43, [58, 62, 65, 69]], [48, [55, 60, 64, 70]],
]
## The title theme, one bar per row: [beat, MIDI note, beats].
const TITLE_MELODY := [
	[[0, 72, 1.5], [1.5, 69, 0.5], [2, 67, 1], [3, 69, 1]],
	[[0, 72, 2], [2, 76, 1], [3, 74, 1]],
	[[0, 74, 1.5], [1.5, 72, 0.5], [2, 69, 2]],
	[[0, 67, 1], [1, 69, 1], [2, 70, 1], [3, 72, 1]],
	[[0, 77, 2], [2, 76, 1], [3, 74, 1]],
	[[0, 74, 1], [1, 72, 1], [2, 69, 2]],
	[[0, 70, 1.5], [1.5, 69, 0.5], [2, 67, 2]],
	[[0, 72, 3.5]],
]
const PENTATONIC := [65, 67, 69, 72, 74, 77, 79, 81] # F major pentatonic

var _buf := PackedFloat32Array()
var _frames := 0
var _rng := RandomNumberGenerator.new()


## A looping stream for `track` ("title" or "shop"). `bars` shortens it for tests.
static func render(track: String, bars := 0) -> AudioStreamWAV:
	var s := MusicSynth.new()
	if track == "title":
		s._title(bars if bars > 0 else 8)
	else:
		s._shop(bars if bars > 0 else 16)
	return s._finish()


static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


# ---------------------------------------------------------------- arrangements

## The shop floor: a slow jazzy loop with brushed drums. The second half adds a
## pentatonic melody so it does not repeat too soon.
func _shop(bars: int) -> void:
	var beat := 60.0 / 88.0
	_start(bars * 4 * beat)
	_rng.seed = 1984
	for bar in bars:
		var chord: Array = SHOP_CHORDS[bar % SHOP_CHORDS.size()]
		var next: Array = SHOP_CHORDS[(bar + 1) % SHOP_CHORDS.size()]
		var t0 := bar * 4 * beat
		var swing := beat * 0.62 # the "and" lands late
		for n in chord[1]:
			_epiano(t0, beat * 1.6, n, 0.075)
			_epiano(t0 + beat + swing, beat * 0.7, n, 0.05)
		_bass(t0, beat * 1.8, chord[0], 0.3)
		_bass(t0 + 2 * beat, beat * 1.2, chord[0] + 7, 0.24)
		_bass(t0 + 3 * beat + swing, beat * 0.4, next[0] - 1 if bar % 2 == 0 else next[0] + 2, 0.18)
		for b in 4:
			_kick(t0 + b * beat, 0.22 if b % 2 == 0 else 0.0)
			_hat(t0 + b * beat, 0.05)
			_hat(t0 + b * beat + swing, 0.035)
			if b % 2 == 1:
				_rim(t0 + b * beat, 0.07)
		if bar >= bars / 2:
			var at := 0.0
			while at < 4.0:
				if _rng.randf() < 0.55:
					var note: int = PENTATONIC[_rng.randi_range(0, PENTATONIC.size() - 1)]
					_bell(t0 + at * beat + (swing - beat * 0.5 if fmod(at, 1.0) > 0.0 else 0.0), beat * 1.2, note, 0.09)
				at += 0.5 if _rng.randf() < 0.6 else 1.0
	_crackle(0.012)


## The title screen: warm pads, a music-box theme and a soft shaker.
func _title(bars: int) -> void:
	var beat := 60.0 / 72.0
	_start(bars * 4 * beat)
	_rng.seed = 7
	for bar in bars:
		var chord: Array = TITLE_CHORDS[bar % TITLE_CHORDS.size()]
		var t0 := bar * 4 * beat
		for n in chord[1]:
			_pad(t0, beat * 4.2, n, 0.05)
		_bass(t0, beat * 3.5, chord[0], 0.26)
		_bass(t0 + 3 * beat, beat, chord[0] + 12, 0.1)
		for k in 8:
			_bell(t0 + k * beat * 0.5, beat, chord[1][[0, 1, 2, 3, 2, 1, 2, 3][k]] + 12, 0.025)
			_hat(t0 + k * beat * 0.5, 0.02 if k % 2 == 0 else 0.012)
		for m in TITLE_MELODY[bar % TITLE_MELODY.size()]:
			_bell(t0 + m[0] * beat, m[2] * beat, m[1], 0.14)


# ---------------------------------------------------------------- voices

func _epiano(t: float, dur: float, note: float, amp: float) -> void:
	_voice(t, dur, midi_hz(note), amp, [[1.0, 1.0, 1.4], [2.0, 0.28, 5.0], [3.0, 0.07, 8.0]], 0.004, 0.08, 4.5)


func _pad(t: float, dur: float, note: float, amp: float) -> void:
	var hz := midi_hz(note)
	_voice(t, dur, hz * 0.998, amp, [[1.0, 1.0, 0.1], [2.0, 0.15, 0.3]], 0.7, 0.9)
	_voice(t, dur, hz * 1.002, amp, [[1.0, 1.0, 0.1]], 0.7, 0.9)


func _bass(t: float, dur: float, note: float, amp: float) -> void:
	_voice(t, dur, midi_hz(note), amp, [[1.0, 1.0, 1.8], [2.0, 0.25, 4.0]], 0.008, 0.05)


## A music-box tine: bright partials that fade fast, like a small struck bar.
func _bell(t: float, dur: float, note: float, amp: float) -> void:
	_voice(t, dur + 0.6, midi_hz(note), amp, [[1.0, 1.0, 2.2], [2.0, 0.35, 4.0], [3.01, 0.12, 6.0], [4.17, 0.06, 9.0]], 0.002, 0.2)


func _kick(t: float, amp: float) -> void:
	if amp <= 0.0:
		return
	var phase := 0.0
	for n in int(0.25 * RATE):
		var lt := n / float(RATE)
		phase += TAU * lerpf(110.0, 42.0, minf(lt / 0.08, 1.0)) / RATE
		_add(t + lt, sin(phase) * amp * exp(-lt * 14.0))


func _hat(t: float, amp: float) -> void:
	var prev := 0.0
	for n in int(0.06 * RATE):
		var lt := n / float(RATE)
		var x := _rng.randf_range(-1.0, 1.0)
		_add(t + lt, (x - prev) * 0.5 * amp * exp(-lt * 70.0))
		prev = x


func _rim(t: float, amp: float) -> void:
	for n in int(0.05 * RATE):
		var lt := n / float(RATE)
		_add(t + lt, (_rng.randf_range(-1.0, 1.0) * 0.6 + sin(TAU * 1750.0 * lt) * 0.4) * amp * exp(-lt * 80.0))


## Dust on the record.
func _crackle(amp: float) -> void:
	for n in int(_frames / float(RATE) * 9.0):
		var at := _rng.randi_range(0, _frames - 1)
		_buf[at] += _rng.randf_range(-1.0, 1.0) * amp * 4.0
		_buf[(at + 1) % _frames] -= _rng.randf_range(0.0, 1.0) * amp * 2.0


## Additive voice. `partials` are [ratio, gain, decay per second]. The note holds for
## `dur` then fades over `release`; `tremolo` (Hz) adds a gentle wobble.
func _voice(t: float, dur: float, hz: float, amp: float, partials: Array, attack: float, release: float, tremolo := 0.0) -> void:
	var count := int((dur + release) * RATE)
	var start := int(t * RATE)
	var env := PackedFloat32Array()
	env.resize(count)
	for n in count:
		var lt := n / float(RATE)
		var e := minf(lt / attack, 1.0) * amp
		if lt > dur:
			e *= 1.0 - (lt - dur) / release
		if tremolo > 0.0:
			e *= 1.0 - 0.12 * (0.5 + 0.5 * sin(TAU * tremolo * lt))
		env[n] = e
	# each partial is a rotating phasor with a multiplicative decay: no sin() or exp() per sample
	for p in partials:
		var w: float = TAU * hz * p[0] / RATE
		if w >= PI:
			continue # above the Nyquist limit
		var cw := cos(w)
		var sw := sin(w)
		var c := 1.0
		var s := 0.0
		var g: float = p[1]
		var d := exp(-float(p[2]) / RATE)
		for n in count:
			var ns := s * cw + c * sw
			c = c * cw - s * sw
			s = ns
			g *= d
			var i := (start + n) % _frames
			_buf[i] += s * g * env[n]
			if g < 0.0005:
				break


# ---------------------------------------------------------------- buffer

func _start(seconds: float) -> void:
	_frames = int(seconds * RATE)
	_buf.resize(_frames)
	_buf.fill(0.0)


## Notes that run past the end wrap to the start, so the loop is seamless.
func _add(t: float, v: float) -> void:
	var i := int(t * RATE) % _frames
	_buf[i] += v


## Warms the mix with a gentle low-pass and soft clipping, then packs it as 16-bit.
func _finish() -> AudioStreamWAV:
	var lp := 0.0
	var k := 0.45
	for round in 2: # the second pass starts from the end of the first, so the loop joins cleanly
		for n in _frames:
			lp += (_buf[n] - lp) * k
			if round == 1:
				_buf[n] = lp
	var peak := 0.001
	for v in _buf:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak
	var data := PackedByteArray()
	data.resize(_frames * 2)
	for n in _frames:
		var x := _buf[n] * gain
		x = x / (1.0 + absf(x) * 0.35) * 1.35 # soft knee, peaks land just under full scale
		data.encode_s16(n * 2, int(clampf(x * 0.75, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = _frames
	return w
