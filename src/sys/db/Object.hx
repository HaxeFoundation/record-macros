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

	public function insert() {
		@:privateAccess _manager.doInsertAsync(this, function (_, _) {});
	}

	public function update() {
		@:privateAccess _manager.doUpdateAsync(this, function (_, _) {});
	}

	public function lock() {
		@:privateAccess _manager.doLockAsync(this, function (_) {});
	}

	public function delete() {
		@:privateAccess _manager.doDeleteAsync(this, function (_) {});
	}

	public function isLocked() {
		return _lock;
	}

	public function toString() : String {
		return @:privateAccess _manager.objectToString(this);
	}

}
