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

#if hscript
import hscript.Expr;
#end

private enum Errors {
	Invalid;
}

private typedef Current = {
	var old : Current;
	var lines : Array<String>;
	var totalSize : Int;
	var maxSize : Int;
	var prefix : String;
	var sep : String;
	var buf : StringBuf;
}

class Serialized {

	var value : String;
	var pos : Int;
	var buf : StringBuf;
	var shash : Map<String,Int>;
	var scount : Int;
	var scache : Array<String>;
	var useEnumIndex : Bool;

	var cur : Current;
	var tabs : Int;

	static var IDENT = "  ";
	static var ident = ~/^[A-Za-z_][A-Za-z0-9_]*$/;
	static var clname = ~/^[A-Za-z_][A-Z.a-z0-9_]*$/;
	static var BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789%:";

	public function new(v) {
		this.value = v;
		pos = 0;
		tabs = 0;
	}

	public function encode() : String {
		#if !hscript
		throw "You can't edit this without -lib hscript";
		return null;
		#else
		if( value == "" )
			return "";
		var p = new hscript.Parser();
		p.allowJSON = true;
		var e = p.parse(new haxe.io.StringInput(value));
		buf = new StringBuf();
		shash = new Map();
		scount = 0;
		encodeRec(e);
		return buf.toString();
		#end
	}

	#if hscript

	inline function expr( e ){
		#if hscriptPos
		return e.e;
		#else
		return e;
		#end
	}

	function getString( e : Expr ) {
		return (e == null) ? null : switch( expr(e) ) {
		case EConst(v):
			switch(v) {
			case CString(s): s;
			default: null;
			}
		default: null;
		};
	}

	function getPath( e : Expr ) {
		if( e == null )
			return null;
		switch( expr(e) ) {
		case EConst(v):
			return switch(v) {
			case CString(s): s;
			default: null;
			}
		case EIdent(v):
			return v;
		case EField(e, f):
			var path = "." + f;
			while( true ) {
				switch( expr(e) ) {
				case EIdent(i): return i + path;
				case EField(p, f): path = "." + f + path; e = p;
				default: return  null;
				}
			}
		default:
		}
		return null;
	}

