/*
 * Copyright (C)2005-2016 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
package sys.db;

import sys.db.AsyncConnection;

/**
	Record Object : the persistent object base type. See the tutorial on Haxe
	website to learn how to use Record.
**/
@:keepSub
@:autoBuild(sys.db.RecordMacros.macroBuild()) @:skipFields
class Object {

	var _lock(default,null) : Bool;
	var _manager(default,null) : sys.db.BaseManager<Dynamic>;
#if !neko
	@:keep var __cache__:Dynamic;
#end

	public function new() {
		#if !neko
		if( _manager == null ) @:privateAccess _manager = __getManager();
		#end
	}

#if !neko
	private function __getManager():sys.db.Manager<Dynamic>
	{
		var cls:Dynamic = Type.getClass(this);
		return cls.manager;
	}
#end

	/**
	Insert the current object to the database.

	To insert an object, you must either have the static `Manager.cnx` set to a valid `Connection`, or you must provide a `Manager` as the first argument.

	If you are using an `AsyncConnection`, you should provide a callback to know when the operation is complete.
	If you do not provide a callback and an error occurs, the error will be re-thrown rather than passed to a callback.
	**/
	public function insert( ?manager : Manager<Object>, ?cb : CompletionCallback ) {
		if (manager != null) {
			_manager = manager;
		} else if (_manager == null || @:privateAccess _manager.getCnx() == null) {
			throw 'Either set `Manager.cnx` before calling `insert()` or provide a `Manager` argument when calling `insert()`';
		}
		@:privateAccess _manager.doInsertAsync(this, handleError.bind(cb,_));
	}

	/**
	Update the current object in the database, saving the current state of it's fields to columns in the table.

	If you are using an `AsyncConnection`, you should provide a callback to know when the operation is complete.
	If you do not provide a callback and an error occurs, the error will be re-thrown rather than passed to a callback.
	**/
	public function update( ?cb : CompletionCallback ) {
		@:privateAccess _manager.doUpdateAsync(this, handleError.bind(cb,_));
	}

	/**
	Lock the current object so that the DB engine is aware you intend to update it.

	If you are using an `AsyncConnection`, you should provide a callback to know when the operation is complete.
	If you do not provide a callback and an error occurs, the error will be re-thrown rather than passed to a callback.
	**/
	public function lock( ?cb : CompletionCallback ) {
		@:privateAccess _manager.doLockAsync(this, handleError.bind(cb,_,null));
	}

	/**
	Delete the current object from the database.

	If you are using an `AsyncConnection`, you should provide a callback to know when the operation is complete.
	If you do not provide a callback and an error occurs, the error will be re-thrown rather than passed to a callback.
	**/
	public function delete( ?cb : CompletionCallback ) {
		@:privateAccess _manager.doDeleteAsync(this, handleError.bind(cb,_,null));
	}

	public function isLocked() {
		return _lock;
	}

	public function toString() : String {
		return @:privateAccess _manager.objectToString(this);
	}

	inline function handleError( ?cb : CompletionCallback, err:String, result:Dynamic ) {
		if (cb!=null) {
			cb(err);
		} else if (err != null) {
			#if cpp
			cpp.Lib.rethrow(err);
			#elseif cs
			cs.Lib.rethrow(err);
			#elseif js
			js.Lib.rethrow();
			#elseif neko
			neko.Lib.rethrow(err);
			#else
			throw err;
			#end
		}
	}
}
