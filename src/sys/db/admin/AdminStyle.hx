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

import haxe.macro.Context;
#if !macro
import sys.db.admin.TableInfos.TableType;
#end

#if neko
import neko.Lib;
import neko.Web;
#elseif php 
import php.Lib;
import php.Web;
#end

class MacroHelper {

	public macro static function importFile( file : String ) {
		var data = try sys.io.File.getContent(Context.resolvePath(file)) catch( e : Dynamic ) null;
		return Context.makeExpr(data,Context.currentPos());
	}

}

#if !macro

class AdminStyle {

	public static var BASE_URL = "/db/";
	public static var CSS = {
		var file = MacroHelper.importFile("db.css");
		if( file == null )
			null
		else
			'<style type="text/css">'+file+'</style>';
	}
	public static var HTML_BOTTOM = "";

	var isNull : Bool;
	var value : String;
	var isHeader : Bool;
	var table : TableInfos;

	public function new(t) {
		this.table = t;
	}

	function out(str : String,?params : Dynamic) {
		if( params != null ) {
			for( x in Reflect.fields(params) )
				str = str.split("@"+x).join(Reflect.field(params,x));
		}
		Sys.println(str);
	}

	public function text(str,?title) {
		str = StringTools.htmlEscape(str);
		if( title != null ) str = '<span title="'+StringTools.htmlEscape(title)+'">'+str+'</span>';
		out(str);
	}

