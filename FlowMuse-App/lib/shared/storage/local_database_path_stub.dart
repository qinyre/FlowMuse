import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<DatabaseFactory> createPlatformLocalDatabaseFactory() {
  throw UnsupportedError('当前平台不支持 FlowMuse 本地数据库');
}

Future<String> platformLocalDatabaseDirectory() {
  throw UnsupportedError('当前平台不支持 FlowMuse 本地数据库路径');
}
