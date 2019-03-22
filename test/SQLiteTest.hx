class SQLiteTest extends CommonDatabaseTest {
	override function connect()
	{
		sys.db.Manager.cnx = sys.db.Sqlite.open("test.sqlite");
	}
}
