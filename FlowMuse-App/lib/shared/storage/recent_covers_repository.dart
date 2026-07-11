import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import 'local_database.dart';

/// 最近使用的封面记录
class RecentCoverItem {
  const RecentCoverItem({
    required this.type, // 'color' 或 'image'
    required this.value, // 颜色值或图片路径
    required this.timestamp,
  });

  final String type;
  final String value;
  final int timestamp;

  Map<String, dynamic> toMap() => {
        'type': type,
        'value': value,
        'timestamp': timestamp,
      };

  factory RecentCoverItem.fromMap(Map<String, dynamic> map) => RecentCoverItem(
        type: map['type'] as String,
        value: map['value'] as String,
        timestamp: map['timestamp'] as int,
      );
}

/// 最近使用的封面存储仓库
class RecentCoversRepository {
  RecentCoversRepository(this._openDatabase);

  final Future<Database> Function() _openDatabase;
  static const _maxRecentItems = 6;

  /// 获取最近使用的封面列表
  Future<List<RecentCoverItem>> getRecentCovers(String category) async {
    final db = await _openDatabase();
    final rows = await db.query(
      'local_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['recent_covers_$category'],
      limit: 1,
    );
    if (rows.isEmpty) return [];

    final jsonStr = rows.first['value'] as String;
    final list = json.decode(jsonStr) as List;
    return list.map((e) => RecentCoverItem.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// 添加最近使用的封面（颜色或图片）
  Future<void> addRecentCover(String category, String type, String value) async {
    final recent = await getRecentCovers(category);

    // 移除重复项
    recent.removeWhere((item) => item.type == type && item.value == value);

    // 添加到最前面
    recent.insert(
      0,
      RecentCoverItem(
        type: type,
        value: value,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    // 限制数量
    final trimmed = recent.take(_maxRecentItems).toList();

    // 保存
    final db = await _openDatabase();
    await db.insert(
      'local_settings',
      {
        'key': 'recent_covers_$category',
        'value': json.encode(trimmed.map((e) => e.toMap()).toList()),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 清除所有最近使用的封面
  Future<void> clearRecentCovers(String category) async {
    final db = await _openDatabase();
    await db.delete(
      'local_settings',
      where: 'key = ?',
      whereArgs: ['recent_covers_$category'],
    );
  }
}

final defaultRecentCoversRepository = RecentCoversRepository(
  LocalDatabase.open,
);
