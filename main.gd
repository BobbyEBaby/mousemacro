extends MarginContainer

enum State { IDLE, COUNTDOWN, RECORDING, PLAYING }

@onready var record_btn: Button = %RecordBtn
@onready var play_btn: Button = %PlayBtn
@onready var status_label: Label = %StatusLabel
@onready var events_label: Label = %EventsLabel
@onready var countdown_label: Label = %CountdownLabel
@onready var loop_check: CheckBox = %LoopCheck
@onready var loop_count_check: CheckBox = %LoopCountCheck
@onready var loop_count_spin: SpinBox = %LoopCountSpin

var state: State = State.IDLE
var process_pid: int = -1
var recording_file: String
var scripts_dir: String
var countdown_timer: float = 0.0
var countdown_value: int = 3


func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_title("Mouse Macro Recorder")

	var project_dir := ProjectSettings.globalize_path("res://")
	recording_file = project_dir.path_join("recording.csv")
	scripts_dir = project_dir.path_join("scripts")

	record_btn.pressed.connect(_on_record_pressed)
	play_btn.pressed.connect(_on_play_pressed)
	countdown_label.visible = false


func _on_record_pressed() -> void:
	if state != State.IDLE:
		return
	state = State.COUNTDOWN
	countdown_value = 3
	countdown_timer = 1.0
	countdown_label.visible = true
	countdown_label.text = str(countdown_value)
	status_label.text = "Get ready..."
	record_btn.disabled = true
	play_btn.disabled = true


func _on_play_pressed() -> void:
	if state != State.IDLE:
		return
	if not FileAccess.file_exists(recording_file):
		status_label.text = "No recording found!"
		return
	_start_playback()


func _start_recording() -> void:
	state = State.RECORDING
	countdown_label.visible = false
	status_label.text = "RECORDING  (press E to stop)"
	var script_path := scripts_dir.path_join("record.ps1")
	process_pid = OS.create_process("powershell.exe", [
		"-ExecutionPolicy", "Bypass",
		"-File", script_path,
		"-OutputFile", recording_file,
	])
	if process_pid == -1:
		status_label.text = "ERROR: Could not start recorder"
		_reset_to_idle()


func _start_playback() -> void:
	state = State.PLAYING
	var looping := loop_check.button_pressed
	var limited := loop_count_check.button_pressed
	var count := int(loop_count_spin.value)
	if looping and limited:
		status_label.text = "LOOPING x%d  (press Esc to stop)" % count
	elif looping:
		status_label.text = "LOOPING  (press Esc to stop)"
	else:
		status_label.text = "PLAYING  (press Esc to stop)"
	record_btn.disabled = true
	play_btn.disabled = true
	loop_check.disabled = true
	loop_count_check.disabled = true
	loop_count_spin.editable = false
	var script_path := scripts_dir.path_join("playback.ps1")
	var args := [
		"-ExecutionPolicy", "Bypass",
		"-File", script_path,
		"-InputFile", recording_file,
	]
	if looping:
		args.append("-Loop")
		if limited:
			args.append("-LoopCount")
			args.append(str(count))
	process_pid = OS.create_process("powershell.exe", args)
	if process_pid == -1:
		status_label.text = "ERROR: Could not start playback"
		_reset_to_idle()


func _process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			countdown_timer -= delta
			if countdown_timer <= 0.0:
				countdown_value -= 1
				if countdown_value <= 0:
					_start_recording()
				else:
					countdown_timer = 1.0
					countdown_label.text = str(countdown_value)
		State.RECORDING:
			if process_pid > 0 and not OS.is_process_running(process_pid):
				_finish_recording()
		State.PLAYING:
			if process_pid > 0 and not OS.is_process_running(process_pid):
				_finish_playback()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E and state == State.RECORDING:
			_kill_process()
			_finish_recording()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and state == State.PLAYING:
			_kill_process()
			_finish_playback()
			get_viewport().set_input_as_handled()


func _kill_process() -> void:
	if process_pid > 0 and OS.is_process_running(process_pid):
		OS.kill(process_pid)
	process_pid = -1


func _finish_recording() -> void:
	process_pid = -1
	var count := _count_events()
	events_label.text = "Events recorded: %d" % count
	status_label.text = "Recording saved!"
	_reset_to_idle()


func _finish_playback() -> void:
	process_pid = -1
	status_label.text = "Playback finished"
	_reset_to_idle()


func _reset_to_idle() -> void:
	state = State.IDLE
	record_btn.disabled = false
	play_btn.disabled = false
	loop_check.disabled = false
	loop_count_check.disabled = false
	loop_count_spin.editable = true
	countdown_label.visible = false


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


func _exit_tree() -> void:
	_kill_process()
