extends SceneTree
## Facade contract: every `app.<name>` that outside code uses must exist on scripts/main.gd.
## scripts/platform/package_validation.gd runs only inside exported builds, so without this check
## a renamed member in main.gd fails tools\verify_exports.ps1 and nothing else. The tests that drive
## main.gd are included for the same reason: they are the proof of later refactors.

const Harness = preload("res://tests/support/harness.gd")
const CALLERS: Array[String] = [
	"res://scripts/platform/package_validation.gd",
	"res://tests/ui_flow_test.gd",
	"res://tests/golden_trace_test.gd",
	"res://tests/support/make_v3_fixtures.gd"]

func _initialize() -> void:
	var t: RefCounted = Harness.new("FACADE CONTRACT")
	var known: Dictionary = _members_of_main()
	var pattern: RegEx = RegEx.new()
	pattern.compile("\\bapp\\.([A-Za-z_][A-Za-z0-9_]*)")
	var total: int = 0
	for path: String in CALLERS:
		var source: String = FileAccess.get_file_as_string(path)
		if not t.check(not source.is_empty(),"Caller can be read: "+path): continue
		var names: Dictionary = {}
		for found: RegExMatch in pattern.search_all(source): names[found.get_string(1)] = true
		t.check(not names.is_empty(),"%s uses main.gd through `app`" % path)
		total += names.size()
		for name: String in names:
			t.check(known.has(name),"%s uses app.%s, which main.gd (or Node) does not define" % [path,name])
	t.check(total >= 25,"The scan found a plausible number of facade names (%d)" % total)
	t.control("a name main.gd does not define",not known.has("definitely_not_a_member_of_main"))
	t.finish(self)

## Script members plus everything inherited from Node, without instantiating main.gd (it builds UI and audio).
func _members_of_main() -> Dictionary:
	var known: Dictionary = {}
	var script: GDScript = load("res://scripts/main.gd")
	for entry: Dictionary in script.get_script_property_list(): known[entry.name] = true
	for entry: Dictionary in script.get_script_method_list(): known[entry.name] = true
	for entry: Dictionary in script.get_script_signal_list(): known[entry.name] = true
	for name: String in script.get_script_constant_map(): known[name] = true
	for entry: Dictionary in ClassDB.class_get_method_list("Node"): known[entry.name] = true
	for entry: Dictionary in ClassDB.class_get_property_list("Node"): known[entry.name] = true
	for entry: Dictionary in ClassDB.class_get_signal_list("Node"): known[entry.name] = true
	return known
