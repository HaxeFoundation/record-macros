package sys.db;

import sys.db.AsyncConnection;

/**
Asynchronous DB Manager - an easy way to get, select, insert and update `Object`s from a database.

See http://haxe.org/manual/spod for a tutorial on how to use `Manager`.
AsyncManager is almost exactly the same, except that it uses asynchronous callbacks.

### Asynchronous Connections

This version of the manager, as compared to `sys.db.Manager`, assumes an asynchronous connection, and callbacks are provided as optional arguments.

One notable difference to the synchronous manager is that you must pass in an AsyncConnection to the constructor - you cannot simply set a static variable as you do with the synchronous manager.
The reason for this is that async platforms often allow multiple requests, and multiple DB connections, to be active simultaneously.
So passing in a connection to the Manager allows you to manage a pool of simultaneous connections, rather than assuming only one connection is active at a time.

### Related objects

With a synchronous manager, Haxe will transform any `@:relation` fields on a `sys.db.Object` into a getter that fetches the object seamlessly.
Because getters work synchronously, it is not possible to emulate this behaviour seamlessly with an asynchronous connection.
Therefore, seamless `@:relation` support is not possible with `AsyncManager` and `AsyncConnection`.

### Caching

This Manager class uses a `Map` stored in a member variable to cache objects that have been fetched from the database.

This ensures that if a call to `Manager.select()` finds an object, a call to `Manager.get()` for the same object won't result in an extra SQL request.
It will also ensure that the object returned by both queries is the same object in memory - so updates to one object update the other object also.

Each instance of an `AsyncManager` will have it's own cache.
To empty the cache, call `cleanup()` on your manager instance, or just discard the Manager and start using a new one.
**/
class AsyncManager<T : Object> extends BaseManager<T> {

   	public var cnx(default, set) : AsyncConnection;
	var lockMode : String;
	var objectCache : haxe.ds.StringMap<Object>;

	public function new( asyncCnx : AsyncConnection, classval : Class<T> ) {
		super(classval);
        set_cnx(asyncCnx);
        objectCache = new haxe.ds.StringMap();
	}

	function set_cnx( c : AsyncConnection ) {
		cnx = c;
		lockMode = (c != null && c.dbName() == "MySQL") ? " FOR UPDATE" : "";
		return c;
	}

	/**
	Reset the object cache.
	See the note in the class documentation for more details on object caching.
	**/
	public function cleanup() {
		objectCache = new haxe.ds.StringMap();
	}

	public function all( ?lock: Bool, cb : Callback<List<T>> ) {
		return unsafeObjects(getAllStatement(), lock, cb);
	}

    #if macro
    static function argIsNull(e:haxe.macro.Expr):Bool {
        if (e == null) return true;
        return switch (e) {
            case macro null: true;
            default: false;
        }
    }
    #end

    /**
    Select a single record from the database based on it's primary key.

    @param id The primary key (or an object containing multiple keys if the tables primary key is made up of multiple fields).
    @param lock (optional) Whether or not to lock the database row. Default true.
    @param cb A callback, in the form `function (error:Null<Dynamic>, object:T)`.
    **/
	public macro function get( ethis, id, ?arg3, ?arg4 ) {
        // Allow `lock` to be an optional argument, but the final `cb` argument to be required.
        var lock, cb;
        if (argIsNull(arg3) && argIsNull(arg4)) {
            haxe.macro.Context.error('Not enough arguments, expected cb', haxe.macro.Context.currentPos());
        } else if (argIsNull(arg4)) {
            lock = macro null;
            cb = arg3;
        } else {
            lock = arg3;
            cb = arg4;
        }
		return RecordMacros.macroGetAsync(ethis, id, lock, cb);
	}

	/**
    Select a single record from the database based on search conditions.

    @param cond The condition to select rows based on. See README for details on how to construct conditions.
    @param options (optional) Options for the query, in the format `{ orderBy : String or Array<String>, limit : Int, forceIndex : Array<String> }`. See the README for details.
    @param lock (optional) Whether or not to lock the database row. Default true.
    @param cb A callback, in the form `function (error:Null<Dynamic>, object:T)`.
    **/
	public macro function select( ethis, cond, ?arg3, ?arg4, ?arg5 ) {
        // Allow `options` and `lock` to be an optional arguments, but the final `cb` argument to be required.
        var options, lock, cb;
        if (argIsNull(arg3) && argIsNull(arg4) && argIsNull(arg5)) {
            haxe.macro.Context.error('Not enough arguments, expected cb', haxe.macro.Context.currentPos());
        } else if (argIsNull(arg4) && argIsNull(arg5)) {
            options = macro null;
            lock = macro null;
            cb = arg3;
        } else if (argIsNull(arg5)) {
            // Either options or lock is provided.
            switch arg3.expr {
                case EObjectDecl(_):
                    options = arg3;
                    lock = macro null;
                default:
                    options = macro null;
                    lock = arg3;
            }
            cb = arg4;
        } else {
            options = arg3;
            lock = arg4;
            cb = arg5;
        }
		return RecordMacros.macroSearchAsync(ethis, cond, options, lock, cb, true);
	}

