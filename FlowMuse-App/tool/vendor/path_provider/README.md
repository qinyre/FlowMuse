# path_provider
<?code-excerpt path-base="example/lib"?>

[![pub package](https://img.shields.io/pub/v/path_provider.svg)](https://pub.dev/packages/path_provider)

A Flutter plugin for finding commonly used locations on the filesystem.
Supports Android, iOS, Linux, macOS and Windows.
Not all methods are supported on all platforms.

|             | Android | iOS   | Linux | macOS  | Windows     | ohos |
|-------------|---------|-------|-------|--------|-------------|------|
| **Support** | SDK 16+ | 11.0+ | Any   | 10.14+ | Windows 10+ |  [API 12+](../path_provider_ohos/README.md)  |

## Usage

To use this plugin, add `path_provider` as a [dependency in your pubspec.yaml file](https://flutter.dev/docs/development/platform-integration/platform-channels).

### OpenHarmony   

- [中文](../path_provider_ohos/README_CN.md)
- [EN](../path_provider_ohos/README.md)

## Example
<?code-excerpt "readme_excerpts.dart (Example)"?>
```dart
final Directory tempDir = await getTemporaryDirectory();

final Directory appDocumentsDir = await getApplicationDocumentsDirectory();

final Directory? downloadsDir = await getDownloadsDirectory();
```

## Supported platforms and paths

Directories support by platform:

| Directory | Android | iOS | Linux | macOS | Windows |
| :--- | :---: | :---: | :---: | :---: | :---: |
| Temporary | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| Application Support | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| Application Library | ❌️ | ✔️ | ❌️ | ✔️ | ❌️ |
| Application Documents | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| Application Cache | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| External Storage | ✔️ | ❌ | ❌ | ❌️ | ❌️ |
| External Cache Directories | ✔️ | ❌ | ❌ | ❌️ | ❌️ |
| External Storage Directories | ✔️ | ❌ | ❌ | ❌️ | ❌️ |
| Downloads | ❌ | ✔️ | ✔️ | ✔️ | ✔️ |

## Testing

`path_provider` now uses a `PlatformInterface`, meaning that not all platforms share a single `PlatformChannel`-based implementation.
With that change, tests should be updated to mock `PathProviderPlatform` rather than `PlatformChannel`.

See this `path_provider` [test](https://github.com/flutter/packages/blob/main/packages/path_provider/path_provider/test/path_provider_test.dart) for an example.
