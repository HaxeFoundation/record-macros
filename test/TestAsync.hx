import sys.db.AsyncConnection;
import sys.db.MysqlJs;

class TestAsync {
    static function main() {
        MysqlJs.connect({
            host: 'localhost',
            user: 'root',
            password: 'root',
            database: 'enthraler'
        }, function (err, cnx) {
            if (err != null) {
                throw err;
                return;
            }
            cnx.request('SELECT * FROM Content', function (err, rs) {
                if (err != null) {
                    throw err;
                    return;
                }

                for (result in rs.results()) {
                    trace(result);
                }

                cnx.close(function (err) {
                    if (err != null) {
                        throw err;
                        return;
                    }
                    trace('Done!');
                });
            });
        });
    }
}
