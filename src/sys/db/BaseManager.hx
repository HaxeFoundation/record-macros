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
import Reflect;
import sys.db.AsyncConnection;
import sys.db.RecordInfos;

/**
	A base class for creating a DB Manager.

	Please use either `Manager` on synchronous platforms (like PHP and Neko) or `AsyncManager` on asynchonous platforms (like NodeJs).
**/
#if !macro @:build(sys.db.RecordMacros.addRtti()) #end
class BaseManager<T : Object> {

	/* ----------------------------- STATICS ------------------------------ */
	private static inline var cache_field = "__cache__";

	private static var init_list : List<BaseManager<Dynamic>> = new List();

	private static var KEYWORDS = {
		var h = new haxe.ds.StringMap();
		for( k in "ADD|ALL|ALTER|ANALYZE|AND|AS|ASC|ASENSITIVE|BEFORE|BETWEEN|BIGINT|BINARY|BLOB|BOTH|BY|CALL|CASCADE|CASE|CHANGE|CHAR|CHARACTER|CHECK|COLLATE|COLUMN|CONDITION|CONSTRAINT|CONTINUE|CONVERT|CREATE|CROSS|CURRENT_DATE|CURRENT_TIME|CURRENT_TIMESTAMP|CURRENT_USER|CURSOR|DATABASE|DATABASES|DAY_HOUR|DAY_MICROSECOND|DAY_MINUTE|DAY_SECOND|DEC|DECIMAL|DECLARE|DEFAULT|DELAYED|DELETE|DESC|DESCRIBE|DETERMINISTIC|DISTINCT|DISTINCTROW|DIV|DOUBLE|DROP|DUAL|EACH|ELSE|ELSEIF|ENCLOSED|ESCAPED|EXISTS|EXIT|EXPLAIN|FALSE|FETCH|FLOAT|FLOAT4|FLOAT8|FOR|FORCE|FOREIGN|FROM|FULLTEXT|GRANT|GROUP|HAVING|HIGH_PRIORITY|HOUR_MICROSECOND|HOUR_MINUTE|HOUR_SECOND|IF|IGNORE|IN|INDEX|INFILE|INNER|INOUT|INSENSITIVE|INSERT|INT|INT1|INT2|INT3|INT4|INT8|INTEGER|INTERVAL|INTO|IS|ITERATE|JOIN|KEY|KEYS|KILL|LEADING|LEAVE|LEFT|LIKE|LIMIT|LINES|LOAD|LOCALTIME|LOCALTIMESTAMP|LOCK|LONG|LONGBLOB|LONGTEXT|LOOP|LOW_PRIORITY|MATCH|MEDIUMBLOB|MEDIUMINT|MEDIUMTEXT|MIDDLEINT|MINUTE_MICROSECOND|MINUTE_SECOND|MOD|MODIFIES|NATURAL|NOT|NO_WRITE_TO_BINLOG|NULL|NUMERIC|ON|OPTIMIZE|OPTION|OPTIONALLY|OR|ORDER|OUT|OUTER|OUTFILE|PRECISION|PRIMARY|PROCEDURE|PURGE|READ|READS|REAL|REFERENCES|REGEXP|RELEASE|RENAME|REPEAT|REPLACE|REQUIRE|RESTRICT|RETURN|REVOKE|RIGHT|RLIKE|SCHEMA|SCHEMAS|SECOND_MICROSECOND|SELECT|SENSITIVE|SEPARATOR|SET|SHOW|SMALLINT|SONAME|SPATIAL|SPECIFIC|SQL|SQLEXCEPTION|SQLSTATE|SQLWARNING|SQL_BIG_RESULT|SQL_CALC_FOUND_ROWS|SQL_SMALL_RESULT|SSL|STARTING|STRAIGHT_JOIN|TABLE|TERMINATED|THEN|TINYBLOB|TINYINT|TINYTEXT|TO|TRAILING|TRIGGER|TRUE|UNDO|UNION|UNIQUE|UNLOCK|UNSIGNED|UPDATE|USAGE|USE|USING|UTC_DATE|UTC_TIME|UTC_TIMESTAMP|VALUES|VARBINARY|VARCHAR|VARCHARACTER|VARYING|WHEN|WHERE|WHILE|WITH|WRITE|XOR|YEAR_MONTH|ZEROFILL|ASENSITIVE|CALL|CONDITION|CONNECTION|CONTINUE|CURSOR|DECLARE|DETERMINISTIC|EACH|ELSEIF|EXIT|FETCH|GOTO|INOUT|INSENSITIVE|ITERATE|LABEL|LEAVE|LOOP|MODIFIES|OUT|READS|RELEASE|REPEAT|RETURN|SCHEMA|SCHEMAS|SENSITIVE|SPECIFIC|SQL|SQLEXCEPTION|SQLSTATE|SQLWARNING|TRIGGER|UNDO|UPGRADE|WHILE".split("|") )
			h.set(k.toLowerCase(),true);
		h;
	}

