// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences_ohos/shared_preferences_ohos.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// 独立的功能测试页面，覆盖 ohos 实现的所有 Legacy API
class FunctionalTestPage extends StatefulWidget {
  const FunctionalTestPage({super.key});

  @override
  State<FunctionalTestPage> createState() => _FunctionalTestPageState();
}

class _FunctionalTestPageState extends State<FunctionalTestPage> {
  final SharedPreferencesStorePlatform _prefs =
      SharedPreferencesStorePlatform.instance;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _log('SharedPreferencesStorePlatform 实例: ${_prefs.runtimeType}');
  }

  void _log(String msg) {
    setState(() {
      _logs.add(msg);
    });
    debugPrint(msg);
  }

  Future<void> _clearLogs() async {
    setState(() {
      _logs.clear();
    });
  }

  // ========== Legacy API 测试方法 ==========

  Future<void> _testSetBool() async {
    _log('--- 测试 setBool ---');
    await _prefs.clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: '')),
    );
    final result = await _prefs.setValue('Bool', 'test.legacy.bool', true);
    _log('setValue Bool key=test.legacy.bool value=true => $result');
    final all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    _log('读取回值: ${all['test.legacy.bool']} (预期: true)');
    _log(all['test.legacy.bool'] == true ? '✅ PASS' : '❌ FAIL');

    final result2 = await _prefs.setValue('Bool', 'test.legacy.bool', false);
    _log('setValue Bool key=test.legacy.bool value=false => $result2');
    final all2 = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    _log('读取回值: ${all2["test.legacy.bool"]} (预期: false)');
    _log(all2["test.legacy.bool"] == false ? '✅ PASS' : '❌ FAIL');
  }

  Future<void> _testSetInt() async {
    _log('--- 测试 setInt ---');
    // 普通整数
    final r1 = await _prefs.setValue('Int', 'test.legacy.int', 42);
    _log('setValue Int key=test.legacy.int value=42 => $r1');
    var all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    _log('读取回值: ${all["test.legacy.int"]} (预期: 42)');
    _log(all["test.legacy.int"] == 42 ? '✅ PASS' : '❌ FAIL');

    // 零值
    final r2 = await _prefs.setValue('Int', 'test.legacy.int_zero', 0);
    _log('setValue Int key=test.legacy.int_zero value=0 => $r2');
    all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    _log('读取回值: ${all["test.legacy.int_zero"]} (预期: 0)');
    _log(all["test.legacy.int_zero"] == 0 ? '✅ PASS' : '❌ FAIL');

    // 负数
    final r3 = await _prefs.setValue('Int', 'test.legacy.int_neg', -999);
    _log('setValue Int key=test.legacy.int_neg value=-999 => $r3');
    all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    _log('读取回值: ${all["test.legacy.int_neg"]} (预期: -999)');
    _log(all["test.legacy.int_neg"] == -999 ? '✅ PASS' : '❌ FAIL');

    // 大整数 (int64)
    const int largeInt = 9007199254740991;
    final r4 = await _prefs.setValue('Int', 'test.legacy.int64', largeInt);
    _log('setValue Int key=test.legacy.int64 value=$largeInt => $r4');
    all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    _log('读取回值: ${all["test.legacy.int64"]} (预期: $largeInt)');
    _log(all["test.legacy.int64"] == largeInt ? '✅ PASS' : '❌ FAIL');
  }

  Future<void> _testSetDouble() async {
    _log('--- 测试 setDouble ---');
    const double testVal = 3.14159;
    final result = await _prefs.setValue('Double', 'test.legacy.double', testVal);
    _log('setValue Double key=test.legacy.double value=$testVal => $result');
    var all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    final readVal = all["test.legacy.double"];
    _log('读取回值: $readVal (预期: $testVal)');
    _log(readVal is double && (readVal - testVal).abs() < 0.0001
        ? '✅ PASS'
        : '❌ FAIL');

    // 零值 double (OHOS: 整数值double可能被识别为int)
    final r2 = await _prefs.setValue('Double', 'test.legacy.double_zero', 0.0);
    _log('setValue Double key=test.legacy.double_zero value=0.0 => $r2');
    all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    final readVal2 = all["test.legacy.double_zero"];
    _log('读取回值: $readVal2 (预期: 0.0)');
    _log(readVal2 is num && readVal2 == 0 ? '✅ PASS' : '❌ FAIL');

    // 负数 double
    final r3 =
        await _prefs.setValue('Double', 'test.legacy.double_neg', -1.5e10);
    _log('setValue Double key=test.legacy.double_neg value=-1.5e10 => $r3');
    all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    final readVal3 = all["test.legacy.double_neg"];
    _log('读取回值: $readVal3 (预期: -15000000000.0)');
    _log(readVal3 is num && (readVal3 - (-1.5e10)).abs() < 1.0
        ? '✅ PASS'
        : '❌ FAIL');

    // 整数值的 double (100.0) (OHOS: 整数值double可能被识别为int)
    final r4 =
        await _prefs.setValue('Double', 'test.legacy.double_int', 100.0);
    _log('setValue Double key=test.legacy.double_int value=100.0 => $r4');
    all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    final readVal4 = all["test.legacy.double_int"];
    _log('读取回值: $readVal4 (预期: 100.0)');
    _log(readVal4 is num && readVal4 == 100 ? '✅ PASS' : '❌ FAIL');
  }

  Future<void> _testSetString() async {
    _log('--- 测试 setString ---');
    // 普通字符串
    const String testVal = 'Hello OHOS';
    var result =
        await _prefs.setValue('String', 'test.legacy.string', testVal);
    _log('setValue String key=test.legacy.string value="$testVal" => $result');
    var all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    _log('读取回值: ${all["test.legacy.string"]} (预期: $testVal)');
    _log(all["test.legacy.string"] == testVal ? '✅ PASS' : '❌ FAIL');

    // 空字符串
    result = await _prefs.setValue('String', 'test.legacy.string_empty', '');
    _log('setValue String key=test.legacy.string_empty value="" => $result');
    all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    _log("读取回值: ${all["test.legacy.string_empty"]} (预期: 空串)");
    _log(all["test.legacy.string_empty"] == '' ? '✅ PASS' : '❌ FAIL');

    // 特殊字符
    const String specialVal = r'Special: !@#$%^&*()';
    result =
        await _prefs.setValue('String', 'test.legacy.string_special', specialVal);
    _log("setValue String key=test.legacy.string_special value=$specialVal => $result");
    all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    _log("读取回值: ${all["test.legacy.string_special"]} (预期: $specialVal)");
    _log(all["test.legacy.string_special"] == specialVal
        ? '✅ PASS'
        : '❌ FAIL');

    // Unicode
    const String unicodeVal = 'Unicode: 中文日本語한국어';
    result =
        await _prefs.setValue('String', 'test.legacy.string_unicode', unicodeVal);
    _log("setValue String key=test.legacy.string_unicode value=$unicodeVal => $result");
    all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    _log("读取回值: ${all["test.legacy.string_unicode"]} (预期: $unicodeVal)");
    _log(all["test.legacy.string_unicode"] == unicodeVal
        ? '✅ PASS'
        : '❌ FAIL');
  }

  Future<void> _testSetStringList() async {
    _log('--- 测试 setStringList ---');
    const List<String> testVal = <String>['foo', 'bar', 'baz'];
    var result =
        await _prefs.setValue('StringList', 'test.legacy.stringlist', testVal);
    _log('setValue StringList key=test.legacy.stringlist value=$testVal => $result');
    var all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    final readVal = all["test.legacy.stringlist"];
    _log('读取回值: $readVal (预期: $testVal)');
    _log(readVal is List && _listEquals(readVal as List, testVal)
        ? '✅ PASS'
        : '❌ FAIL');

    // 空列表
    result = await _prefs.setValue(
        'StringList', 'test.legacy.stringlist_empty', <String>[]);
    _log('setValue StringList key=test.legacy.stringlist_empty value=[] => $result');
    all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    final readVal2 = all["test.legacy.stringlist_empty"];
    _log('读取回值: $readVal2 (预期: [])');
    _log(readVal2 is List && (readVal2 as List).isEmpty
        ? '✅ PASS'
        : '❌ FAIL');

    // 包含特殊字符的列表
    const List<String> specialVal = <String>['hello world', 'foo,bar', 'a\nb\nc', ''];
    result = await _prefs.setValue(
        'StringList', 'test.legacy.stringlist_special', specialVal);
    _log('setValue StringList key=test.legacy.stringlist_special value=$specialVal => $result');
    all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    final readVal3 = all["test.legacy.stringlist_special"];
    _log('读取回值: $readVal3');
    _log(readVal3 is List && _listEquals(readVal3 as List, specialVal)
        ? '✅ PASS'
        : '❌ FAIL');
  }

  Future<void> _testRemove() async {
    _log('--- 测试 remove ---');
    await _prefs.setValue('String', 'test.legacy.remove_me', 'to_be_removed');
    _log('已存入 key=test.legacy.remove_me');
    final result = await _prefs.remove('test.legacy.remove_me');
    _log('remove key=test.legacy.remove_me => $result');
    final all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.legacy.')),
    );
    _log("移除后读取: ${all["test.legacy.remove_me"]} (预期: null)");
    _log(all["test.legacy.remove_me"] == null ? '✅ PASS' : '❌ FAIL');

    // 删除不存在的key
    final result2 = await _prefs.remove('test.legacy.nonexistent_key');
    _log('remove 不存在的key => $result2');
  }

  Future<void> _testGetAllWithPrefix() async {
    _log('--- 测试 getAllWithPrefix ---');
    // 先清空
    await _prefs.clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: '')),
    );
    // 写入不同前缀的数据
    await _prefs.setValue('String', 'prefix_a.key1', 'value_a1');
    await _prefs.setValue('String', 'prefix_a.key2', 'value_a2');
    await _prefs.setValue('String', 'prefix_b.key1', 'value_b1');
    // ignore: deprecated_member_use
    final result = await _prefs.getAllWithPrefix('prefix_a.');
    _log('getAllWithPrefix("prefix_a.") => $result');
    _log(result.length == 2
        ? '✅ PASS'
        : '❌ FAIL (预期2条, 实际${result.length}条)');
  }

  Future<void> _testGetAllWithParameters() async {
    _log('--- 测试 getAllWithParameters ---');
    await _prefs.clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: '')),
    );
    await _prefs.setValue('String', 'test.p1', 'v1');
    await _prefs.setValue('String', 'test.p2', 'v2');
    await _prefs.setValue('String', 'other.p3', 'v3');
    // 无 allowList
    var result = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.')),
    );
    _log('getAllWithParameters(prefix="test.") => $result');
    _log(result.length == 2
        ? '✅ PASS (2条)'
        : '❌ FAIL (${result.length}条)');
    // 有 allowList
    result = await _prefs.getAllWithParameters(
      GetAllParameters(
          filter:
              PreferencesFilter(prefix: 'test.', allowList: <String>{'test.p1'})),
    );
    _log('getAllWithParameters(prefix="test.", allowList={"test.p1"}) => $result');
    _log(result.length == 1
        ? '✅ PASS (1条)'
        : '❌ FAIL (${result.length}条)');
  }

  Future<void> _testClear() async {
    _log('--- 测试 clear ---');
    await _prefs.clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: '')),
    );
    await _prefs.setValue('String', 'clear_test.key1', 'v1');
    await _prefs.setValue('String', 'clear_test.key2', 'v2');
    // 默认前缀 clear
    await _prefs.setValue('String', 'flutter.key3', 'v3');
    final result = await _prefs.clear();
    _log('clear() => $result');
    final all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: '')),
    );
    _log("clear后 flutter.key3 应被删除: ${all["flutter.key3"]} (预期: null)");
    _log(all["flutter.key3"] == null ? '✅ PASS' : '❌ FAIL');
  }

  Future<void> _testClearWithParameters() async {
    _log('--- 测试 clearWithParameters ---');
    await _prefs.clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: '')),
    );
    await _prefs.setValue('String', 'clear_a.key1', 'v1');
    await _prefs.setValue('String', 'clear_b.key2', 'v2');
    // 清除 clear_a 前缀
    await _prefs.clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'clear_a.')),
    );
    final all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: '')),
    );
    _log('clear(prefix="clear_a.") 后所有数据: $all');
    _log(all["clear_a.key1"] == null && all["clear_b.key2"] == 'v2'
        ? '✅ PASS'
        : '❌ FAIL');
  }

  Future<void> _testClearWithAllowList() async {
    _log('--- 测试 clearWithParameters + allowList ---');
    await _prefs.clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: '')),
    );
    await _prefs.setValue('String', 'test.k1', 'v1');
    await _prefs.setValue('String', 'test.k2', 'v2');
    await _prefs.setValue('String', 'test.k3', 'v3');
    // 仅清除 k1 和 k2
    await _prefs.clearWithParameters(
      ClearParameters(
          filter: PreferencesFilter(
        prefix: 'test.',
        allowList: <String>{'test.k1', 'test.k2'},
      )),
    );
    final all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'test.')),
    );
    _log('clear(allowList={k1,k2}) 后: $all');
    _log(all["test.k1"] == null &&
            all["test.k2"] == null &&
            all["test.k3"] == 'v3'
        ? '✅ PASS'
        : '❌ FAIL');
  }

  Future<void> _testClearWithPrefix() async {
    _log('--- 测试 clearWithPrefix ---');
    await _prefs.clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: '')),
    );
    await _prefs.setValue('String', 'prefix_x.key1', 'v1');
    await _prefs.setValue('String', 'prefix_y.key2', 'v2');
    // ignore: deprecated_member_use
    final result = await _prefs.clearWithPrefix('prefix_x.');
    _log('clearWithPrefix("prefix_x.") => $result');
    final all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: '')),
    );
    _log("prefix_x.key1: ${all["prefix_x.key1"]} (预期: null)");
    _log("prefix_y.key2: ${all["prefix_y.key2"]} (预期: v2)");
    _log(all["prefix_x.key1"] == null && all["prefix_y.key2"] == 'v2'
        ? '✅ PASS'
        : '❌ FAIL');
  }

  Future<void> _testGetAll() async {
    _log('--- 测试 getAll ---');
    await _prefs.clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: '')),
    );
    await _prefs.setValue('String', 'flutter.key1', 'v1');
    await _prefs.setValue('Int', 'flutter.key2', 42);
    await _prefs.setValue('String', 'other.key3', 'v3');
    final result = await _prefs.getAll();
    _log('getAll() => $result');
    _log(result.containsKey('flutter.key1') && result.containsKey('flutter.key2') && !result.containsKey('other.key3')
        ? '✅ PASS (仅返回 flutter. 前缀)'
        : '❌ FAIL');
  }

  Future<void> _testStringPrefixClash() async {
    _log('--- 测试 setString 特殊前缀拒绝 ---');
    await _prefs.clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: '')),
    );
    const List<String> specialPrefixes = <String>[
      'VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu',
      'VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGRvdWJsZS4',
    ];
    int passCount = 0;
    for (final String prefix in specialPrefixes) {
      try {
        await _prefs.setValue('String', 'clash_key', '${prefix}test_value');
        _log('setValue 以特殊前缀 "$prefix" 开头: 未被拒绝 ❌ FAIL');
      } catch (e) {
        // ArkTS 侧可能抛出 Error 或通过 Pigeon 返回 PlatformException
        _log('setValue 以特殊前缀开头: 被正确拒绝 ✅ ($e)');
        passCount++;
      }
    }
    try {
      final all = await _prefs.getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: '')),
      );
      _log("特殊前缀数据未被存入: ${all["clash_key"] == null ? "✅ PASS" : "❌ FAIL"}");
    } catch (e) {
      _log('getAll 异常 (可能通道已断开): $e');
    }
    _log(passCount == specialPrefixes.length ? '✅ ALL PASS' : '❌ SOME FAILED ($passCount/${specialPrefixes.length})');
  }

  Future<void> _testSimultaneousWrites() async {
    _log('--- 测试并发写入 ---');
    await _prefs.clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: '')),
    );
    const int writeCount = 100;
    final List<Future<bool>> writes = <Future<bool>>[];
    for (int i = 1; i <= writeCount; i++) {
      writes.add(_prefs.setValue('Int', 'test.legacy.concurrent', i));
    }
    final results = await Future.wait(writes, eagerError: true);
    final failCount = results.where((bool e) => !e).length;
    _log('并发写入 $writeCount 次, 失败 $failCount 次');
    final all = await _prefs.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: '')),
    );
    _log("最终值: ${all["test.legacy.concurrent"]} (预期: $writeCount)");
    _log(all["test.legacy.concurrent"] == writeCount ? '✅ PASS' : '❌ FAIL');
  }

  Future<void> _testRunAll() async {
    _clearLogs();
    await _testSetBool();
    await _testSetInt();
    await _testSetDouble();
    await _testSetString();
    await _testSetStringList();
    await _testRemove();
    await _testGetAll();
    await _testGetAllWithPrefix();
    await _testGetAllWithParameters();
    await _testClear();
    await _testClearWithPrefix();
    await _testClearWithParameters();
    await _testClearWithAllowList();
    await _testStringPrefixClash();
    await _testSimultaneousWrites();
    _log('========== 全部测试完成 ==========');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OHOS 功能测试')),
      body: Column(
        children: [
          // 按钮区
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildAction('全部测试', _testRunAll, highlighted: true),
                _buildAction('setBool', _testSetBool),
                _buildAction('setInt', _testSetInt),
                _buildAction('setDouble', _testSetDouble),
                _buildAction('setString', _testSetString),
                _buildAction('setStringList', _testSetStringList),
                _buildAction('remove', _testRemove),
                _buildAction('getAll', _testGetAll),
                _buildAction('getAllWithPrefix', _testGetAllWithPrefix),
                _buildAction('getAllWithParams', _testGetAllWithParameters),
                _buildAction('clear', _testClear),
                _buildAction('clearWithPrefix', _testClearWithPrefix),
                _buildAction('clearWithParams', _testClearWithParameters),
                _buildAction('clear+allowList', _testClearWithAllowList),
                _buildAction('前缀拒绝', _testStringPrefixClash),
                _buildAction('并发写入', _testSimultaneousWrites),
                _buildAction('清空日志', _clearLogs, highlighted: false),
              ],
            ),
          ),
          const Divider(height: 1),
          // 日志区
          Expanded(
            child: _buildLogView(),
          ),
        ],
      ),
    );
  }

  Widget _buildAction(String label, Future<void> Function() action,
      {bool highlighted = false}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor:
            highlighted ? Theme.of(context).colorScheme.primary : null,
        foregroundColor: highlighted ? Colors.white : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: action,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildLogView() {
    return ListView.builder(
      itemCount: _logs.length,
      itemBuilder: (BuildContext context, int index) {
        final String log = _logs[index];
        final TextStyle style;
        if (log.contains('✅ PASS')) {
          style = const TextStyle(
              color: Colors.green, fontSize: 12, fontFamily: 'monospace');
        } else if (log.contains('❌ FAIL')) {
          style = const TextStyle(
              color: Colors.red, fontSize: 12, fontFamily: 'monospace');
        } else if (log.startsWith('---')) {
          style = const TextStyle(
              color: Colors.blue,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace');
        } else if (log.startsWith('=')) {
          style = const TextStyle(
              color: Colors.purple,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace');
        } else {
          style =
              const TextStyle(fontSize: 12, fontFamily: 'monospace');
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Text(log, style: style),
        );
      },
    );
  }
}

bool _listEquals(List a, List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
