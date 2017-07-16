package sys.db;

import js.Error;
import sys.db.ResultSet;

/**
Almost exactly the same as `sys.db.Manager` except that it uses callbacks to return asynchronous results.
**/
interface AsyncConnection {
	function request( s : String, cb : ResultSetCallback ) : Void;
	function close( cb : CompletionCallback ) : Void;
	function escape( s : String ) : String;
	function quote( s : String ) : String;
	function addValue( s : StringBuf, v : Dynamic ) : Void;
	function lastInsertId( cb : Null<Error> -> Null<Int> -> Void ) : Void;
	function dbName(  ) : String;
	function startTransaction( cb : CompletionCallback ) : Void;
	function commit( cb : CompletionCallback ) : Void;
	function rollback( cb : CompletionCallback ) : Void;
}

typedef ResultSetCallback = Null<Error> -> ResultSet -> Void;
typedef CompletionCallback = Null<Error> -> Void;
