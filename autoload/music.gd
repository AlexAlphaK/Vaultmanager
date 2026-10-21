extends Node
## Background music on the Music bus. Tracks are rendered by MusicSynth on a worker
## thread the first time they are needed, then cached as raw PCM in user:// so later
## launches start instantly. play() crossfades between tracks.

const FADE_SECONDS := 1.5
const CACHE_VERSION := 1 # bump when MusicSynth changes, so old renders are redone
const CACHE_DIR := "user://music_cache"

var current := ""
var _streams := {}
var _rendering := {} # track -> Thread
var _player: AudioStreamPlayer
var _fading: AudioStreamPlayer
var _tweens := {} # player -> its running fade


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps playing in the pause menu
	_player = _new_player()
	_fading = _new_player()


## Starts `track` ("title" or "shop"), fading out whatever was playing.
## If the track is still rendering, it starts as soon as it is ready.
func play(track: String) -> void:
	if track == current:
		return
	current = track
	if _streams.has(track):
		_switch_to(_streams[track])
	else:
		_load_or_render(track)


func stop() -> void:
	current = ""
	_switch_to(null)


func is_ready(track: String) -> bool:
	return _streams.has(track)


func _exit_tree() -> void:
	for thread in _rendering.values():
		thread.wait_to_finish()


func _new_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	add_child(p)
	return p


func _switch_to(stream: AudioStream) -> void:
	# the old track fades on the spare player while the new one fades in
	var old := _player
	_player = _fading
	_fading = old
	if _fading.playing:
		_fade(_fading, -40.0).finished.connect(_fading.stop)
	if stream == null:
		_player.stop()
		return
	_player.stream = stream
	_player.volume_db = -40.0
	_player.play()
	_fade(_player, 0.0)


func _fade(p: AudioStreamPlayer, to_db: float) -> Tween:
	if _tweens.has(p) and _tweens[p].is_valid():
		_tweens[p].kill() # a player being reused must not be stopped by its old fade-out
	var t := create_tween()
	t.tween_property(p, "volume_db", to_db, FADE_SECONDS)
	_tweens[p] = t
	return t


func _load_or_render(track: String) -> void:
	var cached := _read_cache(track)
	if cached:
		_on_rendered(track, cached)
		return
	if _rendering.has(track):
		return
	if DisplayServer.get_name() == "headless":
		return # no speakers in tests and servers; MusicSynth is tested on its own
	var thread := Thread.new()
	_rendering[track] = thread
	thread.start(func():
		var stream := MusicSynth.render(track)
		_finish_render.call_deferred(track, stream))


func _finish_render(track: String, stream: AudioStreamWAV) -> void:
	if _rendering.has(track):
		_rendering[track].wait_to_finish()
		_rendering.erase(track)
	_write_cache(track, stream)
	_on_rendered(track, stream)


func _on_rendered(track: String, stream: AudioStreamWAV) -> void:
	_streams[track] = stream
	if track == current:
		_switch_to(stream)
	# get the next track ready in the background, one at a time
	for other in MusicSynth.TRACKS:
		if not _streams.has(other) and not _rendering.has(other):
			_load_or_render(other)
			break


func _cache_path(track: String) -> String:
	return "%s/%s_v%d.pcm" % [CACHE_DIR, track, CACHE_VERSION]


func _read_cache(track: String) -> AudioStreamWAV:
	var path := _cache_path(track)
	if not FileAccess.file_exists(path):
		return null
	var data := FileAccess.get_file_as_bytes(path)
	if data.size() < MusicSynth.RATE * 2:
		return null
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MusicSynth.RATE
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = data.size() / 2
	return w


func _write_cache(track: String, stream: AudioStreamWAV) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open(_cache_path(track), FileAccess.WRITE)
	if f:
		f.store_buffer(stream.data)
