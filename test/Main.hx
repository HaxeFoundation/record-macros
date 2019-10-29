import hex.unittest.notifier.*;
import hex.unittest.runner.*;

class Main {
	static function main() {
		var arg = Sys.args()[0];
        
        // don't lose Date.toString() to DCE
        var s = Date.now().toString();
        var n = s.length;
		var mysqlConnection = (arg != null && arg.substr(0,8)=="mysql://") ? arg : null;

		var emu = new ExMachinaUnitCore();
		emu.addListener(new ConsoleNotifier(false));
		emu.addListener(new ExitingNotifier());

		// use addRuntimeTest so the inheritance chain is followed
		if(mysqlConnection != null)
			emu.addRuntimeTest(MySQLTest);
		emu.addRuntimeTest(SQLiteTest);

		emu.run();
	}
}
