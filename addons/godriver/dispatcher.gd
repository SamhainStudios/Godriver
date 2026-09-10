class_name TestDriverDispatcher
extends Node
## GTD-012 — main-thread task queue (moved from the GTD-002 spike).
##
## godottpd handles requests on worker threads; Godot's SceneTree/node APIs are
## not thread-safe. Workers call `submit(callable)`; the callable is executed on
## the main thread during `_process`, and the worker blocks on a Semaphore until
## the result is ready. Mutex + Semaphore instead of `call_deferred` because
## workers need the return value synchronously.
##
## Runs with PROCESS_MODE_ALWAYS so the queue keeps draining while
## `get_tree().paused = true` (else /dev/pause would freeze every endpoint).
##
## Error semantics: a handler that hits a script error aborts and returns
## null — the queue still posts the semaphore and keeps draining, so the
## API layer's funnel (api_handler.gd) maps the null result to a 500
## envelope and the server stays up.

var _mutex: Mutex
## Queue records: {callable: Callable, semaphore: Semaphore, result: Variant}
var _queue: Array = []
var _main_id: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mutex = Mutex.new()
	_main_id = OS.get_main_thread_id()


## Submit a callable for execution on the main thread. Blocks the calling
## (worker) thread until the callable has run and its result is available.
## Callable from the main thread too — executes inline to avoid deadlock.
func submit(callable: Callable) -> Variant:
	if OS.get_thread_caller_id() == _main_id:
		return callable.call()
	var semaphore := Semaphore.new()
	var record := {"callable": callable, "semaphore": semaphore, "result": null}
	_mutex.lock()
	_queue.append(record)
	_mutex.unlock()
	semaphore.wait()
	return record.result


func _process(_delta: float) -> void:
	# Debug invariant: the queue must only ever drain on the main thread.
	assert(OS.get_thread_caller_id() == _main_id, "Dispatcher must drain on the main thread")
	while true:
		_mutex.lock()
		if _queue.is_empty():
			_mutex.unlock()
			return
		var record: Dictionary = _queue.pop_front()
		_mutex.unlock()
		record.result = record.callable.call()
		record.semaphore.post()
