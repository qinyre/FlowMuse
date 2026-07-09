import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_database_path_stub.dart'
    if (dart.library.io) 'local_database_path_io.dart';

Future<DatabaseFactory> createLocalDatabaseFactory() {
  return createPlatformLocalDatabaseFactory();
}

Future<String> localDatabaseDirectory() {
  return platformLocalDatabaseDirectory();
}
