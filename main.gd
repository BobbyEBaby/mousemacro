extends MarginContainer

enum State { IDLE, COUNTDOWN, RECORDING, PLAYING }
enum Capture { NONE, HOTKEY, STOP_RECORD, STOP_PLAY }

const CONFIG_PATH := "user://settings.cfg"
const COL_DIM := Color("9a8d7a")
const COL_GOLD := Color("e0a458")
const COL_EMBER := Color("d4593c")
const BTC_ADDR := "3JiaPsUmdf2pqXFrDavzQ4fRpkJSVg5BbH"
const DOGE_ADDR := "DUJPtjifrXtiykXcN389Gw36g5T9ZpWvgZ"
const ZEC_ADDR := "t1fsoScTMB1ERNjVrsS1CpvrVYLVzSECHSc"

@onready var record_btn: Button = %RecordBtn
@onready var play_btn: Button = %PlayBtn
@onready var hotkey_btn: Button = %HotkeyBtn
@onready var status_label: Label = %StatusLabel
@onready var events_label: Label = %EventsLabel
@onready var countdown_label: Label = %CountdownLabel
@onready var loop_check: CheckBox = %LoopCheck
@onready var loop_count_check: CheckBox = %LoopCountCheck
@onready var loop_count_spin: SpinBox = %LoopCountSpin
@onready var stop_record_btn: Button = %StopRecordBtn
@onready var stop_play_btn: Button = %StopPlayBtn
@onready var btc_copy_btn: Button = %BtcCopyBtn
@onready var doge_copy_btn: Button = %DogeCopyBtn
@onready var zec_copy_btn: Button = %ZecCopyBtn

var state: State = State.IDLE
var capture: Capture = Capture.NONE
var process_pid: int = -1
var watcher_pid: int = -1
var recording_file: String
var progress_file: String
var scripts_dir: String
var countdown_timer: float = 0.0
var countdown_value: int = 3
var countdown_is_play: bool = false
var loop_total: int = 0
var last_loop_shown: int = 0

var copied_coin: String = ""
var hotkey_vk: int = -1
var hotkey_name: String = ""
var stop_record_vk: int = 0x20
var stop_record_name: String = "Space"
var stop_play_vk: int = 0x1B
var stop_play_name: String = "Escape"


func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_title("Mouse and Keyboard Macro Recorder")

	# In the editor, work out of the project dir. In an exported exe, res://
	# is read-only (packed), so data goes to user:// and the PowerShell
	# scripts are extracted there where powershell.exe can read them.
	var base_dir: String
	if OS.has_feature("editor"):
		base_dir = ProjectSettings.globalize_path("res://")
		scripts_dir = base_dir.path_join("scripts")
	else:
		base_dir = ProjectSettings.globalize_path("user://")
		scripts_dir = base_dir.path_join("scripts")
		_extract_scripts()
	recording_file = base_dir.path_join("recording.csv")
	progress_file = base_dir.path_join("playback_progress.txt")

	record_btn.pressed.connect(_on_record_pressed)
	play_btn.pressed.connect(_on_play_pressed)
	hotkey_btn.pressed.connect(_on_capture_pressed.bind(Capture.HOTKEY))
	stop_record_btn.pressed.connect(_on_capture_pressed.bind(Capture.STOP_RECORD))
	stop_play_btn.pressed.connect(_on_capture_pressed.bind(Capture.STOP_PLAY))
	btc_copy_btn.pressed.connect(_on_copy_pressed.bind(BTC_ADDR, "BTC"))
	doge_copy_btn.pressed.connect(_on_copy_pressed.bind(DOGE_ADDR, "DOGE"))
	zec_copy_btn.pressed.connect(_on_copy_pressed.bind(ZEC_ADDR, "ZEC"))
	countdown_label.visible = false

	_load_config()
	_refresh_key_buttons()
	_update_watcher()
	_set_status("Ready", COL_DIM)


func _set_status(text: String, color: Color = COL_DIM) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)
	copied_coin = ""


