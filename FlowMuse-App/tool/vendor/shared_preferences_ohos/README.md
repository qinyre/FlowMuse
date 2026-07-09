
<p align="center">
  <h1 align="center"> <code>shared_preferences</code> </h1>
</p>

本项目基于 [shared_preferences@2.2.0](https://pub.dev/packages/shared_preferences/versions/2.2.0) 开发。

`shared_preferences_ohos` 是 `shared_preferences` 的 OpenHarmony 平台实现。它为 OpenHarmony 设备上的轻量级数据提供持久化的键值存储。通过联合插件架构，当您添加 `shared_preferences` 作为依赖时，该实现会自动注册，因此您无需在代码中直接引用此包。

## 1. 安装与使用

### 1.1 安装方式

进入到工程目录并在 pubspec.yaml 中添加以下依赖：

<!-- tabs:start -->

#### pubspec.yaml

```yaml
dependencies:
  shared_preferences:
    git:
      url: "https://gitcode.com/CPF-Flutter/flutter_packages.git"
      path: "packages/shared_preferences/shared_preferences"
      # ref: shared_preferences-v2.2.2-ohos-1.0.0
      ref: TAG  #   请根据下方TAG版本对应表选择TAG
```

执行命令

```bash
flutter pub get
```

**TAG 版本对应表**

| Flutter 框架版本 | TAG | 分支 |
| :--- | :--- | :--- |
| 3.41 | `shared_preferences-v2.5.4-ohos-1.0.0` | `br_shared_preferences-v2.5.4_ohos` |
| 3.35 | `shared_preferences-v2.5.4-ohos-1.0.0` | `br_shared_preferences-v2.5.4_ohos` |
| 3.27 | `shared_preferences-v2.5.3-ohos-1.0.0` | `br_shared_preferences-v2.5.3_ohos` |
| 3.22 | `shared_preferences-v2.3.2-ohos-1.0.0` | `br_shared_preferences-v2.3.2_ohos` |
| 3.7 | `shared_preferences-v2.2.2-ohos-1.0.0` | `master` |

<!-- tabs:end -->

### 1.2 使用案例

#### 基本用法

```dart
import 'package:shared_preferences/shared_preferences.dart';

// 获取 SharedPreferences 实例
final prefs = await SharedPreferences.getInstance();

// 写入数据
await prefs.setString('username', 'Alice');
await prefs.setInt('age', 25);
await prefs.setDouble('score', 95.5);
await prefs.setBool('is_logged_in', true);
await prefs.setStringList('tags', ['flutter', 'ohos', 'mobile']);

// 读取数据
final username = prefs.getString('username');       // 'Alice'
final age = prefs.getInt('age');                   // 25
final score = prefs.getDouble('score');             // 95.5
final loggedIn = prefs.getBool('is_logged_in');     // true
final tags = prefs.getStringList('tags');           // ['flutter', 'ohos', 'mobile']

// 检查某个键是否存在
final hasKey = prefs.containsKey('username');       // true

// 获取所有键
final allKeys = prefs.getKeys();                    // 包含所有已存储键的 Set

// 移除特定键
await prefs.remove('age');

// 清除所有存储数据（仅清除以 'flutter.' 为前缀的键）
await prefs.clear();

// 从磁盘重新加载数据
await prefs.reload();
```

#### 数据持久化示例

以下示例演示了如何使用 `SharedPreferences` 在应用重启之间持久化数据：

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'SharedPreferences 演示',
      home: CounterPage(),
    );
  }
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int _counter = 0;

  @override
  void initState() {
    super.initState();
    _loadCounter();
  }

  // 加载持久化的计数器值
  Future<void> _loadCounter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _counter = prefs.getInt('counter') ?? 0;
    });
  }

  // 递增计数器并持久化新值
  Future<void> _incrementCounter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _counter++;
    });
    await prefs.setInt('counter', _counter);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('计数器演示')),
      body: Center(
        child: Text('按钮被按下 $_counter 次。\n此值在重启后仍然保留。'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: '递增',
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

#### 直接使用 SharedPreferencesOhos

如果您需要直接使用平台实现（例如用于测试或高级场景），可以实例化 `SharedPreferencesOhos`：

```dart
import 'package:shared_preferences_ohos/shared_preferences_ohos.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// 创建 SharedPreferencesOhos 实例
final SharedPreferencesOhos prefs = SharedPreferencesOhos();

// 使用 setValue 写入值
await prefs.setValue('String', 'flutter.username', 'Alice');
await prefs.setValue('Int', 'flutter.age', 25);
await prefs.setValue('Double', 'flutter.score', 95.5);
await prefs.setValue('Bool', 'flutter.is_logged_in', true);
await prefs.setValue('StringList', 'flutter.tags', ['flutter', 'ohos']);

// 读取具有特定前缀的所有值
final Map<String, Object> values = await prefs.getAllWithParameters(
  GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
);
print(values); // {flutter.username: Alice, flutter.age: 25, ...}

// 清除具有特定前缀的值
await prefs.clearWithParameters(
  ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')),
);

// 使用允许列表清除（仅移除特定键）
await prefs.clearWithParameters(
  ClearParameters(
    filter: PreferencesFilter(
      prefix: 'flutter.',
      allowList: {'flutter.username', 'flutter.age'},
    ),
  ),
);

// 注册为默认平台实现（通常自动完成）
SharedPreferencesOhos.registerWith();
```

更多使用案例详见 [shared_preferences_ohos/example](./example)。

## 2. 约束与限制

### 2.1 兼容性

在以下版本中已测试通过：

1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;

### 2.2 键前缀行为

- `SharedPreferences.getInstance()` API 使用 `'flutter.'` 作为所有键的默认前缀。例如，当您调用 `prefs.setInt('counter', 5)` 时，键在内部存储为 `'flutter.counter'`。
- `clear()` 方法仅移除以 `'flutter.'` 前缀开头的键。其他前缀的键不受影响。
- 直接使用 `SharedPreferencesOhos` 时，可以通过 `getAllWithParameters` / `clearWithParameters` 指定任意前缀（包括空前缀 `''`）。

## 3. 属性

> [!TIP] "ohos Support"列为 **yes** 表示 ohos 平台支持该属性；**no** 表示不支持；**partially** 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android。

#### 存储类型

| Name         | Description    | Type   | **ohos Support** |
| ------------ | -------------- | ------ | ---------------- |
| String       | 存储字符串值   | String | yes              |
| int          | 存储整数值     | int    | yes              |
| double       | 存储浮点数值   | double | yes              |
| bool         | 存储布尔值     | bool   | yes              |
| List<String> | 存储字符串列表 | List   | yes              |

## 4. API

> [!TIP] "ohos Support"列为 **yes** 表示 ohos 平台支持该属性；**no** 表示不支持；**partially** 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android。

### SharedPreferences（面向用户的 API）

这些是 `shared_preferences` 包提供的开发者通常使用的 API。ohos 平台实现支持所有这些方法。

| Name            | **return value**          | Description                          | **ohos Support** |
| --------------- | ------------------------- | ------------------------------------ | ---------------- |
| getInstance()   | Future<SharedPreferences> | 返回 SharedPreferences 实例。在 OpenHarmony 设备上会自动选择 ohos 平台实现。 | yes |
| getString()     | String?                   | 读取给定键的字符串值。如果键不存在则返回 `null`。 | yes |
| getInt()        | int?                      | 读取给定键的整数值。如果键不存在则返回 `null`。 | yes |
| getDouble()     | double?                   | 读取给定键的浮点数值。如果键不存在则返回 `null`。 | yes |
| getBool()       | bool?                     | 读取给定键的布尔值。如果键不存在则返回 `null`。 | yes |
| getStringList() | List<String>?             | 读取给定键的字符串列表。如果键不存在则返回 `null`。 | yes |
| setString()     | Future<bool>              | 写入字符串值。成功提交返回 `true`，否则返回 `false`。 | yes |
| setInt()        | Future<bool>              | 写入整数值。成功提交返回 `true`，否则返回 `false`。 | yes |
| setDouble()     | Future<bool>              | 写入浮点数值。成功提交返回 `true`，否则返回 `false`。 | yes |
| setBool()       | Future<bool>              | 写入布尔值。成功提交返回 `true`，否则返回 `false`。 | yes |
| setStringList() | Future<bool>              | 写入字符串列表。成功提交返回 `true`，否则返回 `false`。 | yes |
| remove()        | Future<bool>              | 移除与给定键关联的值。成功移除返回 `true`。 | yes |
| clear()         | Future<bool>              | 移除所有以 `'flutter.'` 前缀开头的键。其他前缀的键不受影响。成功返回 `true`。 | yes |
| reload()        | Future<bool>              | 从磁盘重新加载首选项。当首选项可能被其他进程修改时非常有用。成功返回 `true`。 | yes |
| containsKey()   | bool                      | 检查给定键是否存在于首选项中。 | yes |
| getKeys()       | Set<String>               | 返回当前存储在首选项中的所有键（仅包含以 `'flutter.'` 前缀开头的键）。 | yes |

#### 方法参数

##### getInstance()

无参数。

```dart
final prefs = await SharedPreferences.getInstance();
```

##### getString(key)

| Parameter | Type     | Description              | Required |
| --------- | -------- | ------------------------ | -------- |
| key       | String   | 用于存储字符串值的键     | Yes      |

```dart
final value = prefs.getString('username');
```

##### getInt(key)

| Parameter | Type     | Description              | Required |
| --------- | -------- | ------------------------ | -------- |
| key       | String   | 用于存储整数值的键       | Yes      |

```dart
final value = prefs.getInt('age');
```

##### getDouble(key)

| Parameter | Type     | Description              | Required |
| --------- | -------- | ------------------------ | -------- |
| key       | String   | 用于存储浮点数值的键     | Yes      |

```dart
final value = prefs.getDouble('score');
```

##### getBool(key)

| Parameter | Type     | Description              | Required |
| --------- | -------- | ------------------------ | -------- |
| key       | String   | 用于存储布尔值的键       | Yes      |

```dart
final value = prefs.getBool('is_logged_in');
```

##### getStringList(key)

| Parameter | Type     | Description              | Required |
| --------- | -------- | ------------------------ | -------- |
| key       | String   | 用于存储字符串列表的键   | Yes      |

```dart
final value = prefs.getStringList('tags');
```

##### setString(key, value)

| Parameter | Type     | Description            | Required |
| --------- | -------- | ---------------------- | -------- |
| key       | String   | 与字符串关联的键       | Yes      |
| value     | String   | 要存储的字符串值       | Yes      |

```dart
await prefs.setString('username', 'Alice');
```

##### setInt(key, value)

| Parameter | Type     | Description            | Required |
| --------- | -------- | ---------------------- | -------- |
| key       | String   | 与整数关联的键         | Yes      |
| value     | int      | 要存储的整数值         | Yes      |

```dart
await prefs.setInt('age', 25);
```

##### setDouble(key, value)

| Parameter | Type     | Description            | Required |
| --------- | -------- | ---------------------- | -------- |
| key       | String   | 与浮点数关联的键       | Yes      |
| value     | double   | 要存储的浮点数值       | Yes      |

```dart
await prefs.setDouble('score', 95.5);
```

##### setBool(key, value)

| Parameter | Type     | Description            | Required |
| --------- | -------- | ---------------------- | -------- |
| key       | String   | 与布尔值关联的键       | Yes      |
| value     | bool     | 要存储的布尔值         | Yes      |

```dart
await prefs.setBool('is_logged_in', true);
```

##### setStringList(key, value)

| Parameter | Type          | Description            | Required |
| --------- | ------------- | ---------------------- | -------- |
| key       | String        | 与字符串列表关联的键   | Yes      |
| value     | List<String>  | 要存储的字符串列表     | Yes      |

```dart
await prefs.setStringList('tags', ['flutter', 'ohos']);
```

##### remove(key)

| Parameter | Type     | Description            | Required |
| --------- | -------- | ---------------------- | -------- |
| key       | String   | 要移除其值的键         | Yes      |

```dart
await prefs.remove('username');
```

##### clear()

无参数。移除所有以 `'flutter.'` 前缀开头的键。

```dart
await prefs.clear();
```

##### reload()

无参数。从磁盘重新加载首选项数据。

```dart
await prefs.reload();
```

##### containsKey(key)

| Parameter | Type     | Description            | Required |
| --------- | -------- | ---------------------- | -------- |
| key       | String   | 要检查是否存在的键     | Yes      |

```dart
final exists = prefs.containsKey('username'); // true 或 false
```

##### getKeys()

无参数。返回所有以 `'flutter.'` 前缀开头的键。

```dart
final keys = prefs.getKeys(); // 包含所有已存储键的 Set<String>
```

### SharedPreferencesOhos（平台实现 API）

这些是 `SharedPreferencesOhos` 平台实现类提供的 API。大多数开发者应使用上方的 `SharedPreferences` 面向用户 API。仅在需要直接访问平台实现时使用这些 API。

| Name                       | **return value**        | Description                                                                 | **ohos Support** |
| -------------------------- | ----------------------- | --------------------------------------------------------------------------- | ---------------- |
| registerWith()             | void                    | 将此类注册为 SharedPreferencesStorePlatform 的默认实例。由插件注册机制自动调用。 | yes |
| setValue(valueType, key, value) | Future<bool>      | 写入一个值。`valueType` 必须是 `'String'`、`'Bool'`、`'Int'`、`'Double'` 或 `'StringList'` 之一。成功返回 `true`。 | yes |
| remove(key)                | Future<bool>            | 移除给定键的值。成功返回 `true`。                                           | yes              |
| clear()                    | Future<bool>            | 移除所有以 `'flutter.'` 前缀开头的键。成功返回 `true`。                     | yes              |
| clearWithPrefix(prefix)    | Future<bool>            | 移除所有以给定前缀开头的键。成功返回 `true`。                               | yes              |
| clearWithParameters(parameters) | Future<bool>      | 基于 ClearParameters（前缀 + 可选 allowList）移除键。成功返回 `true`。     | yes              |
| getAll()                   | Future<Map<String, Object>> | 返回所有以 `'flutter.'` 前缀开头的键值对。                             | yes              |
| getAllWithPrefix(prefix)   | Future<Map<String, Object>> | 返回所有以给定前缀开头的键值对。                                         | yes              |
| getAllWithParameters(parameters) | Future<Map<String, Object>> | 基于 GetAllParameters（前缀 + 可选 allowList）返回键值对。               | yes              |

#### SharedPreferencesOhos 方法参数

##### registerWith()

无参数。由 Flutter 插件注册系统自动调用。

```dart
SharedPreferencesOhos.registerWith();
```

##### setValue(valueType, key, value)

| Parameter  | Type     | Description                                                              | Required |
| ---------- | -------- | ------------------------------------------------------------------------ | -------- |
| valueType  | String   | 类型标识符：`'String'`、`'Bool'`、`'Int'`、`'Double'` 或 `'StringList'` | Yes      |
| key        | String   | 与值关联的键                                                             | Yes      |
| value      | Object   | 要存储的值。类型必须与 `valueType` 匹配                                 | Yes      |

```dart
await prefs.setValue('String', 'flutter.username', 'Alice');
await prefs.setValue('Int', 'flutter.age', 25);
await prefs.setValue('Double', 'flutter.score', 95.5);
await prefs.setValue('Bool', 'flutter.is_logged_in', true);
await prefs.setValue('StringList', 'flutter.tags', ['flutter', 'ohos']);
```

##### remove(key)

| Parameter | Type     | Description            | Required |
| --------- | -------- | ---------------------- | -------- |
| key       | String   | 要移除其值的键         | Yes      |

```dart
await prefs.remove('flutter.username');
```

##### clear()

无参数。移除所有以 `'flutter.'` 前缀开头的键。

```dart
await prefs.clear();
```

##### clearWithPrefix(prefix)

| Parameter | Type     | Description                                                      | Required |
| --------- | -------- | ---------------------------------------------------------------- | -------- |
| prefix    | String   | 前缀过滤器。仅移除以此前缀开头的键。使用 `''` 移除所有键。       | Yes      |

```dart
await prefs.clearWithPrefix('flutter.');
await prefs.clearWithPrefix('');  // 清除所有键，无论前缀如何
```

##### clearWithParameters(parameters)

| Parameter   | Type             | Description                                  | Required |
| ----------- | ---------------- | -------------------------------------------- | -------- |
| parameters  | ClearParameters  | 包含带有前缀和可选 allowList 的 PreferencesFilter | Yes      |

**ClearParameters**

| Field   | Type              | Description                              | Required |
| ------- | ----------------- | ---------------------------------------- | -------- |
| filter  | PreferencesFilter | 指定要清除哪些键的过滤器                 | Yes      |

**PreferencesFilter**

| Field     | Type          | Description                                                              | Required |
| --------- | ------------- | ------------------------------------------------------------------------ | -------- |
| prefix    | String        | 仅考虑以此前缀开头的键                                                   | Yes      |
| allowList | Set<String>?  | 可选的特定键白名单，用于指定要清除的键。如果为 null，则清除所有匹配的键。 | No       |

```dart
// 清除所有以 'flutter.' 前缀开头的键
await prefs.clearWithParameters(
  ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')),
);

// 仅清除 'flutter.' 前缀下的特定键
await prefs.clearWithParameters(
  ClearParameters(
    filter: PreferencesFilter(
      prefix: 'flutter.',
      allowList: {'flutter.username', 'flutter.age'},
    ),
  ),
);

// 清除所有键，无论前缀如何
await prefs.clearWithParameters(
  ClearParameters(filter: PreferencesFilter(prefix: '')),
);
```

##### getAll()

无参数。返回所有以 `'flutter.'` 前缀开头的键值对。

```dart
final Map<String, Object> values = await prefs.getAll();
```

##### getAllWithPrefix(prefix)

| Parameter | Type     | Description                                                      | Required |
| --------- | -------- | ---------------------------------------------------------------- | -------- |
| prefix    | String   | 前缀过滤器。仅返回以此前缀开头的键值对。使用 `''` 获取所有键。   | Yes      |

```dart
final Map<String, Object> values = await prefs.getAllWithPrefix('flutter.');
final Map<String, Object> allValues = await prefs.getAllWithPrefix('');
```

##### getAllWithParameters(parameters)

| Parameter   | Type              | Description                                  | Required |
| ----------- | ----------------- | -------------------------------------------- | -------- |
| parameters  | GetAllParameters  | 包含带有前缀和可选 allowList 的 PreferencesFilter | Yes      |

**GetAllParameters**

| Field   | Type              | Description                              | Required |
| ------- | ----------------- | ---------------------------------------- | -------- |
| filter  | PreferencesFilter | 指定要检索哪些键的过滤器                 | Yes      |

**PreferencesFilter**

| Field     | Type          | Description                                                              | Required |
| --------- | ------------- | ------------------------------------------------------------------------ | -------- |
| prefix    | String        | 仅考虑以此前缀开头的键                                                   | Yes      |
| allowList | Set<String>?  | 可选的特定键白名单，用于指定要检索的键。如果为 null，则返回所有匹配的键。 | No       |

```dart
// 获取所有以 'flutter.' 前缀开头的键
final Map<String, Object> values = await prefs.getAllWithParameters(
  GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
);

// 仅获取 'flutter.' 前缀下的特定键
final Map<String, Object> values = await prefs.getAllWithParameters(
  GetAllParameters(
    filter: PreferencesFilter(
      prefix: 'flutter.',
      allowList: {'flutter.username', 'flutter.age'},
    ),
  ),
);

// 获取所有键，无论前缀如何
final Map<String, Object> allValues = await prefs.getAllWithParameters(
  GetAllParameters(filter: PreferencesFilter(prefix: '')),
);
```

## 5. 遗留问题

- 以特殊内部前缀（`VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGRvdWJsZS4`）开头的字符串无法通过 `setValue('String', ...)` 存储，因为该前缀在内部用于编码 `double` 值。尝试存储此类字符串将抛出 `PlatformException`。

## 6. 开源协议

本项目基于 [BSD-3-Clause](https://gitcode.com/CPF-Flutter/flutter_packages/blob/master/packages/shared_preferences/shared_preferences/LICENSE)

> 模板版本: v0.0.1