	/* ---------------------------- BASIC API ----------------------------- */

	var table_infos : RecordInfos;
	var table_name : String;
	var table_keys : Array<String>;
	var class_proto : { prototype : Dynamic };

	function new( classval : Class<T> ) {
		var m : Array<Dynamic> = haxe.rtti.Meta.getType(classval).rtti;
		if( m == null ) throw "Missing @rtti for class " + Type.getClassName(classval);
		table_infos = haxe.Unserializer.run(m[0]);
		table_name = quoteField(table_infos.name);
		table_keys = table_infos.key;
		// set the manager and ready for further init
		class_proto = cast classval;
		#if neko
		class_proto.prototype._manager = this;
		init_list.add(this);
		#end
	}

	function getAllStatement() : String {
		return "SELECT * FROM " + table_name;
	}

	function getDynamicSearchStatement( x : {} ) : String {
		var s = new StringBuf();
		s.add("SELECT * FROM ");
		s.add(table_name);
		s.add(" WHERE ");
		addCondition(s,x);
		return s.toString();
	}

	function quote( s : String ) : String {
		return getCnx().quote( s );
	}

	/* -------------------------- RECORDOBJECT API -------------------------- */

	function doUpdateCache( x : T, name : String, v : Dynamic ) {
		var cache : { v : Dynamic } = Reflect.field(x, "cache_" + name);
		// if the cache has not been fetched (for instance if the field was set by reflection)
		// then we directly use the new value
		if( cache == null )
			return v;
		var v = doSerialize(name, cache.v);
		// don't set it since the value might change again later
		// Reflect.setField(x, name, v);
		return v;
	}

	static function getFieldName(field:RecordField):String
	{
		return switch (field.t) {
			case DData | DEnum(_):
				"data_" + field.name;
			case _:
				field.name;
		}
	}

	function doInsertAsync( x : T, cb : Callback<T> ) {
		unsafeExecute(getInsertStatement(x), function (err, rs) {
			if (err != null) {
				cb(err, null);
				return;
			}
			@:privateAccess x._lock = true;
			// If the table just has one key, and it's not set on this object, check for an auto-increment.
			if( table_keys.length == 1 && Reflect.field(x,table_keys[0]) == null ) {
				getCnx().lastInsertId(function (err, id) {
					if (err != null) {
						cb(err, null);
						return;
					}
					Reflect.setField(x,table_keys[0],id);
					addToCache(x);
					cb(null, x);
				});
			}
		});
	}

	function getInsertStatement( x : T ) : String {
		var s = new StringBuf();
		var fields = new List();
		var values = new List();
		var cache = Reflect.field(x,cache_field);
		if (cache == null)
		{
			Reflect.setField(x,cache_field,cache = {});
		}

		for( f in table_infos.fields ) {
			var name = f.name,
			    fieldName = getFieldName(f);
			var v:Dynamic = Reflect.field(x,fieldName);
			if( v != null ) {
				fields.add(quoteField(name));
				switch( f.t ) {
				case DData: v = doUpdateCache(x, name, v);
				default:
				}
				values.add(v);
			} else if( !f.isNull ) {
				// if the field is not defined, give it a default value on insert
				switch( f.t ) {
				case DUInt, DTinyInt, DInt, DSingle, DFloat, DFlags(_), DBigInt, DTinyUInt, DSmallInt, DSmallUInt, DMediumInt, DMediumUInt, DEnum(_):
					Reflect.setField(x, fieldName, 0);
				case DBool:
					Reflect.setField(x, fieldName, false);
				case DTinyText, DText, DString(_), DSmallText, DSerialized:
					Reflect.setField(x, fieldName, "");
				case DSmallBinary, DNekoSerialized, DLongBinary, DBytes(_), DBinary:
					Reflect.setField(x, fieldName, haxe.io.Bytes.alloc(0));
				case DDate, DDateTime, DTimeStamp:
					// default date might depend on database
				case DId, DUId, DBigId, DNull, DInterval, DEncoded, DData:
					// no default value for these
				}
			}

			Reflect.setField(cache, name, v);
		}
		s.add("INSERT INTO ");
		s.add(table_name);
		if (fields.length > 0 || getCnx().dbName() != "SQLite")
		{
			s.add(" (");
			s.add(fields.join(","));
			s.add(") VALUES (");
			var first = true;
			for( v in values ) {
				if( first )
					first = false;
				else
					s.add(", ");
				getCnx().addValue(s,v);
			}
			s.add(")");
		} else {
			s.add(" DEFAULT VALUES");
		}
		return s.toString();
	}

