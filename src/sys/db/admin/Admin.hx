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
import sys.db.Types;

import sys.db.admin.Custom;
import sys.db.admin.TableInfos.TableType;
import sys.db.admin.TableInfos.ManagerAccess;
#if neko
import neko.Lib;
import neko.Web;
#elseif php 
import php.Lib;
import php.Web;
#end

@:access(sys.db.Manager)
class Admin {

	var style : AdminStyle;
	var hasSyncAction : Bool;
	var countCache : Map<String,Bool>;
	public var allowDrop : Bool;
	public var default_rights : RightsInfos;
	public var maxUploadSize : Int;
	public var maxInstanceCount : Int;

	public function new() {
		maxInstanceCount = 100;
		maxUploadSize = 1000000;
		allowDrop = false;
		countCache = new Map();
		default_rights = {
			can : {
				insert : true,
				delete : true,
				modify : true,
				truncate : false,
			},
			invisible : [],
			readOnly : [],
		};
	}

	function execute(sql) {
		return Manager.cnx.request(sql);
	}

	function request( t : TableInfos, sql ) {
		return Manager.cnx.request(sql);
	}

	function boolResult(sql) {
		try {
			execute(sql);
			return true;
		} catch( e : Dynamic ) {
			return false;
		}
	}

	function getTables():Array<sys.db.admin.TableInfos> {
		var tables = new Array();
		var classes = Lib.getClasses();
		crawl(tables, classes);
		tables.sort(function(t1,t2) { return if( t1.name > t2.name ) 1 else if( t1.name < t2.name ) -1 else 0; });
		return tables;
	}

	function has<T>( a : { function iterator() : Iterator<T>; }, v : T ) {
		for( x in a.iterator() )
			if( x == v )
				return true;
		return false;
	}

	/**
	 * Filter classes who sublass sys.db.Object and get TableInfos
	 */
	function crawl(tables : Array<TableInfos>,classes : Dynamic) {
		for( cname in Reflect.fields(classes) ) {

			var v : Dynamic = Reflect.field(classes,cname);
			var c = cname.charAt(0);
			if( c >= "a" && c <= "z" ) {
				//explore sub packages
				crawl(tables,v);
				continue;
			}
			#if !php
			if( haxe.rtti.Meta.getType(v).rtti == null )
				continue;
			#end
			var s = Type.getSuperClass(v);
			while( s != null ) {
				if( s == sys.db.Object ) {
					tables.push(new TableInfos(Type.getClassName(v)));
					break;
				}
				s = Type.getSuperClass(s);
			}
		}
	}

	public function index( ?errorMsg ) {
		style.begin("Tables");
		style.beginForm("doSync");
		style.beginTable();
		var sync = false;
		var allTables = new List();
		var rq = execute(TableInfos.allTablesRequest());
		for( r in rq ){
			if (rq.getResult(0) == null) continue;
			allTables.add(rq.getResult(0));
		}
		var windows = Sys.systemName() == "Windows";
		for( t in getTables() ) {
			var rights = getRights(createInstance(t));
			style.beginLine(true);
			style.text(t.name);
			style.nextRow();
			if( !boolResult(t.existsRequest()) ) {
				style.linkConfirm(t.className+"/doCreate","create");
				style.text("Table is Missing !");
			} else {
				if( needSync(t) )
					sync = true;
				if( rights.can.insert )
					style.link(t.className+"/insert","insert");
				style.nextRow();
				style.link(t.className+"/search","search");
				if( rights.can.truncate )
					style.linkConfirm(t.className+"/doCleanup","cleanup");
				if( allowDrop ) {
					style.nextRow();
					style.linkConfirm(t.className+"/doDrop","drop");
				}
			}
			style.endLine();
			allTables.remove(t.name);
			if( windows || TableInfos.OLD_COMPAT ) allTables.remove(t.name.toLowerCase());
		}
		style.endTable();
		if( sync )
			style.addSubmit("Synchronize Database",true);
		style.endForm();
		if( !allTables.isEmpty() ) {
			style.beginList();
			for( t in allTables ) {
				style.beginItem();
				style.text('Table "$t" does not have any matching object');
				style.endItem();
			}
			style.endList();
		}
		if( errorMsg != null )
			style.error(errorMsg);
		style.end();
	}

	function isBinary(t) {
		return switch( t ) {
		case DBinary, DSmallBinary, DLongBinary, DBytes(_): true;
		default: false;
		};
	}

