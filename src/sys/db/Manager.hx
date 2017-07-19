package sys.db;

class Manager<T : Object> extends BaseManager<T> {
   	public static var cnx(default, set) : Connection;
	public static var lockMode : String;

	private static function set_cnx( c : Connection ) {
		cnx = c;
		lockMode = (c != null && c.dbName() == "MySQL") ? " FOR UPDATE" : "";
		return c;
	}

    /**
    @deprecated This function is mostly for internal use but was previously exposed with a public API. It will likely be removed in a future version.
    **/
	public static function nullCompare( a : String, b : String, eq : Bool ) {
		return BaseManager.nullCompare(cnx.dbName(), a, b, eq);
	}

	/* ---------------------------- QUOTES -------------------------- */

    // TODO: in a future version this should be deprecated and moved to the `sys.db.Connection` and `sys.db.AsyncConnection` interfaces.
    // However, this is a breaking change, so it needs to be saved for a major version bump.
    /**
    Return an SQL fragment that represents the current value, wrapped in quotes.
    This will use the `Connection.addValue()` method of the current `Manager.cnx` connection.
    **/
	public static function quoteAny( v : Dynamic ) {
		if (v == null) {
			return 'NULL';
		}

		var s = new StringBuf();
		cnx.addValue(s, v);
		return s.toString();
	}

    // TODO: in a future version this should be deprecated and moved to the `sys.db.Connection` and `sys.db.AsyncConnection` interfaces.
    // However, this is a breaking change, so it needs to be saved for a major version bump.
	/**
    Return an SQL fragment that represents the current list of values, formatted as needed for the current DB connection.
    This will use the `Connection.addValue()` method of the current `Manager.cnx` connection.
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

    /**
    `BaseManager` has an object cache it uses to prevent unnecessary SQL lookups.
    Calling `cleanup()` will clear this cache.
    **/
    public static inline function cleanup() {
        BaseManager.cleanup();
    }

    /**
    @deprecated Calling this method is no longer required.
    **/
    public static inline function initialize() {
        BaseManager.initialize();
    }

	override function getCnx() {
        return cnx;
	}

	override function getLockMode() {
        return lockMode;
	}
}
