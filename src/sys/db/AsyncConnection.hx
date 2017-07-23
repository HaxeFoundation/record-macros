package sys.db;

import sys.db.ResultSet;

/**
A database connection that expects operations to complete asynchcronously.

Almost exactly the same as `sys.db.Connection` except that it uses callbacks to return asynchronous results.
**/
interface AsyncConnection {
	function request( s : String, cb : ResultSetCallback ) : Void;
	function close( cb : CompletionCallback ) : Void;
	function escape( s : String ) : String;
	function quote( s : String ) : String;
	function addValue( s : StringBuf, v : Dynamic ) : Void;
	function quoteAny( v : Dynamic ) : String;
	function quoteList( v : String, it : Iterable<Dynamic> ) : String;
	function lastInsertId( cb : Null<AsyncError> -> Null<Int> -> Void ) : Void;
	function dbName() : String;
	function startTransaction( cb : CompletionCallback ) : Void;
	function commit( cb : CompletionCallback ) : Void;
	function rollback( cb : CompletionCallback ) : Void;
}

/**
A simple way to wrap any `sys.db.Connection` so that it can be used where a `sys.db.AsyncConnection` is expected.
**/
class AsyncConnectionWrapper implements AsyncConnection {
	var syncCnx : Connection;
	public function new( syncCnx : Connection ) {
		this.syncCnx = syncCnx;
	}

	public function request( s : String, cb : ResultSetCallback ) : Void {
		try {
			cb(null, syncCnx.request(s));
		} catch (e:Dynamic) {
			cb(e, null);
		}
	}

	public function close( cb : CompletionCallback ) : Void {
		try {
			syncCnx.close();
			cb(null);
		} catch (e:Dynamic) {
			cb(e);
		}
	}

	public function escape( s : String ) : String {
		return syncCnx.escape(s);
	}

	public function quote( s : String ) : String {
		return syncCnx.quote(s);
	}

	public function addValue( s : StringBuf, v : Dynamic ) : Void {
		return syncCnx.addValue(s, v);
	}

	public function quoteAny( v : Dynamic ) : String {
		if (v == null) {
			return 'NULL';
		}

		var s = new StringBuf();
		addValue(s, v);
		return s.toString();
	}

	public function quoteList( v : String, it : Iterable<Dynamic> ) : String {
		var b = new StringBuf();
		var first = true;
		if( it != null )
			for( v in it ) {
				if( first ) first = false else b.addChar(','.code);
				addValue(b, v);
			}
		if( first )
			return "FALSE";
		return v + " IN (" + b.toString() + ")";
	}

	public function lastInsertId( cb : Null<AsyncError> -> Null<Int> -> Void ) : Void {
		try {
			cb(null, syncCnx.lastInsertId());
		} catch (e:Dynamic) {
			cb(e, null);
		}
	}

	public function dbName() : String {
		return syncCnx.dbName();
	}

	public function startTransaction( cb : CompletionCallback ) : Void {
		try {
			syncCnx.startTransaction();
			cb(null);
		} catch (e:Dynamic) {
			cb(e);
		}
	}

	public function commit( cb : CompletionCallback ) : Void {
		try {
			syncCnx.commit();
			cb(null);
		} catch (e:Dynamic) {
			cb(e);
		}
	}

	public function rollback( cb : CompletionCallback ) : Void {
		try {
			syncCnx.rollback();
			cb(null);
		} catch (e:Dynamic) {
			cb(e);
		}
	}
}

typedef AsyncError = Dynamic;
typedef Callback<T> = Null<AsyncError> -> T -> Void;
typedef ResultSetCallback = Callback<ResultSet>;
typedef CompletionCallback = Null<AsyncError> -> Void;