	function canDisplay( m : ManagerAccess ) {
		var c = countCache.get(m.table_name);
		if( c != null )
			return c;
		c = execute(TableInfos.countRequest(m,maxInstanceCount)).length < maxInstanceCount;
		countCache.set(m.table_name,c);
		return c;
	}

	function inputField( table : TableInfos, f, id : String, readonly, ?defval : Dynamic, ?rawValue : Bool ) {
		var prim = has(table.primary,f.name);
		var insert = (id == null);
		for( r in table.relations )
			if( r.key == f.name ) {
				var values = null;
				if( canDisplay(r.manager) || r.className == "db.File" )
					values = r.manager.all(false).map(function(d) {
						return {
							id : Std.string(Reflect.field(d,r.manager.table_keys[0])),
							str : d.toString()
						};
					});
				var cname = r.className.substr(0,3) == "db." ? r.className.substr(3) : r.className;
				style.choiceField(
					r.prop,
					values,
					Std.string(defval),
					cname+"/edit/",
					!insert && (prim || readonly),
					r.className == "db.File"
				);
				return;
			}
		if( defval != null && !rawValue ) {
			switch( f.type ) {
			case DEncoded:
				defval = Std.parseInt(Std.string(defval));
				defval = Id.decode(defval);
			case DSerialized:
				defval = new Serialized(defval).escape();
				
			case DNekoSerialized:
				#if neko
				var v = try haxe.Serializer.run(Lib.localUnserialize(defval)) catch( e : Dynamic ) ("ERROR : " + Std.string(e));
				defval = new Serialized(v).escape();
				#else
				throw "DNekoSerialized is only available on neko target";
				#end
			case DData:
				#if haxe3
					var str = try haxe.Serializer.run((untyped table.manager).doUnserialize(f.name, defval)) catch( e : Dynamic ) ("ERROR : " + Std.string(e));
				#else
					var str = defval.toString();
				#end
				defval = new Serialized(str).escape();
			default:
			}
		}
		if( isBinary(f.type) )
			style.binField(f.name,table.nulls.exists(f.name),defval,if( insert ) null else function() { return table.name+"/doDownload/"+id+"/"+f.name; });
		else if( insert && readonly )
			return;
		else if( !insert && (prim || readonly) )
			style.infoField(f.name,defval);
		else
			style.inputField(f.name,f.type,table.nulls.exists(f.name),defval);
	}

	/**
	 * Prints an insert form
	 */
	function insert(table : TableInfos, ?params : Map<String,String>, ?error : String, ?errorMsg : String ) {
		var binary = false;
		for( f in table.fields )
			if( isBinary(f.type) ) {
				binary = true;
				break;
			}
		style.begin("Insert new "+table.name);
		style.beginForm(table.className+"/doInsert",binary,table.name);
		var rights = getRights(table);
		for( f in table.fields ) {
			if( f.name == error ) {
				style.errorField((errorMsg == null) ? "Invalid format" : errorMsg);
				errorMsg = null;
			}
			if( has(rights.invisible,f.name) )
				continue;
			var readonly = has(rights.readOnly,f.name);
			inputField(table,f,null,readonly,if( params == null ) null else params.get(f.name), params != null );
		}
		style.addSubmit("Insert");
		style.addSubmit("Insert New",null,false,"__new");
		style.endForm();
		if( errorMsg != null )
			style.error(errorMsg);
		style.end();
	}

