extends RefCounted

const STATUS_LOADED := &"loaded"
const STATUS_NEW := &"new"
const STATUS_UNAVAILABLE := &"unavailable"
const DEFAULT_EXECUTABLE := "git"

var _command_runner: Callable
var _availability: Dictionary = {}


func _init(command_runner: Callable = Callable()) -> void:
	_command_runner = command_runner if command_runner.is_valid() else Callable(self, "_execute_git")


func check_availability() -> Dictionary:
	if not _availability.is_empty():
		return _availability.duplicate(true)

	var result := _run(["--version"])
	if result.exit_code == 0:
		_availability = {
			"available": true,
			"executable": DEFAULT_EXECUTABLE,
			"version": str(result.output).strip_edges(),
			"error": "",
		}
	else:
		var detail := str(result.output).strip_edges()
		var error := "The '%s' executable is not available in PATH." % DEFAULT_EXECUTABLE
		if not detail.is_empty():
			error += " %s" % detail
		_availability = {
			"available": false,
			"executable": DEFAULT_EXECUTABLE,
			"version": "",
			"error": error,
		}
	return _availability.duplicate(true)


func load_baseline(absolute_file_path: String) -> Dictionary:
	var file_path := absolute_file_path.simplify_path()
	var discovery := _run([
		"-C",
		file_path.get_base_dir(),
		"rev-parse",
		"--show-toplevel",
	])
	if discovery.exit_code != 0:
		return _unavailable(discovery.output)

	var repository_root: String = str(discovery.output).strip_edges().simplify_path()
	if repository_root.is_empty() or not _is_inside(file_path, repository_root):
		return _unavailable(
			"File is outside Git repository: %s" % repository_root,
			repository_root
		)

	var relative_path := file_path.substr(repository_root.length()).trim_prefix("/")
	var head := _run([
		"-C",
		repository_root,
		"rev-parse",
		"--verify",
		"HEAD^{commit}",
	])
	if head.exit_code != 0:
		return _unavailable(head.output, repository_root, relative_path)

	var object_name := "HEAD:%s" % relative_path
	var exists := _run([
		"-C",
		repository_root,
		"cat-file",
		"-e",
		object_name,
	])
	if exists.exit_code != 0:
		return _result(STATUS_NEW, "", repository_root, relative_path)

	var contents := _run([
		"-C",
		repository_root,
		"show",
		object_name,
	])
	if contents.exit_code != 0:
		return _unavailable(contents.output, repository_root, relative_path)

	return _result(
		STATUS_LOADED,
		contents.output,
		repository_root,
		relative_path
	)


func _run(arguments: Array[String]) -> Dictionary:
	var raw_result: Variant = _command_runner.call(arguments)
	if raw_result is not Dictionary:
		return {
			"exit_code": -1,
			"output": "Git command runner returned an invalid result",
		}

	var result := raw_result as Dictionary
	return {
		"exit_code": int(result.get("exit_code", -1)),
		"output": str(result.get("output", "")),
	}


func _execute_git(arguments: Array[String]) -> Dictionary:
	var output: Array = []
	var exit_code := OS.execute(DEFAULT_EXECUTABLE, arguments, output, true)
	var text := ""
	for part in output:
		text += str(part)
	return {
		"exit_code": exit_code,
		"output": text,
	}


func _is_inside(file_path: String, repository_root: String) -> bool:
	if repository_root == "/":
		return file_path.begins_with("/")
	return file_path.begins_with(repository_root.trim_suffix("/") + "/")


func _unavailable(
	error: String,
	repository_root: String = "",
	relative_path: String = ""
) -> Dictionary:
	var message := error.strip_edges()
	if message.is_empty():
		message = "Git baseline is unavailable"
	return _result(
		STATUS_UNAVAILABLE,
		"",
		repository_root,
		relative_path,
		message
	)


func _result(
	status: StringName,
	text: String,
	repository_root: String,
	relative_path: String,
	error: String = ""
) -> Dictionary:
	return {
		"status": status,
		"text": text,
		"repository_root": repository_root,
		"relative_path": relative_path,
		"error": error,
	}
