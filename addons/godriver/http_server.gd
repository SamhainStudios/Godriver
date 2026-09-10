class_name TestDriverServer
extends Node
## GTD-011 — HTTP server wrapper around vendored godottpd.
##
## Binds 127.0.0.1 only (SPEC §1). start() returns false when the port could
## not be bound — godottpd's HttpServer.start() swallows listen errors
## (only _print_debug + stop()), so we must check is_listening() ourselves.

var bound_port := -1

var _http: HttpServer
var _api: TestDriverApi


func setup(port: int, token: String) -> void:
	_api = TestDriverApi.new()
	_api.token = token
	add_child(_api)
	_http = HttpServer.new(true)
	_http.bind_address = "127.0.0.1"
	_http.port = port
	_http.register_router(HttpRouter.new("/health", {"get": _api.handle_health}))
	add_child(_http)


func start() -> bool:
	_http.start()
	# godottpd does not signal listen failure — verify ourselves.
	if not _http._server.is_listening():
		return false
	bound_port = _http._server.get_local_port()
	return true


func stop() -> void:
	if _http:
		_http.stop()