	public function begin( title ) {
		out('<html><head><title>@title</title>',{ title: title });
		if( CSS != null )
			out(CSS);
		out('<meta http-equiv="Content-Type" content="text/html;charset=UTF-8"/>');
		out('
			<script lang="text/javascript">
				function updateLink(name,url,value) {
					document.getElementById(name+"__goto").href = (value == "")?"#":("@base" + url + value);
				}
				function updateImage(name,url,value) {
					updateLink(name,url,value);
					document.getElementById(name+"__img").src = "'+getFileURL('::f::')+'".split("::f::").join(value);
				}
			</script>
		',{ base : BASE_URL });
		out('</head><body>');
		out('<h1>@title</h1><div class="main">',{ title : title });
	}

	public function end() {
		out('<div class="links">');
		out('<a href="/">Exit</a> | <a href="@url">Database</a>',{ url : BASE_URL });
		if( table != null )
			out('| <a href="@url@table/search">Search</a>',{ url : BASE_URL, table : table.className });
		if( table != null )
			out('| <a href="@url@table/insert">Insert</a>',{ url : BASE_URL, table : table.className });
		out('</div></div>');
		out(HTML_BOTTOM);
		out('</body></html>');
	}

	public function beginList() {
		out("<ul>");
	}

	public function endList() {
		out("</ul>");
	}

	public function beginItem() {
		out("<li>");
	}

	public function endItem() {
		out("</li>");
	}

	public function goto(url) {
		Web.redirect(BASE_URL+url);
	}

	public function link( url, name ) {
		out('<a href="@url">@name</a>',{ url : BASE_URL+url, name : name });
	}

	public function linkConfirm( url, name ) {
		out('<a href="@url" onclick="return confirm(\'Please confirm this action\')">@name</a>',{ url : BASE_URL+url, name : name });
	}

	public function beginForm(url,?file,?id) {
		out('<form id="@id" action="@url" method="POST"@enc>',{ id:id, url : BASE_URL+url, enc : if( file ) ' enctype="multipart/form-data"' else "" });
		beginTable();
	}

	public function endForm() {
		endTable();
		out('</form>');
	}

	public function beginTable( ?css ) {
		if( css != null )
			out('<table class="@css">',{ css : css });
		else
			out('<table>');
	}

	public function endTable() {
		out('</table>');
	}

	public function beginLine( ?isHeader, ?css ) {
		var str = '<tr';
		if( css != null )
			str += ' class="'+css+'"';
		str += '>';
		str += if( isHeader ) '<th>' else '<td>';
		out(str);
		this.isHeader = isHeader;
	}

	public function nextRow( ?isHeader ) {
		out((if( this.isHeader ) '</th>' else '</td>')+(if( isHeader ) '<th>' else '<td>'));
		this.isHeader = isHeader;
	}

	public function endLine() {
		out((if( this.isHeader ) '</th>' else '</td>')+'</tr>');
	}

	public function addSubmit( name, ?url, ?confirm, ?iname ) {
		beginLine();
		nextRow();
		out('<input type="submit" class="button" value="@name"',{ name : name });
		if( iname != null )
			out(' name="@name"',{ name : iname });
		if( url != null ) {
			var conf = if( confirm ) "if( confirm('Please confirm this action') )" else "";
			out(' onclick="@conf document.location = \'@url\'; return false"', { conf : conf, url : BASE_URL + url });
		} else if( confirm )
			out(' onclick="return confirm(\'Please confirm this action\');"');
		out('/>');
		endLine();
	}

	public function checkBox(name,checked) {
		out('<input name="@name" type="checkbox" class="dcheck"',{ name : name });
		if( checked )
			out(' checked="1"');
		out('/>');
	}

	function input(name,css,?options : Dynamic) {
		if( options == null )
			options = {};
		beginLine(true);
		out(name);
		nextRow();
		if( isNull )
			checkBox(name+"__data",value != null);
		out('<input name="@name" class="@css"',{ name : name, css : css });
		if( options.size != null )
			out(' maxlength="@size"',options);
		if( options.isCheck )
			out(' type="checkbox"');
		if( value != null ) {
			if( options.isCheck ) {
				if( Std.string(value) != "false" ) out(' checked="1"');
			} else
				out(' value="@v"',{ v : Std.string(value).split("\"").join("&quot;") });
		}
		out('/>');
		endLine();
	}

	function getFileURL( v : String ) {
		return "/file/" + v + ".png";
	}

	function inputText(name, css, ?noWrap ) {
		beginLine(true);
		out(name);
		nextRow();
		if( isNull )
			checkBox(name+"__data",value != null);
		out('<textarea name="@name" class="@css"@noWrap>@value</textarea>',{ noWrap : noWrap?' wrap="off"':'', name : name, css : css, value : if( value != null ) StringTools.htmlEscape(value) else "" });
		endLine();
	}

	public function inputField( name : String, type : TableType, isNull, value ) {
		this.isNull = isNull;
		this.value = value;
		switch( type ) {
		case DId, DUId, DBigId:
			infoField(name,if( value == null ) "#ID" else value);
		case DInt:
			input(name,"dint",{ size : 10 });
		case DBigInt:
			input(name,"dbigint",{ size : 20 });
		case DUInt:
			input(name,"duint",{ size : 10 });
		case DTinyInt:
			input(name, "dtint", { size : 4 } );
		case DTinyUInt, DSmallInt, DSmallUInt, DMediumInt, DMediumUInt:
			input(name, "dint", { size : 10 } );
		case DFloat, DSingle:
			input(name,"dfloat",{ size : 10 });
		case DBool:
			input(name,"dbool",{ isCheck : true });
		case DString(n):
			input(name,"dstring",{ size : n });
		case DTinyText:
			input(name,"dtinytext");
		case DDate:
			if( value != null )
				this.value = try value.toString().substr(0,10) catch( e : Dynamic ) "#INVALID";
			input(name,"ddate",{ size : 10 });
		case DDateTime, DTimeStamp:
			if( value != null )
				this.value = try value.toString() catch( e : Dynamic ) "#INVALID";
			input(name, "ddatetime", { size : 19 } );
		case DText, DSmallText:
			inputText(name, "dtext");
		case DSerialized, DNekoSerialized:
			inputText(name, "dtext", true);
		case DData:
			inputText(name, "dtext", true);
		case DEnum(_):
			// todo : use a select box with possible constructors
			input(name, "dtint", { size : 4 } );
		case DEncoded:
			input(name,"denc",{ size : 6 });
		case DFlags(fl,_):
			beginLine(true);
			out(name);
			nextRow();
			if( isNull )
				checkBox(name+"__data",value != null);
			var vint = Std.parseInt(value);
			if( vint == null ) vint = 0;
			var pos = 0;
			for( i in 0...fl.length ) {
				out('<input name="@name" class="@css"',{ name : name + "_" + fl[i], css : "dbool" });
				out(' type="checkbox"');
				if( vint & (1 << i) != 0 ) out(' checked="1"');
				out('/>');
				out(fl[i]);
			}
			endLine();
		case DBinary, DSmallBinary, DLongBinary, DBytes(_), DNull, DInterval:
			throw "NotSupported";
		}
	}

	public function binField( name : String, isNull, value : String, url : Void -> String ) {
		beginLine(true);
		out(name);
		nextRow();
		if( isNull )
			checkBox(name+"__data",value != null);
		if( value != null )
			text("["+value.length+" bytes]");
		else if( url != null )
			text("null");
		out('<input type="file" class="dfile" name="@name"/>',{ name : name });
		if( value != null && url != null )
			link(url(),"download");
		endLine();
	}

	public function infoField( name : String, value ) {
		beginLine(true);
		out(name);
		nextRow();
		out(value);
		endLine();
	}

	public function choiceField( name : String, values : List<{ id : String, str : String }>, def : String, link, ?disabled : Bool, ?isImage: Bool ) {
		beginLine(true);
		out(name);
		nextRow();
		var infos = {
			func : if( isImage ) "updateImage" else "updateLink",
			name : name,
			link : link,
			size : if( values != null && values.length > 15 ) 10 else 1,
			dis : if( disabled ) 'disabled="yes"' else "",
			def : if( def == "null" ) "" else def,
		};
		if( values == null )
			out('<input id="@name" name="@name" class="dint" value="@def" @dis onchange="@func(\'@name\',\'@link\',this.value)"/>',infos);
		else {
			out('<select id="@name" name="@name" class="dselect" size="@size" @dis onchange="@func(\'@name\',\'@link\',this.value)">',infos);
			out('<option value="">---- none -----</option>');
			for( v in values )
				out('<option value="@id"@sel>@str</option>',{ id : v.id, str : v.str, sel : if( v.id == def ) ' selected="yes"' else "" });
			out('</select>');
		}
		out('<a id="@name__goto" href="#">goto</a>',{ name : name });
		if( isImage )
			out('<img class="dfile" id="@name__img" src="@file"/>',{ name : name, file : getFileURL(def) });
		out('<script lang="text/javascript">document.getElementById("@name").onchange()</script>',{ name : name });
		endLine();
	}

	public function errorField( message ) {
		beginLine(true);
		nextRow();
		error(message);
		endLine();
	}

	public function error( message ) {
		out('<div class="derror">@msg</div>',{ msg : message });
	}

}

#end
