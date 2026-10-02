import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openOffgridDatabase() async {
  final directory = await getApplicationDocumentsDirectory();
  await directory.create(recursive: true);

  final databasePath = p.join(directory.path, 'offgrid_sos_week3.db');

  return databaseFactoryIo.openDatabase(databasePath);
}
