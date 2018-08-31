import hex.unittest.notifier.*;
import hex.unittest.runner.*;

using Lambda;

class Main
{
	static function main() {
		var arg = Sys.args()[0];
		var mysqlConnection = (arg != null && arg.substr(0,8)=="mysql://") ? arg : null;

		var emu = new ExMachinaUnitCore();
		emu.addListener(new ConsoleNotifier(false));
		emu.addListener(new ExitingNotifier());
		if(mysqlConnection!=null) emu.addTest(MySQLTest);
		emu.addTest(SQLiteTest);		
		emu.run();
	}

	
}
