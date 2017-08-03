package sys.db;

import js.Error;
import sys.db.AsyncConnection;

typedef MysqlJsConnectionProps = {
    host : String,
    user : String,
    pass : String,
    database : String
};

@:jsRequire('mysql')
extern class MysqlJs {
    public static inline function connect( connectionProps : MysqlJsConnectionProps, cb : Null<Error> -> Null<AsyncConnection> -> Void ) : Void {
        var cnx = MysqlJs.createConnection({
            host: connectionProps.host,
            user: connectionProps.user,
            password: connectionProps.pass,
            database: connectionProps.database,
        });
        cnx.connect(function (err) {
            if (err != null) {
                cb(err, null);
                return;
            }
            cb(null, new MysqlJsConnectionWrapper(cnx));
        });
    }

    static function createConnection( connectionProps : {host : String, user : String, password : String, database : String} ) : MysqlJsConnection;
}

extern class MysqlJsConnection {
    public var threadId : Int;
    public function connect( cb : CompletionCallback ) : Void;
    public function query( sql : String, handler : Null<Error> -> Array<Dynamic> -> FieldsMeta -> Void ) : Void;
    public function end( cb : CompletionCallback ) : Void;
    public function escape( str : String ) : String;
    public function beginTransaction( cb : CompletionCallback ) : Void;
    public function commit( cb : CompletionCallback ) : Void;
    public function rollback( cb : CompletionCallback ) : Void;
}

class MysqlJsConnectionWrapper implements AsyncConnection {
    public var lastResultSet(default, null) : Null<MysqlJsResultSet>;
    var jsCnx : MysqlJsConnection;

    public function new( jsCnx : MysqlJsConnection ) {
        this.jsCnx = jsCnx;
    }

    public function request( sql : String, cb : ResultSetCallback ) : Void {
        jsCnx.query(sql, function (err, results, fields) {
            if (err != null) {
                cb(err, null);
                return;
            }

            var resultSet = new MysqlJsResultSet(results, fields);
            this.lastResultSet = resultSet;

            cb(null, resultSet);
        });
    }

    public function close( cb : CompletionCallback ) : Void {
        jsCnx.end(cb);
    }

    public function escape( s : String ) : String {
        return jsCnx.escape(s);
    }

    public function quote( s : String ) : String {
        return "'" + escape(s) + "'";
    }

    public function addValue( sb : StringBuf, v : Dynamic ) : Void {
        var str = switch Type.typeof(v) {
            case TNull, TInt, TFloat: ''+v;
            case TBool: (v==true) ? '1' : '0';
            case _: quote(''+v);
        }
        sb.add(str);
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

    public function lastInsertId( cb : Null<Error> -> Null<Int> -> Void ) : Void {
        cb(null, this.lastResultSet.insertId);
    }

    public function dbName() : String {
        return 'MySQL';
    }

    public function startTransaction( cb : CompletionCallback ) : Void {
        jsCnx.beginTransaction(cb);
    }

    public function commit( cb : CompletionCallback ) : Void {
        jsCnx.commit(cb);
    }

    public function rollback( cb : CompletionCallback ) : Void {
        jsCnx.rollback(cb);
    }
}

class MysqlJsResultSet implements ResultSet {
    public var length(get,null)  :  Int;
	public var nfields(get,null)  :  Int;

    public var rawResults(default,null) : Array<Dynamic>;
    public var insertId(default, null) : Null<Int>;
    public var affectedRows(default, null) : Null<Int>;
    public var changedRows(default, null) : Null<Int>;
    public var fields(default, null) : Array<String>;

    /** Because ResultSet is an iterator with next() and hasNext(), we need to keep track of the current position. **/
    var i:Int;

    public function new( rawResults : Array<Dynamic>, fields : FieldsMeta ) {
        this.rawResults = rawResults;
        this.fields = [for (f in fields) f.name];

        var meta : {insertId : Int, affectedRows : Int, changedRows : Int} = cast rawResults;
        this.insertId = meta.insertId;
        this.affectedRows = meta.affectedRows;
        this.changedRows = meta.changedRows;

        this.i = 0;
    }

    public function results() : List<Dynamic> {
        // The results we pass in are actually already passed correctly, so just turn them into a list to satisfy the
        return Lambda.list(rawResults);
    }

    function get_length() : Int {
        return rawResults.length;
    }

    function get_nfields() : Int {
        return fields.length;
    }

	public function hasNext() : Bool {
        return i < rawResults.length;
    }

    public function next() : Dynamic {
        return rawResults[i++];
    }

    public function getResult( n : Int ) : String {
        var fieldName = fields[n];
        var fieldValue = Reflect.field(rawResults[i], fieldName);
        return ''+fieldValue;
    }

    public function getIntResult( n : Int ) : Int {
        return Std.parseInt(getResult(n));
    }

    public function getFloatResult( n : Int ) : Float {
        return Std.parseFloat(getResult(n));
    }

    public function getFieldsNames() : Array<String> {
        return this.fields;
    }
}

typedef FieldsMeta = Array<{
    catalog : String,
    db : String,
    table : String,
    orgTable : String,
    name : String,
    orgName : String,
    charsetNr : Int,
    length : Int,
    type : Int,
    flags : Int,
    decimals : Int,
    zeroFill : Bool,
    protocol41 : Bool
}>;
