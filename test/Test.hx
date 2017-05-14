import sys.db.*;
import sys.db.Types;
import haxe.io.Bytes;
import haxe.EnumFlags;
import MySpodClass;

using Lambda;

class Test
{
	//static var out = sys.io.File.write("debug.txt", false);

	static inline function incrCount(?pos:haxe.PosInfos) {
		++count;
		//out.writeString(pos.methodName +":" +pos.lineNumber + "\n");
	}

	function eq<T>( v : T, v2 : T, ?pos ) {
		incrCount(pos);
		if( v != v2 ) {
			report(Std.string(v)+" should be "+Std.string(v2),pos);
			success = false;
		}
	}

	function feq( v : Float, v2 : Float, ?pos ) {
		incrCount(pos);
		if (!Math.isFinite(v) || !Math.isFinite(v2))
			eq(v, v2, pos);
		else if ( Math.abs(v - v2) > 1e-10 ) {
			report(v+" should be "+v2,pos);
			success = false;
		}
	}

	function aeq<T>(expected:Array<T>, actual:Array<T>, ?pos:haxe.PosInfos) {
		if (expected.length != actual.length) {
			report('Array length differs (${actual.length} should be ${expected.length})', pos);
			success = false;
		} else {
			for (i in 0...expected.length) {
				if (expected[i] != actual[i]) {
					report('[${i}] ${actual[i]} should be ${expected[i]}', pos);
					success = false;
				}
			}
		}
	}

	function t( v, ?pos ) {
		eq(v,true,pos);
	}

	function f( v, ?pos ) {
		eq(v,false,pos);
	}

	function assert( ?pos ) {
		report("Assert",pos);
	}

	function exc( f : Void -> Void, ?pos ) {
		incrCount(pos);
		try {
			f();
			report("No exception occurred",pos);
			success = false;
		} catch( e : Dynamic ) {
		}
	}

	function unspec( f : Void -> Void, ?pos ) {
		incrCount(pos);
		try {
			f();
		} catch( e : Dynamic ) {
		}
	}

	function allow<T>( v : T, values : Array<T>, ?pos ) {
		incrCount(pos);
		for( v2 in values )
			if( v == v2 )
				return;
		report(v+" not in "+Std.string(values),pos);
		success = false;
	}

	function hf(c:Class<Dynamic>, n:String, ?pos:haxe.PosInfos) {
		Test.incrCount(pos);
		if (!Lambda.has(Type.getInstanceFields(c), n)) {
			Test.report(Type.getClassName(c) + " should have member field " +n, pos);
			success = false;
		}
	}

	function nhf(c:Class<Dynamic>, n:String, ?pos:haxe.PosInfos) {
		Test.incrCount(pos);
		if (Lambda.has(Type.getInstanceFields(c), n)) {
			Test.report(Type.getClassName(c) + " should not have member field " +n, pos);
			success = false;
		}
	}

	function hsf(c:Class<Dynamic> , n:String, ?pos:haxe.PosInfos) {
		Test.incrCount(pos);
		if (!Lambda.has(Type.getClassFields(c), n)) {
			Test.report(Type.getClassName(c) + " should have static field " +n, pos);
			success = false;
		}
	}

	function nhsf(c:Class<Dynamic> , n:String, ?pos:haxe.PosInfos) {
		Test.incrCount(pos);
		if (Lambda.has(Type.getClassFields(c), n)) {
			Test.report(Type.getClassName(c) + " should not have static field " +n, pos);
			success = false;
		}
	}

	function infos( m : String ) {
		reportInfos = m;
	}

	function async<Args,T>( f : Args -> (T -> Void) -> Void, args : Args, v : T, ?pos : haxe.PosInfos ) : Void {
		if( asyncWaits.length >= AMAX ) {
			asyncCache.push(async.bind(f,args,v,pos));
			return;
		}
		asyncWaits.push(pos);
		f(args,function(v2) {
			incrCount(pos);
			if( !asyncWaits.remove(pos) ) {
				report("Double async result",pos);
				success = false;
				return;
			}
			if( v != v2 ) {
				report(v2+" should be "+v,pos);
				success = false;
			}
			checkDone();
		});
	}