	function updateField( fname : String, v : String, ftype : TableType, table : TableInfos ) : Dynamic {
		switch( ftype ) {
		case DId, DUId, DBigId:
			return null;
		case DDate:
			var d = if( v == "NOW" || v == "NOW()" ) Date.now() else try Date.fromString(v) catch( e : Dynamic ) null;
			if( d == null )
				return null;
			try d.toString() catch( e : Dynamic ) return null;
			return d;
		case DDateTime, DTimeStamp:
			var d = if( v == "NOW" || v == "NOW()" ) Date.now() else try Date.fromString(v) catch( e : Dynamic ) null;
			if( d == null )
				return null;
			try d.toString() catch( e : Dynamic ) return null;
			return d;
		case DInt:
			if( v == "" ) return 0;
			return Std.parseInt(v);
		case DUInt, DFlags(_):
			if( v == "" ) return 0;
			var i = Std.parseInt(v);
			if( i < 0 )
				return null;
			return i;
		case DTinyInt:
			if( v == "" ) return 0;
			var i = Std.parseInt(v);
			if( i < -128 || i > 127 )
				return null;
			return i;
		case DTinyUInt:
			if( v == "" ) return 0;
			var i = Std.parseInt(v);
			if( i < 0 || i > 255 )
				return null;
			return i;
		case DSmallInt:
			if( v == "" ) return 0;
			var i = Std.parseInt(v);
			if( i < -32768 || i > 32767 )
				return null;
			return i;
		case DSmallUInt:
			if( v == "" ) return 0;
			var i = Std.parseInt(v);
			if( i < 0 || i > 65535 )
				return null;
			return i;
		case DMediumInt:
			if( v == "" ) return 0;
			var i = Std.parseInt(v);
			if( i < -8388608 || i > 8388607 )
				return null;
			return i;
		case DMediumUInt:
			if( v == "" ) return 0;
			var i = Std.parseInt(v);
			if( i < 0 || i > 16777215 )
				return null;
			return i;
		case DBigInt:
			if( v == "" ) return 0;
			var i = Std.parseFloat(v);
			if( i == null || i%1 != 0 || i < -9223372036854775808.0 || i > 9223372036854775807.0 )
				return null;
			return i;
		case DFloat, DSingle:
			if( v == "" ) return 0;
			var fl = Std.parseFloat(v);
			if( Math.isNaN(fl) )
				return null;
			return fl;
		case DString(n):
			if( v.length > n )
				return null;
			return v;
		case DTinyText:
			if( v.length > 255 )
				return null;
			return v;
		case DSmallText, DSmallBinary:
			if( v.length > 0xFFFF )
				return null;
			return v;
		case DText, DBinary:
			if( v.length > 0xFFFFFF )
				return null;
			return v;
		case DBytes(n):
			if( v.length > n )
				return null;
			return v;
		case DLongBinary:
			return v;
		case DBool:
			return (v == "true");
		case DEncoded:
			if( v == "" ) return null;
			return try Id.encode(v) catch( e : Dynamic ) null;
		case DSerialized:
			return new Serialized(v).encode();
		case DNekoSerialized:
			#if neko
			var str = new Serialized(v).encode();
			var val = neko.Lib.serialize(haxe.Unserializer.run(str));
			return val;
			#else
			throw "DNekoSerialized is only available on neko target";
			return null;
			#end
		case DData:
			var s = new Serialized(v).encode();	
			if( s.length > 0xFFFFFF )
				return null;
			#if haxe3
				return (untyped table.manager).doSerialize(fname, haxe.Unserializer.run(s)) ;
			#else
				return haxe.io.Bytes.ofString(s);
			#end
		case DEnum(e):
			if( v == "" ) return 0;
			var i = Std.parseInt(v);
			var ev = Type.resolveEnum(e);
			if( i < 0 || (ev != null && i >= Type.getEnumConstructs(ev).length) )
				return null;
			return i;
		case DNull, DInterval:
			throw "assert";
		}
	}

	function createInstance( table : TableInfos ) : Object {		
		var c = Type.createEmptyInstance(table.cl);
		#if !neko
		untyped if( c._manager == null )  c._manager = c.__getManager();
		#end
		return c;
	}

	function getRights( ?t : Object, ?table : TableInfos ) : RightsInfos {
		if( t == null )
			t = createInstance(table);
		if( untyped t.dbRights == null )
			return default_rights;
		var r : RightsInfos = untyped t.dbRights();
		if( r == null )
			return default_rights;
		if( r.can == null )
			r.can = default_rights.can;
		return r;
	}

	function getSInfos( t : Object ) : SearchInfos {
		if( untyped t.dbSearch == null )
			return null;
		return untyped t.dbSearch();
	}

