class MySQLTest extends CommonDatabaseTest {
	override function connect()
	{
		var dbstr = Sys.args()[0];
		var dbreg = ~/([^:]+):\/\/([^:]+):([^@]*?)@([^:]+)(:[0-9]+)?\/(.*?)$/;
		if( !dbreg.match(dbstr) )
			throw "Configuration requires a valid database attribute, format is : mysql://user:password@host:port/dbname";
		var port = dbreg.matched(5);
		var dbparams = {
			user:dbreg.matched(2),
			pass:dbreg.matched(3),
			host:dbreg.matched(4),
			port:port == null ? 3306 : Std.parseInt(port.substr(1)),
			database:dbreg.matched(6),
			socket:null
		};
		sys.db.Manager.cnx = sys.db.Mysql.connect(dbparams);
	}
}