	function asyncExc<Args>( seterror : (Dynamic -> Void) -> Void, f : Args -> (Dynamic -> Void) -> Void, args : Args, ?pos : haxe.PosInfos ) : Void {
		if( asyncWaits.length >= AMAX ) {
		asyncCache.push(asyncExc.bind(seterror,f,args,pos));
			return;
		}
		asyncWaits.push(pos);
		seterror(function(e) {
			incrCount(pos);
			if( asyncWaits.remove(pos) )
				checkDone();
			else {
				report("Multiple async events",pos);
				success = false;
			}
		});
		f(args,function(v) {
			incrCount(pos);
			if( asyncWaits.remove(pos) ) {
				report("No exception occurred",pos);
				success = false;
				checkDone();
			} else {
				report("Multiple async events",pos);
				success = false;
			}
		});
	}

	function log( msg, ?pos : haxe.PosInfos ) {
		haxe.Log.trace(msg,pos);
	}

   static function logVerbose(msg:String) {
	  #if (cpp || neko || php)
	  Sys.println(msg);
	  #end
   }

	static var count = 0;
	static var reportInfos = null;
	static var reportCount = 0;
	static var checkCount = 0;
	static var asyncWaits = new Array<haxe.PosInfos>();
	static var asyncCache = new Array<Void -> Void>();
	static var AMAX = 3;
	static var timer : haxe.Timer;
	static var success = true;

	dynamic static function report( msg : String, ?pos : haxe.PosInfos ) {
		if( reportInfos != null ) {
			msg += " ("+reportInfos+")";
			reportInfos = null;
		}
		haxe.Log.trace(msg,pos);
		reportCount++;
#if !(java || cs)
		if( reportCount == 50 ) {
			trace("Too many errors");
			report = function(msg,?pos) {};
		}
#end
	}

	static function checkDone() {
		if( asyncWaits.length != 0 ) return;
		if( asyncCache.length == 0 ) {
			report("DONE ["+count+" tests]");
			report("SUCCESS: " + success);

			//out.close();

			#if js
			if (js.Browser.supported) {
				untyped js.Browser.window.success = success;
			}
			#end

			#if sys
			Sys.exit(success ? 0 : 1);
			#end

			return;
		}
		resetTimer();
		while( asyncCache.length > 0 && asyncWaits.length < AMAX )
			asyncCache.shift()();
	}

	static function asyncTimeout() {
		if( asyncWaits.length == 0 )
			return;
		for( pos in asyncWaits ) {
			report("TIMEOUT",pos);
			success = false;
		}
		asyncWaits = new Array();
		checkDone();
	}

	static function resetTimer() {
		#if (neko || php || cpp || java || cs || python || hl || lua)
		#else
		if( timer != null ) timer.stop();
		timer = new haxe.Timer(30000);
		timer.run = asyncTimeout;
		#end
	}

	static function onError( e : Dynamic, msg : String, context : String ) {
		var msg = "???";
		var stack :String = #if js
			e.stack;
		#else
			haxe.CallStack.toString(haxe.CallStack.exceptionStack());
		#end
		try msg = Std.string(e) catch( e : Dynamic ) {};
		reportCount = 0;
		report("ABORTED : "+msg+" in "+context);
		success = false;
		reportInfos = null;
		trace("STACK :\n"+stack);
#if lua
		Sys.exit(1);
#end
	}

