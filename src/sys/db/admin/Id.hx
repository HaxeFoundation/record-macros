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

class Id {

	public static function encode( id : String ) : Int {
		var l = id.length;
		if( l > 6 )
			throw "Invalid identifier '"+id+"'";
		var k = 0;
		var p = l;
		while( p > 0 ) {
			var c = id.charCodeAt(--p) - 96;
			if( c < 1 || c > 26 ) {
				c = c + 96 - 48;
				if( c >= 1 && c <= 5 )
					c += 26;
				else
					throw "Invalid character "+id.charCodeAt(p)+" in "+id;
			}
			k <<= 5;
			k += c;
		}
		return k;
	}

	public static function decode( id : Int ) : String {
		var s = new StringBuf();
		if( id < 1 ) {
			if( id == 0 ) return "";
			throw "Invalid ID "+id;
		}
		while( id > 0 ) {
			var k = id & 31;
			if( k < 27 )
				s.addChar(k + 96);
			else
				s.addChar(k + 22);
			id >>= 5;
		}
		return s.toString();
	}

}