	function encodeRec( e : Expr ) {
		switch( expr(e) ) {
		case EConst(v):
			switch(v) {
			case CString(s):
				encodeString(s);
			case CInt(v):
				if( v == 0 ) {
					buf.add("z");
					return;
				}
				buf.add("i");
				buf.add(v);
			case CFloat(v):
				if( Math.isNaN(v) )
					buf.add("k");
				else if( !Math.isFinite(v) )
					buf.add(if( v < 0 ) "m" else "p");
				else {
					buf.add("d");
					buf.add(v);
				}
			#if !haxe3
			case CInt32(i):
				buf.add("d");
				buf.add(v);
			#end
			}
		case EUnop(op, _, es):
			if( op == "-" )
				switch( expr(es) ) {
				case EConst(v):
					switch(v) {
					case CInt(i):
						#if hscriptPos
						encodeRec({e: EConst(CInt(-i)), pmin: es.pmin, pmax: es.pmax});
						#else
						encodeRec(EConst(CInt(-i)));
						#end
						return;
					case CFloat(f):
						#if hscriptPos
						encodeRec({e: EConst(CFloat(-f)), pmin: es.pmin, pmax: es.pmax});
						#else
						encodeRec(EConst(CFloat(-f)));
						#end
						return;
					default:
					}
				default:
				}
			throw "Unsupported " + Type.enumConstructor(expr(e));
		case EIdent(v):
			switch( v ) {
			case "null":
				buf.add("n");
			case "true":
				buf.add("t");
			case "false":
				buf.add("f");
			case "NaN":
				buf.add("k");
			case "Inf":
				buf.add("p");
			case "NegInf":
				buf.add("m");
			default:
				throw "Unknown identifier " + v;
			}
		case EArrayDecl(el):
			var ucount = 0;
			buf.add("a");
			for( e in el ) {
				switch( expr(e) ) {
				case EIdent(i):
					if( i == "null" ) {
						ucount++;
						continue;
					}
				default:
				}
				if( ucount > 0 ) {
					if( ucount == 1 )
						buf.add("n");
					else {
						buf.add("u");
						buf.add(ucount);
					}
					ucount = 0;
				}
				encodeRec(e);
			}
			if( ucount > 0 ) {
				if( ucount == 1 )
					buf.add("n");
				else {
					buf.add("u");
					buf.add(ucount);
				}
			}
			buf.add("h");
		case EObject(fields):
			buf.add("o");
			for( f in fields ) {
				encodeString(f.name);
				encodeRec(f.e);
			}
			buf.add("g");
		case ECall(e, params):
			switch( expr(e) ) {
			case EIdent(call):
				switch(call) {
				case "empty":
					if( params.length == 0 )
						return;
				case "invalid":
					var str = getString(params[0]);
					if( params.length == 1 && str != null ) {
						buf.add(str);
						return;
					}
				case "list":
					buf.add("l");
					for( e in params )
						encodeRec(e);
					buf.add("h");
					return;
				case "date":
					var str = getString(params[0]);
					// check format
					if( params.length == 1 && str != null ) {
						var d = Date.fromString(str);
						buf.add("v");
						buf.add(d.toString());
						return;
					}
				case "now":
					if( params.length == 0 ) {
						buf.add("v");
						buf.add(Date.now());
						return;
					}
				case "error":
					if( params.length == 1 ) {
						buf.add("x");
						encodeRec(params[0]);
						return;
					}
				case "hash":
					if( params.length == 1 )
						switch( expr(params[0]) ) {
						case EObject(fields):
							buf.add("b");
							for( f in fields ) {
								encodeString(f.name);
								encodeRec(f.e);
							}
							buf.add("h");
							return;
						default:
						}
				case "inthash":
					if( params.length == 1 )
						switch( expr(params[0]) ) {
						case EObject(fields):
							buf.add("q");
							for( f in fields ) {
								if( !~/^-?[0-9]+$/.match(f.name) )
									throw "Invalid IntHash key '"+f.name+"'";
								buf.add(":");
								buf.add(f.name);
								encodeRec(f.e);
							}
							buf.add("h");
							return;
						default:
						}
				case "bytes":
					var str = getString(params[0]);
					if( params.length == 1 && str != null ) {
						for( i in 0...str.length )
							if( BASE64.indexOf(str.charAt(i)) == -1 )
								throw "Invalid Base64 char";
						buf.add("s");
						buf.add(str.length);
						buf.add(":");
						buf.add(str);
						return;
					}
				case "indexes":
					if( params.length == 1 ) {
						useEnumIndex = true;
						encodeRec(params[0]);
						return;
					}
				case "ref":
					if( params.length == 1 ) {
						switch( expr(params[0]) ) {
						case EConst(v):
							switch(v) {
							case CInt(i):
								buf.add("r");
								buf.add(i);
								return;
							default:
							}
						default:
						}
					}
				default:
					throw "Unsupported call '"+call+"'";
				}
			case EField(e, f):
				encodeEnum(e, f, params);
				return;
			case EArray(e, index):
				encodeEnum(e, index, params);
				return;
			default:
			}
			throw "Unsupported call";
		case EField(e, f):
			encodeEnum(e, f, []);
		case EArray(e,index):
			encodeEnum(e, index, []);
		case ENew(c, params):
			var fields = null, cname = null;
			if( c == "class" ) {
				if( params.length == 2 ) {
					cname = getString(params[0]);
					fields = switch( expr(params[1]) ) { case EObject(fields): fields; default : null; }
				}
			} else if( c == "custom" ) {
				cname = getPath(params[0]);
				if( cname != null ) {
					buf.add("C");
					encodeString(cname);
					for( i in 1...params.length )
						encodeRec(params[i]);
					buf.add("g");
					return;
				}
			} else {
				if( params.length == 1 ) {
					cname = c;
					fields = switch( expr(params[0]) ) { case EObject(fields): fields; default : null; }
				}
			}
			if( cname == null || fields == null )
				throw "Invalid 'new'";
			buf.add("c");
			encodeString(cname);
			for( f in fields ) {
				encodeString(f.name);
				encodeRec(f.e);
			}
			buf.add("g");
		default:
			throw "Unsupported " + Type.enumConstructor(expr(e));
		}
	}

