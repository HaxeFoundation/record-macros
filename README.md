[![Build Status](https://travis-ci.org/HaxeFoundation/record-macros.svg?branch=master)](https://travis-ci.org/HaxeFoundation/record-macros)

Record macros is a macro-based library that provides object-relational mapping to Haxe.
With `record-macros`, you can define some Classes that will map to your database tables. You can then manipulate tables like objects, by simply modifying the table fields and calling a method to update the datas or delete the entry. For most of the standard stuff, you only need to provide some basic declarations and you don't have to write one single SQL statement. You can later extend `record-macros` by adding your own SQL requests for some application-specific stuff.

## Creating a Record
You can simply declare a `record-macros` Object by extending the sys.db.Object class :

```haxe
import sys.db.Types;

class User extends sys.db.Object {
    public var id : SId;
    public var name : SString<32>;
    public var birthday : SDate;
    public var phoneNumber : SNull<SText>;
}
```
As you can see in this example, we are using special types declared in sys.db.Types in order to provide additional information for `record-macros`. Here's the list of supported types :

  * `Null<T>, SNull<T>` : tells that this field can be NULL in the database
  * `Int, SInt` : a classic 32 bits signed integer (SQL INT)
  * `Float, SFloat` : a double precision float value (SQL DOUBLE)
  * `Bool, SBool` : a boolean value (SQL TINYINT(1) or BOOL)
  * `Date, SDateTime` : a complete date value (SQL DATETIME)
  * `SDate` : a date-only value (SQL DATE)
  * `SString<K>` : a size-limited string value (SQL VARCHAR(K))
  * `String, SText` : a text up to 16 MB (SQL MEDIUMTEXT)
  * `SBytes<K>` : a fixed-size bytes value (SQL BINARY(K))
  * `SBinary, haxe.io.Bytes` : up to 16 MB bytes (SQL MEDIUMBLOB)
  * `SId` : same as SInt but used as an unique ID with auto increment (SQL INT AUTO INCREMENT)
  * `SEnum<E>` : a single enum without parameters which index is stored as a small integer (SQL TINYINT UNSIGNED)
  * `SFlags<E>` : a 32 bits flag that uses an enum as bit markers. See EnumFlags
  * `SData<Anything>` : allow arbitrary serialized data (see below)

### Advanced Types

The following advanced types are also available if you want a more custom storage size :

  * `SUInt` : an unsigned 32 bits integer (SQL UNSIGNED INT)
  * `STinyInt / STinyUInt` : a small 8 bits signed/unsigned integer (SQL TINYINT)
  * `SSmallInt / SSmallUInt` : a small 16 bits signed/unsigned integer (SQL SMALLINT)
  * `SMediumIInt / SMediumUInt` : a small 24 bits signed/unsigned integer (SQL MEDIUMINT)
  * `SBigInt` : a 64 bits signed integer (SQL BIGINT) - typed as Float in Haxe
  * `SSingle` : a single precision float value (SQL FLOAT)
  * `STinyText` : a text up to 255 bytes (SQL TINYTEXT)
  * `SSmallText` : a text up to 65KB (SQL TEXT)
  * `STimeStamp` : a 32-bits date timestamp (SQL TIMESTAMP)
  * `SSmallBinary` : up to 65 KB bytes (SQL BLOB)
  * `SLongBinary` : up to 4GB bytes (SQL LONGBLOB)
  * `SUId` : same as SUInt but used as an unique ID with auto increment (SQL INT UNSIGNED AUTO INCREMENT)
  * `SBigId` : same as SBigInt but used as an unique ID with auto increment (SQL BIGINT AUTO INCREMENT) - compiled as Float in Haxe
  * `SSmallFlags<E>` : similar to SFlags except that the integer used to store the data is based on the number of flags allowed

## Metadata
You can add Metadata to your `record-macros` class to declare additional informations that will be used by `record-macros`.

Before each class field :

  * `@:skip` : ignore this field, which will not be part of the database schema
  * `@:relation` : declare this field as a relation (see specific section below)

Before the `record-macros` class :

  * `@:table("myTableName")` : change the table name (by default it's the same as the class name)
  * `@:id(field1,field2,...)` : specify the primary key fields for this table. For instance the following class does not have a unique id with auto increment, but a two-fields unique primary key :

```haxe
@:id(uid,gid)
class UserGroup extends sys.db.Object {
    public var uid : SInt;
    public var gid : SInt;
}
```

  * `@:index(field1,field2,...,[unique])` : declare an index consisting of the specified classes fields - in that order. If the last field is unique then it means that's an unique index (each combination of fields values can only occur once)


## Init/Cleanup
There are two static methods that you might need to call before/after using `record-macros` :

  * `sys.db.Manager.initialize()` : will initialize the created managers. Make sure to call it at least once before using `record-macros`.
  * `sys.db.Manager.cleanup()` : will cleanup the temporary object cache. This can be done if you are using server module caching to free memory or after a rollback to make sure that we don't use the cached object version.

## Creating the Table
After you have declared your table you can create it directly from code without writing SQL. All you need is to connect to your database, for instance by using sys.db.Mysql, then calling sys.db.TableCreate.create that will execute the CREATE TABLE SQL request based on the `record-macros` infos :

```haxe
var cnx = sys.db.Mysql.connect({
   host : "localhost",
   port : null,
   user : "root",
   pass : "",
   database : "testBase",
   socket : null,
});
sys.db.Manager.cnx = cnx;
if ( !sys.db.TableCreate.exists(User.manager) )
{
    sys.db.TableCreate.create(User.manager);
}
```

Please note that currently TableCreate will not create the index or initialize the relations of your table.

## Insert
In order to insert a new `record-macros`, you can simply do the following :

```haxe
var u = new User();
u.name = "Random156";
u.birthday = Date.now();
u.insert();
```
After the `.insert()` is done, the auto increment unique id will be set and all fields that were null but not declared as nullable will be set to their default value (0 for numbers, "" for strings and empty bytes for binaries)

## Manager
Each `record-macros` object need its own manager. You can create your own manager by adding the following line to your `record-macros` class body :

```haxe
public static var manager = new sys.db.Manager<User>(User);
```
However, the `record-macros` Macros will do it automatically for you, so only add this if you want create your own custom Manager which will extend the default one.

## Get
In order to retrieve an instance of your `record-macros`, you can call the manager get method by using the object unique identifier (primary key) :

```haxe
var u = User.manager.get(1);
if( u == null ) throw "User #1 not found";
trace(u.name);
```
If you have a primary key with multiple values, you can use the following declaration :

```haxe
var ug = UserGroup.manager.get({ uid : 1, gid : 2 });
// ...
```

## Update/Delete
Once you have an instance of your `record-macros` object, you can modify its fields and call .update() to send these changes to the database :

```haxe
var u = User.manager.get(1);
if( u.phoneNumber == null ) u.phoneNumber = "+3360000000";
u.update();
```
You can also use `.delete()` to delete this object from the database :

```haxe
var u = User.manager.get(1);
if( u != null ) u.delete();
```

## Search Queries
If you want to search for some objects, you can use the `.manager.search` method :

```haxe
var minId = 10;
for( u in User.manager.search($id < minId) ) {
    trace(u);
}
```
In order to differentiate between the database fields and the Haxe variables, all the database fields are prefixed with a dollar in search queries.

Search queries are checked at compiletime and the following SQL code is generated instead :

```haxe
unsafeSearch("SELECT * FROM User WHERE id < "+Manager.quoteInt(minId));
```
The code generator also makes sure that no SQL injection is ever possible.

## Syntax
The following syntax is supported :

  * constants : integers, floats, strings, null, true and false
  * all operations `+, -, *, /, %, |, &, ^, >>, <<, >>>`
  * unary operations `!, - and ~`
  * all comparisons : `== , >= , <=, >, <, !=`
  * bool tests : `&& , ||`
  * parenthesis
  * calls and fields accesses (compiled as Haxe expressions)

When comparing two values with == or != and when one of them can be NULL, the SQL generator is using the <=> SQL operator to ensure that NULL == NULL returns true and NULL != NULL returns false.

## Additional Syntax
It is also possible to use anonymous objects to match exact values for some fields (similar to previous `record-macros` but typed :

```haxe
User.manager.search({ id : 1, name : "Nicolas" })
// same as :
User.manager.search($id == 1 && $name == "Nicolas")
// same as :
User.manager.search($id == 1 && { name : "Nicolas" })
```

You can also use if conditions to generate different SQL based on Haxe variables (you cannot use database fields in if test) :

```haxe
function listName( ?name : String ) {
    return User.manager.search($id < 10 && if( name == null ) true else $name == name);
}
```

## SQL operations
You can use the following SQL global functions in search queries :

  * `$now() : SDateTime`, returns the current datetime (SQL NOW())
  * `$curDate() : SDate`, returns the current date (SQL CURDATE())
  * `$date(v:SDateTime) : SDate`, returns the date part of the DateTime (SQL DATE())
  * `$seconds(v:Float) : SInterval`, returns the date interval in seconds (SQL INTERVAL v SECOND)
  * `$minutes(v:Float) : SInterval`, returns the date interval in minutes (SQL INTERVAL v MINUTE)
  * `$hours(v:Float) : SInterval`, returns the date interval in hours (SQL INTERVAL v HOUR)
  * `$days(v:Float) : SInterval`, returns the date interval in days (SQL INTERVAL v DAY)
  * `$months(v:Float) : SInterval`, returns the date interval in months (SQL INTERVAL v MONTH)
  * `$years(v:Float) : SInterval`, returns the date interval in years (SQL INTERVAL v YEAR)

You can use the following SQL operators in search queries :

  * `stringA.like(stringB)` : will use the SQL LIKE operator to find if stringB if contained into stringA

## SQL IN
You can also use the Haxe in operator to get similar effect as SQL IN :

```haxe
User.manager.search($name in ["a","b","c"]);
```
You can pass any Iterable to the in operator. An empty iterable will emit a false statement to prevent sql errors when doing IN ().

## Search Options
After the search query, you can specify some search options :

```haxe
// retrieve the first 20 users ordered by ascending name
User.manager.search(true,{ orderBy : name, limit : 20 });
```

The following options are supported :

  * `orderBy` : you can specify one of several order database fields and use a minus operation in front of the field to indicate that you want to sort in descending order. For instance orderBy : [-name,id] will generate SQL ORDER BY name DESC, id
  * `limit` : specify which result range you want to obtain. You can use Haxe variables and expressions in limit values, for instance : { limit : [pos,length] }
  * `forceIndex` : specify that you want to force this search to use the specific index. For example to force a two-fields index use { forceIndex : [name,date] }. The index name used in that case will be TableName_name_date

## Select/Count/Delete
Instead of search you can use the `manager.select` method, which will only return the first result object :

```haxe
var u = User.manager.select($name == "John");
// ...
```
You can also use the manager.count method to count the number of objects matching the given search query :

```haxe
var n = User.manager.count($name.like("J%") && $phoneNumber != null);
// ...
```
You can delete all objects matching the given query :

```haxe
User.manager.delete($id > 1000);
```

## Relations
You can declare relations between your database classes by using the @:relation metadata :

```haxe
class User extends sys.db.Object {
    public var id : SId;
    // ....
}
class Group extends sys.db.Object {
   public var id : SId;
   // ...
}

@:id(gid,uid)
class UserGroup extends sys.db.Object {
    @:relation(uid) public var user : User;
    @:relation(gid) public var group : Group;
}
```
The first time you read the user field from an UserGroup instance, `record-macros` will fetch the User instance corresponding to the current uid value and cache it. If you set the user field, it will modify the uid value as the same time.

## Locking
When using transactions, the default behavior for relations is that they are not locked. You can make there that the row is locked (SQL SELECT...FOR UPDATE) by adding the lock keyword after the relation key :

```haxe
@:relation(uid,lock) public var user : User;
```

## Cascading
Relations can be strongly enforced by using CONSTRAINT/FOREIGN KEY with MySQL/InnoDB. This way when an User instance is deleted, all the corresponding UserGroup for the given user will be deleted as well.

However if the relation field can be nullable, the value will be set to NULL.

If you want to enforce cascading for nullable-field relations, you can add the cascade keyword after the relation key :

```haxe
    @:relation(uid,cascade) var user : Null<User>;
```

## Relation Search
You can search a given relation by using either the relation key or the relation property :

```haxe
var user = User.manager.get(1);
var groups = UserGroup.manager.search($uid == user.id);
// same as :
var groups = UserGroup.manager.search($user == user);
```

The second case is more strictly typed since it does not only check that the key have the same type, and it also safer because it will use null id if the user value is null at runtime.

## Dynamic Search
If you want to build at runtime you own exact-values search criteria, you can use manager.dynamicSearch that will build the SQL query based on the values you pass it :

```haxe
var o = { name : "John", phoneNumber : "+818123456" };
var users = User.manager.dynamicSearch(o);
```
Please note that you can get runtime errors if your object contain fields that are not in the database table.

## Serialized Data

In order to store arbitrary serialized data in a `record-macros` object, you can use the SData type. For example :

```
import sys.db.Types
enum PhoneKind {
    AtHome;
    AtWork;
    Mobile;
}
class User extends sys.db.Object {
    public var id : SId;
    ...
    public var phones : SData<Array<{ kind : PhoneKind, number : String }>>;
}
```
When the phones field is accessed for reading (the first time only), it is unserialized. By default the data is stored as an haxe-serialized string, but you can override the doSerialize and doUnserialize methods of your Manager to have a specific serialization for a specific table or field
When the phones field has been either read or written, a flag will be set to remember that potential changes were made
When the `record-macros` object is either inserted or updated, the modified data is serialized and eventually sent to the database if some actual change have been done
As a consequence, pushing data into the phones Array or directly modifying the phone number will be noticed by the `record-macros` engine.

The SQL data type for SData is a binary blob, in order to allow any kind of serialization (text or binary), so the actual runtime value of the phones field is a Bytes. It will however only be accessible by reflection, since `record-macros` is changing the phones field into a property.

## Accessing the record-macros Infos
You can get the database schema by calling the `.dbInfos()` method on the Manager. It will return a `sys.db.RecordInfos` structure.

## Automatic Insert/Search/Edit Generation
The [dbadmin](https://github.com/ncannasse/dbadmin) project provides an HTML based interface that allows inserting/searching/editing and deleting `record-macros` objects based on the compiled `record-macros` information. It also allows database synchronization based on the `record-macros` schema by automatically detecting differences between the compile time schema and the current DB one.

## Compatibility
When using MySQL 5.7+, consider disabling [strict mode](https://dev.mysql.com/doc/refman/5.7/en/sql-mode.html#sql-mode-strict). Record-macros do not provide sufficient checks (strings length,field default values...) to avoid errors in strict mode.



