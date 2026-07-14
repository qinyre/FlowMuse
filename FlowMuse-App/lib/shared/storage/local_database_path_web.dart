import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<DatabaseFactory> createPlatformLocalDatabaseFactory() async {
  return databaseFactoryFfiWeb;
}

Future<String> platformLocalDatabaseDirectory() async => '';