	/**
	 * insert a new object in a table
	 */
	function doInsert( table : TableInfos, params : Map<String,String> ) {
		var inst = createInstance(table);
		updateParams(table,params);
		for( f in table.fields ) {
			var v = params.get(f.name);
			#if (haxe_ver < 3.2)
			var fieldName = f.name;
			#else
			var fieldName = Manager.getFieldName({name: f.name, t: f.type, isNull: table.nulls.exists(f.name)});
			#end
			if( v == null ) {
				if( table.nulls.exists(f.name) )
					Reflect.setField(inst,fieldName,null);
				else
					for( r in table.relations )
						if( f.name == r.key ) {
							insert(table,params,f.name);
							return;
						}
				continue;
			}
			var msg = null;
			var v = try updateField(f.name, v, f.type, table) catch( err : String ) { msg = err; null; };
			if( v == null ) {
				// loop in case of error Invalid_format
				insert(table,params,f.name,msg);
				return;
			}
			Reflect.setField(inst,fieldName,v);
		}
		if( table.primary.length == 1 && Reflect.field(inst,table.primary.first()) == 0 )
			Reflect.deleteField(inst,table.primary.first());
		try {
			if( !getRights(inst).can.insert )
				throw "Can't insert";
			if(inst == null)
				throw "instance is null";
			inst.insert();
			log("Inserted "+table.name+" "+table.identifier(inst));
		} catch( e : Dynamic ) {
			insert(table,params,null,Std.string(e));
			return;
		}
		
		//display a blank form to insert a new object
		if( params.exists("__new") ) {
			insert(table,params);
			return;
		}
		style.goto(table.className+"/edit/"+table.identifier(inst));
	}

	function doCreate(table : TableInfos) {
		try {
			execute(table.createRequest(false));
			style.goto("");
		} catch( e : Dynamic ) {
			index(Std.string(e));
		}
	}

	function doDrop(table : TableInfos) {
		if( !allowDrop )
			throw "Drop not allowed";
		execute(table.dropRequest());
		style.goto("");
	}

	function doCleanup( table : TableInfos ) {
		if( !getRights(table).can.truncate )
			throw "Can't cleanup";
		execute(table.truncateRequest());
		style.goto("");
	}

	function edit( table :  TableInfos, id : String, ?params : Map<String,String>, ?error : String, ?errorMsg : String ) {
		var obj = table.fromIdentifier(id);
		var objStr = try Std.string(obj) catch( e : Dynamic ) "#"+id;
		style.begin("Edit "+table.name+" "+objStr);
		if( obj == null ) {
			style.error("This object does not exists");
			style.end();
			return;
		}
		var binary = false;
		for( f in table.fields )
			if( isBinary(f.type) ) {
				binary = true;
				break;
			}
		style.beginForm(table.className+"/doEdit/"+id,binary,table.name);
		var rights = getRights(obj);
		var hasBinary = false;
		for( f in table.fields ) {
			if( f.name == error ) {
				style.errorField((errorMsg == null) ? "Invalid format" : errorMsg);
				errorMsg = null;
			}
			if( has(rights.invisible,f.name) )
				continue;
			var readonly = has(rights.readOnly,f.name);
			inputField(table,f,id,readonly,if( params == null ) Reflect.field(obj,f.name) else params.get(f.name), params != null);
			if( !readonly && isBinary(f.type) )
				hasBinary = true;
		}
		if( rights.can.modify ) {
			style.addSubmit("Modify");
			if( hasBinary )
				style.addSubmit("Upload",null,null,"__upload");
		}
		style.addSubmit("Cancel",table.className+"/edit/"+id);
		if( rights.can.delete )
			style.addSubmit("Delete",table.className+"/doDelete/"+id,true);
		style.endForm();
		if( errorMsg != null )
			style.error(errorMsg);
		style.end();
	}

	function doEdit( table : TableInfos, id : String, params : Map<String,String> ) {
		var inst = table.fromIdentifier(id);
		if( inst == null ) {
			style.goto(table.className+"/edit/"+id);
			return;
		}
		updateParams(table,params);
		var rights = getRights(inst);
		var binaries = new List();
		for( f in table.fields ) {
			if( has(rights.readOnly,f.name) || has(rights.invisible,f.name) )
				continue;
			#if (haxe_ver < 3.2)
			var fieldName = f.name;
			#else
			var fieldName = Manager.getFieldName({name: f.name, t: f.type, isNull: table.nulls.exists(f.name)});
			#end
			var v = params.get(f.name);
			if( v == null ) {
				if( table.nulls.exists(f.name) )
					Reflect.setField(inst,fieldName,null);
				continue;
			}
			var msg = null;
			var v = try updateField(f.name, v, f.type, table) catch( err : Dynamic ) { msg = err; null; };
			if( v == null ) {
				// insert ID into params
				if( table.primary != null ) {
					for( p in table.primary )
						params.set(p,Reflect.field(inst,p));
				}
				for( f in rights.readOnly )
					params.set(f, Reflect.field(inst, f));
				// error Invalid_format
				edit(table,id,params,f.name, msg);
				return;
			}
			var bin = isBinary(f.type);
			if( Std.is(v,String) && v == "" && bin )
				continue;
			Reflect.setField(inst,fieldName,v);
			if( bin )
				binaries.add({ name : f.name, value : v });
		}
		try {
			if( !rights.can.modify )
				throw "Can't modify";
			if( params.exists("__upload") )
				request(table,table.updateFields(inst,binaries));
			else {
				inst.update();
				log("Updated "+table.name+" "+table.identifier(inst));
			}
		} catch( e : Dynamic ) {
			edit(table,id,params,null,Std.string(e));
			return;
		}
		style.goto(table.className+"/edit/"+table.identifier(inst));
	}

