@tool
class_name ScopeLocker
extends Node

signal locked
signal unlocked
signal lock_changed(locked: bool)

var _lock_ops: Array[Callable] = []
var _unlock_ops: Array[Callable] = []

var _is_locked: bool:
	get:
		return _lock_count > 0
var _lock_count: int = 0

class ScopeLock:
	extends RefCounted
	var _locker: ScopeLocker
			
	func _init(locker: ScopeLocker):
		_locker = locker
		_locker._lock()
	
	func _notification(what):
		if what == NOTIFICATION_PREDELETE:
			_locker._unlock()

func get_lock() -> ScopeLock:
	return ScopeLock.new(self)

func add_lock_ops(do_lock: Callable, do_unlock: Callable):
	_lock_ops.append(do_lock)
	_unlock_ops.append(do_unlock)

func _lock():
	_lock_count += 1
	locked.emit()
	lock_changed.emit(true)
	for op in _lock_ops:
		op.call()

func _unlock():
	_lock_count -= 1
	if _lock_count < 0:
		_lock_count = 0
	if not _is_locked:
		unlocked.emit()
		lock_changed.emit(false)
		for op in _unlock_ops:
			op.call()

func is_locked() -> bool:
	return _is_locked
