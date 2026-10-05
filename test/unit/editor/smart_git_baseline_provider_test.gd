extends GdUnitTestSuite

const GitBaselineProvider := preload(
	"res://addons/smart-editor-plugin/features/git_changes/git_baseline_provider.gd"
)


class FakeGitRunner extends RefCounted:
	var calls: Array[Array] = []
	var responses: Array[Dictionary] = []

	func _init(new_responses: Array[Dictionary]) -> void:
		responses = new_responses.duplicate(true)

	func execute(arguments: Array[String]) -> Dictionary:
		calls.append(arguments.duplicate())
		if responses.is_empty():
			return {
				"exit_code": -1,
				"output": "Unexpected Git command",
			}
		return responses.pop_front()


func test_availability_check_uses_default_git_executable_and_is_cached() -> void:
	var git := FakeGitRunner.new([
		_response(0, "git version 2.50.1\n"),
	])
	var provider := GitBaselineProvider.new(git.execute)

	var first: Dictionary = provider.check_availability()
	var second: Dictionary = provider.check_availability()

	assert_bool(first.available).is_true()
	assert_str(first.executable).is_equal("git")
	assert_str(first.version).is_equal("git version 2.50.1")
	assert_dict(second).is_equal(first)
	assert_array(git.calls).is_equal([["--version"]])


func test_availability_check_reports_missing_git_without_throwing() -> void:
	var git := FakeGitRunner.new([
		_response(-1),
	])
	var provider := GitBaselineProvider.new(git.execute)

	var result: Dictionary = provider.check_availability()

	assert_bool(result.available).is_false()
	assert_str(result.executable).is_equal("git")
	assert_str(result.error).contains("not available")


func test_tracked_file_loads_its_exact_head_contents() -> void:
	var git := FakeGitRunner.new([
		_response(0, "/project\n"),
		_response(0, "abc123\n"),
		_response(0),
		_response(0, "extends Node\n\nfunc old_name():\n\tpass\n"),
	])
	var provider := GitBaselineProvider.new(git.execute)

	var result := provider.load_baseline("/project/scripts/player.gd")

	assert_str(result.status).is_equal(GitBaselineProvider.STATUS_LOADED)
	assert_str(result.text).is_equal("extends Node\n\nfunc old_name():\n\tpass\n")
	assert_str(result.repository_root).is_equal("/project")
	assert_str(result.relative_path).is_equal("scripts/player.gd")
	assert_str(result.error).is_empty()
	assert_array(git.calls).is_equal([
		["-C", "/project/scripts", "rev-parse", "--show-toplevel"],
		["-C", "/project", "rev-parse", "--verify", "HEAD^{commit}"],
		["-C", "/project", "cat-file", "-e", "HEAD:scripts/player.gd"],
		["-C", "/project", "show", "HEAD:scripts/player.gd"],
	])


func test_file_missing_from_head_is_reported_as_new() -> void:
	var git := FakeGitRunner.new([
		_response(0, "/project\n"),
		_response(0, "abc123\n"),
		_response(128, "fatal: path does not exist in HEAD\n"),
	])
	var provider := GitBaselineProvider.new(git.execute)

	var result := provider.load_baseline("/project/scripts/new_player.gd")

	assert_str(result.status).is_equal(GitBaselineProvider.STATUS_NEW)
	assert_str(result.text).is_empty()
	assert_str(result.repository_root).is_equal("/project")
	assert_str(result.relative_path).is_equal("scripts/new_player.gd")
	assert_str(result.error).is_empty()
	assert_int(git.calls.size()).is_equal(3)


func test_path_with_spaces_is_passed_as_arguments_without_shell_escaping() -> void:
	var git := FakeGitRunner.new([
		_response(0, "/my project\n"),
		_response(0, "abc123\n"),
		_response(0),
		_response(0, "old text"),
	])
	var provider := GitBaselineProvider.new(git.execute)

	var result := provider.load_baseline("/my project/code/player state.gd")

	assert_str(result.status).is_equal(GitBaselineProvider.STATUS_LOADED)
	assert_array(git.calls[3]).is_equal([
		"-C",
		"/my project",
		"show",
		"HEAD:code/player state.gd",
	])


func test_non_repository_is_unavailable_and_stops_after_discovery() -> void:
	var git := FakeGitRunner.new([
		_response(128, "fatal: not a git repository\n"),
	])
	var provider := GitBaselineProvider.new(git.execute)

	var result := provider.load_baseline("/outside/player.gd")

	assert_str(result.status).is_equal(GitBaselineProvider.STATUS_UNAVAILABLE)
	assert_str(result.error).contains("not a git repository")
	assert_int(git.calls.size()).is_equal(1)


func test_repository_without_head_is_unavailable_instead_of_marking_file_new() -> void:
	var git := FakeGitRunner.new([
		_response(0, "/project\n"),
		_response(128, "fatal: Needed a single revision\n"),
	])
	var provider := GitBaselineProvider.new(git.execute)

	var result := provider.load_baseline("/project/player.gd")

	assert_str(result.status).is_equal(GitBaselineProvider.STATUS_UNAVAILABLE)
	assert_str(result.error).contains("Needed a single revision")
	assert_int(git.calls.size()).is_equal(2)


func test_failure_reading_a_known_blob_is_unavailable() -> void:
	var git := FakeGitRunner.new([
		_response(0, "/project\n"),
		_response(0, "abc123\n"),
		_response(0),
		_response(128, "fatal: unable to read object\n"),
	])
	var provider := GitBaselineProvider.new(git.execute)

	var result := provider.load_baseline("/project/player.gd")

	assert_str(result.status).is_equal(GitBaselineProvider.STATUS_UNAVAILABLE)
	assert_str(result.error).contains("unable to read object")


func test_repository_result_that_does_not_contain_file_is_rejected() -> void:
	var git := FakeGitRunner.new([
		_response(0, "/different-project\n"),
	])
	var provider := GitBaselineProvider.new(git.execute)

	var result := provider.load_baseline("/project/player.gd")

	assert_str(result.status).is_equal(GitBaselineProvider.STATUS_UNAVAILABLE)
	assert_str(result.error).contains("outside Git repository")
	assert_int(git.calls.size()).is_equal(1)


func _response(exit_code: int, output: String = "") -> Dictionary:
	return {
		"exit_code": exit_code,
		"output": output,
	}
