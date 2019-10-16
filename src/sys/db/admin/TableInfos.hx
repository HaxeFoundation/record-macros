/*
 * Copyright (c)2012 Nicolas Cannasse
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 * LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
package sys.db.admin;

import sys.db.Object;
import sys.db.Manager;

typedef TableType = sys.db.RecordInfos.RecordType;

typedef ManagerAccess = {
	private var table_name : String;
	private var table_keys : Array<String>;
	private function quote( v : Dynamic ) : String;
	private function quoteField( f : String ) : String;
	private function addKeys( s : StringBuf, x : {} ) : Void;
	function all( ?lock : Bool ) : List<Object>;
	function dbClass() : Class<Dynamic>;
}

private typedef TableRelation = {
	var prop : String;
	var key : String;
	var lock : Bool;
	var manager : ManagerAccess;
	var className : String;
	var cascade : Bool;
}

class TableInfos {

	public static var ENGINE = "InnoDB";
	public static var OLD_COMPAT = false; // only set for old DBs !

	public var primary(default,null) : List<String>;
	public var cl(default,null) : Class<Object>;
	public var name(default,null) : String;
	public var className(default,null) : String;
	public var hfields(default,null) : Map<String,TableType>;
	public var fields(default,null) : List<{ name : String, type : TableType }>;
	public var nulls(default,null) : Map<String,Bool>;
	public var relations(default,null) : Array<TableRelation>;
	public var indexes(default,null) : List<{ keys : List<String>, unique : Bool }>;
	public var manager : Manager<Object>;

	public function new( cname : String ) {
		hfields = new Map();
		fields = new List();
		nulls = new Map();
		cl = cast Type.resolveClass("db."+cname);
		if( cl == null )
			cl = cast Type.resolveClass(cname);
		else
			cname = "db."+cname;
		if( cl == null )
			throw "Class not found : "+cname;
		manager = untyped cl.manager;
		if( manager == null )
			throw "No static manager for "+cname;
		className = cname;
		if( className.substr(0,3) == "db." ) className = className.substr(3);
		var a = cname.split(".");
		name = a.pop();
		processClass();
	}

	function processClass() {
		var rtti = haxe.rtti.Meta.getType(cl).rtti;
		if( rtti == null )
			throw "Class "+name+" does not have RTTI";
		var infos : sys.db.RecordInfos = haxe.Unserializer.run(rtti[0]);
		name = infos.name;
		primary = Lambda.list(infos.key);
		for( f in infos.fields ) {
			fields.add({ name : f.name, type : f.t });
			hfields.set(f.name, f.t);
			if( f.isNull ) nulls.set(f.name, true);
		}
		relations = new Array();
		for( r in infos.relations ) {
			var t = Type.resolveClass(r.type);
			if( t == null ) throw "Missing type " + r.type + " for relation " + name + "." + r.prop;
			var manager : ManagerAccess = Reflect.field(t, "manager");
			if( manager == null ) throw r.type + " does not have a static field manager";
			relations.push( { prop : r.prop, key : r.key, lock : r.lock, manager : manager, className : Type.getClassName(manager.dbClass()), cascade : r.cascade } );
		}
		indexes = new List();
		for( i in infos.indexes )
			indexes.push( { keys : Lambda.list(i.keys), unique : i.unique } );
	}

	function escape( name : String ) {
		var m : ManagerAccess = manager;
		return m.quoteField(name);
	}

	public static function unescape( field : String ) {
		if( field.length > 1 && field.charAt(0) == '`' && field.charAt(field.length-1) == '`' )
			return field.substr(1,field.length-2);
		return field;
	}

	public function isRelationActive( r : Dynamic ) {
		return true;
	}

	public function createRequest( full : Bool ) {
		var str = "CREATE TABLE "+escape(name)+" (\n";
		var keys = fields.iterator();
		for( f in keys ) {
			str += escape(f.name)+" "+fieldInfos(f);
			if( keys.hasNext() )
				str += ",";
			str += "\n";
		}
		if( primary != null )
			str += ", PRIMARY KEY ("+primary.map(escape).join(",")+")\n";
		if( full ) {
			for( r in relations )
				if( isRelationActive(r) )
					str += ", "+relationInfos(r);
			for( i in indexes )
				str += ", "+(if( i.unique ) "UNIQUE " else "")+"KEY "+escape(name+"_"+i.keys.join("_"))+"("+i.keys.map(escape).join(",")+")\n";
		}
		str += ")";
		if( ENGINE != null )
			str += " ENGINE="+ENGINE;
		return str;
	}

	function relationInfos(r : TableRelation) {
		if( r.manager.table_keys.length != 1 )
			throw "Relation on a multiple-keys table";
		var rq = "CONSTRAINT "+escape(name+"_"+r.prop)+" FOREIGN KEY ("+escape(r.key)+") REFERENCES "+escape(r.manager.table_name)+"("+escape(r.manager.table_keys[0])+") ";
		rq += "ON DELETE "+(if( nulls.get(r.key) && r.cascade != true ) "SET NULL" else "CASCADE")+"\n";
		return rq;
	}

	function fieldInfos(f) {
		return (switch( f.type ) {
		case DId: "INT AUTO_INCREMENT";
		case DUId: "INT UNSIGNED AUTO_INCREMENT";
		case DInt, DEncoded: "INT";
		case DFlags(fl, auto): auto ? (fl.length <= 8 ? "TINYINT UNSIGNED" : (fl.length <= 16 ? "SMALLINT UNSIGNED" : (fl.length <= 24 ? "MEDIUMINT UNSIGNED" : "INT"))) : "INT";
		case DTinyInt: "TINYINT";
		case DUInt: "INT UNSIGNED";
		case DSingle: "FLOAT";
		case DFloat: "DOUBLE";
		case DBool: "TINYINT(1)";
		case DString(n): "VARCHAR("+n+")";
		case DDate: "DATE";
		case DDateTime: "DATETIME";
		case DTimeStamp: "TIMESTAMP"+(nulls.exists(f.name) ? " NULL DEFAULT NULL" : " DEFAULT 0");
		case DTinyText: "TINYTEXT";
		case DSmallText: "TEXT";
		case DText, DSerialized: "MEDIUMTEXT";
		case DSmallBinary: "BLOB";
		case DBinary, DNekoSerialized: "MEDIUMBLOB";
		case DData: "MEDIUMBLOB";
		case DEnum(_): "TINYINT UNSIGNED";
		case DLongBinary: "LONGBLOB";
		case DBigInt: "BIGINT";
		case DBigId: "BIGINT AUTO_INCREMENT";
		case DBytes(n): "BINARY(" + n + ")";
		case DTinyUInt: "TINYINT UNSIGNED";
		case DSmallInt: "SMALLINT";
		case DSmallUInt: "SMALLINT UNSIGNED";
		case DMediumInt: "MEDIUMINT";
		case DMediumUInt: "MEDIUMINT UNSIGNED";
		case DNull, DInterval: throw "assert";
		}) + if( nulls.exists(f.name) ) "" else " NOT NULL";
	}

	public function dropRequest() {
		return "DROP TABLE "+escape(name);
	}

	public function truncateRequest() {
		return "TRUNCATE TABLE "+escape(name);
	}

	public function descriptionRequest() {
		return "SHOW CREATE TABLE "+escape(name);
	}

	public function existsRequest() {
		return "SELECT * FROM "+escape(name)+" LIMIT 0";
	}

	public static function countRequest( m : ManagerAccess, max : Int ) {
		return "SELECT " + m.quoteField(m.table_keys[0]) + " FROM " + m.quoteField(m.table_name) + " LIMIT " + max;
	}

	public function addFieldRequest( fname : String ) {
		var ftype = hfields.get(fname);
		if( ftype == null )
			throw "No field "+fname;
		var rq = "ALTER TABLE "+escape(name)+" ADD ";
		return rq + escape(fname)+" "+fieldInfos({ name : fname, type : ftype });
	}

	public function removeFieldRequest( fname : String ) {
		return "ALTER TABLE "+escape(name)+" DROP "+escape(fname);
	}

	public function renameFieldRequest( old : String, newname : String ) {
		var ftype = hfields.get(newname);
		if( ftype == null )
			throw "No field "+newname;
		var rq = "ALTER TABLE "+escape(name)+" CHANGE "+escape(old)+" ";
		return rq + escape(newname) + " " + fieldInfos({ name : newname, type : ftype });
	}

	public function updateFieldRequest( fname : String ) {
		var ftype = hfields.get(fname);
		if( ftype == null )
			throw "No field "+fname;
		var rq = "ALTER TABLE "+escape(name)+" MODIFY ";
		return rq + escape(fname)+" "+fieldInfos({ name : fname, type : ftype });
	}

	public function addRelationRequest( key : String, prop : String ) {
		for( r in relations )
			if( r.key == key && r.prop == prop )
				return "ALTER TABLE "+escape(name)+" ADD "+relationInfos(r);
		return throw "No such relation : "+prop+"("+key+")";
	}

	public function deleteRelationRequest( rel : String ) {
		return "ALTER TABLE "+escape(name)+" DROP FOREIGN KEY "+escape(rel);
	}

	public function indexName( idx : Array<String> ) {
		return name+"_"+idx.join("_");
	}

	public function addIndexRequest( idx : Array<String>, unique : Bool ) {
		var eidx = new Array();
		for( i in idx ) {
			var k = escape(i);
			var f = hfields.get(i);
			if( f != null )
			switch( f ) {
			case DTinyText, DSmallText, DText, DSmallBinary, DLongBinary, DBinary:
				k += "(4)"; // index size
			default:
			}
			eidx.push(k);
		}
		return "ALTER TABLE "+escape(name)+" ADD "+(if( unique ) "UNIQUE " else "")+"INDEX "+escape(indexName(idx))+"("+eidx.join(",")+")";
	}

	public function deleteIndexRequest( idx : String ) {
		return "ALTER TABLE "+escape(name)+" DROP INDEX "+escape(idx);
	}

	public function updateFields( o : {}, fields : List<{ name : String, value : Dynamic }> ) {
		var me = this;
		var s = new StringBuf();
		s.add("UPDATE ");
		s.add(escape(name));
		s.add(" SET ");
		var first = true;
		for( f in fields ) {
			if( first )
				first = false;
			else
				s.add(", ");
			s.add(escape(f.name));
			s.add(" = ");
			Manager.cnx.addValue(s,f.value);
		}
		s.add(" WHERE ");
		var m : ManagerAccess = manager;
		m.addKeys(s,o);
		return s.toString();
	}

	public function identifier( o : Object ) : String {
		if( primary == null )
			throw "No primary key";
		return primary.map(function(p) { return Std.string(Reflect.field(o,p)).split(".").join("~"); }).join("@");
	}

	public function fromIdentifier( id : String ) : Object {
		var ids = id.split("@");
		if( primary == null )
			throw "No primary key";
		if( ids.length != primary.length )
			throw "Invalid identifier";
		var keys = {};
		for( p in primary )
			Reflect.setField(keys, p, makeNativeValue(hfields.get(p), ids.shift().split("~").join(".")));
		return manager.unsafeGetWithKeys(keys);
	}

	function makeNativeValue( t : TableType, v : String ) : Dynamic {
		return switch( t ) {
		case DInt, DUInt, DId, DUId, DEncoded, DFlags(_), DTinyInt: cast Std.parseInt(v);
		case DTinyUInt, DSmallInt, DSmallUInt, DMediumUInt, DMediumInt: cast Std.parseInt(v);
		case DFloat, DSingle, DBigInt, DBigId: cast Std.parseFloat(v);
		case DDate, DDateTime, DTimeStamp: cast Date.fromString(v);
		case DBool: cast (v == "true");
		case DText, DString(_), DSmallText, DTinyText, DBinary, DSmallBinary, DLongBinary, DSerialized, DNekoSerialized, DBytes(_): cast v;
		case DData: cast v;
		case DEnum(_): cast v;
		case DNull, DInterval: throw "assert";
		};
	}

	public function fromSearch( params : Map<String,String>, order : String, pos : Int, count : Int ) : List<Object> {
		var rop = ~/^([<>]=?)(.+)$/;
		var cond = "TRUE";
		var m : ManagerAccess = manager;
		for( p in params.keys() ) {
			var f = hfields.get(p);
			var v = params.get(p);
			if( f == null )
				continue;
			cond += " AND " + escape(p);
			if( v == null || v == "NULL" )
				cond += " IS NULL";
			else switch( f ) {
			case DEncoded:
				cond += " = "+(try Id.encode(v) catch( e : Dynamic ) 0);
			case DString(_),DTinyText,DSmallText,DText:
				cond += " LIKE "+m.quote(v);
			case DBool:
				cond += " = "+((v == "true") ? 1 : 0);
			case DId,DUId,DInt,DUInt,DSingle,DFloat,DDate,DDateTime,DBigInt,DBigId:
				if( rop.match(v) )
					cond += " "+rop.matched(1)+" "+m.quote(rop.matched(2));
				else
					cond += " = "+m.quote(v);
			default:
				cond += " = "+m.quote(v);
			}
		}
		if( order != null ) {
			if( order.charAt(0) == "-" )
				cond += " ORDER BY "+escape(order.substr(1))+" DESC";
			else
				cond += " ORDER BY "+escape(order);
		}

		var sql = "SELECT * FROM " + escape(name) + " WHERE " + cond + " LIMIT " + pos + "," + count;
		return manager.unsafeObjects(sql, false);
	}

	static function fromTypeDescription( desc : String ) {
		var fdesc = desc.toUpperCase().split(" ");
		var ftype = fdesc.shift();
		var tparam = ~/^([A-Za-z]+)\(([0-9]+)\)$/;
		var param = null;
		if( tparam.match(ftype) ) {
			ftype = tparam.matched(1);
			param = Std.parseInt(tparam.matched(2));
		}
		var nullable = true;
		var t = switch( ftype ) {
		case "VARCHAR","CHAR":
			if( param == null )
				null;
			else
				DString(param);
		case "INT":
			if( param == 11 && fdesc.remove("AUTO_INCREMENT") )
				DId
			else if( param == 10 && fdesc.remove("UNSIGNED") ) {
				if( fdesc.remove("AUTO_INCREMENT") )
					DUId
				else
					DUInt;
			} else if( param == 11 )
				DInt;
			else
				null;
		case "BIGINT":
			if( fdesc.remove("AUTO_INCREMENT") ) DBigId else DBigInt;
		case "DOUBLE": DFloat;
		case "FLOAT": DSingle;
		case "DATE": DDate;
		case "DATETIME": DDateTime;
		case "TIMESTAMP": DTimeStamp;
		case "TINYTEXT": DTinyText;
		case "TEXT": DSmallText;
		case "MEDIUMTEXT": DText;
		case "BLOB": DSmallBinary;
		case "MEDIUMBLOB": DBinary;
		case "LONGBLOB": DLongBinary;
		case "TINYINT":
			switch( param ) {
			case 1:
				fdesc.remove("UNSIGNED");
				DBool;
			case 4:
				DTinyInt;
			case 3:
				if( fdesc.remove("UNSIGNED") ) DTinyUInt else null;
			default:
				if( OLD_COMPAT )
					DInt;
				else
					null;
			}
		case "SMALLINT":
			fdesc.remove("UNSIGNED") ? DSmallUInt : DSmallInt;
		case "MEDIUMINT":
			fdesc.remove("UNSIGNED") ? DMediumUInt : DMediumInt;
		case "BINARY":
			if( param == null )
				null;
			else
				DBytes(param);
		default:
			null;
		}
		if( t == null )
			return null;
		while( fdesc.length > 0  ) {
			var d = fdesc.shift();
			switch( d ) {
			case "NOT":
				if( fdesc.shift() != "NULL" )
					return null;
				nullable = false;
			case "DEFAULT":
				var v = fdesc.shift();
				if( nullable ) {
					if( v == "NULL" )
						continue;
					return null;
				}
				var def = switch( t ) {
				case DId, DUId, DInt, DUInt, DBool, DSingle, DFloat, DEncoded, DBigInt, DBigId, DFlags(_), DTinyInt: "'0'";
				case DTinyUInt, DSmallInt, DSmallUInt, DMediumUInt, DMediumInt: "'0'";
				case DTinyText, DText, DString(_), DSmallText, DSerialized: "''";
				case DDateTime,DTimeStamp:
					if( v.length > 0 && v.charAt(v.length-1) != "'" )
						v += " "+fdesc.shift();
					"'0000-00-00 00:00:00'";
				case DDate: "'0000-00-00'";
				case DSmallBinary, DBinary, DLongBinary, DNekoSerialized, DBytes(_), DNull, DInterval: null;
				case DData: null;
				case DEnum(_): "'0'";
				}
				if( v != def && !OLD_COMPAT )
					return null;
			case "NULL":
				if( !nullable ) return null;
				nullable = true;
				continue;
			default:
				return null;
			}
		}
		return { t : t, nullable : nullable };
	}

	public static function fromDescription( desc : String ) {
		var r = ~/^CREATE TABLE `([^`]*)` \((.*)\)( ENGINE=([^ ]+))?( AUTO_INCREMENT=[^ ]+)?( DEFAULT CHARSET=.*)?$/sm;
		if( !r.match(desc) )
			throw "Invalid "+desc;
		var tname = r.matched(1);
		if( r.matched(4).toUpperCase() != "INNODB" )
			throw "Table "+tname+" should be INNODB";
		var matches = r.matched(2).split(",\n");
		var field_r = ~/^[ \r\n]*`(.*)` (.*)$/;
		var primary_r = ~/^[ \r\n]*PRIMARY KEY +\((.*)\)[ \r\n]*$/;
		var index_r = ~/^[ \r\n]*(UNIQUE )?KEY `(.*)` \((.*)\)[ \r\n]*$/;
		var foreign_r = ~/^[ \r\n]*CONSTRAINT `(.*)` FOREIGN KEY \(`(.*)`\) REFERENCES `(.*)` \(`(.*)`\) ON DELETE (SET NULL|CASCADE)[ \r\n]*$/;
		var index_key_r = ~/^`?(.*?)`?(\([0-9+]\))?$/;
		var fields = new Map();
		var nulls = new Map();
		var indexes = new Map();
		var relations = new Array();
		var primary = null;
		for( f in matches ) {
			if( field_r.match(f) ) {
				var fname = field_r.matched(1);
				var ftype = fromTypeDescription(field_r.matched(2));
				if( ftype == null )
					throw "Unknown description '"+field_r.matched(2)+"'";
				fields.set(fname,ftype.t);
				if( ftype.nullable )
					nulls.set(fname,true);
			} else if( primary_r.match (f) ) {
				if( primary != null )
					throw "Duplicate primary key";
				primary = primary_r.matched(1).split(",");
				for( i in 0...primary.length ) {
					var k = unescape(primary[i]);
					primary[i] = k;
				}
			} else if( index_r.match(f) ) {
				var unique = index_r.matched(1);
				var idxname = index_r.matched(2);
				var fs = Lambda.list(index_r.matched(3).split(","));
				indexes.set(idxname,{ keys : fs.map(function(r) {
					if( !index_key_r.match(r) ) throw "Invalid index key "+r;
					return index_key_r.matched(1);
				}), unique : unique != "" && unique != null, name : idxname });
			} else if( foreign_r.match(f) ) {
				var name = foreign_r.matched(1);
				var key = foreign_r.matched(2);
				var table = foreign_r.matched(3);
				table = table.substr(0,1).toUpperCase() + table.substr(1); // hack for MySQL on windows
				var id = foreign_r.matched(4);
				var setnull = if( foreign_r.matched(5) == "SET NULL" ) true else null;
				relations.push({ name : name, key : key, table : table, id : id, setnull : setnull });
			} else
				throw "Invalid "+f+" in "+desc;
		}
		return {
			table : tname,
			fields : fields,
			nulls : nulls,
			indexes : indexes,
			relations : relations,
			primary : primary,
		};
	}

	public static function sameDBStorage( dt : TableType, rt : TableType ) {
		return switch( rt ) {
		case DEncoded: dt == DInt;
		case DFlags(fl, auto): auto ? (fl.length <= 8 ? dt == DTinyUInt : (fl.length <= 16 ? dt == DSmallUInt : (fl.length <= 24 ? dt == DMediumUInt : dt == DInt))) : (dt == DInt);
		case DSerialized: (dt == DText);
		case DNekoSerialized: (dt == DBinary);
		case DData: dt == DBinary;
		case DEnum(_): dt == DTinyUInt;
		default: false;
		};
	}

	public static function allTablesRequest() {
		return "SHOW TABLES";
	}

}