	static function main() {
	  var verbose = #if ( cpp || neko || php ) Sys.args().indexOf("-v") >= 0 #else false #end;

		resetTimer();
		trace("START");
		#if flash
		var tf : flash.text.TextField = untyped flash.Boot.getTrace();
		tf.selectable = true;
		tf.mouseEnabled = true;
		#end
		var classes = [
			// new Test(sys.db.Mysql.connect({
			// 	host : "127.0.0.1",
			// 	user : "travis",
			// 	pass : "",
			// 	port : 3306,
			// 	database : "haxe_test" })),
			new Test(sys.db.Sqlite.open("test.sqlite")),
		];
		var current = null;
		#if (!fail_eager)
		try
		#end
		{
			asyncWaits.push(null);
			for( inst in classes ) {
				current = Type.getClass(inst);
			if (verbose)
			   logVerbose("Class " + Std.string(current) );
				for( f in Type.getInstanceFields(current) )
					if( f.substr(0,4) == "test" ) {
				  if (verbose)
					 logVerbose("   " + f);
						#if fail_eager
						Reflect.callMethod(inst,Reflect.field(inst,f),[]);
						#else
						try {
							Reflect.callMethod(inst,Reflect.field(inst,f),[]);
						}
						#if !as3
						catch( e : Dynamic ) {
							onError(e,"EXCEPTION",Type.getClassName(current)+"."+f);
						}
						#end
						#end
						reportInfos = null;
					}
			}
			asyncWaits.remove(null);
			checkDone();
		}
		#if (!as3 && !(fail_eager))
		catch( e : Dynamic ) {
			asyncWaits.remove(null);
			onError(e,"ABORTED",Type.getClassName(current));
		}
		#end
	}


	private var cnx:Connection;
	public function new(cnx:Connection)
	{
		this.cnx = cnx;
		Manager.cnx = cnx;
		try cnx.request('DROP TABLE MySpodClass') catch(e:Dynamic) {}
		try cnx.request('DROP TABLE OtherSpodClass') catch(e:Dynamic) {}
		try cnx.request('DROP TABLE NullableSpodClass') catch(e:Dynamic) {}
		try cnx.request('DROP TABLE ClassWithStringId') catch(e:Dynamic) {}
		try cnx.request('DROP TABLE ClassWithStringIdRef') catch(e:Dynamic) {}
		try cnx.request('DROP TABLE IssueC3828') catch(e:Dynamic) {}
		try cnx.request('DROP TABLE Issue6041Table') catch(e:Dynamic) {}
		TableCreate.create(MySpodClass.manager);
		TableCreate.create(OtherSpodClass.manager);
		TableCreate.create(NullableSpodClass.manager);
		TableCreate.create(ClassWithStringId.manager);
		TableCreate.create(ClassWithStringIdRef.manager);
		TableCreate.create(IssueC3828.manager);
		TableCreate.create(Issue6041Table.manager);
	}

	private function setManager()
	{
		Manager.initialize();
		Manager.cnx = cnx;
		Manager.cleanup();
	}

	function getDefaultClass()
	{
		var scls = new MySpodClass();
		scls.int = 1;
		scls.double = 2.0;
		scls.boolean = true;
		scls.string = "some string";
		scls.date = new Date(2012, 7, 30, 0, 0, 0);
		scls.abstractType = "other string";

		var bytes = Bytes.ofString("\x01\n\r'\x02");
		scls.binary = bytes;
		scls.enumFlags = EnumFlags.ofInt(0);
		scls.enumFlags.set(FirstValue);
		scls.enumFlags.set(ThirdValue);
		scls.bytes = Bytes.ofString("\000a");

		scls.data = [new ComplexClass( { name:"test", array:["this", "is", "a", "test"] } )];
		scls.anEnum = SecondValue;

		return scls;
	}

	function getDefaultNull() {
		var scls = new NullableSpodClass();
		scls.int = 1;
		scls.double = 2.0;
		scls.boolean = true;
		scls.string = "some string";
		scls.date = new Date(2012, 7, 30, 0, 0, 0);
		scls.abstractType = "other string";

		var bytes = Bytes.ofString("\x01\n\r'\x02");
		scls.binary = bytes;
		scls.enumFlags = EnumFlags.ofInt(0);
		scls.enumFlags.set(FirstValue);
		scls.enumFlags.set(ThirdValue);

		scls.data = [new ComplexClass( { name:"test", array:["this", "is", "a", "test"] } )];
		scls.anEnum = SecondValue;
		return scls;
	}

