class_name TestCase
extends RefCounted
## Minimal assertion base for tests/run_tests.gd. Kept in-repo to avoid a test framework dependency.

var failures: PackedStringArray = []
var current_test: String = ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("%s: %s" % [current_test, message])


func check_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: %s expected <%s> got <%s>" % [current_test, message, expected, actual])


func check_near(actual: float, expected: float, tolerance: float, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s: %s expected %.4f +/- %.4f got %.4f" % [current_test, message, expected, tolerance, actual])


func check_has_error(errors: PackedStringArray, fragment: String) -> void:
	for e in errors:
		if fragment in e:
			return
	failures.append("%s: expected an error containing '%s', got %s" % [current_test, fragment, errors])
