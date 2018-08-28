import hex.unittest.assertion.Assert;
import hex.unittest.notifier.*;
import hex.unittest.runner.*;

using Lambda;

class Main
{
	static function main() {
		var emu = new ExMachinaUnitCore();
		emu.addListener(new ConsoleNotifier(false));
		emu.addListener(new ExitingNotifier());
		emu.addTest(MySQLTest);
		emu.addTest(SQLiteTest);		
		emu.run();
	}

	
}