	public function testNull() {
		setManager();
		var n1 = getDefaultNull();
		n1.insert();
		var n2 = new NullableSpodClass();
		n2.insert();
		var id = n2.theId;

		n1 = null; n2 = null;
		Manager.cleanup();

		var nullVal = getNull();
		inline function checkReq(lst:List<NullableSpodClass>, ?nres=1, ?pos:haxe.PosInfos) {
			eq(lst.length,nres, pos);
			if (lst.length == 1) {
				eq(lst.first().theId, id, pos);
			}
		}

		checkReq(NullableSpodClass.manager.search($relationNullable == null), 2);
		checkReq(NullableSpodClass.manager.search($data == null));
		checkReq(NullableSpodClass.manager.search($anEnum == null));

		checkReq(NullableSpodClass.manager.search($int == null));
		checkReq(NullableSpodClass.manager.search($double == null));
		checkReq(NullableSpodClass.manager.search($boolean == null));
		checkReq(NullableSpodClass.manager.search($string == null));
		checkReq(NullableSpodClass.manager.search($date == null));
		checkReq(NullableSpodClass.manager.search($binary == null));
		checkReq(NullableSpodClass.manager.search($abstractType == null));

		checkReq(NullableSpodClass.manager.search($enumFlags == null));


		var relationNullable:Null<OtherSpodClass> = getNull();
		checkReq(NullableSpodClass.manager.search($relationNullable == relationNullable), 2);
		var data:Null<Bytes> = getNull();
		checkReq(NullableSpodClass.manager.search($data == data));
		var anEnum:Null<SEnum<SpodEnum>> = getNull();
		checkReq(NullableSpodClass.manager.search($anEnum == anEnum));

		var int:Null<Int> = getNull();
		checkReq(NullableSpodClass.manager.search($int == int));
		var double:Null<Float> = getNull();
		checkReq(NullableSpodClass.manager.search($double == double));
		var boolean:Null<Bool> = getNull();
		checkReq(NullableSpodClass.manager.search($boolean == boolean));
		var string:SNull<SString<255>> = getNull();
		checkReq(NullableSpodClass.manager.search($string == string));
		var date:SNull<SDateTime> = getNull();
		checkReq(NullableSpodClass.manager.search($date == date));
		var binary:SNull<SBinary> = getNull();
		checkReq(NullableSpodClass.manager.search($binary == binary));
		var abstractType:SNull<String> = getNull();
		checkReq(NullableSpodClass.manager.search($abstractType == abstractType));

		for (val in NullableSpodClass.manager.all()) {
			val.delete();
		}
	}

	private function getNull<T>():Null<T> {
		return null;
	}

	public function testIssue3828()
	{
		setManager();
		var u1 = new IssueC3828();
		u1.insert();
		var u2 = new IssueC3828();
		u2.refUser = u1;
		u2.insert();
		var u1id = u1.id, u2id = u2.id;
		u1 = null; u2 = null;
		Manager.cleanup();

		var u1 = IssueC3828.manager.get(u1id);
		var u2 = IssueC3828.manager.search($refUser == u1).first();
		eq(u1.id, u1id);
		eq(u2.id, u2id);
	}

	public function testIssue6041()
	{
		setManager();
		var item = new Issue6041Table();
		item.insert();
		var result = cnx.request('SELECT * FROM Issue6041Table LIMIT 1');
		var amount = 1;
		for(row in result) {
			if(--amount < 0) throw "Invalid amount of rows in result";
		}
		eq(amount, 0);
	}
	
