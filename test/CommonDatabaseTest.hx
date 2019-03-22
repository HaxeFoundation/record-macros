import MySpodClass;
import haxe.EnumFlags;
import haxe.io.Bytes;
import hex.unittest.assertion.Assert;
import sys.db.*;
import sys.db.Types;

using Lambda;

class CommonDatabaseTest {
	function connect()
	{
		throw "Not implemented";
	}

	static var testClasses:Array<{ manager:Manager<Dynamic> }> = [
		MySpodClass,
		OtherSpodClass,
		NullableSpodClass,
		ClassWithStringId,
		ClassWithStringIdRef,
		IssueC3828,
		Issue6041Table,
		Issue19SpodClass
	];

	@Before
	public function before()
	{
		Manager.initialize();
		connect();
		for (cls in testClasses) {
			var quoteField = @:privateAccess cls.manager.quoteField;
			var name = cls.manager.dbInfos().name;
			try {
				Manager.cnx.request('DROP TABLE ${quoteField(name)}');
			}
			catch (e:Dynamic) {
				// ignore
			}
			TableCreate.create(cls.manager);
		}
		Manager.cleanup();
	}

	@After
	public function after()
	{
		Manager.cnx.close();
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

	@Test
	public function testNull() {
		var n1 = getDefaultNull();
		n1.insert();
		var n2 = new NullableSpodClass();
		n2.insert();
		var id = n2.theId;

		n1 = null; n2 = null;
		Manager.cleanup();

		var nullVal = getNull();
		inline function checkReq(lst:List<NullableSpodClass>, ?nres=1, ?pos:haxe.PosInfos) {
			Assert.equals(nres, lst.length, null, pos);
			if (lst.length == 1) {
				Assert.equals(id, lst.first().theId, null, pos);
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

	@Test
	public function testIssue3828()
	{
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
		Assert.equals(u1id, u1.id);
		Assert.equals(u2id, u2.id);
	}

	@Test
	public function testIssue6041()
	{
		var item = new Issue6041Table();
		item.insert();
		var result = Manager.cnx.request('SELECT * FROM Issue6041Table LIMIT 1');
		var amount = 1;
		for(row in result) {
			Assert.isFalse(--amount < 0, "Invalid amount of rows in result");
		}
		Assert.equals(0, amount);
	}

	@Test
	public function testStringIdRel()
	{
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
		Assert.equals(1, first.length);
		var first = first.first();
		Assert.equals(1, first.field);
		var frel = ClassWithStringIdRef.manager.search($ref == first);
		Assert.equals(2, frel.length);
		for (rel in frel)
			Assert.equals(first, rel.ref);
		var frel2 = ClassWithStringIdRef.manager.search($ref_id == "first");
		Assert.equals(2, frel2.length);
		for (rel in frel2)
			Assert.equals(first, rel.ref);

		var second = ClassWithStringId.manager.search($name == "second");
		Assert.equals(1, second.length);
		var second = second.first();
		Assert.equals(2, second.field);
		var srel = ClassWithStringIdRef.manager.search($ref == second);
		Assert.equals(1, srel.length);
		for (rel in srel)
			Assert.equals(second, rel.ref);

		Assert.equals(-1, frel.array().indexOf(srel.first()));
		second.delete();
		for (r in srel) r.delete();
		first.delete();
		for (r in frel) r.delete();
	}

	@Test
	public function testEnum()
	{
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
		Assert.deepEquals(r1s, [id1, id2]);
		var r2s = MySpodClass.manager.search($anEnum == FirstValue);
		Assert.equals(1, r2s.length);
		Assert.equals(id3, r2s.first().theId);
		Assert.equals(id1, r2s.first().next.theId);
		Assert.equals(id2, r2s.first().next.next.theId);

		var fv = getSecond();
		var r1s = [ for (c in MySpodClass.manager.search($anEnum == fv,{orderBy:theId})) c.theId ];
		Assert.deepEquals(r1s, [id1, id2]);
		var r2s = MySpodClass.manager.search($anEnum == getFirst());
		Assert.equals(1, r2s.length);
		Assert.equals(id3, r2s.first().theId);

		var ids = [id1,id2,id3];
		var s = [ for (c in MySpodClass.manager.search( $anEnum == SecondValue || ($theId in ids) )) c.theId ];
		s.sort(Reflect.compare);
		Assert.deepEquals(s, [id1, id2, id3]);

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

	@Test
	public function testUpdate()
	{
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
		Assert.isNull(untyped MySpodClass.manager.getUpdateStatement(scls));
		Manager.cleanup();
		scls = MySpodClass.manager.get(id);
		Assert.isNull(untyped MySpodClass.manager.getUpdateStatement(scls));
		scls.delete();

		//try now with null SData and null relation
		var scls = new NullableSpodClass();
		scls.insert();

		var id = scls.theId;

		//if no change made, update should return nothing
		Assert.isNull(untyped NullableSpodClass.manager.getUpdateStatement(scls));
		Manager.cleanup();
		scls = NullableSpodClass.manager.get(id);
		Assert.isNull(untyped NullableSpodClass.manager.getUpdateStatement(scls));
		Assert.isNull(scls.data);
		Assert.isNull(scls.relationNullable);
		Assert.isNull(scls.abstractType);
		Assert.isNull(scls.anEnum);
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
		Assert.isNull(untyped NullableSpodClass.manager.getUpdateStatement(scls));
		Manager.cleanup();
		scls = NullableSpodClass.manager.get(id);
		Assert.isNull(untyped NullableSpodClass.manager.getUpdateStatement(scls));
		Assert.isNull(scls.data);
		Assert.isNull(scls.relationNullable);
		Assert.isNull(scls.abstractType);
		Assert.isNull(scls.anEnum);
		Manager.cleanup();

		scls = new NullableSpodClass();
		scls.theId = id;
		Assert.isNotNull(untyped NullableSpodClass.manager.getUpdateStatement(scls));

		scls.delete();
	}

	@Test
	public function testSpodTypes()
	{
		var c1 = new OtherSpodClass("first spod");
		c1.insert();
		var c2 = new OtherSpodClass("second spod");
		c2.insert();

		var scls = getDefaultClass();

		scls.relation = c1;
		scls.relationNullable = c2;
		scls.insert();

		//after inserting, id must be filled
		Assert.notEquals(0, scls.theId, pos());
		Assert.isNotNull(scls.theId);
		var theid = scls.theId;

		c1 = c2 = null;
		Manager.cleanup();

		var cls1 = MySpodClass.manager.get(theid);
		Assert.isNotNull(cls1, pos());
		//after Manager.cleanup(), the instances should be different
		Assert.isFalse(cls1 == scls, pos());
		scls = null;

		Assert.isInstanceOf(cls1.int, Int, pos());
		Assert.equals(1, cls1.int, pos());
		Assert.isInstanceOf(cls1.double, Float, pos());
		Assert.equals(2.0, cls1.double, pos());
		Assert.isInstanceOf(cls1.boolean, Bool, pos());
		Assert.isTrue(cls1.boolean, pos());
		Assert.isInstanceOf(cls1.string, String, pos());
		Assert.equals("some string", cls1.string, pos());
		Assert.isInstanceOf(cls1.abstractType, String, pos());
		Assert.equals("other string", cls1.abstractType.get(), pos());
		Assert.isNotNull(cls1.date, pos());
		Assert.isInstanceOf(cls1.date, Date, pos());
		Assert.equals(new Date(2012, 7, 30, 0, 0, 0).getTime(), cls1.date.getTime(), pos());

		Assert.isInstanceOf(cls1.binary, Bytes, pos());
		Assert.equals(0, cls1.binary.compare(Bytes.ofString("\x01\n\r'\x02")), pos());
		Assert.isTrue(cls1.enumFlags.has(FirstValue), pos());
		Assert.isFalse(cls1.enumFlags.has(SecondValue), pos());
		Assert.isTrue(cls1.enumFlags.has(ThirdValue), pos());

		Assert.isInstanceOf(cls1.data, Array, pos());
		Assert.isInstanceOf(cls1.data[0], ComplexClass, pos());

		Assert.equals("test", cls1.data[0].val.name, pos());
		Assert.equals(4, cls1.data[0].val.array.length, pos());
		Assert.equals("is", cls1.data[0].val.array[1], pos());

		Assert.equals("first spod", cls1.relation.name, pos());
		Assert.equals("second spod", cls1.relationNullable.name, pos());

		Assert.equals(SecondValue, cls1.anEnum, pos());
		Assert.isInstanceOf(cls1.anEnum, SpodEnum, pos());

		Assert.equals("\000a", cls1.bytes.toString());

		Assert.equals(MySpodClass.manager.select($anEnum == SecondValue), cls1, pos());

		//test create a new class
		var scls = getDefaultClass();

		c1 = new OtherSpodClass("third spod");
		c1.insert();

		scls.relation = c1;
		scls.insert();

		scls = cls1 = null;
		Manager.cleanup();

		Assert.equals(2, MySpodClass.manager.all().length, pos());
		var req = MySpodClass.manager.search({ relation: OtherSpodClass.manager.select({ name:"third spod"} ) });
		Assert.equals(1, req.length, pos());
		scls = req.first();

		scls.relation.name = "Test";
		scls.relation.update();

		Assert.isNull(OtherSpodClass.manager.select({ name:"third spod" }), pos());

		for (c in MySpodClass.manager.all())
			c.delete();
		for (c in OtherSpodClass.manager.all())
			c.delete();

		//issue #3598
		var inexistent = MySpodClass.manager.get(1000,false);
		Assert.isNull(inexistent);
	}

	@Test
	public function testDateQuery()
	{
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
		Assert.equals(1, q.length, pos());
		Assert.equals(c2, q.first(), pos());

		q = MySpodClass.manager.search($date == now);
		Assert.equals(1, q.length, pos());
		Assert.equals(c1, q.first(), pos());

		q = MySpodClass.manager.search($date >= now);
		Assert.equals(2, q.length, pos());
		Assert.equals(c1, q.first(), pos());

		q = MySpodClass.manager.search($date >= DateTools.delta(now, DateTools.hours(2)));
		Assert.equals(0, q.length, pos());
		Assert.isNull(q.first(), pos());

		c1.delete();
		c2.delete();
		other1.delete();
	}

	@Test
	public function testData()
	{
		var other1 = new OtherSpodClass("required field");
		other1.insert();

		var c1 = getDefaultClass();
		c1.relation = other1;
		c1.insert();

		Assert.equals(1, c1.data.length, pos());
		c1.data.pop();
		c1.update();

		Manager.cleanup();
		c1 = null;

		c1 = MySpodClass.manager.select($relation == other1);
		Assert.equals(0, c1.data.length, pos());
		c1.data.push(new ComplexClass({ name: "test1", array:["complex","field"] }));
		c1.data.push(null);
		Assert.equals(2, c1.data.length, pos());
		c1.update();

		Manager.cleanup();
		c1 = null;

		c1 = MySpodClass.manager.select($relation == other1);
		Assert.equals(2, c1.data.length, pos());
		Assert.equals("test1", c1.data[0].val.name, pos());
		Assert.equals(2, c1.data[0].val.array.length, pos());
		Assert.equals("complex", c1.data[0].val.array[0], pos());
		Assert.isNull(c1.data[1], pos());

		c1.delete();
		other1.delete();
	}

	@Test("Check that relations are not affected by the analyzer")
	public function testIssue6()
	{
		/*
		The way the analyzer transforms the expression (to prevent
		potential side-effects) might change the context where `untyped
		__this__` is evaluated.

		See: #6 and HaxeFoundation/haxe#6048
		*/
		var parent = new MySpodClass();
		parent.relation = new OtherSpodClass("i");

		Assert.isNotNull(parent.relation);
		Assert.equals("i", parent.relation.name);
	}

	@Test("Ensure that field types using full paths can be matched")
	public function testIssue19()
	{
		var val = new Issue19SpodClass();
		val.anEnum = SecondValue;
		val.insert();
	}

	@Test("Test that cache management doesn't break @:skip fields")
	public function testIssue34()
	{
		var child = new OtherSpodClass("i");
		child.insert();
		var main = getDefaultClass();
		main.relation = child;
		main.insert();
		Manager.cleanup();

		// underlying problem
		child = OtherSpodClass.manager.all(false).first();
		child = OtherSpodClass.manager.all(true).first();
		Assert.isNull(child.ignored);

		// reported/real world case
		main = MySpodClass.manager.all().first();
		Assert.isNotNull(main.relation);  // cache child, but !lock
		child = OtherSpodClass.manager.all().first();  // cache and lock
		Assert.isNull(child.ignored);
	}

	private function pos(?p:haxe.PosInfos):haxe.PosInfos
	{
		p.fileName = p.fileName + "(" + Manager.cnx.dbName()  +")";
		return p;
	}
}