func _on_record_pressed() -> void:
	if state != State.IDLE:
		return
	capture = Capture.NONE
	_begin_countdown(false)


func _on_play_pressed() -> void:
	if state != State.IDLE:
		return
	if not FileAccess.file_exists(recording_file):
		_set_status("No recording found!", COL_EMBER)
		return
	capture = Capture.NONE
	_begin_countdown(true)


func _begin_countdown(for_play: bool) -> void:
	_kill_watcher()
	countdown_is_play = for_play
	state = State.COUNTDOWN
	countdown_value = 3
	countdown_timer = 1.0
	countdown_label.visible = true
	countdown_label.text = str(countdown_value)
	_set_status("Get ready...", COL_GOLD)
	_set_controls_enabled(false)


func _on_capture_pressed(target: Capture) -> void:
	if state != State.IDLE:
		return
	if capture == target:
		capture = Capture.NONE
		_set_status("Ready", COL_DIM)
		return
	capture = target
	match target:
		Capture.HOTKEY:
			_set_status("Press a key to use as the run hotkey...", COL_GOLD)
		Capture.STOP_RECORD:
			_set_status("Press a key to stop recording with...", COL_GOLD)
		Capture.STOP_PLAY:
			_set_status("Press a key to stop playback with...", COL_GOLD)


func _on_copy_pressed(address: String, coin: String) -> void:
	DisplayServer.clipboard_set(address)
	if state != State.IDLE:
		return
	if copied_coin == coin:
		_set_status("Ready", COL_DIM)
	else:
		_set_status("%s address copied — thanks for buying me a cigar!" % coin, COL_GOLD)
		copied_coin = coin


func _start_recording() -> void:
	state = State.RECORDING
	countdown_label.visible = false
	_set_status("RECORDING  (press %s to stop)" % stop_record_name, COL_EMBER)
	var script_path := scripts_dir.path_join("record.ps1")
	process_pid = OS.create_process("powershell.exe", [
		"-ExecutionPolicy", "Bypass",
		"-WindowStyle", "Hidden",
		"-File", script_path,
		"-OutputFile", recording_file,
		"-StopVK", str(stop_record_vk),
	])
	if process_pid == -1:
		_set_status("ERROR: Could not start recorder", COL_EMBER)
		_reset_to_idle()


func _start_playback() -> void:
	_kill_watcher()
	state = State.PLAYING
	countdown_label.visible = false
	var looping := loop_check.button_pressed
	var limited := loop_count_check.button_pressed
	var count := int(loop_count_spin.value)
	loop_total = count if (looping and limited) else 0
	last_loop_shown = 0
	if DirAccess.dir_exists_absolute(progress_file.get_base_dir()):
		DirAccess.remove_absolute(progress_file)
	if looping and limited:
		_set_status("LOOPING  loop 1 of %d, %d remaining  (press %s to stop)" % [count, count - 1, stop_play_name], COL_GOLD)
	elif looping:
		_set_status("LOOPING  (press %s to stop)" % stop_play_name, COL_GOLD)
	else:
		_set_status("PLAYING  (press %s to stop)" % stop_play_name, COL_GOLD)
	_set_controls_enabled(false)
	var script_path := scripts_dir.path_join("playback.ps1")
	var args := [
		"-ExecutionPolicy", "Bypass",
		"-WindowStyle", "Hidden",
		"-File", script_path,
		"-InputFile", recording_file,
		"-StopVK", str(stop_play_vk),
		"-ProgressFile", progress_file,
	]
	if looping:
		args.append("-Loop")
		if limited:
			args.append("-LoopCount")
			args.append(str(count))
	process_pid = OS.create_process("powershell.exe", args)
	if process_pid == -1:
		_set_status("ERROR: Could not start playback", COL_EMBER)
		_reset_to_idle()