	/**
	 * Sync some of the object fields from the web request
	 */
	function updateParams( table : TableInfos, params : Map<String,String> ) {
		var tmp = Web.getMultipart(maxUploadSize);
		for( k in tmp.keys() )
			params.set(k,tmp.get(k));
		for( r in table.relations ) {
			var p = params.get(r.prop);
			params.remove(r.prop);
			if( p == null || p == "" )
				continue;
			params.set(r.key,p);
			params.remove(r.prop+"__data");
			params.set(r.key+"__data","on");
		}
		for( f in table.fields ) {
			switch( f.type ) {
			case DFlags(flags,_):
				var vint = 0;
				for( i in 0...flags.length )
					if( params.exists(f.name + "_" + flags[i]) )
						vint |= 1 << i;
				if( table.nulls.exists(f.name) && !params.exists(f.name+"__data") && vint == 0 ) {
					params.remove(f.name);
					continue;
				}
				params.set(f.name, Std.string(vint));
				params.set(f.name + "__data", "true");
			default:
			}
			if( table.nulls.exists(f.name) && !params.exists(f.name+"__data") && (params.get(f.name) == "" || params.get(f.name) == null) ) {
				params.remove(f.name);
				continue;
			}
			if( f.type == DBool ) {
				var v = params.exists(f.name);
				params.set(f.name,if( v ) "true" else "false");
			}
		}
	}

	/**
	 * Deletes a record
	 */
	function doDelete( table : TableInfos, id : String ) {
		var inst = table.fromIdentifier(id);
		if( inst == null ) {
			style.goto(table.className+"/edit/"+id);
			return;
		}
		if( !getRights(inst).can.delete ) {
			edit(table,id,null,null,"Can't Delete");
			return;
		}
		inst.delete();
		log("Deleted "+table.name+" "+id);
		style.goto("");
	}

	function doDownload( table : TableInfos, id : String, field : String ) {
		var inst = table.fromIdentifier(id);
		if( inst == null ) {
			style.goto(table.className+"/edit/"+id);
			return;
		}
		var rights = getRights(inst);
		var f = table.hfields.get(field);
		var data : String = Reflect.field(inst,field);
		if( has(rights.invisible,field) || data == null || !isBinary(f) ) {
			edit(table,id,null,null,"Can't Download data");
			return;
		}
		Web.setHeader("Content-Type","text/binary");
		Web.setHeader("Content-Length",Std.string(data.length));
		Sys.print(data);
	}