	inline function isBinary( t : RecordInfos.RecordType ) {
		return switch( t ) {
			case DSmallBinary, DNekoSerialized, DLongBinary, DBytes(_), DBinary: true;
			//case DData: true // -- disabled for implementation purposes
			default: false;
		};
	}

	inline function hasBinaryChanged( a : haxe.io.Bytes, b : haxe.io.Bytes ) {
		return a != b && (a == null || b == null || a.compare(b) != 0);
	}

	function doUpdateAsync( x : T, cb : Callback<T> ) {
		if( @:privateAccess !x._lock )
			throw "Cannot update a not locked object";
		var upd = getUpdateStatement(x);
		if (upd == null) return;
		unsafeExecute(upd, function (err, rs) {
			if (err != null) {
				cb(err, null);
				return;
			}
			cb(null, x);
		});
	}

	function getUpdateStatement( x : T ):Null<String> {
		var s = new StringBuf();
		s.add("UPDATE ");
		s.add(table_name);
		s.add(" SET ");
		var cache = Reflect.field(x,cache_field);
		var mod = false;
		for( f in table_infos.fields ) {
			if (table_keys.indexOf(f.name) >= 0)
				continue;
			var name = f.name,
			    fieldName = getFieldName(f);
			var v : Dynamic = Reflect.field(x,fieldName);
			var vc : Dynamic = Reflect.field(cache,name);
			if( cache == null || v != vc ) {
				switch( f.t ) {
				case DSmallBinary, DNekoSerialized, DLongBinary, DBytes(_), DBinary:
					if ( !hasBinaryChanged(v,vc) )
						continue;
				case DData:
					v = doUpdateCache(x, name, v);
					if( !hasBinaryChanged(v,vc) )
						continue;
				default:
				}
				if( mod )
					s.add(", ");
				else
					mod = true;
				s.add(quoteField(name));
				s.add(" = ");
				getCnx().addValue(s,v);
				if ( cache != null )
					Reflect.setField(cache,name,v);
			}
		}
		if( !mod )
			return null;
		s.add(" WHERE ");
		addKeys(s,x);
		return s.toString();
	}

	function doDeleteAsync( x : T, cb : CompletionCallback ) {
		unsafeExecute(getDeleteStatement(x), function (err, _) {
			if (err != null) {
				cb(err);
				return;
			}
			removeFromCache(x);
			cb(null);
		});
	}

	function getDeleteStatement( x : T ) : String {
		var s = new StringBuf();
		s.add("DELETE FROM ");
		s.add(table_name);
		s.add(" WHERE ");
		addKeys(s,x);
		return s.toString();
	}

	function doLockAsync( i : T, cb : CompletionCallback ) {
		if( @:privateAccess i._lock ) {
			cb(null);
			return;
		}
		var s = new StringBuf();
		s.add("SELECT * FROM ");
		s.add(table_name);
		s.add(" WHERE ");
		addKeys(s, i);
		// will force sync
		unsafeObjectAsync(s.toString(), true, function (err, o) {
			if (err != null) {
				cb(err);
				return;
			}
			if (o != i) {
				cb("Could not lock object - perhaps it was deleted? Try restarting transaction.");
				return;
			}
			cb(null);
		});
	}

	function objectToString( it : T ) : String {
		var s = new StringBuf();
		s.add(table_name);
		if( table_keys.length == 1 ) {
			s.add("#");
			s.add(Reflect.field(it,table_keys[0]));
		} else {
			s.add("(");
			var first = true;
			for( f in table_keys ) {
				if( first )
					first = false;
				else
					s.add(",");
				s.add(quoteField(f));
				s.add(":");
				s.add(Reflect.field(it,f));
			}
			s.add(")");
		}
		return s.toString();
	}

