class_name Sfx
extends RefCounted
## Sound effects synthesised at runtime, so the game ships without audio files.

const RATE := 22050

static var _cache := {}


## A struck coin: a few inharmonic partials decaying over `seconds`.
## Genuine silver and gold ring clean and long; fakes clunk and die fast.
static func coin_ring(hz: float, seconds: float, clean: bool) -> AudioStreamWAV:
	var partials := [[1.0, 1.0], [2.76, 0.45], [5.40, 0.22], [8.93, 0.1]] if clean else [[1.0, 1.0], [1.58, 0.7], [2.31, 0.5], [3.9, 0.35]]
	var total := seconds + 0.08
	var data := PackedByteArray()
	data.resize(int(total * RATE) * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 3
	for n in int(total * RATE):
		var t := n / float(RATE)
		var env := minf(t / 0.003, 1.0) * exp(-t * 5.0 / seconds)
		var v := 0.0
		for p in partials:
			var decay := exp(-t * p[0] * (1.5 if clean else 6.0) / seconds)
			v += sin(TAU * hz * p[0] * t) * p[1] * decay
		if t < 0.01:
			v += noise.randf_range(-1.0, 1.0) * (1.0 - t / 0.01) * 0.6 # the tap
		data.encode_s16(n * 2, int(clampf(v * env * 0.3, -1.0, 1.0) * 32767.0))
	return _wav(data)


static func scale_beep() -> AudioStreamWAV:
	return _cached("beep", func(): return _tone([[2400.0, 0.0, 0.07]], 0.25))


static func register_chime() -> AudioStreamWAV:
	return _cached("chime", func(): return _tone([[1568.0, 0.0, 0.5], [2093.0, 0.09, 0.6]], 0.22))


static func door_bell() -> AudioStreamWAV:
	return _cached("bell", func(): return _tone([[2637.0, 0.0, 0.6], [1975.0, 0.12, 0.7]], 0.15))


static func click() -> AudioStreamWAV:
	return _cached("click", func(): return _tone([[900.0, 0.0, 0.03]], 0.25))


static func magnet_snap() -> AudioStreamWAV:
	return _cached("snap", func(): return _tone([[320.0, 0.0, 0.06], [180.0, 0.0, 0.05]], 0.35))


## Plays `stream` once on a throwaway player under `owner`.
static func play(owner: Node, stream: AudioStream, volume_db := 0.0) -> void:
	if stream == null or not owner.is_inside_tree():
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	owner.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Sine notes [hz, start s, length s] with a quick attack and exponential decay.
static func _tone(notes: Array, gain: float) -> AudioStreamWAV:
	var total := 0.0
	for note in notes:
		total = maxf(total, note[1] + note[2])
	var count := int(total * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for n in count:
		var t := n / float(RATE)
		var v := 0.0
		for note in notes:
			var lt: float = t - note[1]
			if lt >= 0.0 and lt < note[2]:
				v += sin(TAU * note[0] * lt) * minf(lt / 0.002, 1.0) * exp(-lt * 6.0 / note[2])
		data.encode_s16(n * 2, int(clampf(v * gain, -1.0, 1.0) * 32767.0))
	return _wav(data)


static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


static func _cached(key: String, make: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


## A safe door swinging shut and its bolts throwing.
static func safe_clunk() -> AudioStreamWAV:
	return _cached("clunk", func(): return _tone([[110.0, 0.0, 0.18], [220.0, 0.0, 0.08], [1400.0, 0.14, 0.04], [1250.0, 0.2, 0.04]], 0.45))


## The last seconds of the lock-up clock.
static func tick() -> AudioStreamWAV:
	return _cached("tick", func(): return _tone([[1800.0, 0.0, 0.02]], 0.2))


## A burglar alarm: two alternating tones.
static func alarm() -> AudioStreamWAV:
	return _cached("alarm", func():
		var notes := []
		for k in 6:
			notes.append([960.0 if k % 2 == 0 else 720.0, k * 0.22, 0.22])
		return _tone(notes, 0.25))
