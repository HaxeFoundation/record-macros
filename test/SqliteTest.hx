class SqliteTest extends CommonDatabaseTest {
	var dbPath:String;

	public function new(dbPath) {
		this.dbPath = dbPath;
		super();
	}

	override function connect() {
		sys.db.Manager.cnx = sys.db.Sqlite.open(dbPath);
	}
}