	function doSerialize( field : String, v : Dynamic ) : haxe.io.Bytes {
		var s = new haxe.Serializer();
		s.useEnumIndex = true;
		s.serialize(v);
		var str = s.toString();
		#if neko
		return neko.Lib.bytesReference(str);
		#else
		return haxe.io.Bytes.ofString(str);
		#end
	}

	function doUnserialize( field : String, b : haxe.io.Bytes ) : Dynamic {
		if( b == null )
			return null;
		var str;
		#if neko
		str = neko.Lib.stringReference(b);
		#else
		str = b.toString();
		#end
		if( str == "" )
			return null;
		return haxe.Unserializer.run(str);
	}

	/* ---------------------------- INTERNAL API -------------------------- */

	function normalizeCache(x:CacheType<T>)
	{
		for (f in Reflect.fields(x) )
		{
			var val:Dynamic = Reflect.field(x,f), info = table_infos.hfields.get(f);
			if (info != null)
			{
				if (val != null) switch (info.t) {
					case DDate, DDateTime if (!Std.is(val,Date)):
						if (Std.is(val,Float))
						{
							val = Date.fromTime(val);
						} else {
							var v = val + "";
							var index = v.indexOf('.');
							if (index >= 0)
								v = v.substr(0,index);
							val = Date.fromString(v);
						}
					case DSmallBinary, DLongBinary, DBinary, DBytes(_), DData if (Std.is(val, String)):
						val = haxe.io.Bytes.ofString(val);
					case DString(_) | DTinyText | DSmallText | DText if(!Std.is(val,String)):
						val = val + "";
#if (cs && erase_generics)
					// on C#, SQLite Ints are returned as Int64
					case DInt if (!Std.is(val,Int)):
						val = cast(val,Int);
#end
					case DBool if (!Std.is(val,Bool)):
						if (Std.is(val,Int))
							val = val != 0;
						else if (Std.is(val, String)) switch (val.toLowerCase()) {
							case "1", "true": val = true;
							case "0", "false": val = false;
						}
					case DFloat if (Std.is(val,String)):
						val = Std.parseFloat(val);
					case _:
				}
				Reflect.setField(x, f, val);
			}
		}
	}

	function cacheObject( x : T, lock : Bool ) {
		#if neko
		var o = untyped __dollar__new(x);
		untyped __dollar__objsetproto(o, class_proto.prototype);
		#else
		var o : T = Type.createEmptyInstance(cast class_proto);
		@:privateAccess o._manager = this;
		#end
		normalizeCache(x);
		for (f in Reflect.fields(x) )
		{
			var val:Dynamic = Reflect.field(x,f), info = table_infos.hfields.get(f);
			if (info != null)
			{
				var fieldName = getFieldName(info);
				Reflect.setField(o, fieldName, val);
			}
		}
		Reflect.setField(o,cache_field,x);
		addToCache(o);
		@:privateAccess o._lock = lock;
		return o;
	}

	function quoteField(f : String) {
		return KEYWORDS.exists(f.toLowerCase()) ? "`"+f+"`" : f;
	}

	function addKeys( s : StringBuf, x : {} ) {
		var first = true;
		for( k in table_keys ) {
			if( first )
				first = false;
			else
				s.add(" AND ");
			s.add(quoteField(k));
			s.add(" = ");
			var f = Reflect.field(x,k);
			if( f == null )
				throw ("Missing key "+k);
			getCnx().addValue(s,f);
		}
	}

	function unsafeExecute( sql : String, cb : ResultSetCallback ) {
		getCnx().request(sql, cb);
	}

	function unsafeObjectAsync( sql : String, lock : Bool, cb : Callback<T> ) {
		if( lock != false ) {
			lock = true;
			sql += getLockMode();
		}
		unsafeExecute(sql, function (err, r) {
			if (err != null) {
				cb(err, null);
				return;
			}
			var r = r.hasNext() ? r.next() : null;
			if( r == null )
				return null;
			normalizeCache(r);
			var c = getFromCache(r,lock);
			if( c != null ) {
				cb(null, c);
				return;
			}
			r = cacheObject(r,lock);
			cb(null, r);
		});
	}

