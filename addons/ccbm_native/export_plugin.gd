@tool
extends EditorPlugin
var _export: EditorExportPlugin

func _enter_tree() -> void:
	_export = NativeExport.new()
	add_export_plugin(_export)

func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null

class NativeExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "NaretNativeCCBM"
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid
	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["res://addons/ccbm_native/naret_ccbm_runtime.aar"])