	function search( table : TableInfos, params : Map<String,String> ) {
		style.begin("Search "+table.name);

		var pagesize = 30;
		var page = Std.parseInt(params.get("__p"));
		var order = params.get("__o");
		if( page == null )
			page = 0;
		params.remove("__p");
		params.remove("__o");

		// save params for later usage
		var paramsStr = "";
		for( p in params.keys() ) {
			var v = params.get(p);
			paramsStr += p+"="+StringTools.urlEncode(v)+";";
		}

		// set nullable for all types which can be searched with empty string or no values
		for( f in table.fields )
			switch( f.type ) {
			case DBool, DString(_), DTinyText, DText, DSmallText, DFlags(_):
				table.nulls.set(f.name,true);
			default:
			}

		updateParams(table,params);

		// remove not null fields that have not been completed
		for( f in table.fields )
			if( !table.nulls.exists(f.name) && params.get(f.name) == "" )
				params.remove(f.name);

		var rights = getRights(table);
		for( f in rights.invisible )
			params.remove(f);

		var results = table.fromSearch(params,order,page*pagesize,pagesize+1);
		var hasNext = false;
		if( results.length > pagesize ) {
			results.remove(results.last());
			hasNext = true;
		}

		var sinfos : SearchInfos = getSInfos(createInstance(table));
		var fields;
		if( sinfos != null && sinfos.fields != null )
			fields = sinfos.fields;
		else {
			fields = new Array();
			for( f in table.fields ) {
				var bad = false;
				for( r in table.relations )
					if( r.key == f.name && r.className == "db.File" ) {
						bad = true;
						break;
					}
				if( bad )
					continue;
				fields.push(f.name);
			}
		}

		style.beginForm(table.className+"/search",table.name);
		for( f in fields ) {
			var t = table.hfields.get(f);
			if( t == null )
				continue;
			var t = switch( t ) {
				case DId, DUId: DInt;
				case DBigId: DFloat;
				case DText,DSmallText: DTinyText;
				default: t;
			};
			inputField(table,{ name : f, type : t },null,false,if( params == null ) null else params.get(f));
		}
		style.addSubmit("Search");
		style.endForm();

		style.beginTable("results");
		style.beginLine(true,"header");
		style.text("actions");

		if( sinfos != null && sinfos.names != null ) {
			for( f in sinfos.names ) {
				style.nextRow(true);
				if( table.hfields.exists(f) ) {
					var cur = (order == f);
					var curNeg = (order == "-"+f);
					style.link(table.className+"/search?"+paramsStr+"__o="+(cur ? "-"+f : f),(cur ? "+" : curNeg ? "-" : "") + f);
				} else
					style.text(f);
			}
		} else {
			for( f in table.fields ) {
				if( has(rights.invisible,f.name) )
					continue;
				style.nextRow(true);
				var cur = (order == f.name);
				var curNeg = (order == "-"+f.name);
				style.link(table.className+"/search?"+paramsStr+"__o="+(cur ? "-"+f.name : f.name),(cur ? "+" : curNeg ? "-" : "") + f.name);
			}
		}
		style.endLine();

		var odd = false;
		for( r in results ) {
			var k = table.fields.iterator();
			style.beginLine(if( odd ) "odd" else null);
			style.link(table.className+"/edit/"+table.identifier(r),"Edit");
			odd = !odd;
			if( sinfos != null && sinfos.names != null ) {
				var rinfos = getSInfos(r);
				for( v in rinfos.values ) {
					style.nextRow(false);
					style.text(Std.string(v));
				}
			} else {
				var rinst = getRights(r);
				for( f in k ) {
					if( has(rights.invisible,f.name) )
						continue;
					var data = Reflect.field(r,f.name);
					var str = try Std.string(data) catch( e : Dynamic ) { if(!Std.is(data,Date)) Lib.rethrow(e); "#INVALID"; };
					if( str.length >= 20 )
						str = str.substr(0,17) + "...";
					style.nextRow(false);
					if( has(rinst.invisible,f.name) )
						style.text("???");
					else if( data == null )
						style.text(str)
					else switch( f.type ) {
					case DEncoded:
						style.text(Id.decode(data),str);
					case DDate:
						style.text(str.substr(0,10)); // remove 00:00:00 time
					case DFlags(flags,_):
						var fl = [];
						for( i in 0...flags.length )
							if( data & (1 << i) != 0 )
								fl.push(flags[i]);
						str = fl.join(",");
						if( str.length >= 20 )
							style.text(str.substr(0,17) + "...",fl.join(",")+" ("+data+")");
						else
							style.text(str,"("+data+")");
					default:
						style.text(str);
					}
				}
			}
			style.endLine();
		}
		style.endTable();

		if( order != null )
			paramsStr += "__o="+order+";";

		if( page > 0 )
			style.link(table.className+"/search?"+paramsStr+"__p="+(page-1),"Previous");
		else
			style.text("Previous");
		style.text(" | ");
		if( hasNext )
			style.link(table.className+"/search?"+paramsStr+"__p="+(page+1),"Next");
		else
			style.text("Next");
		style.end();
	}

	function syncAction( t : TableInfos, act : Array<String>, text : String, ?def ) {
		if( !hasSyncAction ) {
			style.beginList();
			hasSyncAction = true;
		}
		style.beginItem();
		style.checkBox(t.className+"@"+act.join("@"),if( def == null ) true else def);
		style.text(text);
		style.endItem();
	}

