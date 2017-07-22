package sys.db;

/**
Synchronous DB Manager - an easy way to get, select, insert and update `Object`s from a database.

See http://haxe.org/manual/spod for a tutorial on how to use `Manager`.

### Caching

This Manager class uses a `Map` stored in a static variable to cache objects that have been fetched from the database.

This ensures that if a call to `Manager.select()` finds an object, a call to `Manager.get()` for the same object won't result in an extra SQL request.
It will also ensure that the object returned by both queries is the same object in memory.

To clear the cache, call `Manager.cleanup()`.
This is important if you have an app that runs for a long time, or that persists static variables between requests, as seen with `neko.Web.cacheModule()`.
**/
class Manager<T : Object> extends BaseManager<T> {

	/* ---------------------------- STATIC API -------------------------- */

   	public static var cnx(default, set) : Connection;
	public static var lockMode : String;
	static var object_cache : haxe.ds.StringMap<Object> = new haxe.ds.StringMap();

	private static function set_cnx( c : Connection ) {
		cnx = c;
		lockMode = (c != null && c.dbName() == "MySQL") ? " FOR UPDATE" : "";
		return c;
	}

	/**
	Reset the object cache.
	See the note in the class documentation for more details on object caching.
	**/
	public static inline function cleanup() {
		object_cache = new haxe.ds.StringMap();
	}

	/**
	@deprecated Calling this method is no longer required.
	**/
	public static inline function initialize() {
		BaseManager.initialize();
	}

	/**
	@deprecated This function is mostly for internal use but was previously exposed with a public API. It will likely be removed in a future version.
	**/
	public static function nullCompare( a : String, b : String, eq : Bool ) {
		return BaseManager.nullCompare(cnx.dbName(), a, b, eq);
	}

	/**
	Return an SQL fragment that represents the current value, wrapped in quotes.
	This will use the `Connection.addValue()` method of the current `Manager.cnx` connection.

	Depration Warning: this is mostly for low-level use, and in future may be deprecated and moved to the `sys.db.Connection` interface.
	A version of this method is already required by the `sys.db.AsyncConnection` interface.
	**/
	public static function quoteAny( v : Dynamic ) {
		if (v == null) {
			return 'NULL';
		}

		var s = new StringBuf();
		cnx.addValue(s, v);
		return s.toString();
	}

	/**
	Return an SQL fragment that represents the current list of values, formatted as needed for the current DB connection.
	This will use the `Connection.addValue()` method of the current `Manager.cnx` connection.

	Depration Warning: this is mostly for low-level use, and in future may be deprecated and moved to the `sys.db.Connection` interface.
	A version of this method is already required by the `sys.db.AsyncConnection` interface.
	**/
	public static function quoteList( v : String, it : Iterable<Dynamic> ) {
		var b = new StringBuf();
		var first = true;
		if( it != null )
			for( v in it ) {
				if( first ) first = false else b.addChar(','.code);
				cnx.addValue(b, v);
			}
		if( first )
			return "FALSE";
		return v + " IN (" + b.toString() + ")";
	}

	/* ---------------------------- INSTANCE API -------------------------- */

	public function new( classval : Class<T> ) {
		super(classval);
	}

	override function getObjectCache():Map<String, Object> {
		return object_cache;
	}

	override function getCnx() {
		return cnx;
	}

	override function getLockMode() {
		return lockMode;
	}
}
