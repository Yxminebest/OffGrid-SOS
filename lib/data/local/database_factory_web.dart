import 'package:sembast_web/sembast_web.dart';

Future<Database> openOffgridDatabase() {
  return databaseFactoryWeb.openDatabase('offgrid_sos_week3');
}