	public function unsafeObjectsAsync( sql : String, lock : Bool, cb : Callback<List<T>> ) {
		if( lock != false ) {
			lock = true;
			sql += getLockMode();
		}
		unsafeExecute(sql, function (err, rs) {
			if (err != null) {
				cb(err, null);
				return;
			}
			var l = rs.results();
			var l2 = new List<T>();
			for( x in l ) {
				normalizeCache(x);
				var c = getFromCache(x,lock);
				if( c != null )
					l2.add(c);
				else {
					x = cacheObject(x,lock);
					l2.add(x);
				}
			}
			cb(null, l2);
		});
	}

	public function unsafeCountAsync( sql : String, cb : Callback<Int> ) {
		unsafeExecute(sql, function (err, rs) {
			if (err != null) {
				cb(err, null);
				return;
			}
			cb(null, rs.getIntResult(0));
		});
	}

	public function unsafeDeleteAsync( sql : String, cb : CompletionCallback ) {
		unsafeExecute(sql, function (err, _) cb(err));
	}

	public function unsafeGetAsync( id : Dynamic, ?lock : Bool, cb : Callback<T> ) {
		if( lock == null ) lock = true;
		if( table_keys.length != 1 ) {
			cb("Invalid number of keys", null);
			return;
		}
		if( id == null ) {
			cb(null, null);
			return;
		}
		var x : Dynamic = getFromCacheKey(Std.string(id) + table_name);
		if( x != null && (!lock || x._lock) ) {
			cb(null, x);
			return;
		}
		unsafeObjectAsync(getGetStatement(id), lock, cb);
	}

	function getGetStatement( id : Dynamic ) : String {
		var s = new StringBuf();
		s.add("SELECT * FROM ");
		s.add(table_name);
		s.add(" WHERE ");
		s.add(quoteField(table_keys[0]));
		s.add(" = ");
		getCnx().addValue(s,id);
		return s.toString();
	}

	public function unsafeGetWithKeysAsync( keys : { }, ?lock : Bool, cb : Callback<T> ) {
		if( lock == null ) lock = true;
		var x : Dynamic = getFromCacheKey(makeCacheKey(cast keys));
		if( x != null && (!lock || x._lock) ) {
			cb(null, x);
			return;
		}
		unsafeObjectAsync(getGetWithKeyStatement(keys),lock, cb);
	}

	function getGetWithKeyStatement( keys : { } ) : String {
		var s = new StringBuf();
		s.add("SELECT * FROM ");
		s.add(table_name);
		s.add(" WHERE ");
		addKeys(s,keys);
		return s.toString();
	}

	public function unsafeGetId( o : T ) : Dynamic {
		return o == null ? null : Reflect.field(o, table_keys[0]);
	}

	static function getNullComparison( dbName : String, a : String, b : String, eq : Bool ) {
		if (a == null || a == 'NULL') {
			return eq ? '$b IS NULL' : '$b IS NOT NULL';
		} else if (b == null || b == 'NULL') {
			return eq ? '$a IS NULL' : '$a IS NOT NULL';
		}
		// we can't use a null-safe operator here
		if( dbName != "MySQL" )
			return a + (eq ? " = " : " != ") + b;
		var sql = a+" <=> "+b;
		if( !eq ) sql = "NOT("+sql+")";
		return sql;
	}

	function addCondition(s : StringBuf,x) {
		var first = true;
		if( x != null )
			for( f in Reflect.fields(x) ) {
				if( first )
					first = false;
				else
					s.add(" AND ");
				s.add(quoteField(f));
				var d = Reflect.field(x,f);
				if( d == null )
					s.add(" IS NULL");
				else {
					s.add(" = ");
					getCnx().addValue(s,d);
				}
			}
		if( first )
			s.add("TRUE");
	}

	/* --------------------------- MISC API  ------------------------------ */

	public function dbClass() : Class<Dynamic> {
		return cast class_proto;
	}

	public function dbInfos() {
		return table_infos;
	}

	function getCnx() : AsyncConnection {
		return throw 'BaseManager should not be used directly, please use a subclass that implements getCnx()';
	}

	function getLockMode() : String {
		return throw 'BaseManager should not be used directly, please use a subclass that implements getLockMode()';
	}

