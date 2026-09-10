extends Node
## GTD-011 — Godriver autoload entry point.
##
## Dormant unless the game is launched with `--test-driver` (user args, after
## `--`). When active it starts the HTTP server (SPEC §5.1 /health) on
## 127.0.0.1, default port 9090.
##
## CLI:
##   --test-driver                 activate the driver
##   --test-driver-port=N          override port (default 9090; 0 = ephemeral,
##                                 actual port printed as GODRIVER_PORT=<n>)
##   --test-driver-token=SECRET    require Authorization: Bearer SECRET

const DEFAULT_PORT := 9090

var _server: TestDriverServer


static func parse_args(args: PackedStringArray) -> Dictionary:
	## Unit-testable arg parsing. Returns {port: int, token: String}.
	var port := DEFAULT_PORT
	var token := ""
	for arg in args:
		if arg.begins_with("--test-driver-port="):
			port = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--test-driver-token="):
			token = arg.get_slice("=", 1)
	return {"port": port, "token": token}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--test-driver" in args:
		return  # dormant: no socket, no processing
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Headless fix (GTD-005, engine-source verified): under --headless the root
	# Window defaults to 64x64 and hover resolution drops any pushed position
	# outside the visible rect. Size the root from project settings.
	var root := get_tree().root
	root.size = Vector2i(
			int(ProjectSettings.get_setting("display/window/size/viewport_width", 1152)),
			int(ProjectSettings.get_setting("display/window/size/viewport_height", 648)))
	var parsed := parse_args(args)
	_server = TestDriverServer.new()
	add_child(_server)
	_server.setup(parsed.port, parsed.token)
	if not _server.start():
		push_error("[godriver] could not bind port %d — is another instance running? Override with --test-driver-port=N" % parsed.port)
		get_tree().quit(1)
		return
	if parsed.port == 0:
		print("GODRIVER_PORT=%d" % _server.bound_port)
	else:
		print("[godriver] listening on http://127.0.0.1:%d" % _server.bound_port)