	public function testStringIdRel()
	{
		setManager();
		var s = new ClassWithStringId();
		s.name = "first";
		s.field = 1;
		s.insert();
		var v1 = new ClassWithStringIdRef();
		v1.ref = s;
		v1.insert();
		var v2 = new ClassWithStringIdRef();
		v2.ref = s;
		v2.insert();

		s = new ClassWithStringId();
		s.name = "second";
		s.field = 2;
		s.insert();
		v1 = new ClassWithStringIdRef();
		v1.ref = s;
		v1.insert();
		s = null; v1 = null; v2 = null;
		Manager.cleanup();

		var first = ClassWithStringId.manager.search($name == "first");
		eq(first.length,1);
		var first = first.first();
		eq(first.field,1);
		var frel = ClassWithStringIdRef.manager.search($ref == first);
		eq(frel.length,2);
		for (rel in frel)
			eq(rel.ref, first);
		var frel2 = ClassWithStringIdRef.manager.search($ref_id == "first");
		eq(frel2.length,2);
		for (rel in frel2)
			eq(rel.ref, first);

		var second = ClassWithStringId.manager.search($name == "second");
		eq(second.length,1);
		var second = second.first();
		eq(second.field,2);
		var srel = ClassWithStringIdRef.manager.search($ref == second);
		eq(srel.length,1);
		for (rel in srel)
			eq(rel.ref, second);

		eq(frel.array().indexOf(srel.first()), -1);
		second.delete();
		for (r in srel) r.delete();
		first.delete();
		for (r in frel) r.delete();
	}

	public function testEnum()
	{
		setManager();
		var c1 = new OtherSpodClass("first spod");
		c1.insert();
		var c2 = new OtherSpodClass("second spod");
		c2.insert();

		var scls = getDefaultClass();
		var scls1 = scls;
		scls.relation = c1;
		scls.insert();
		var id1 = scls.theId;
		scls = getDefaultClass();
		scls.relation = c1;
		scls.insert();

		scls1.next = scls;
		scls1.update();

		var id2 = scls.theId;
		scls = getDefaultClass();
		scls.relation = c1;
		scls.next = scls1;
		scls.anEnum = FirstValue;
		scls.insert();
		var id3 = scls.theId;
		scls = null;

		Manager.cleanup();
		var r1s = [ for (c in MySpodClass.manager.search($anEnum == SecondValue,{orderBy:theId})) c.theId ];
		eq([id1,id2].join(','),r1s.join(','));
		var r2s = MySpodClass.manager.search($anEnum == FirstValue);
		eq(r2s.length,1);
		eq(r2s.first().theId,id3);
		eq(r2s.first().next.theId,id1);
		eq(r2s.first().next.next.theId,id2);

		var fv = getSecond();
		var r1s = [ for (c in MySpodClass.manager.search($anEnum == fv,{orderBy:theId})) c.theId ];
		eq([id1,id2].join(','),r1s.join(','));
		var r2s = MySpodClass.manager.search($anEnum == getFirst());
		eq(r2s.length,1);
		eq(r2s.first().theId,id3);

		var ids = [id1,id2,id3];
		var s = [ for (c in MySpodClass.manager.search( $anEnum == SecondValue || $theId in ids )) c.theId ];
		s.sort(Reflect.compare);
		eq([id1,id2,id3].join(','),s.join(','));

		r2s.first().delete();
		for (v in MySpodClass.manager.search($anEnum == fv)) v.delete();
	}

	public function getFirst()
	{
		return FirstValue;
	}

	public function getSecond()
	{
		return SecondValue;
	}

