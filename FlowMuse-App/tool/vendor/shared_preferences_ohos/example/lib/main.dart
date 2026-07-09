// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';
import 'package:shared_preferences_ohos/shared_preferences_ohos.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'pages/functional_test_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'SharedPreferences Demo',
      home: SharedPreferencesDemo(),
    );
  }
}

class SharedPreferencesDemo extends StatefulWidget {
  const SharedPreferencesDemo({super.key});

  @override
  SharedPreferencesDemoState createState() => SharedPreferencesDemoState();
}

class SharedPreferencesDemoState extends State<SharedPreferencesDemo> {
  // Use the implementation provided in this package.
  final SharedPreferencesOhos _prefs = SharedPreferencesOhos();
  late Future<int> _counter;

  // Store the latest test data to display in the UI.
  Map<String, Object> _testResults = <String, Object>{};

  static const String _counterKey = 'flutter.counter';

  Future<void> _incrementCounter() async {
    final Map<String, Object> values = await _prefs.getAll();
    final int counter = ((values[_counterKey] as int?) ?? 0) + 10000000000000000;

    setState(() {
      _counter = _prefs.setValue('Int', _counterKey, counter).then((bool success) {
        return counter;
      });
    });
  }

  // Run the test storage and return all preferences. Also update UI state.
  Future<Map<String, Object>> _testGetAll() async {
    try {
      // Store test data with different types
      await _prefs.setValue('Int', 'test_int64', 9223372036854775807);
      await _prefs.setValue('Int', 'test_uint32', 2147483648);
      await _prefs.setValue('Int', 'test_int32', 4294967296);
      await _prefs.setValue('Double', 'test_double', 100.1);
      await _prefs.setValue('Double', 'test_double_is_int', 100.0);
      await _prefs.setValue('String', 'test_string', 'Hello OHOS');
      await _prefs.setValue('Bool', 'test_bool', true);

      final Map<String, Object> allData = await _prefs.getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: '')),
      );

      // Build display text
      StringBuffer displayText = StringBuffer();
      displayText.writeln('SharedPreferences Test Data');
      // Add Set Data section
      displayText.writeln('setInt key: test_int64, value: 9223372036854775807');
      displayText.writeln('setInt key: test_uint32, value: 2147483648');
      displayText.writeln('setInt key: test_int32, value: 4294967296');
      displayText.writeln('setDouble key: test_double, value: 100.1');
      displayText.writeln('setDouble key: test_double_is_int, value: 100.0');
      displayText.writeln('setString key: test_string, value: Hello OHOS');
      displayText.writeln('setBool key: test_bool, value: true');
      displayText.writeln('*' * 50);
      displayText.writeln('getAll:');

      // Add Get Data section
      allData.forEach((key, value) {
        displayText.writeln('key: $key, value: $value');
      });
      displayText.writeln('*' * 50);

      setState(() {
        _testResults = {'result': displayText.toString()};
      });

      return allData;
    } catch (e) {
      setState(() {
        _testResults = <String, Object>{'error': '$e'};
      });
      return <String, Object>{};
    }
  }

  // Called when FAB is pressed — run the test and show results.
  Future<void> _showTestData() async {
    await _testGetAll();
  }

  @override
  void initState() {
    super.initState();
    _counter = _prefs.getAll().then((Map<String, Object> values) {
      return (values[_counterKey] as int?) ?? 0;
    });
    _testGetAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SharedPreferences Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.science),
            tooltip: 'OHOS 功能测试',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FunctionalTestPage()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            FutureBuilder<int>(
              future: _counter,
              builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
                switch (snapshot.connectionState) {
                  case ConnectionState.none:
                  case ConnectionState.waiting:
                    return const CircularProgressIndicator();
                  case ConnectionState.active:
                  case ConnectionState.done:
                    if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else if (snapshot.hasData) {
                      return Text(
                        'Button tapped ${snapshot.data} time${snapshot.data == 1 ? '' : 's'}. This should persist across restarts.',
                      );
                    } else {
                      return const Text('platform return empty.');
                    }
                }
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: _buildTestResults(),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTestResults() {
    if (_testResults.isEmpty) {
      return const Center(child: Text('No test data. Loading...'));
    }

    final String result = _testResults['result']?.toString() ?? 'No data';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          result,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