	/**
		Remove the cached value for the given Object field : this will ensure
		that the value is updated when calling .update(). This is necessary if
		you are modifying binary data in-place since the cache will be modified
		as well.
	**/
	public function forceUpdate( o : T, field : String ) {
		// set a reference that will ensure != and .compare() != 0
		Reflect.setField(Reflect.field(o,cache_field),field,null);
	}

	/* --------------------------- INIT / CLEANUP ------------------------- */

	// TODO: remove this function and replace it with a cross-platform compile-time check.
	// It's purpose is to check that any relations are to correctly configured tables.
	// However, the check is only applied on Neko and it only occurs at runtime, not compiletime.
	public static function initialize() {
		var l = init_list;
		init_list = new List();
		for( m in l )
			for( r in m.table_infos.relations )
				m.initRelation(r);
	}

	function initRelation( r : RecordInfos.RecordRelation ) {
		// setup getter/setter
		var spod : Dynamic = Type.resolveClass(r.type);
		if( spod == null ) throw "Missing spod type " + r.type;
		var manager : Manager<Dynamic> = spod.manager;
		if( manager == null || manager.table_keys == null ) throw ("Invalid manager for relation "+table_name+":"+r.prop);
		if( manager.table_keys.length != 1 ) throw ("Relation " + r.prop + "(" + r.key + ") on a multiple key table");
	}

	function __get( x : Dynamic, prop : String, key : String, lock ) {
		var v = Reflect.field(x,prop);
		if( v != null )
			return v;
		var y = null;
		unsafeGetAsync(Reflect.field(x, key), lock, function (err, obj) {
			if (err != null) {
				throw err;
				return;
			}
			y = obj;
			Reflect.setField(x,prop,v);
		});
		if (y == null && !Std.is(getCnx(), AsyncConnection.AsyncConnectionWrapper)) {
			// Because this is called in a `get` getter function, there is no way we can use an async callback.
			// Supporting relationships via properties seamlessly may not be possible when using an async manager.
			throw 'Seamless fetching of @:relation related objects is not supported with AsyncConnections';
		}
		return y;
	}

	function __set( x : Dynamic, prop : String, key : String, v : T ) {
		Reflect.setField(x,prop,v);
		if( v == null )
			Reflect.setField(x,key,null);
		else
			Reflect.setField(x,key,Reflect.field(v,table_keys[0]));
		return v;
	}

	/* ---------------------------- OBJECT CACHE -------------------------- */

	function getObjectCache():Map<String, Object> {
		return throw 'BaseManager should not be used directly, please use a subclass that implements getObjectCache()';
	}

	function makeCacheKey( x : T ) : String {
		if( table_keys.length == 1 ) {
			var k = Reflect.field(x,table_keys[0]);
			if( k == null )
				throw("Missing key "+table_keys[0]);
			return Std.string(k)+table_name;
		}
		var s = new StringBuf();
		for( k in table_keys ) {
			var v = Reflect.field(x,k);
			if( k == null )
				throw("Missing key "+k);
			s.add(v);
			s.add("#");
		}
		s.add(table_name);
		return s.toString();
	}

	function addToCache( x : CacheType<T> ) {
		getObjectCache().set(makeCacheKey(x),x);
	}

	function removeFromCache( x : CacheType<T> ) {
		getObjectCache().remove(makeCacheKey(x));
	}

	function getFromCacheKey( key : String ) : T {
		return cast getObjectCache().get(key);
	}

	function getFromCache( x : CacheType<T>, lock : Bool ) : T {
		var c : Dynamic = getObjectCache().get(makeCacheKey(x));
		if( c != null && lock && !c._lock ) {
			// synchronize the fields since our result is up-to-date !
			for( f in Reflect.fields(c) )
				Reflect.deleteField(c,f);
			for (f in table_infos.fields)
			{
				var name = f.name,
				    fieldName = getFieldName(f);
				Reflect.setField(c,fieldName,Reflect.field(x,name));
			}
			// mark as locked
			c._lock = true;
			// restore our manager
			#if !neko
			@:privateAccess c._manager = this;
			#end
			// use the new object as our cache of fields
			Reflect.setField(c,cache_field,x);
		}
		return c;
	}

	// We need Bytes.toString to not be DCE'd. See #1937
	@:keep static function __depends() { return haxe.io.Bytes.alloc(0).toString(); }
}

private typedef CacheType<T> = Dynamic;
