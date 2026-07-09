import 'package:sqflite_common/sqlite_api.dart';

import 'local_database_path_stub.dart'
    if (dart.library.io) 'local_database_path_io.dart';

Future<DatabaseFactory> createLocalDatabaseFactory() {
  return createPlatformLocalDatabaseFactory();
}

Future<String> localDatabaseDirectory() {
  return platformLocalDatabaseDirectory();
}