	/**
    Select a group of records from the database based on search conditions.

    @param cond The condition to select rows based on. See README for details on how to construct conditions.
    @param options (optional) Options for the query, in the format `{ orderBy : String or Array<String>, limit : Int, forceIndex : Array<String> }`. See the README for details.
    @param lock (optional) Whether or not to lock the database rows. Default true.
    @param cb A callback, in the form `function (error:Null<Dynamic>, objects:List<T>)`.
    **/
	public macro function search( ethis, cond, ?arg3, ?arg4, ?arg5 ) {
        // Allow `options` and `lock` to be an optional arguments, but the final `cb` argument to be required.
        var options, lock, cb;
        if (argIsNull(arg3) && argIsNull(arg4) && argIsNull(arg5)) {
            haxe.macro.Context.error('Not enough arguments, expected cb', haxe.macro.Context.currentPos());
        } else if (argIsNull(arg4) && argIsNull(arg5)) {
            options = macro null;
            lock = macro null;
            cb = arg3;
        } else if (argIsNull(arg5)) {
            // Either options or lock is provided.
            switch arg3.expr {
                case EObjectDecl(_):
                    options = arg3;
                    lock = macro null;
                default:
                    options = macro null;
                    lock = arg3;
            }
            cb = arg4;
        } else {
            options = arg3;
            lock = arg4;
            cb = arg5;
        }
		return RecordMacros.macroSearchAsync(ethis, cond, options, lock, cb);
	}

	/**
    Count the number of rows in the database that match a condition.

    @param cond The condition to count rows based on. See README for details on how to construct conditions.
    @param cb A callback, in the form `function (error:Null<Dynamic>, count:Int)`.
    **/
	public macro function count( ethis, cond, cb ) {
		return RecordMacros.macroCountAsync(ethis, cond, cb);
	}

	/**
    Delete a group of records from the database based on search conditions.

    @param cond The condition to select rows based on. See README for details on how to construct conditions.
    @param options (optional) Options for the query, in the format `{ orderBy : String or Array<String>, limit : Int, forceIndex : Array<String> }`. See the README for details.
    @param cb A callback, in the form `function (error:Null<Dynamic>)`.
    **/
	public macro function delete( ethis, cond, ?arg3, ?arg4 ) {
        // Allow `options` to be an optional arguments, but the final `cb` argument to be required.
        var options, cb;
        if (argIsNull(arg3) && argIsNull(arg4)) {
            haxe.macro.Context.error('Not enough arguments, expected cb', haxe.macro.Context.currentPos());
        } else if (argIsNull(arg4)) {
            options = macro null;
            cb = arg3;
        } else {
            options = arg3;
            cb = arg4;
        }
		return RecordMacros.macroDeleteAsync(ethis, cond, options, cb);
	}

	public function dynamicSearch( x : {}, ?lock : Bool, cb : Callback<List<T>> ) {
		return unsafeObjects(getDynamicSearchStatement(x), lock, cb);
	}

	function doInsert( x : T, cb : Callback<T> ) {
        doInsertAsync(x, cb);
	}

	function doUpdate( x : T, cb : Callback<T> ) {
        doUpdateAsync(x, cb);
	}

	function doDelete( x : T, cb : CompletionCallback ) {
        doDeleteAsync(x, cb);
	}

	function doLock( i : T, cb : CompletionCallback ) {
        doLockAsync(i, cb);
	}

	public function unsafeObject( sql : String, lock : Bool, cb : Callback<T> ) {
        unsafeObjectAsync(sql, lock, cb);
	}

	public function unsafeObjects( sql : String, lock : Bool, cb : Callback<List<T>> ) {
        unsafeObjectsAsync(sql, lock, cb);
	}

	public function unsafeCount( sql : String, cb : Callback<Int> ) {
        unsafeCountAsync(sql, cb);
	}

	public function unsafeDelete( sql : String, cb : CompletionCallback ) {
        unsafeDeleteAsync(sql, cb);
	}

	public function unsafeGet( id : Dynamic, ?lock : Bool, cb : Callback<T> ) {
        unsafeGetAsync(id, lock, cb);
	}

	public function unsafeGetWithKeys( keys : { }, ?lock : Bool, cb : Callback<T> ) {
        unsafeGetWithKeysAsync(keys, lock, cb);
	}

	override function getObjectCache():Map<String, Object> {
		return objectCache;
	}

	override function getCnx() {
		return cnx;
	}

	override function getLockMode() {
		return lockMode;
	}
}