func _process(delta: float) -> void:
	match state:
		State.IDLE:
			if watcher_pid > 0 and not OS.is_process_running(watcher_pid):
				watcher_pid = -1
				if FileAccess.file_exists(recording_file):
					_start_playback()
				else:
					_set_status("Hotkey pressed, but no recording found!", COL_EMBER)
					_update_watcher()
		State.COUNTDOWN:
			countdown_timer -= delta
			if countdown_timer <= 0.0:
				countdown_value -= 1
				if countdown_value <= 0:
					if countdown_is_play:
						_start_playback()
					else:
						_start_recording()
				else:
					countdown_timer = 1.0
					countdown_label.text = str(countdown_value)
		State.RECORDING:
			if process_pid > 0 and not OS.is_process_running(process_pid):
				_finish_recording()
		State.PLAYING:
			_update_loop_status()
			if process_pid > 0 and not OS.is_process_running(process_pid):
				_finish_playback()


func _update_loop_status() -> void:
	var current := _read_progress()
	if current <= 0 or current == last_loop_shown:
		return
	last_loop_shown = current
	if loop_total > 0:
		_set_status("LOOPING  loop %d of %d, %d remaining  (press %s to stop)" % [
			current, loop_total, loop_total - current, stop_play_name], COL_GOLD)
	elif loop_check.button_pressed:
		_set_status("LOOPING  loop %d  (press %s to stop)" % [current, stop_play_name], COL_GOLD)


func _read_progress() -> int:
	if not FileAccess.file_exists(progress_file):
		return 0
	var f := FileAccess.open(progress_file, FileAccess.READ)
	if f == null:
		return 0
	var text := f.get_as_text().strip_edges()
	f.close()
	return int(text)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if capture == Capture.NONE:
		return
	var vk := _key_to_vk(event.keycode)
	if vk == -1:
		_set_status("Unsupported key — try letters, digits, F-keys, arrows...", COL_EMBER)
		get_viewport().set_input_as_handled()
		return
	var key_name := OS.get_keycode_string(event.keycode)
	match capture:
		Capture.HOTKEY:
			if vk == stop_record_vk or vk == stop_play_vk:
				_set_status("That key is already a stop key — pick another", COL_EMBER)
				get_viewport().set_input_as_handled()
				return
			hotkey_vk = vk
			hotkey_name = key_name
			_set_status("Run hotkey set to %s" % key_name, COL_GOLD)
			_update_watcher()
		Capture.STOP_RECORD:
			if vk == hotkey_vk or vk == stop_play_vk:
				_set_status("That key is already in use — pick another", COL_EMBER)
				get_viewport().set_input_as_handled()
				return
			stop_record_vk = vk
			stop_record_name = key_name
			_set_status("Stop-recording key set to %s" % key_name, COL_GOLD)
		Capture.STOP_PLAY:
			if vk == hotkey_vk or vk == stop_record_vk:
				_set_status("That key is already in use — pick another", COL_EMBER)
				get_viewport().set_input_as_handled()
				return
			stop_play_vk = vk
			stop_play_name = key_name
			_set_status("Stop-playback key set to %s" % key_name, COL_GOLD)
	capture = Capture.NONE
	_refresh_key_buttons()
	_save_config()
	get_viewport().set_input_as_handled()


# Map a Godot keycode to a Windows virtual-key code (used by the PS scripts).
func _key_to_vk(keycode: int) -> int:
	if keycode >= KEY_A and keycode <= KEY_Z:
		return keycode
	if keycode >= KEY_0 and keycode <= KEY_9:
		return keycode
	if keycode >= KEY_F1 and keycode <= KEY_F12:
		return 0x70 + (keycode - KEY_F1)
	match keycode:
		KEY_SPACE: return 0x20
		KEY_ESCAPE: return 0x1B
		KEY_TAB: return 0x09
		KEY_ENTER: return 0x0D
		KEY_BACKSPACE: return 0x08
		KEY_INSERT: return 0x2D
		KEY_DELETE: return 0x2E
		KEY_HOME: return 0x24
		KEY_END: return 0x23
		KEY_PAGEUP: return 0x21
		KEY_PAGEDOWN: return 0x22
		KEY_LEFT: return 0x25
		KEY_UP: return 0x26
		KEY_RIGHT: return 0x27
		KEY_DOWN: return 0x28
		KEY_QUOTELEFT: return 0xC0
	return -1