	public function testUpdate()
	{
		setManager();
		var c1 = new OtherSpodClass("first spod");
		c1.insert();
		var c2 = new OtherSpodClass("second spod");
		c2.insert();
		var scls = getDefaultClass();
		scls.relation = c1;
		scls.relationNullable = c2;
		scls.insert();

		var id = scls.theId;

		//if no change made, update should return nothing
		eq( untyped MySpodClass.manager.getUpdateStatement( scls ), null );
		Manager.cleanup();
		scls = MySpodClass.manager.get(id);
		eq( untyped MySpodClass.manager.getUpdateStatement( scls ), null );
		scls.delete();

		//try now with null SData and null relation
		var scls = new NullableSpodClass();
		scls.insert();

		var id = scls.theId;

		//if no change made, update should return nothing
		eq( untyped NullableSpodClass.manager.getUpdateStatement( scls ), null );
		Manager.cleanup();
		scls = NullableSpodClass.manager.get(id);
		eq( untyped NullableSpodClass.manager.getUpdateStatement( scls ), null );
		eq(scls.data,null);
		eq(scls.relationNullable,null);
		eq(scls.abstractType,null);
		eq(scls.anEnum,null);
		scls.delete();

		//same thing with explicit null set
		var scls = new NullableSpodClass();
		scls.data = null;
		scls.relationNullable = null;
		scls.abstractType = null;
		scls.anEnum = null;
		scls.insert();

		var id = scls.theId;

		//if no change made, update should return nothing
		eq( untyped NullableSpodClass.manager.getUpdateStatement( scls ), null );
		Manager.cleanup();
		scls = NullableSpodClass.manager.get(id);
		eq( untyped NullableSpodClass.manager.getUpdateStatement( scls ), null );
		eq(scls.data,null);
		eq(scls.relationNullable,null);
		eq(scls.abstractType,null);
		eq(scls.anEnum,null);
		Manager.cleanup();

		scls = new NullableSpodClass();
		scls.theId = id;
		t( untyped NullableSpodClass.manager.getUpdateStatement( scls ) != null );

		scls.delete();
	}

	public function testSpodTypes()
	{
		setManager();
		var c1 = new OtherSpodClass("first spod");
		c1.insert();
		var c2 = new OtherSpodClass("second spod");
		c2.insert();

		var scls = getDefaultClass();

		scls.relation = c1;
		scls.relationNullable = c2;
		scls.insert();

		//after inserting, id must be filled
		t(scls.theId != 0 && scls.theId != null,pos());
		var theid = scls.theId;

		c1 = c2 = null;
		Manager.cleanup();

		var cls1 = MySpodClass.manager.get(theid);
		t(cls1 != null,pos());
		//after Manager.cleanup(), the instances should be different
		f(cls1 == scls,pos());
		scls = null;

		t((cls1.int is Int),pos());
		eq(cls1.int, 1,pos());
		t((cls1.double is Float),pos());
		eq(cls1.double, 2.0,pos());
		t((cls1.boolean is Bool),pos());
		eq(cls1.boolean, true,pos());
		t((cls1.string is String),pos());
		eq(cls1.string, "some string",pos());
		t((cls1.abstractType is String),pos());
		eq(cls1.abstractType.get(), "other string",pos());
		t(cls1.date != null,pos());
		t((cls1.date is Date),pos());
		eq(cls1.date.getTime(), new Date(2012, 7, 30, 0, 0, 0).getTime(),pos());

		t((cls1.binary is Bytes),pos());
		eq(cls1.binary.compare(Bytes.ofString("\x01\n\r'\x02")), 0,pos());
		t(cls1.enumFlags.has(FirstValue),pos());
		f(cls1.enumFlags.has(SecondValue),pos());
		t(cls1.enumFlags.has(ThirdValue),pos());

		t((cls1.data is Array),pos());
		t((cls1.data[0] is ComplexClass),pos());

		eq(cls1.data[0].val.name, "test",pos());
		eq(cls1.data[0].val.array.length, 4,pos());
		eq(cls1.data[0].val.array[1], "is",pos());

		eq(cls1.relation.name, "first spod",pos());
		eq(cls1.relationNullable.name, "second spod",pos());

		eq(cls1.anEnum, SecondValue,pos());
		t((cls1.anEnum is SpodEnum),pos());

		eq("\000a", cls1.bytes.toString());

		eq(cls1, MySpodClass.manager.select($anEnum == SecondValue),pos());

		//test create a new class
		var scls = getDefaultClass();

		c1 = new OtherSpodClass("third spod");
		c1.insert();

		scls.relation = c1;
		scls.insert();

		scls = cls1 = null;
		Manager.cleanup();

		eq(2, MySpodClass.manager.all().length,pos());
		var req = MySpodClass.manager.search({ relation: OtherSpodClass.manager.select({ name:"third spod"} ) });
		eq(req.length, 1,pos());
		scls = req.first();

		scls.relation.name = "Test";
		scls.relation.update();

		eq(OtherSpodClass.manager.select({ name:"third spod" }), null,pos());

		for (c in MySpodClass.manager.all())
			c.delete();
		for (c in OtherSpodClass.manager.all())
			c.delete();

		//issue #3598
		var inexistent = MySpodClass.manager.get(1000,false);
		eq(inexistent,null);
	}