	function encodeEnum( e : Expr, ?name : String, ?eindex : Expr, args : Array<Expr> ) {
		var ename = getPath(e);
		if( ename == null )
			throw "Invalid enum path";
		var index : Null<Int> = null;
		if( eindex != null ) {
			switch( expr(eindex) ) {
			case EConst(c):
				switch( c ) {
				case CInt(i): index = i;
				case CString(s): name = s;
				default:
				}
			default:
			}
			if( index == null && name == null ) throw "Invalid enum index";
		}
		if( name != null ) {
			var e = try Type.resolveEnum(ename) catch( e : Dynamic ) null;
			if( e == null ) {
				if( useEnumIndex )
					throw "Unknown enum '" + ename + "' : use index";
			} else {
				index = Lambda.indexOf(Type.getEnumConstructs(e), name);
				if( index < 0 ) throw name + " is not part of enum " + ename + "(" + Type.getEnumConstructs(e).join(",") + ")";
				if( useEnumIndex ) name = null else index = null;
			}
		}
		buf.add((index != null)?"j":"w");
		encodeString(ename);
		if( index != null ) {
			buf.add(":");
			buf.add(index);
		} else
			encodeString(name);
		buf.add(":");
		buf.add(args.length);
		for( a in args )
			encodeRec(a);
	}

	function encodeString( s : String ) {
		var x = shash.get(s);
		if( x != null ) {
			buf.add("R");
			buf.add(x);
			return;
		}
		shash.set(s,scount++);
		buf.add("y");
		s = StringTools.urlEncode(s);
		buf.add(s.length);
		buf.add(":");
		buf.add(s);
	}
	#end

	function quote( s : String, ?r : EReg ) {
		if( r != null && r.match(s) )
			return s;
		return "'"+s.split("\\").join("\\\\").split("'").join("\\'").split("\n").join("\\n").split("\r").join("\\r").split("\t").join("\\t")+"'";
	}

	public function escape() {
		if( value == "" )
			return "empty()";
		buf = new StringBuf();
		scache = new Array();
		try loop() catch( e : Errors ) pos = -1;
		if( pos != value.length )
			return "invalid(" + quote(value) + ")";
		var str = buf.toString();
		if( useEnumIndex )
			str = "indexes(" + str + ")";
		return str;
	}

	inline function get(pos) {
		return value.charCodeAt(pos);
	}

 	function readDigits() {
 		var k = 0;
 		var s = false;
 		var fpos = pos;
 		while( true ) {
 			var c = get(pos);
 			if( c == null )
 				break;
 			if( c == "-".code ) {
 				if( pos != fpos )
 					break;
 				s = true;
 				pos++;
 				continue;
 			}
 			if( c < "0".code || c > "9".code )
 				break;
 			k = k * 10 + (c - "0".code);
 			pos++;
 		}
 		if( s )
 			k *= -1;
 		return k;
 	}

