class_name TestDriverServer
extends Node
## GTD-011/012 — HTTP server wrapper around vendored godottpd.
##
## Binds 127.0.0.1 only (SPEC §1). start() returns false when the port could
## not be bound — godottpd's HttpServer.start() swallows listen errors
## (only _print_debug + stop()), so we must check is_listening() ourselves.
##
## GTD-012: routes are registered from TestDriverApi.routes (the handler
## registration map); every handler is wrapped so it executes on the main
## thread through the TestDriverDispatcher queue.

var bound_port := -1

var _http: HttpServer
var _api: TestDriverApi


func setup(port: int, token: String, dispatcher: TestDriverDispatcher = null) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_api = TestDriverApi.new()
	_api.token = token
	if dispatcher != null:
		_api.dispatcher = dispatcher
	else:
		# Standalone/test usage: own our dispatcher (must be in the tree to
		# drain — we are in the tree by the time setup() is called).
		var d := TestDriverDispatcher.new()
		_api.dispatcher = d
		add_child(d)
	add_child(_api)
	_http = HttpServer.new(true)
	_http.bind_address = "127.0.0.1"
	_http.port = port
	register_routes()
	add_child(_http)


## Register godottpd routers from the api's handler map. Public so tests can
## re-register after extending TestDriverApi.routes.
func register_routes() -> void:
	for path in _api.routes:
		var methods := {}
		for method in _api.routes[path]:
			var handler_name: String = _api.routes[path][method]
			methods[method] = func(req: HttpRequest, res: HttpResponse) -> bool:
				return _api.dispatch(handler_name, req, res)
		_http.register_router(HttpRouter.new(path, methods))


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