func _refresh_key_buttons() -> void:
	stop_record_btn.text = stop_record_name
	stop_play_btn.text = stop_play_name
	if hotkey_vk > 0:
		hotkey_btn.text = hotkey_name
	else:
		hotkey_btn.text = "None"


# Keeps a background watcher running while idle; it exits when the hotkey
# is pressed anywhere in Windows, which _process picks up to start playback.
func _update_watcher() -> void:
	_kill_watcher()
	if hotkey_vk > 0 and state == State.IDLE:
		var script_path := scripts_dir.path_join("hotkey_wait.ps1")
		watcher_pid = OS.create_process("powershell.exe", [
			"-ExecutionPolicy", "Bypass",
			"-WindowStyle", "Hidden",
			"-File", script_path,
			"-VK", str(hotkey_vk),
		])


func _kill_watcher() -> void:
	if watcher_pid > 0 and OS.is_process_running(watcher_pid):
		OS.kill(watcher_pid)
	watcher_pid = -1


func _kill_process() -> void:
	if process_pid > 0 and OS.is_process_running(process_pid):
		OS.kill(process_pid)
	process_pid = -1


func _finish_recording() -> void:
	process_pid = -1
	var count := _count_events()
	events_label.text = "Events recorded: %d" % count
	_set_status("Recording saved!", COL_GOLD)
	_reset_to_idle()


func _finish_playback() -> void:
	process_pid = -1
	_set_status("Playback finished", COL_DIM)
	_reset_to_idle()


func _reset_to_idle() -> void:
	state = State.IDLE
	_set_controls_enabled(true)
	countdown_label.visible = false
	_update_watcher()


func _set_controls_enabled(enabled: bool) -> void:
	record_btn.disabled = not enabled
	play_btn.disabled = not enabled
	hotkey_btn.disabled = not enabled
	stop_record_btn.disabled = not enabled
	stop_play_btn.disabled = not enabled
	loop_check.disabled = not enabled
	loop_count_check.disabled = not enabled
	loop_count_spin.editable = enabled


func _count_events() -> int:
	if not FileAccess.file_exists(recording_file):
		return 0
	var f := FileAccess.open(recording_file, FileAccess.READ)
	if f == null:
		return 0
	var count := 0
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line != "":
			count += 1
	f.close()
	return count


func _extract_scripts() -> void:
	DirAccess.make_dir_recursive_absolute(scripts_dir)
	for script_name in ["record.ps1", "playback.ps1", "hotkey_wait.ps1"]:
		var src := FileAccess.open("res://scripts/" + script_name, FileAccess.READ)
		if src == null:
			_set_status("ERROR: missing bundled script %s" % script_name, COL_EMBER)
			continue
		var dst := FileAccess.open(scripts_dir.path_join(script_name), FileAccess.WRITE)
		if dst != null:
			dst.store_buffer(src.get_buffer(src.get_length()))
			dst.close()
		src.close()


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("keys", "hotkey_vk", hotkey_vk)
	cfg.set_value("keys", "hotkey_name", hotkey_name)
	cfg.set_value("keys", "stop_record_vk", stop_record_vk)
	cfg.set_value("keys", "stop_record_name", stop_record_name)
	cfg.set_value("keys", "stop_play_vk", stop_play_vk)
	cfg.set_value("keys", "stop_play_name", stop_play_name)
	cfg.save(CONFIG_PATH)


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	hotkey_vk = cfg.get_value("keys", "hotkey_vk", -1)
	hotkey_name = cfg.get_value("keys", "hotkey_name", "")
	stop_record_vk = cfg.get_value("keys", "stop_record_vk", 0x20)
	stop_record_name = cfg.get_value("keys", "stop_record_name", "Space")
	stop_play_vk = cfg.get_value("keys", "stop_play_vk", 0x1B)
	stop_play_name = cfg.get_value("keys", "stop_play_name", "Escape")


func _exit_tree() -> void:
	_kill_process()
	_kill_watcher()
