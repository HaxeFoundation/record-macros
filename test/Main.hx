class Main {
	static function main() {

		var runner = new utest.Runner();
		utest.ui.Report.create(runner);

		var sqlitePath = ":memory:";
		var mysqlParams = null;

		for (arg in Sys.args()) {
			switch arg {
			case dbstr if (mysqlParams == null && dbstr.indexOf("mysql://") == 0):
				var dbreg = ~/([^:]+):\/\/([^:]+):([^@]*?)@([^:]+)(:[0-9]+)?\/(.*?)$/;
				if (!dbreg.match(dbstr))
					throw "Configuration requires a valid database attribute, format is : mysql://user:password@host:port/dbname";
				var port = dbreg.matched(5);
				mysqlParams = {
					user:dbreg.matched(2),
					pass:dbreg.matched(3),
					host:dbreg.matched(4),
					port:port == null ? 3306 : Std.parseInt(port.substr(1)),
					database:dbreg.matched(6),
					socket:null
				};
			case "--on-disk-sqlite":
				sqlitePath = "test.db";
			case other:
				throw 'Unsupported command line option or parameter: $other';
			}
		}

		runner.addCase(new SqliteTest(sqlitePath));
		if (mysqlParams != null)
			runner.addCase(new MysqlTest(mysqlParams));

		runner.run();
	}
}
