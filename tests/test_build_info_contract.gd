extends TestCase
## Build metadata must describe the running project, not a cached or hard-coded version.

const VERSION_KEY := "application/config/version"

var _original_version: Variant


func before_each() -> void:
	_original_version = ProjectSettings.get_setting(VERSION_KEY)


func after_each() -> void:
	ProjectSettings.set_setting(VERSION_KEY, _original_version)


func test_read_matches_running_project_and_engine() -> void:
	var first := BuildInfo.read()
	check_eq(first.version, str(ProjectSettings.get_setting(VERSION_KEY)), "project version")
	check_eq(first.engine, Engine.get_version_info().string, "running engine")
	check_eq(first, BuildInfo.read(), "repeated reads are deterministic")


func test_build_id_tracks_version_changes_without_stale_cache() -> void:
	var original_commit: String = str(BuildInfo.read().commit)
	ProjectSettings.set_setting(VERSION_KEY, "9.8.7-test")
	check_eq(BuildInfo.read().version, "9.8.7-test", "read uses current version")
	check_eq(
		BuildInfo.build_id(),
		"9.8.7-test+%s" % original_commit,
		"build id uses current version and metadata commit"
	)


func test_metadata_source_or_dev_fallback() -> void:
	var info := BuildInfo.read()
	check(info.has("commit") and info.has("built_at"), "build metadata keys are present")
	check(info.commit is String and info.built_at is String, "build metadata is text")
	if not FileAccess.file_exists(BuildInfo.PATH):
		check_eq(info.commit, "dev", "source checkout uses the dev commit marker")
		check_eq(info.built_at, "", "source checkout has no build time")