	function loop() {
		switch( get(pos++) ) {
		case "n".code:
			buf.add(null);
		case "i".code:
			buf.add(readDigits());
		case "z".code:
			buf.add(0);
		case "t".code:
			buf.add(true);
		case "f".code:
			buf.add(false);
		case "k".code:
			buf.add("NaN");
		case "p".code:
			buf.add("Inf");
		case "m".code:
			buf.add("NegInf");
		case "d".code:
 			var p1 = pos;
 			while( true ) {
 				var c = get(pos);
 				// + - . , 0-9
 				if( (c >= 43 && c < 58) || c == "e".code || c == "E".code )
 					pos++;
 				else
 					break;
 			}
 			buf.add(value.substr(p1, pos - p1));
		case "a".code:
			open("[",", ");
 			while( true ) {
 				var c = get(pos);
 				if( c == "h".code ) {
					pos++;
 					break;
				}
 				if( c == "u".code ) {
					pos++;
 					for( i in 0...readDigits() - 1 ) {
						buf.add("null");
						next();
					}
					buf.add("null");
 				} else
					loop();
				next();
 			}
			close("]");
		case "y".code, "R".code:
			pos--;
			buf.add(quote(readString()));
		case "l".code:
			open("list(",", ");
			while( get(pos) != "h".code ) {
				loop();
				next();
			}
			close(")");
			pos++;
		case "v".code:
			buf.add("date(");
			buf.add(quote(value.substr(pos, 19)));
			buf.add(")");
			pos += 19;
		case "x".code:
			buf.add("error(");
			loop();
			buf.add(")");
		case "o".code:
			loopObj("g".code);
		case "b".code:
			buf.add("hash(");
			loopObj("h".code);
			buf.add(")");
		case "q".code:
			buf.add("inthash(");
			open("{",", "," ");
			var c = get(pos++);
			while( c == ":".code ) {
				buf.add("'"+readDigits()+"'");
				buf.add(" : ");
				loop();
				c = get(pos++);
				next();
			}
			if( c != "h".code )
				throw Invalid;
			close("}", " ");
			buf.add(")");
		case "s".code:
 			var len = readDigits();
 			if( get(pos++) != ":".code || value.length - pos < len )
				throw Invalid;
			buf.add("bytes(");
			buf.add(quote(value.substr(pos, len)));
			buf.add(")");
			pos += len;
		case "w".code:
			buf.add(quote(readString(), clname));
			var constr = readString();
			if( ident.match(constr) )
				buf.add("." + constr);
			else
				buf.add("["+quote(constr)+"]");
			if( get(pos++) != ":".code )
				throw Invalid;
			var nargs = readDigits();
			if( nargs > 0 ) {
				buf.add("(");
				for( i in 0...nargs ) {
					if( i > 0 ) buf.add(", ");
					loop();
				}
				buf.add(")");
			}
		case "j".code:
			var cl = readString();
			buf.add(quote(cl, clname));
			if( get(pos++) != ":".code )
				throw Invalid;
			var index = readDigits();
			var e = Type.resolveEnum(cl);
			if( e == null )
				buf.add("["+index+"]");
			else {
				useEnumIndex = true;
				buf.add("."+Type.getEnumConstructs(e)[index]);
			}
			if( get(pos++) != ":".code )
				throw Invalid;
			var nargs = readDigits();
			if( nargs > 0 ) {
				buf.add("(");
				for( i in 0...nargs ) {
					if( i > 0 ) buf.add(", ");
					loop();
				}
				buf.add(")");
			}
		case "c".code:
			buf.add("new ");
			var cl = readString();
			if( clname.match(cl) )
				buf.add(cl + "(");
			else {
				buf.add("class(");
				buf.add(quote(cl));
				buf.add(",");
			}
			loopObj("g".code);
			buf.add(")");
		case "C".code:
			open("new custom(",", ");
			buf.add(quote(readString(), clname));
			next();
			while( get(pos) != "g".code ) {
				loop();
				next();
			}
			close(")");
			pos++;
		case "r".code:
			buf.add("ref("+readDigits()+")");
		default:
			throw Invalid;
		}
	}

	function readString() : String {
		switch( value.charCodeAt(pos++) ) {
		case "y".code:
 			var len = readDigits();
 			if( get(pos++) != ":".code || value.length - pos < len )
 				throw Invalid;
			var s = value.substr(pos,len);
			pos += len;
			s = StringTools.urlDecode(s);
			scache.push(s);
			return s;
 		case "R".code:
			var n = readDigits();
			if( n < 0 || n >= scache.length )
				throw "Invalid string reference";
			return scache[n];
		default:
			throw Invalid;
		}
	}

	function loopObj(eof) {
		open("{",", "," ");
		while( true ) {
			if( pos >= value.length )
				throw Invalid;
			if( get(pos) == eof )
				break;
			buf.add(quote(readString(), ident));
			buf.add(" : ");
			loop();
			next();
		}
		close("}"," ");
		pos++;
	}

	function open(str, sep, ?prefix) {
		buf.add(str);
		tabs++;
		cur = { old : cur, sep : sep, prefix : prefix, lines : [], buf : buf, totalSize : 0, maxSize : 0 };
		buf = new StringBuf();
	}

	function next() {
		var line = buf.toString();
		if( line.length > cur.maxSize ) cur.maxSize = line.length;
		cur.totalSize += line.length;
		cur.lines.push(line);
		buf = new StringBuf();
	}

	function close(end,?postfix) {
		buf = cur.buf;
		var t = "\n";
		for( i in 0...tabs-1 )
			t += IDENT;
		if( t.length + cur.totalSize > 80 && cur.maxSize > 10 ) {
			var first = true;
			for( line in cur.lines ) {
				if( first ) first = false else buf.add(cur.sep);
				buf.add(t + IDENT + line);
			}
			buf.add(t);
			buf.add(end);
		} else {
			if( cur.prefix != null && cur.lines.length > 0 ) buf.add(cur.prefix);
			var first = true;
			for( line in cur.lines ) {
				if( first ) first = false else buf.add(cur.sep);
				buf.add(line);
			}
			if( !first && postfix != null ) buf.add(postfix);
			buf.add(end);
		}
		cur = cur.old;
		tabs--;
	}

}