class MysqlTest extends CommonDatabaseTest {
	var dbparams:{
		host:String,
		?port:Int,
		user:String,
		pass:String,
		?socket:String,
		?database:String,
	};

	public function new(dbparams) {
		this.dbparams = dbparams;
		super();
	}

	override function connect() {
		sys.db.Manager.cnx = sys.db.Mysql.connect(dbparams);
	}
}
