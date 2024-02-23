class_name JamThreadHelper
extends Node
## A [Node] that provides utilities for simplifying common [Thread] operations

var _product_mtx := Mutex.new()
var _product_map: Dictionary = {}

var _lazy_timer: Timer
var _thread_wait_timer: Timer:
	get:
		if not _lazy_timer:
			_lazy_timer = Timer.new()
			add_child(_lazy_timer)
			_lazy_timer.start(.25)
		return _lazy_timer

class ThreadProduct:
	extends RefCounted
	var value: Variant = null
	var errored: bool = false
	var error_msg: String = ""
	
	static func make(val: Variant) -> ThreadProduct:
		var p = ThreadProduct.new()
		p.value = val
		return p
	
	static func err(msg: String) -> ThreadProduct:
		var p = ThreadProduct.new()
		p.errored = true
		p.error_msg = msg
		return p

func take_product(id: int) -> ThreadProduct:
	var product: Variant = _product_map.get(id, null)
	if product == null:
		return ThreadProduct.err("task finished without producing a result")
	_product_mtx.lock()
	_product_map.erase(id)
	_product_mtx.unlock()
	return product

func put_product(id: int, product: ThreadProduct) -> void:
	_product_mtx.lock()
	_product_map[id] = product
	_product_mtx.unlock()

func producer_wrapper(id: int, producer: Callable):
	var r = producer.call()
	put_product(id, ThreadProduct.make(r))

## An awaitable function that runs a thread-safe function on a separate thread
## and retrieves the return value. Useful for async-ifying functions and
## retrieving their result.
func run_threaded_producer(producer: Callable) -> ThreadProduct:
	var product_id := randi()
	while product_id in _product_map:
		product_id = randi()
	var task_id := WorkerThreadPool.add_task(producer_wrapper.bind(product_id, producer))
	while true:
		await _thread_wait_timer.timeout
		if WorkerThreadPool.is_task_completed(task_id):
			return take_product(product_id)
	
	return ThreadProduct.err("unexpected failure while waiting for threaded task completion")