	function doSync( params : Map<String,String> ) {
		var order = ["create","add","reldel","idxdel","update","remove","rename","idxadd","reladd"];
		var cmd = new Array();
		for( p in params.keys() ) {
			if( !~/[A-Za-z0-9_@]*/.match(p) )
				throw "Invalid command "+p;
			cmd.push(p.split("@"));
		}
		cmd.sort(function(c1,c2) {
			var p1 = 0, p2 = 0;
			for( i in 0...order.length )
				if( order[i] == c1[1] )
					p1 = i;
				else if( order[i] == c2[1] )
					p2 = i;
			return p1 - p2;
		});
		for( data in cmd ) {
			var tname = data.shift();
			#if php
			// php replaces dots by _ in post keys
			tname = tname.split("_").join(".");
			#end
			var table = new TableInfos(tname);
			var act = data.shift();
			var field = data.shift();
			try {
				switch( act ) {
				case "create":
					execute(table.createRequest(false));
				case "add":
					execute(table.addFieldRequest(field));
				case "update":
					execute(table.updateFieldRequest(field));
				case "remove":
					execute(table.removeFieldRequest(field));
				case "rename":
					execute(table.renameFieldRequest(field,data.shift()));
				case "reladd":
					execute(table.addRelationRequest(field,data.shift()));
				case "reldel":
					execute(table.deleteRelationRequest(field));
				case "idxadd":
					execute(table.addIndexRequest(data,field == "true"));
				case "idxdel":
					execute(table.deleteIndexRequest(field));
				default:
					throw "Unknown action "+act;
				}
			} catch( e : Dynamic ) {
				index(Std.string(e));
				return;
			}
		}
		style.goto("");
	}

	function indexId( i : { unique : Bool, keys : List<String> } ) {
		return i.unique+"@"+i.keys.join("@");
	}

	/**
	 * check for differences between classes and tables in DB
	 */
	function needSync( t : TableInfos ) {
		var desc = execute(t.descriptionRequest()).getResult(1);
		var inf = TableInfos.fromDescription(desc);
		var renames = new Map();
		hasSyncAction = false;
		
		// ADD/CHANGE FIELDS
		for( f in t.fields ) {
			var t2 = inf.fields.get(f.name);
			if( t2 == null ) {
				var rename = false;
				for( n in inf.fields.keys() )
					if( !t.hfields.exists(n) && Type.enumEq(inf.fields.get(n),f.type) && inf.nulls.get(n) == t.nulls.get(f.name) ) {
						rename = true;
						renames.set(n,true);
						syncAction(t,["rename",n,f.name],'Rename field "$n" to "${f.name}"');
						break;
					}
				syncAction(t,["add",f.name],"Add field "+f.name,!rename);
			} else {
				inf.fields.remove(f.name);
				var isnull = inf.nulls.get(f.name);
				var changed = false;
				var txt = "Change "+f.name+" : ";
				if( !Type.enumEq(f.type,t2) && !TableInfos.sameDBStorage(t2,f.type) ) {
					changed = true;
					txt += " S"+Std.string(t2).substr(1)+" becomes S"+Std.string(f.type).substr(1);
				}
				if( isnull != t.nulls.get(f.name) ) {
					if( changed )
						txt += " and";
					else
						changed = true;
					if( isnull )
						txt += " can't be NULL";
					else
						txt += " can be NULL";
				}
				if( changed )
					syncAction(t,["update",f.name],txt);
			}
		}
		// REMOVE FIELDS
		for( f in inf.fields.keys() )
			syncAction(t,["remove",f],"Remove field "+f,!renames.exists(f));
		// ADD RELATIONS
		for( r in t.relations ) {
			if( !t.isRelationActive(r) )
				continue;
			var tname = TableInfos.unescape(r.manager.table_name);
			var found = false;
			var setnull = t.nulls.get(r.key);
			if( setnull && untyped r.cascade == true )
				setnull = null;
			for( r2 in inf.relations )
				if( (t.name + "_" + r.prop == r2.name || TableInfos.OLD_COMPAT) &&
					r.key == r2.key &&
					tname.toLowerCase() == r2.table.toLowerCase() &&
					r.manager.table_keys.length == 1 && r.manager.table_keys[0] == r2.id &&
					r2.setnull == setnull
				) {
					found = true;
					inf.relations.remove(r2);
					break;
				}
			if( !found )
				syncAction(t,["reladd",r.key,r.prop],"Add Relation "+r.prop+"("+r.key+") on "+tname+"("+r.manager.table_keys[0]+")"+if( setnull ) " set-null" else "");
		}
		// REMOVE RELATIONS
		for( r in inf.relations )
			syncAction(t,["reldel",r.name],"Remove Relation "+r.name+"("+r.key+") on "+r.table+"("+r.id+")"+if( r.setnull ) " set-null" else "");
		// INDEXES
		var hidx = new Map();
		for( i in t.indexes )
			hidx.set(indexId(i),i);
		var used = new List();
		for( r in t.relations ) {
			var found : { keys : List<String>, unique : Bool } = null;
			for( i in t.indexes )
				if( i.keys.first() == r.key && (found == null || found.keys.length < i.keys.length) )
					found = i;
			if( found == null ) {
				// in primary key ?
				if( t.primary.first() == r.key )
					continue;
				// default relation-index
				found = { keys : Lambda.list([r.key]), unique : false };
			}
			hidx.remove(indexId(found));
			for( i in inf.indexes )
				if( i.keys.join("#") == found.keys.join("#") && i.unique == found.unique ) {
					used.add(i);
					found = null;
					break;
				}
			// we need it
			if( found != null )
				hidx.set(indexId(found),found);
		}
		for( i in used )
			inf.indexes.remove(i.name);
		for( iname in inf.indexes.keys() ) {
			var i = inf.indexes.get(iname);
			if( !hidx.remove(indexId(i)) )
				syncAction(t,["idxdel",iname],"Remove "+(if( i.unique ) "Unique " else "")+"Index "+iname+" ("+i.keys.join(",")+")");
		}
		for( i in hidx )
			syncAction(t,["idxadd",indexId(i)],"Add "+(if( i.unique ) "Unique " else "")+"Index ("+i.keys.join(",")+")");
		// PRIMARY KEYS
		if( (inf.primary == null) != (t.primary == null) || (inf.primary != null && inf.primary.join("-") != t.primary.join("-")) ) {
			style.text("PRIMARY KEY CHANGED !");
			hasSyncAction = true;
		}
		if( hasSyncAction )
			style.endList();
		return hasSyncAction;
	}

