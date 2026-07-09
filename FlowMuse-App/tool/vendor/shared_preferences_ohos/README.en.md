
<p align="center">
  <h1 align="center"> <code>shared_preferences</code> </h1>
</p>

This project is developed based on [shared_preferences@2.2.0](https://pub.dev/packages/shared_preferences/versions/2.2.0).

`shared_preferences_ohos` is the OpenHarmony platform implementation of `shared_preferences`. It provides persistent key-value storage for lightweight data on OpenHarmony devices. With the federated plugin architecture, this implementation is registered automatically when you add `shared_preferences` as a dependency, so you don't need to reference this package directly in your code.

## 1. Installation and Usage

### 1.1 Installation

Navigate to your project directory and add the following dependency to `pubspec.yaml`:

<!-- tabs:start -->

#### pubspec.yaml

```yaml
dependencies:
  shared_preferences:
    git:
      url: "https://gitcode.com/CPF-Flutter/flutter_packages.git"
      path: "packages/shared_preferences/shared_preferences"
      # ref: shared_preferences-v2.2.2-ohos-1.0.0
      ref: TAG  #   Select a TAG according to the TAG version table below
```

Run the command:

```bash
flutter pub get
```

**TAG Version Table**

| Flutter Version | TAG | Branch |
| :--- | :--- | :--- |
| 3.41 | `shared_preferences-v2.5.4-ohos-1.0.0` | `br_shared_preferences-v2.5.4_ohos` |
| 3.35 | `shared_preferences-v2.5.4-ohos-1.0.0` | `br_shared_preferences-v2.5.4_ohos` |
| 3.27 | `shared_preferences-v2.5.3-ohos-1.0.0` | `br_shared_preferences-v2.5.3_ohos` |
| 3.22 | `shared_preferences-v2.3.2-ohos-1.0.0` | `br_shared_preferences-v2.3.2_ohos` |
| 3.7 | `shared_preferences-v2.2.2-ohos-1.0.0` | `master` |

<!-- tabs:end -->

### 1.2 Usage

#### Basic usage

```dart
import 'package:shared_preferences/shared_preferences.dart';

// Get the SharedPreferences instance
final prefs = await SharedPreferences.getInstance();

// Write data
await prefs.setString('username', 'Alice');
await prefs.setInt('age', 25);
await prefs.setDouble('score', 95.5);
await prefs.setBool('is_logged_in', true);
await prefs.setStringList('tags', ['flutter', 'ohos', 'mobile']);

// Read data
final username = prefs.getString('username');       // 'Alice'
final age = prefs.getInt('age');                   // 25
final score = prefs.getDouble('score');             // 95.5
final loggedIn = prefs.getBool('is_logged_in');     // true
final tags = prefs.getStringList('tags');           // ['flutter', 'ohos', 'mobile']

// Check whether a key exists
final hasKey = prefs.containsKey('username');       // true

// Get all keys
final allKeys = prefs.getKeys();                    // Set containing all stored keys

// Remove a specific key
await prefs.remove('age');

// Clear all stored data (only keys prefixed with 'flutter.')
await prefs.clear();

// Reload data from disk
await prefs.reload();
```

#### Data persistence example

The following example shows how to use `SharedPreferences` to persist data across app restarts:

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
      title: 'SharedPreferences Demo',
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

  // Load the persisted counter value
  Future<void> _loadCounter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _counter = prefs.getInt('counter') ?? 0;
    });
  }

  // Increment the counter and persist the new value
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
      appBar: AppBar(title: const Text('Counter Demo')),
      body: Center(
        child: Text('Button pressed $_counter times.\nThis value persists across restarts.'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

#### Using SharedPreferencesOhos directly

If you need to use the platform implementation directly (e.g., for testing or advanced scenarios), you can instantiate `SharedPreferencesOhos`:

```dart
import 'package:shared_preferences_ohos/shared_preferences_ohos.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// Create a SharedPreferencesOhos instance
final SharedPreferencesOhos prefs = SharedPreferencesOhos();

// Write values using setValue
await prefs.setValue('String', 'flutter.username', 'Alice');
await prefs.setValue('Int', 'flutter.age', 25);
await prefs.setValue('Double', 'flutter.score', 95.5);
await prefs.setValue('Bool', 'flutter.is_logged_in', true);
await prefs.setValue('StringList', 'flutter.tags', ['flutter', 'ohos']);

// Read all values with a specific prefix
final Map<String, Object> values = await prefs.getAllWithParameters(
  GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
);
print(values); // {flutter.username: Alice, flutter.age: 25, ...}

// Clear values with a specific prefix
await prefs.clearWithParameters(
  ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')),
);

// Clear with an allow list (only removes specific keys)
await prefs.clearWithParameters(
  ClearParameters(
    filter: PreferencesFilter(
      prefix: 'flutter.',
      allowList: {'flutter.username', 'flutter.age'},
    ),
  ),
);

// Register as the default platform implementation (usually automatic)
SharedPreferencesOhos.registerWith();
```

For more usage examples, see [shared_preferences_ohos/example](./example).

## 2. Constraints and Limitations

### 2.1 Compatibility

Tested and passed on the following versions:

1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;

### 2.2 Key prefix behavior

- The `SharedPreferences.getInstance()` API uses `'flutter.'` as the default prefix for all keys. For example, when you call `prefs.setInt('counter', 5)`, the key is stored internally as `'flutter.counter'`.
- The `clear()` method only removes keys that start with the `'flutter.'` prefix. Keys with other prefixes are not affected.
- When using `SharedPreferencesOhos` directly, you can specify any prefix (including an empty prefix `''`) via `getAllWithParameters` / `clearWithParameters`.

## 3. Properties

> [!TIP] An **ohos Support** value of **yes** means the property is supported on the ohos platform; **no** means not supported; **partially** means partially supported. The usage method is consistent across platforms, and the behavior is aligned with iOS or Android.

#### Storage types

| Name         | Description    | Type   | **ohos Support** |
| ------------ | -------------- | ------ | ---------------- |
| String       | Stores a string value   | String | yes              |
| int          | Stores an integer value     | int    | yes              |
| double       | Stores a floating-point value   | double | yes              |
| bool         | Stores a boolean value     | bool   | yes              |
| List<String> | Stores a list of strings | List   | yes              |

## 4. API

> [!TIP] An **ohos Support** value of **yes** means the property is supported on the ohos platform; **no** means not supported; **partially** means partially supported. The usage method is consistent across platforms, and the behavior is aligned with iOS or Android.

### SharedPreferences (user-facing API)

These are the APIs typically used by developers, provided by the `shared_preferences` package. The ohos platform implementation supports all of these methods.

| Name            | **return value**          | Description                          | **ohos Support** |
| --------------- | ------------------------- | ------------------------------------ | ---------------- |
| getInstance()   | Future<SharedPreferences> | Returns a SharedPreferences instance. On OpenHarmony devices, the ohos platform implementation is automatically selected. | yes |
| getString()     | String?                   | Reads the string value for the given key. Returns `null` if the key does not exist. | yes |
| getInt()        | int?                      | Reads the integer value for the given key. Returns `null` if the key does not exist. | yes |
| getDouble()     | double?                   | Reads the floating-point value for the given key. Returns `null` if the key does not exist. | yes |
| getBool()       | bool?                     | Reads the boolean value for the given key. Returns `null` if the key does not exist. | yes |
| getStringList() | List<String>?             | Reads the list of strings for the given key. Returns `null` if the key does not exist. | yes |
| setString()     | Future<bool>              | Writes a string value. Returns `true` on successful commit, `false` otherwise. | yes |
| setInt()        | Future<bool>              | Writes an integer value. Returns `true` on successful commit, `false` otherwise. | yes |
| setDouble()     | Future<bool>              | Writes a floating-point value. Returns `true` on successful commit, `false` otherwise. | yes |
| setBool()       | Future<bool>              | Writes a boolean value. Returns `true` on successful commit, `false` otherwise. | yes |
| setStringList() | Future<bool>              | Writes a list of strings. Returns `true` on successful commit, `false` otherwise. | yes |
| remove()        | Future<bool>              | Removes the value associated with the given key. Returns `true` on success. | yes |
| clear()         | Future<bool>              | Removes all keys starting with the `'flutter.'` prefix. Keys with other prefixes are not affected. Returns `true` on success. | yes |
| reload()        | Future<bool>              | Reloads preferences from disk. Useful when preferences may have been modified by another process. Returns `true` on success. | yes |
| containsKey()   | bool                      | Checks whether the given key exists in the preferences. | yes |
| getKeys()       | Set<String>               | Returns all keys currently stored in the preferences (only keys starting with the `'flutter.'` prefix). | yes |

#### Method parameters

##### getInstance()

No parameters.

```dart
final prefs = await SharedPreferences.getInstance();
```

##### getString(key)

| Parameter | Type     | Description              | Required |
| --------- | -------- | ------------------------ | -------- |
| key       | String   | The key used to store the string value     | Yes      |

```dart
final value = prefs.getString('username');
```

##### getInt(key)

| Parameter | Type     | Description              | Required |
| --------- | -------- | ------------------------ | -------- |
| key       | String   | The key used to store the integer value       | Yes      |

```dart
final value = prefs.getInt('age');
```

##### getDouble(key)

| Parameter | Type     | Description              | Required |
| --------- | -------- | ------------------------ | -------- |
| key       | String   | The key used to store the floating-point value     | Yes      |

```dart
final value = prefs.getDouble('score');
```

##### getBool(key)

| Parameter | Type     | Description              | Required |
| --------- | -------- | ------------------------ | -------- |
| key       | String   | The key used to store the boolean value       | Yes      |

```dart
final value = prefs.getBool('is_logged_in');
```

##### getStringList(key)

| Parameter | Type     | Description              | Required |
| --------- | -------- | ------------------------ | -------- |
| key       | String   | The key used to store the list of strings   | Yes      |

```dart
final value = prefs.getStringList('tags');
```

##### setString(key, value)

| Parameter | Type     | Description            | Required |
| --------- | -------- | ---------------------- | -------- |
| key       | String   | The key associated with the string       | Yes      |
| value     | String   | The string value to store       | Yes      |

```dart
await prefs.setString('username', 'Alice');
```

##### setInt(key, value)

| Parameter | Type     | Description            | Required |
| --------- | -------- | ---------------------- | -------- |
| key       | String   | The key associated with the integer         | Yes      |
| value     | int      | The integer value to store         | Yes      |

```dart
await prefs.setInt('age', 25);
```

##### setDouble(key, value)

| Parameter | Type     | Description            | Required |
| --------- | -------- | ---------------------- | -------- |
| key       | String   | The key associated with the floating-point value       | Yes      |
| value     | double   | The floating-point value to store       | Yes      |

```dart
await prefs.setDouble('score', 95.5);
```

##### setBool(key, value)

| Parameter | Type     | Description            | Required |
| --------- | -------- | ---------------------- | -------- |
| key       | String   | The key associated with the boolean       | Yes      |
| value     | bool     | The boolean value to store         | Yes      |

```dart
await prefs.setBool('is_logged_in', true);
```

##### setStringList(key, value)

| Parameter | Type          | Description            | Required |
| --------- | ------------- | ---------------------- | -------- |
| key       | String        | The key associated with the list of strings   | Yes      |
| value     | List<String>  | The list of strings to store     | Yes      |

```dart
await prefs.setStringList('tags', ['flutter', 'ohos']);
```

##### remove(key)

| Parameter | Type     | Description            | Required |
| --------- | -------- | ---------------------- | -------- |
| key       | String   | The key whose value should be removed         | Yes      |

```dart
await prefs.remove('username');
```

##### clear()

No parameters. Removes all keys starting with the `'flutter.'` prefix.

```dart
await prefs.clear();
```

##### reload()

No parameters. Reloads preference data from disk.

```dart
await prefs.reload();
```

##### containsKey(key)

| Parameter | Type     | Description            | Required |
| --------- | -------- | ---------------------- | -------- |
| key       | String   | The key to check for existence     | Yes      |

```dart
final exists = prefs.containsKey('username'); // true or false
```

##### getKeys()

No parameters. Returns all keys starting with the `'flutter.'` prefix.

```dart
final keys = prefs.getKeys(); // Set<String> containing all stored keys
```

### SharedPreferencesOhos (platform implementation API)

These are the APIs provided by the `SharedPreferencesOhos` platform implementation class. Most developers should use the `SharedPreferences` user-facing API above. Use these APIs only when you need direct access to the platform implementation.

| Name                       | **return value**        | Description                                                                 | **ohos Support** |
| -------------------------- | ----------------------- | --------------------------------------------------------------------------- | ---------------- |
| registerWith()             | void                    | Registers this class as the default instance of SharedPreferencesStorePlatform. Called automatically by the plugin registration mechanism. | yes |
| setValue(valueType, key, value) | Future<bool>      | Writes a value. `valueType` must be one of `'String'`, `'Bool'`, `'Int'`, `'Double'`, or `'StringList'`. Returns `true` on success. | yes |
| remove(key)                | Future<bool>            | Removes the value for the given key. Returns `true` on success.                                           | yes              |
| clear()                    | Future<bool>            | Removes all keys starting with the `'flutter.'` prefix. Returns `true` on success.                     | yes              |
| clearWithPrefix(prefix)    | Future<bool>            | Removes all keys starting with the given prefix. Returns `true` on success.                               | yes              |
| clearWithParameters(parameters) | Future<bool>      | Removes keys based on ClearParameters (prefix + optional allowList). Returns `true` on success.     | yes              |
| getAll()                   | Future<Map<String, Object>> | Returns all key-value pairs starting with the `'flutter.'` prefix.                             | yes              |
| getAllWithPrefix(prefix)   | Future<Map<String, Object>> | Returns all key-value pairs starting with the given prefix.                                         | yes              |
| getAllWithParameters(parameters) | Future<Map<String, Object>> | Returns key-value pairs based on GetAllParameters (prefix + optional allowList).               | yes              |

#### SharedPreferencesOhos method parameters

##### registerWith()

No parameters. Called automatically by the Flutter plugin registration system.

```dart
SharedPreferencesOhos.registerWith();
```

##### setValue(valueType, key, value)

| Parameter  | Type     | Description                                                              | Required |
| ---------- | -------- | ------------------------------------------------------------------------ | -------- |
| valueType  | String   | Type identifier: `'String'`, `'Bool'`, `'Int'`, `'Double'`, or `'StringList'` | Yes      |
| key        | String   | The key associated with the value                                                             | Yes      |
| value      | Object   | The value to store. The type must match `valueType`                                 | Yes      |

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
| key       | String   | The key whose value should be removed         | Yes      |

```dart
await prefs.remove('flutter.username');
```

##### clear()

No parameters. Removes all keys starting with the `'flutter.'` prefix.

```dart
await prefs.clear();
```

##### clearWithPrefix(prefix)

| Parameter | Type     | Description                                                      | Required |
| --------- | -------- | ---------------------------------------------------------------- | -------- |
| prefix    | String   | Prefix filter. Only keys starting with this prefix are removed. Use `''` to remove all keys.       | Yes      |

```dart
await prefs.clearWithPrefix('flutter.');
await prefs.clearWithPrefix('');  // Clear all keys regardless of prefix
```

##### clearWithParameters(parameters)

| Parameter   | Type             | Description                                  | Required |
| ----------- | ---------------- | -------------------------------------------- | -------- |
| parameters  | ClearParameters  | PreferencesFilter containing a prefix and an optional allowList | Yes      |

**ClearParameters**

| Field   | Type              | Description                              | Required |
| ------- | ----------------- | ---------------------------------------- | -------- |
| filter  | PreferencesFilter | Filter specifying which keys to clear                 | Yes      |

**PreferencesFilter**

| Field     | Type          | Description                                                              | Required |
| --------- | ------------- | ------------------------------------------------------------------------ | -------- |
| prefix    | String        | Only keys starting with this prefix are considered                                                   | Yes      |
| allowList | Set<String>?  | Optional allow list of specific keys to clear. If null, all matching keys are cleared. | No       |

```dart
// Clear all keys starting with the 'flutter.' prefix
await prefs.clearWithParameters(
  ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')),
);

// Clear only specific keys under the 'flutter.' prefix
await prefs.clearWithParameters(
  ClearParameters(
    filter: PreferencesFilter(
      prefix: 'flutter.',
      allowList: {'flutter.username', 'flutter.age'},
    ),
  ),
);

// Clear all keys regardless of prefix
await prefs.clearWithParameters(
  ClearParameters(filter: PreferencesFilter(prefix: '')),
);
```

##### getAll()

No parameters. Returns all key-value pairs starting with the `'flutter.'` prefix.

```dart
final Map<String, Object> values = await prefs.getAll();
```

##### getAllWithPrefix(prefix)

| Parameter | Type     | Description                                                      | Required |
| --------- | -------- | ---------------------------------------------------------------- | -------- |
| prefix    | String   | Prefix filter. Only key-value pairs starting with this prefix are returned. Use `''` to get all keys.   | Yes      |

```dart
final Map<String, Object> values = await prefs.getAllWithPrefix('flutter.');
final Map<String, Object> allValues = await prefs.getAllWithPrefix('');
```

##### getAllWithParameters(parameters)

| Parameter   | Type              | Description                                  | Required |
| ----------- | ----------------- | -------------------------------------------- | -------- |
| parameters  | GetAllParameters  | PreferencesFilter containing a prefix and an optional allowList | Yes      |

**GetAllParameters**

| Field   | Type              | Description                              | Required |
| ------- | ----------------- | ---------------------------------------- | -------- |
| filter  | PreferencesFilter | Filter specifying which keys to retrieve                 | Yes      |

**PreferencesFilter**

| Field     | Type          | Description                                                              | Required |
| --------- | ------------- | ------------------------------------------------------------------------ | -------- |
| prefix    | String        | Only keys starting with this prefix are considered                                                   | Yes      |
| allowList | Set<String>?  | Optional allow list of specific keys to retrieve. If null, all matching keys are returned. | No       |

```dart
// Get all keys starting with the 'flutter.' prefix
final Map<String, Object> values = await prefs.getAllWithParameters(
  GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
);

// Get only specific keys under the 'flutter.' prefix
final Map<String, Object> values = await prefs.getAllWithParameters(
  GetAllParameters(
    filter: PreferencesFilter(
      prefix: 'flutter.',
      allowList: {'flutter.username', 'flutter.age'},
    ),
  ),
);

// Get all keys regardless of prefix
final Map<String, Object> allValues = await prefs.getAllWithParameters(
  GetAllParameters(filter: PreferencesFilter(prefix: '')),
);
```

## 5. Known Issues

- Strings starting with the special internal prefix (`VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGRvdWJsZS4`) cannot be stored via `setValue('String', ...)` because this prefix is used internally to encode `double` values. Attempting to store such a string will throw a `PlatformException`.

## 6. License

This project is licensed under [BSD-3-Clause](https://gitcode.com/CPF-Flutter/flutter_packages/blob/master/packages/shared_preferences/shared_preferences/LICENSE)

> Template version: v0.0.1
