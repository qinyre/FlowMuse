

<p align="center">
  <h1 align="center"> <code>path_provider</code> </h1>
</p>

This project is developed based on [path_provider@2.1.0](https://pub.dev/packages/path_provider/versions/2.1.0).

## Introduction

`path_provider` is used in Flutter to obtain common file system paths on a device, such as the temporary directory, application document directory, cache directory, and external storage related paths. This implementation integrates with `path_provider` as a federated plugin, providing platform-channel capabilities consistent with the official plugin on OpenHarmony.

## Installation

Navigate to your project directory and add the following dependency to `pubspec.yaml`:

```yaml
...
dependencies:
  path_provider:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/path_provider/path_provider
      # ref: provider-v2.1.1-ohos-1.0.0
      ref: TAG  #   Select a TAG according to the TAG version table below
```

Run the command:

```bash
flutter pub get
```

**TAG Version Table**

| Flutter Version | TAG | Branch |
| :--- | :--- | :--- |
| 3.41 | `provider-v2.1.5-ohos-1.0.0` | `br_path_provider-v2.1.5_ohos` |
| 3.35 | `provider-v2.1.5-ohos-1.0.0` | `br_path_provider-v2.1.5_ohos` |
| 3.27 | `provider-v2.1.5-ohos-1.0.0` | `br_path_provider-v2.1.5_ohos` |
| 3.22 | `provider-v2.1.4_ohos-1.0.0` | `br_path_provider-v2.1.4_ohos` |
| 3.7 | `provider-v2.1.1-ohos-1.0.0` | `master` |

## Constraints and Limitations

### Compatibility

Tested and passed on the following versions:
1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;


### Permission Requirements

Some permissions are system-level (`system-level`), while the default application level is `normal`, which can only use `normal`-level permissions. Therefore, if a system-level permission is requested in the app, installing the HAP package may fail.

Open `entry/src/main/module.json5` and add:

```yaml
"requestPermissions": [
  {
   "name": "ohos.permission.INTERNET",
    "reason": "$string:network_reason",
    "usedScene": {
      "abilities": [
        "EntryAbility"
      ],
      "when":"inuse"
    }
  },
]
```

Open `entry/src/main/resources/base/element/string.json` and add:

```
...
{
  "string": [
    {
      "name": "network_reason",
      "value": "Use network"
    },
  ]
}
```

## Usage Example

The example in this repo [`example/lib/main.dart`](./example/lib/main.dart) is consistent with the snippet below in implementation approach: both depend on `path_provider_platform_interface` and use `PathProviderPlatform.instance` to call `getTemporaryPath()`, `getApplicationDocumentsPath()`, etc.; the UI side triggers requests in button `onPressed` and displays paths or errors via `FutureBuilder`. The code snippet here is a simplified example; for a complete runnable version, refer to `example/lib/main.dart`.


```dart
import 'package:flutter/material.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

Future<void> logPathsFromExample() async {
  final PathProviderPlatform provider = PathProviderPlatform.instance;

  final temp = await provider.getTemporaryPath();
  debugPrint('Temporary: $temp');

  final docs = await provider.getApplicationDocumentsPath();
  debugPrint('Documents: $docs');

  final support = await provider.getApplicationSupportPath();
  debugPrint('Support: $support');

  final cache = await provider.getApplicationCachePath();
  debugPrint('Cache: $cache');
}
```

## Usage Instructions

1. Depend on `path_provider` in `pubspec.yaml` (Git source and `ref` as configured above); the example project will resolve `path_provider_platform_interface` through transitive dependencies.
2. For path queries, refer to the example implementation approach: call `getTemporaryPath()` and similar methods via `PathProviderPlatform.instance`, trigger them via buttons on the UI side, and display results through `FutureBuilder`. The code snippet here is a simplified example; for a complete runnable version, refer to `example/lib/main.dart`.

## API Reference

### API

The following lists the support status of path-related capabilities of the `path_provider` platform interface in this OHOS implementation. The app layer still uses the functions exported by the `path_provider` main package.

| Name                | Return Value                        |  Description               | Type       | OHOS Support |
|---------------------|-------------------------------------------------------------------------------------------------------|------|-------|-------------------|
| getTemporaryPath()   |   Future<String?>             |         Obtains the path to the temporary directory on the device that is not backed up, suitable for storing cache of downloaded files.     | function | yes               |
| getApplicationSupportPath()   |    Future<String?>     |    Obtains the path to the directory where the application may place application support files. If the directory does not exist, it will be created automatically.         | function | yes               |
| getLibraryPath()   |    Future<String?>     |    Obtains the application's Library directory path (used on iOS/macOS platforms). OHOS does not support it; calling it will throw `UnsupportedError`. The example app still provides a corresponding button to verify this behavior.         | function | no               |
| getApplicationDocumentsPath() |     Future<String?>  |          Obtains the path to the directory where the application can place user-generated data, or data that cannot be recreated by the application.       | function | yes               |
| getApplicationCachePath()   | Future<String?>       |          Obtains the path to the directory where the application may place application-specific cache files. If the directory does not exist, it will be created automatically.      | function       | yes              |
| getExternalCachePaths()     | Future<List<String?>> | Obtains the directory paths where the application's cache data can be stored externally, typically on external storage such as a separate partition or SD card. A phone may have multiple available storage directories.  | function       | yes               |
| getExternalStoragePath()    |   Future<String?>         |       Obtains the path to the application's top-level storage directory, where the application can access the top-level storage directory path.     |        function       | yes               |
| getExternalStoragePaths([StorageDirectory](#StorageDirectory) arg_directory)   | Future<List<String?>> |   Obtains the directory paths where the application-specific data can be stored externally, typically on external storage such as a separate partition or SD card. A phone may have multiple available storage directories. | function       | yes               |
| getDownloadsPath()   | Future<String?>       | Obtains the path to the downloads directory; on OHOS this is implemented based on `getExternalStoragePaths(StorageDirectory.downloads)` and returns null when no path is available. | function | yes               |

### Properties

#### StorageDirectory

| Name              | Description                                                | Type                                        | OHOS Support |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------- | ------------ |
|  StorageDirectory.music  | Music file type for the storage directory |  enum | yes   |
|  StorageDirectory.podcasts  | Audio file type for the storage directory |  enum | yes   |
|  StorageDirectory.ringtones  | Ringtone file type for the storage directory |  enum | yes   |
|  StorageDirectory.alarms  | Alarm sound file type for the storage directory |  enum | yes   |
|  StorageDirectory.notifications  | Notification file type for the storage directory |  enum | yes   |
|  StorageDirectory.pictures  | Picture file type for the storage directory |  enum | yes   |
|  StorageDirectory.movies  | Movie file type for the storage directory |  enum | yes   |
|  StorageDirectory.downloads  | Downloaded file type for the storage directory |  enum | yes   |
|  StorageDirectory.dcim  | Photo and video file type for the storage directory |  enum | yes   |
|  StorageDirectory.documents  | General file type for the storage directory |  enum | yes   |

## Unsupported Capabilities

- `StorageDirectory.root`: The public API's `StorageDirectory` enum **does not include** `root`, and **does not support** the `StorageDirectory.root` syntax. To obtain the root directory, use `getExternalStoragePaths(type: null)`.
- `getLibraryPath()`: OHOS does not provide an equivalent Library directory concept as iOS/macOS. This implementation throws `UnsupportedError('getLibraryPath is not supported on OHOS')` (consistent with the Android implementation). The example app [`example/lib/main.dart`](./example/lib/main.dart) still keeps the **Get Library Directory** button; clicking it will display the error message via `FutureBuilder`.

## Differences from Android

Some "external storage" related interfaces behave inconsistently with Android and cannot be aligned due to platform capability limitations:

- `getExternalStorageDirectory()`: Android returns the app-specific directory on external storage, while OHOS returns the `files` directory within the app sandbox (internal storage).
- `getExternalCacheDirectories()`: Android may return multiple external cache directories, while OHOS only returns a single app `cache` directory.
- `getExternalStorageDirectories(type)`: Android returns multiple system-level external media/storage directories, while OHOS creates subdirectories by type under the `files` directory and returns a single path.
## Known Issues

## Directory Structure

```
|---- path_provider_ohos
|     |---- example                    # Example app
|           |---- lib                  # Example Dart code
|           |---- ohos                 # Example app native code
|     |---- lib                        # Dart core implementation
|           |---- path_provider_ohos.dart   # Plugin main entry
|           |---- messages.g.dart           # Platform channel message definitions
|     |---- ohos                       # OpenHarmony native code directory
|           |---- src/main/ets/components/plugin/PathProviderOhosPlugin.ets  # Plugin entry
|     |---- test                       # Unit tests
|     |---- CHANGELOG.md               # Version changelog
|     |---- LICENSE                    # BSD-3-Clause
|     |---- pubspec.yaml               # Package configuration file
|     |---- README.md      # Chinese documentation
|     |---- README.en.md   # English documentation
```

## Contributing

If you find any issues during use, please submit an [Issue](https://gitcode.com/CPF-Flutter/flutter_packages/issues). PRs are also welcome.

## License

This project is licensed under [BSD-3-Clause](https://gitcode.com/CPF-Flutter/flutter_packages/blob/master/packages/path_provider/path_provider_ohos/LICENSE), feel free to use and contribute.

> Template version: v0.0.1
