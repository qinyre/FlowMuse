import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<DatabaseFactory> createLibraryDatabaseFactory() {
  throw UnsupportedError('当前平台暂不支持本地 SQLite 资料库。');
}

Future<String> libraryDatabaseDirectory() {
  throw UnsupportedError('当前平台暂不支持本地 SQLite 资料库。');
}
