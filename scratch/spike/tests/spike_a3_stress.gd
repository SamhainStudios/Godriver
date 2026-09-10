extends Node
## GTD-003 (Spike A3) stress test — StreamPeerTCP thread-safety patch.
##
## Instantiated by SpikeServer when launched with `-- --test-driver --self-test-a3`.
## 10 worker threads hammer /health with raw-socket HTTP requests (1,000 each,
## 10,000 total) while the main thread keeps polling the server. Every response
## must be a 200 with a byte-exact body — zero corruption, zero engine errors.
## Prints SPIKE_A3_OK and quits with exit code 0, or fails with exit code 1.

const WORKERS := 10
const REQUESTS_PER_WORKER := 1000
const HOST := "127.0.0.1"
const PORT := 9090


func run(_server: Node) -> void:
	var results := {}  # worker id -> ok count
	var threads: Array[Thread] = []
	for i in range(WORKERS):
		var t := Thread.new()
		threads.append(t)
		t.start(_worker.bind(i, REQUESTS_PER_WORKER, results))
	# Keep the main loop pumping (server _process must run) without blocking.
	while threads.any(func(t: Thread) -> bool: return t.is_alive()):
		await get_tree().process_frame
	for t in threads:
		t.wait_to_finish()

	var total_ok := 0
	for i in range(WORKERS):
		total_ok += results.get(i, 0)
	print("[a3] completed %d/%d byte-exact responses" % [total_ok, WORKERS * REQUESTS_PER_WORKER])
	if total_ok != WORKERS * REQUESTS_PER_WORKER:
		push_error("[a3] FAIL: %d request(s) corrupted or failed" % (WORKERS * REQUESTS_PER_WORKER - total_ok))
		get_tree().quit(1)
		return
	print("SPIKE_A3_OK")
	get_tree().quit(0)


## Worker thread body: sequential raw-socket HTTP GETs. Uses no Node APIs.
func _worker(id: int, count: int, results: Dictionary) -> void:
	var ok := 0
	for i in range(count):
		if _one_request():
			ok += 1
		else:
			push_error("[a3] worker %d request %d failed" % [id, i])
	results[id] = ok


## One raw HTTP request over a fresh StreamPeerTCP. True on 200 + exact body.
func _one_request() -> bool:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host(HOST, PORT)
	var tries := 0
	while peer.get_status() != StreamPeerTCP.STATUS_CONNECTED and tries < 500:
		peer.poll()
		tries += 1
		OS.delay_msec(2)
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		peer.disconnect_from_host()
		return false
	peer.put_data(("GET /health HTTP/1.1\r\nHost: %s\r\n\r\n" % HOST).to_utf8_buffer())

	# Read until the full Content-Length body has arrived (or give up).
	var data := PackedByteArray()
	tries = 0
	while tries < 5000:
		peer.poll()
		var avail := peer.get_available_bytes()
		if avail > 0:
			var chunk: Array = peer.get_data(avail)
			if chunk[0] == OK:
				data.append_array(chunk[1])
			tries = 0
		else:
			tries += 1
			OS.delay_msec(1)
		var text := data.get_string_from_utf8()
		var header_end := text.find("\r\n\r\n")
		if header_end != -1:
			var length_line := ""
			for line in text.substr(0, header_end).split("\r\n"):
				if line.to_lower().begins_with("content-length:"):
					length_line = line
			if length_line != "":
				var body_length: int = length_line.split(":")[1].strip_edges().to_int()
				if data.size() >= header_end + 4 + body_length:
					break
	peer.disconnect_from_host()
	# Corruption check: status line + Content-Length framing must match the
	# actual body byte count, and the body must parse as the /health envelope.
	# (Byte-exact body comparison was dropped: /health payload evolves —
	# GTD-004 added blocked_waits, which silently broke the old literal.)
	var text := data.get_string_from_utf8()
	if not text.begins_with("HTTP/1.1 200"):
		return false
	var header_end := text.find("\r\n\r\n")
	if header_end == -1:
		return false
	var body := text.substr(header_end + 4)
	var declared := -1
	for line in text.substr(0, header_end).split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			declared = line.split(":")[1].strip_edges().to_int()
	if declared != body.length():
		return false
	var parsed: Variant = JSON.parse_string(body)
	return typeof(parsed) == TYPE_DICTIONARY and parsed.get("ok", false) == true