	public function process( ?url : Array<String> ) {
		if( url == null ) {
			url = Web.getURI().split("/");
			url.shift(); // empty : url starts with /
			url.shift(); // "admin"
			if( url[0] == "index.n" )
				url.shift();
		}
		if( url.length == 0 ) url.push("");
		var params = Web.getParams();
		switch( url[0] ) {
		case "":
			
			style = new AdminStyle(null);
			index();
			return;
			
		case "doSync":
			style = new AdminStyle(null);
			doSync(params);
			return;
		}
		var table = new TableInfos(url.shift());
		style = new AdminStyle(table);
		var act = url.shift();
		switch( act ) {
		case "insert":
			insert(table,params);
		case "doInsert":
			doInsert(table,params);
		case "edit":
			edit(table,url.join("/"));
		case "doEdit":
			doEdit(table,url.join("/"),params);
		case "doCreate":
			doCreate(table);
		case "doDrop":
			doDrop(table);
		case "doCleanup":
			doCleanup(table);
		case "doDelete":
			doDelete(table,url.join("/"));
		case "doDownload":
			doDownload(table,url.shift(),url.shift());
		case "search":
			search(table,params);
		default:
			throw "Unknown action "+act;
		}
	}

	static function log(msg:String) {
		#if neko
		Web.logMessage("[DBADM] " + neko.Web.getHostName() + " " + Date.now().toString() + " " + neko.Web.getClientIP() + " - " + msg);
		#end
	}

	public static function handler() {
		Manager.initialize(); // make sure it's been done
		try {
			new Admin().process();
		} catch( e : Dynamic ) {
			// rollback in case of multiple delete/update - no effect on DB struct changes
			// since they are done outside of transaction
			Manager.cnx.rollback();
			
			Sys.print("<h2>Error :</h2>"+Std.string(e));
			Sys.print("<h2>Stack :</h2><pre>");
			Sys.print(haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
			Sys.print("</pre>");
		}
	}

	public static function initializeDatabase( initIndexes = true, initRelations = true ) {
		var a = new Admin();
		var tables = a.getTables();
		for( t in tables )
			a.execute(t.createRequest(false));
		for( t in tables ) {
			if( initIndexes )
				for( i in t.indexes )
					a.execute(t.addIndexRequest(Lambda.array(i.keys), i.unique));
			if( initRelations )
				for( r in t.relations )
					a.execute(t.addRelationRequest(r.key, r.prop));
		}
	}

}