	public function testDateQuery()
	{
		setManager();
		var other1 = new OtherSpodClass("required field");
		other1.insert();

		var now = Date.now();
		var c1 = getDefaultClass();
		c1.relation = other1;
		c1.date = now;
		c1.insert();

		var c2 = getDefaultClass();
		c2.relation = other1;
		c2.date = DateTools.delta(now, DateTools.hours(1));
		c2.insert();

		var q = MySpodClass.manager.search($date > now);
		eq(q.length, 1,pos());
		eq(q.first(), c2,pos());

		q = MySpodClass.manager.search($date == now);
		eq(q.length, 1,pos());
		eq(q.first(), c1,pos());

		q = MySpodClass.manager.search($date >= now);
		eq(q.length, 2,pos());
		eq(q.first(), c1,pos());

		q = MySpodClass.manager.search($date >= DateTools.delta(now, DateTools.hours(2)));
		eq(q.length, 0,pos());
		eq(q.first(), null,pos());

		c1.delete();
		c2.delete();
		other1.delete();
	}

	public function testData()
	{
		setManager();
		var other1 = new OtherSpodClass("required field");
		other1.insert();

		var c1 = getDefaultClass();
		c1.relation = other1;
		c1.insert();

		eq(c1.data.length,1,pos());
		c1.data.pop();
		c1.update();

		Manager.cleanup();
		c1 = null;

		c1 = MySpodClass.manager.select($relation == other1);
		eq(c1.data.length, 0,pos());
		c1.data.push(new ComplexClass({ name: "test1", array:["complex","field"] }));
		c1.data.push(null);
		eq(c1.data.length, 2,pos());
		c1.update();

		Manager.cleanup();
		c1 = null;

		c1 = MySpodClass.manager.select($relation == other1);
		eq(c1.data.length,2,pos());
		eq(c1.data[0].val.name, "test1",pos());
		eq(c1.data[0].val.array.length, 2,pos());
		eq(c1.data[0].val.array[0], "complex",pos());
		eq(c1.data[1], null,pos());

		c1.delete();
		other1.delete();
	}

	/**
		Check that relations are not affected by the analyzer

		See: #6 and HaxeFoundation/haxe#6048

		The way the analyzer transforms the expression (to prevent potential
		side-effects) might change the context where `untyped __this__` is
		evaluated.
	**/
	public function testIssue6()
	{
		setManager();

		var parent = new MySpodClass();
		parent.relation = new OtherSpodClass("i");

		f(parent.relation == null);
		eq(parent.relation.name, "i");
	}

	private function pos(?p:haxe.PosInfos):haxe.PosInfos
	{
		p.fileName = p.fileName + "(" + cnx.dbName()  +")";
		return p;
	}
	
	/**
	 * Relation issue with haxe 3.4.*
	 * 
	 * https://github.com/HaxeFoundation/haxe/issues/6048
	 * https://github.com/HaxeFoundation/record-macros/issues/6
	 */
	public function testIssue6048(){
		
		setManager();
		
		var sp = MySpodClass.manager.get(1, true);
		var sp2 = MySpodClass.manager.get(2, true);
		
		sp.next = sp2;
		sp.update();
		
		eq(sp2.theId, sp.next.theId);		
	}
}
