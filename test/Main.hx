class Main {
	static function main() {
		var dbstr = Sys.args()[0];

		var runner = new utest.Runner();
		utest.ui.Report.create(runner);

		runner.addCase(new SqliteTest("test.sqlite"));

		if(dbstr != null) {
			var dbreg = ~/([^:]+):\/\/([^:]+):([^@]*?)@([^:]+)(:[0-9]+)?\/(.*?)$/;
			if (!dbreg.match(dbstr))
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
			runner.addCase(new MysqlTest(dbparams));
		}

		runner.run();
	}
}
