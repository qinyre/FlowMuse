# 依赖许可核对清单（2026-10-27）

基线：main `1b955b32`。从锁文件、已解析包目录和 Go 模块信息核对实际许可文本；四个未缓存的 Go 声明依赖只从对应上游 tag/commit 读取并校验许可 blob，未升级依赖或工具链。

核对范围为 **186 个 Dart/SDK 包、43 个 Go 声明依赖**；其中 Linux 服务入口实际使用 39 个 Go 模块。Dart 清单包含开发/测试及 SDK 包，不表示它们全都打入每个平台的发行包。

Go 的完整模块图还有 213 个未缓存、未纳入该发布依赖集合的开发/测试工具依赖，未逐项审计，不将它们虚称为已检查或已授权。未来分发开发工具、增改依赖或原生二进制时须重新核对。

下表许可标签是辅助识别，完整原文优先。Flutter SDK 中五个包没有独立根许可文件，核对其 SDK 根 BSD 许可；sky_engine 包含多个组件的合并通知，其中 GPL 关键词位于 MPL 的 Secondary License 定义，不据此判断整包 GPL。相关 MPL 等文本仍原样保留。

本清单不证明全部贡献者/学校或单位的权属，不替代法律审阅，也不覆盖所有平台 SDK、原生预编译依赖及模型权重的完整供应链。模型与鸿蒙 SQLite 的待补证事项见[第三方声明](../../../THIRD_PARTY_NOTICES.md)。

## Dart 与 Flutter SDK

| 组件 | 锁定版本 | 原始许可识别 | 核对来源 | 许可文本 SHA-256 |
| --- | --- | --- | --- | --- |
| `_fe_analyzer_shared` | `93.0.0` | BSD-3-Clause | [来源](https://pub.dev/packages/_fe_analyzer_shared/versions/93.0.0/license) | `LICENSE`: `efa31b5ac790016736fa9761642b0af16d37cd4fb483de2905adb5258cb89722` |
| `analyzer` | `10.0.1` | BSD-3-Clause | [来源](https://pub.dev/packages/analyzer/versions/10.0.1/license) | `LICENSE`: `7e124af6a556f045cb3a20cafbdaa31602ac2c82cbcb3c3b15faaaf514b06028` |
| `archive` | `4.0.9` | MIT | [来源](https://pub.dev/packages/archive/versions/4.0.9/license) | `LICENSE`: `32f97d332eae7453ec4079858e6f1d74be85beeb6d3881068b47d02a379cccea` |
| `args` | `2.7.0` | BSD-3-Clause | [来源](https://pub.dev/packages/args/versions/2.7.0/license) | `LICENSE`: `dfb09c74e29386cd3e2719f32d4995d59526179753931d31840757c77fbf2791` |
| `async` | `2.13.1` | BSD-3-Clause | [来源](https://pub.dev/packages/async/versions/2.13.1/license) | `LICENSE`: `ff15faa32a2e638107b7789592b14426162a75ba620044ee2340a20ec6ce5e73` |
| `boolean_selector` | `2.1.2` | BSD-3-Clause | [来源](https://pub.dev/packages/boolean_selector/versions/2.1.2/license) | `LICENSE`: `b71519245009a3b8f126196a5408ec031e216e8e0d985085958c6543f82a8a2a` |
| `characters` | `1.4.1` | BSD-3-Clause | [来源](https://pub.dev/packages/characters/versions/1.4.1/license) | `LICENSE`: `0371d1da6a57fb791db29d29b95333429205f51f3cb2eb3a0c12d91838a38744` |
| `cli_config` | `0.2.0` | BSD-3-Clause | [来源](https://pub.dev/packages/cli_config/versions/0.2.0/license) | `LICENSE`: `605bcf409f2347e3bcc9905ab70a2f3218e841bae372b0cbfbf305a222f74222` |
| `clock` | `1.1.2` | Apache-2.0 | [来源](https://pub.dev/packages/clock/versions/1.1.2/license) | `LICENSE`: `58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd` |
| `code_assets` | `1.2.1` | BSD-3-Clause | [来源](../../../FlowMuse-App/tool/vendor/code_assets) | `LICENSE`: `2f09397553ac82aec4a049c328fd97b97b87175419d6aa493f92d53c348274c9` |
| `collection` | `1.19.1` | BSD-3-Clause | [来源](https://pub.dev/packages/collection/versions/1.19.1/license) | `LICENSE`: `ff15faa32a2e638107b7789592b14426162a75ba620044ee2340a20ec6ce5e73` |
| `convert` | `3.1.2` | BSD-3-Clause | [来源](https://pub.dev/packages/convert/versions/3.1.2/license) | `LICENSE`: `ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888` |
| `coverage` | `1.15.1` | BSD-3-Clause | [来源](https://pub.dev/packages/coverage/versions/1.15.1/license) | `LICENSE`: `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` |
| `cross_file` | `0.3.5+4` | BSD-3-Clause | [来源](https://pub.dev/packages/cross_file/versions/0.3.5+4/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `crypto` | `3.0.7` | BSD-3-Clause | [来源](https://pub.dev/packages/crypto/versions/3.0.7/license) | `LICENSE`: `ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888` |
| `cryptography` | `2.9.0` | Apache-2.0 | [来源](https://pub.dev/packages/cryptography/versions/2.9.0/license) | `LICENSE`: `59899c6091b540582ed617e8eeaac4919dc985ccfc35459ee9752b699be5205b` |
| `dev_build` | `1.1.7+4` | BSD | [来源](https://pub.dev/packages/dev_build/versions/1.1.7+4/license) | `LICENSE`: `784539c5676fd830e5d7c8caf3d35e7d12ca4512573617027bc7120ea83c505b` |
| `device_info_plus` | `11.5.0` | BSD-3-Clause | [来源](https://pub.dev/packages/device_info_plus/versions/11.5.0/license) | `LICENSE`: `3b38d48befd0af70b892e13d10c9e34679416c24a9277f962629951c64d71f4c` |
| `device_info_plus_platform_interface` | `7.0.3` | BSD-3-Clause | [来源](https://pub.dev/packages/device_info_plus_platform_interface/versions/7.0.3/license) | `LICENSE`: `3b38d48befd0af70b892e13d10c9e34679416c24a9277f962629951c64d71f4c` |
| `extension` | `0.6.0` | MIT | [来源](https://pub.dev/packages/extension/versions/0.6.0/license) | `LICENSE`: `da3ece2d2daf5c812c8606d2922094f51818258d4ce0e041b4ee8409ba3b381f` |
| `fake_async` | `1.3.3` | Apache-2.0 | [来源](https://pub.dev/packages/fake_async/versions/1.3.3/license) | `LICENSE`: `58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd` |
| `ffi` | `2.2.0` | BSD-3-Clause | [来源](https://pub.dev/packages/ffi/versions/2.2.0/license) | `LICENSE`: `0371d1da6a57fb791db29d29b95333429205f51f3cb2eb3a0c12d91838a38744` |
| `file` | `7.0.1` | BSD-3-Clause | [来源](https://pub.dev/packages/file/versions/7.0.1/license) | `LICENSE`: `f6df86b1412172537273e8e80ee2fb8a66aa7307ce0b39ea5ddab47ca41b8c49` |
| `file_picker` | `8.3.7` | MIT | [来源](https://pub.dev/packages/file_picker/versions/8.3.7/license) | `LICENSE`: `6278994817bd65fa32404e53c3a62a09d824d3f9a71f7fadcaca3e4f02641d66` |
| `fixnum` | `1.1.1` | BSD-3-Clause | [来源](https://pub.dev/packages/fixnum/versions/1.1.1/license) | `LICENSE`: `ff0b91d4f3c32b25cb6ec84985e8da89b0ba2a2b2f7eef353cda5e5423a20390` |
| `flutter` | `0.0.0` | BSD-3-Clause | [来源](https://github.com/flutter/flutter/blob/3.41.10/LICENSE) | `LICENSE`: `a3a9fd82f800a47377f7d3f60c60a5c91cae0495be8f329031e1448ce0f5dab9` |
| `flutter_dotenv` | `6.0.1` | MIT | [来源](https://pub.dev/packages/flutter_dotenv/versions/6.0.1/license) | `LICENSE`: `638e544426255b39311e3abe90dab5d20379aedaf0f9ca9b58b721922760e3f7` |
| `flutter_driver` | `0.0.0` | BSD-3-Clause | [来源](https://github.com/flutter/flutter/blob/3.41.10/LICENSE) | `LICENSE`: `a3a9fd82f800a47377f7d3f60c60a5c91cae0495be8f329031e1448ce0f5dab9` |
| `flutter_lints` | `6.0.0` | BSD-3-Clause | [来源](https://pub.dev/packages/flutter_lints/versions/6.0.0/license) | `LICENSE`: `89519eca6f7b9529b35bdddd623a58c3af06a88c458dbd6531ddb4675acf75a9` |
| `flutter_markdown_plus` | `1.0.12` | BSD-3-Clause | [来源](https://pub.dev/packages/flutter_markdown_plus/versions/1.0.12/license) | `LICENSE`: `89519eca6f7b9529b35bdddd623a58c3af06a88c458dbd6531ddb4675acf75a9` |
| `flutter_math_fork` | `0.7.4` | Apache-2.0 | [来源](../../../FlowMuse-App/tool/vendor/flutter_math_fork) | `LICENSE`: `49bbe9114e49214df2ccc324cb3ac8d1d1aa1c3a0947f94c286765e86647b32e` |
| `flutter_plugin_android_lifecycle` | `2.0.35` | BSD-3-Clause | [来源](https://pub.dev/packages/flutter_plugin_android_lifecycle/versions/2.0.35/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `flutter_riverpod` | `3.3.2` | MIT | [来源](https://pub.dev/packages/flutter_riverpod/versions/3.3.2/license) | `LICENSE`: `757d9c09a9a2a701144328c0fd596234ea287ff62952b39cd22f9ad4caed1171` |
| `flutter_secure_storage` | `9.2.4` | BSD-3-Clause | [来源](https://pub.dev/packages/flutter_secure_storage/versions/9.2.4/license) | `LICENSE`: `55dafb084270616f95b9bea53654adda8bdcad95c022a83c4cf8769073f829fa` |
| `flutter_secure_storage_linux` | `1.2.3` | BSD-3-Clause | [来源](https://pub.dev/packages/flutter_secure_storage_linux/versions/1.2.3/license) | `LICENSE`: `55dafb084270616f95b9bea53654adda8bdcad95c022a83c4cf8769073f829fa` |
| `flutter_secure_storage_macos` | `3.1.3` | BSD-3-Clause | [来源](https://pub.dev/packages/flutter_secure_storage_macos/versions/3.1.3/license) | `LICENSE`: `55dafb084270616f95b9bea53654adda8bdcad95c022a83c4cf8769073f829fa` |
| `flutter_secure_storage_ohos` | `1.0.0` | MIT | [来源](https://pub.dev/packages/flutter_secure_storage_ohos/versions/1.0.0/license) | `LICENSE`: `d87381742347e8737819c77cde52cfbd5062f7ae0f5ad2224fb4156ff7335d8e` |
| `flutter_secure_storage_platform_interface` | `1.1.2` | BSD-3-Clause | [来源](https://pub.dev/packages/flutter_secure_storage_platform_interface/versions/1.1.2/license) | `LICENSE`: `55dafb084270616f95b9bea53654adda8bdcad95c022a83c4cf8769073f829fa` |
| `flutter_secure_storage_web` | `1.2.1` | BSD-3-Clause | [来源](https://pub.dev/packages/flutter_secure_storage_web/versions/1.2.1/license) | `LICENSE`: `55dafb084270616f95b9bea53654adda8bdcad95c022a83c4cf8769073f829fa` |
| `flutter_secure_storage_windows` | `3.1.2` | BSD-3-Clause | [来源](https://pub.dev/packages/flutter_secure_storage_windows/versions/3.1.2/license) | `LICENSE`: `55dafb084270616f95b9bea53654adda8bdcad95c022a83c4cf8769073f829fa` |
| `flutter_svg` | `2.3.0` | MIT | [来源](https://pub.dev/packages/flutter_svg/versions/2.3.0/license) | `LICENSE`: `dc54ae36c905edfbf3c6678ee34d8da5989d7ccc7b993857a9d89db06a67eb18` |
| `flutter_test` | `0.0.0` | BSD-3-Clause | [来源](https://github.com/flutter/flutter/blob/3.41.10/LICENSE) | `LICENSE`: `a3a9fd82f800a47377f7d3f60c60a5c91cae0495be8f329031e1448ce0f5dab9` |
| `flutter_web_plugins` | `0.0.0` | BSD-3-Clause | [来源](https://github.com/flutter/flutter/blob/3.41.10/LICENSE) | `LICENSE`: `a3a9fd82f800a47377f7d3f60c60a5c91cae0495be8f329031e1448ce0f5dab9` |
| `freezed_annotation` | `2.4.4` | MIT | [来源](https://pub.dev/packages/freezed_annotation/versions/2.4.4/license) | `LICENSE`: `757d9c09a9a2a701144328c0fd596234ea287ff62952b39cd22f9ad4caed1171` |
| `frontend_server_client` | `4.0.0` | BSD-3-Clause | [来源](https://pub.dev/packages/frontend_server_client/versions/4.0.0/license) | `LICENSE`: `f3fedf65adeec4d6ccb2abf053ebc0f07603d402db3d3c5651322b50502e1071` |
| `fuchsia_remote_debug_protocol` | `0.0.0` | BSD-3-Clause | [来源](https://github.com/flutter/flutter/blob/3.41.10/LICENSE) | `LICENSE`: `a3a9fd82f800a47377f7d3f60c60a5c91cae0495be8f329031e1448ce0f5dab9` |
| `glob` | `2.1.3` | BSD-3-Clause | [来源](https://pub.dev/packages/glob/versions/2.1.3/license) | `LICENSE`: `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` |
| `go_router` | `17.3.0` | BSD-3-Clause | [来源](https://pub.dev/packages/go_router/versions/17.3.0/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `google_fonts` | `6.3.3` | BSD-3-Clause | [来源](https://pub.dev/packages/google_fonts/versions/6.3.3/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `hooks` | `2.0.2` | BSD-3-Clause | [来源](https://pub.dev/packages/hooks/versions/2.0.2/license) | `LICENSE`: `21ae23b0b9ff67a2dc75ab085d1e8db8ac548c5faf370af17f28dd2ef3b52b7b` |
| `http` | `1.6.0` | BSD-3-Clause | [来源](https://pub.dev/packages/http/versions/1.6.0/license) | `LICENSE`: `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` |
| `http_multi_server` | `3.2.2` | BSD-3-Clause | [来源](https://pub.dev/packages/http_multi_server/versions/3.2.2/license) | `LICENSE`: `ff0b91d4f3c32b25cb6ec84985e8da89b0ba2a2b2f7eef353cda5e5423a20390` |
| `http_parser` | `4.1.2` | BSD-3-Clause | [来源](https://pub.dev/packages/http_parser/versions/4.1.2/license) | `LICENSE`: `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` |
| `integration_test` | `0.0.0` | BSD-3-Clause | [来源](https://github.com/flutter/flutter/blob/3.41.10/LICENSE) | `LICENSE`: `a3a9fd82f800a47377f7d3f60c60a5c91cae0495be8f329031e1448ce0f5dab9` |
| `io` | `1.0.5` | BSD-3-Clause | [来源](https://pub.dev/packages/io/versions/1.0.5/license) | `LICENSE`: `ea97a7558a7bd7cee4e2355f7529e3cbebb0dcbb546ddb9a90f10c9eb6b08da5` |
| `irondash_engine_context` | `0.5.5` | MIT | [来源](https://pub.dev/packages/irondash_engine_context/versions/0.5.5/license) | `LICENSE`: `152ba1ff4e506f8be162929039a0f0abfe172b658a10027d2ef3abe2e4aa4207` |
| `irondash_message_channel` | `0.7.0` | MIT | [来源](https://pub.dev/packages/irondash_message_channel/versions/0.7.0/license) | `LICENSE`: `152ba1ff4e506f8be162929039a0f0abfe172b658a10027d2ef3abe2e4aa4207` |
| `isolate_contactor` | `4.1.0` | MIT | [来源](https://pub.dev/packages/isolate_contactor/versions/4.1.0/license) | `LICENSE`: `b6ac5dcee3faa11230fe658a928f486f79d8686e7ff735db85b5b50d3679df70` |
| `isolate_manager` | `4.1.5+1` | MIT | [来源](https://pub.dev/packages/isolate_manager/versions/4.1.5+1/license) | `LICENSE`: `814d2c7b35235559712567b8e719fa781059019ece0ba05807b8467ec6b45ee4` |
| `jni` | `1.0.0` | BSD-3-Clause | [来源](https://pub.dev/packages/jni/versions/1.0.0/license) | `LICENSE`: `08a004aa8956c3cf3b24f7f69c966247233953e18e6afaa61191ea47b7eb70f6` |
| `jni_flutter` | `1.0.1` | BSD-3-Clause | [来源](https://pub.dev/packages/jni_flutter/versions/1.0.1/license) | `LICENSE`: `b1fcb475d67817411f335ac92872507011e574c4cb29cfdaaf7707b75641932c` |
| `js` | `0.6.7` | BSD-3-Clause | [来源](https://pub.dev/packages/js/versions/0.6.7/license) | `LICENSE`: `efa4eaf6fdec22a36a61395ea70843db9ae815760bf663e068012c92b93c0184` |
| `json_annotation` | `4.12.0` | BSD-3-Clause | [来源](https://pub.dev/packages/json_annotation/versions/4.12.0/license) | `LICENSE`: `143839f62c9b7f88143ea9f688361c27050888acde7696b34e04414bd254fafc` |
| `leak_tracker` | `11.0.2` | BSD-3-Clause | [来源](https://pub.dev/packages/leak_tracker/versions/11.0.2/license) | `LICENSE`: `08a004aa8956c3cf3b24f7f69c966247233953e18e6afaa61191ea47b7eb70f6` |
| `leak_tracker_flutter_testing` | `3.0.10` | BSD-3-Clause | [来源](https://pub.dev/packages/leak_tracker_flutter_testing/versions/3.0.10/license) | `LICENSE`: `08a004aa8956c3cf3b24f7f69c966247233953e18e6afaa61191ea47b7eb70f6` |
| `leak_tracker_testing` | `3.0.2` | BSD-3-Clause | [来源](https://pub.dev/packages/leak_tracker_testing/versions/3.0.2/license) | `LICENSE`: `08a004aa8956c3cf3b24f7f69c966247233953e18e6afaa61191ea47b7eb70f6` |
| `lints` | `6.1.0` | BSD-3-Clause | [来源](https://pub.dev/packages/lints/versions/6.1.0/license) | `LICENSE`: `421fe78c3b5df297f8b4ab2c74f2450a274ee6d245a113091f6b9f90570af193` |
| `logging` | `1.3.0` | BSD-3-Clause | [来源](https://pub.dev/packages/logging/versions/1.3.0/license) | `LICENSE`: `dfb09c74e29386cd3e2719f32d4995d59526179753931d31840757c77fbf2791` |
| `lucide_icons_flutter` | `3.1.14+2` | MIT | [来源](https://pub.dev/packages/lucide_icons_flutter/versions/3.1.14+2/license) | `LICENSE`: `e314b096fc1cfa025b5e43cc5774fadbaec8f5f4fd4f0c415fe17fbcc1410dd5` |
| `markdown` | `7.3.1` | BSD-3-Clause | [来源](https://pub.dev/packages/markdown/versions/7.3.1/license) | `LICENSE`: `0aa335b5e036b9efbb35ad7a35835cd32e4eb656c08bfe040550a9f6fa84fcc7` |
| `matcher` | `0.12.19` | BSD-3-Clause | [来源](https://pub.dev/packages/matcher/versions/0.12.19/license) | `LICENSE`: `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` |
| `material_color_utilities` | `0.13.0` | Apache-2.0 | [来源](https://pub.dev/packages/material_color_utilities/versions/0.13.0/license) | `LICENSE`: `d103f246ef4c18dab8af0c1dcf6a8af884e5cff554da7261a48ac43c17d98f2e` |
| `meta` | `1.17.0` | BSD-3-Clause | [来源](https://pub.dev/packages/meta/versions/1.17.0/license) | `LICENSE`: `b71519245009a3b8f126196a5408ec031e216e8e0d985085958c6543f82a8a2a` |
| `mime` | `2.0.0` | BSD-3-Clause | [来源](https://pub.dev/packages/mime/versions/2.0.0/license) | `LICENSE`: `ff15faa32a2e638107b7789592b14426162a75ba620044ee2340a20ec6ce5e73` |
| `mobile_scanner` | `7.4.2` | BSD-3-Clause | [来源](https://pub.dev/packages/mobile_scanner/versions/7.4.2/license) | `LICENSE`: `339ba81aabe6518f26ab5c9d2f76ca1732349360ba18d61bb93acb694dee7afe` |
| `native_toolchain_c` | `0.19.2` | BSD-3-Clause | [来源](https://pub.dev/packages/native_toolchain_c/versions/0.19.2/license) | `LICENSE`: `aa81abb1ac43e40d2f5a606385edd37e974a5858d4109f7f439dd43d964487a7` |
| `nested` | `1.0.0` | MIT | [来源](https://pub.dev/packages/nested/versions/1.0.0/license) | `LICENSE`: `fccaeae95a39c93176de9321c734c90d8e36f465c48fcf278840844d8eab1af4` |
| `node_preamble` | `2.0.2` | MIT, BSD-3-Clause | [来源](https://pub.dev/packages/node_preamble/versions/2.0.2/license) | `LICENSE`: `41997ee02074e3796e539b81b4501ed7d8bc1a620d11ef32cf56494e778461a9` |
| `objective_c` | `9.4.1` | BSD-3-Clause | [来源](https://pub.dev/packages/objective_c/versions/9.4.1/license) | `LICENSE`: `1cda25a8de6880c5338de0b4a06ee89e8537c213eb1379c16a4c035bfd198b5c` |
| `package_config` | `2.2.0` | BSD-3-Clause | [来源](https://pub.dev/packages/package_config/versions/2.2.0/license) | `LICENSE`: `0371d1da6a57fb791db29d29b95333429205f51f3cb2eb3a0c12d91838a38744` |
| `path` | `1.9.1` | BSD-3-Clause | [来源](https://pub.dev/packages/path/versions/1.9.1/license) | `LICENSE`: `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` |
| `path_parsing` | `1.1.0` | MIT | [来源](https://pub.dev/packages/path_parsing/versions/1.1.0/license) | `LICENSE`: `f4fc0fe1e273823b06540b3b948640ff81f3a5c5dc7088972eef662fe450ad77` |
| `path_provider` | `2.1.0` | BSD-3-Clause | [来源](../../../FlowMuse-App/tool/vendor/path_provider) | `LICENSE`: `0b1949a190148858a1ad558d451ec37f6ae7e80f379bde355cf6224103327e35` |
| `path_provider_android` | `2.3.1` | BSD-3-Clause | [来源](https://pub.dev/packages/path_provider_android/versions/2.3.1/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `path_provider_foundation` | `2.6.0` | BSD-3-Clause | [来源](https://pub.dev/packages/path_provider_foundation/versions/2.6.0/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `path_provider_linux` | `2.2.2` | BSD-3-Clause | [来源](https://pub.dev/packages/path_provider_linux/versions/2.2.2/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `path_provider_ohos` | `2.2.1` | BSD-3-Clause | [来源](../../../FlowMuse-App/tool/vendor/path_provider_ohos) | `LICENSE`: `0b1949a190148858a1ad558d451ec37f6ae7e80f379bde355cf6224103327e35` |
| `path_provider_platform_interface` | `2.1.3` | BSD-3-Clause | [来源](https://pub.dev/packages/path_provider_platform_interface/versions/2.1.3/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `path_provider_windows` | `2.3.0` | BSD-3-Clause | [来源](https://pub.dev/packages/path_provider_windows/versions/2.3.0/license) | `LICENSE`: `89519eca6f7b9529b35bdddd623a58c3af06a88c458dbd6531ddb4675acf75a9` |
| `pdfx` | `2.9.2` | MIT | [来源](https://pub.dev/packages/pdfx/versions/2.9.2/license) | `LICENSE`: `44e34f70d50670fa260cd7db787cc06ba532c06a72011dd3fcd3b1e700ccdfd0` |
| `perfect_freehand` | `2.5.2+1` | MIT | [来源](https://pub.dev/packages/perfect_freehand/versions/2.5.2+1/license) | `LICENSE`: `2225e448984b6bc9a25ef6fe0bccd9ec75e139d940107f02690387be56843c3c` |
| `petitparser` | `7.0.2` | MIT | [来源](https://pub.dev/packages/petitparser/versions/7.0.2/license) | `LICENSE`: `d2e8ffdbe89acbc10d5d1f2b03e7dbddf0a9f1742e809176682b62ef3d573b3e` |
| `photo_view` | `0.15.0` | MIT | [来源](https://pub.dev/packages/photo_view/versions/0.15.0/license) | `LICENSE`: `731117906ac75af8cdb23377bab020db62045fbe385ef0c4ed6157120f502fc2` |
| `pixel_snap` | `0.1.5` | MIT | [来源](https://pub.dev/packages/pixel_snap/versions/0.1.5/license) | `LICENSE`: `152ba1ff4e506f8be162929039a0f0abfe172b658a10027d2ef3abe2e4aa4207` |
| `platform` | `3.1.6` | BSD-3-Clause | [来源](https://pub.dev/packages/platform/versions/3.1.6/license) | `LICENSE`: `143839f62c9b7f88143ea9f688361c27050888acde7696b34e04414bd254fafc` |
| `plugin_platform_interface` | `2.1.8` | BSD-3-Clause | [来源](https://pub.dev/packages/plugin_platform_interface/versions/2.1.8/license) | `LICENSE`: `89519eca6f7b9529b35bdddd623a58c3af06a88c458dbd6531ddb4675acf75a9` |
| `pool` | `1.5.2` | BSD-3-Clause | [来源](https://pub.dev/packages/pool/versions/1.5.2/license) | `LICENSE`: `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` |
| `posix` | `6.5.0` | MIT | [来源](https://pub.dev/packages/posix/versions/6.5.0/license) | `LICENSE`: `aaf6271abd048deb3125828613f1797b7556472de6c7acd7103bd43e9cb6a84b` |
| `process` | `5.0.5` | BSD-3-Clause | [来源](https://pub.dev/packages/process/versions/5.0.5/license) | `LICENSE`: `5f018bbc25a55406d7a4e1d3229135439e315210b0050ca56dbb367a4934e85d` |
| `process_run` | `1.3.3+1` | BSD | [来源](https://pub.dev/packages/process_run/versions/1.3.3+1/license) | `LICENSE`: `edeea764d77807e2dc1455b990f96686d8ea4e24c7c14d7c854e915f365128bb` |
| `provider` | `6.1.5+1` | MIT | [来源](https://pub.dev/packages/provider/versions/6.1.5+1/license) | `LICENSE`: `fccaeae95a39c93176de9321c734c90d8e36f465c48fcf278840844d8eab1af4` |
| `pub_semver` | `2.2.0` | BSD-3-Clause | [来源](https://pub.dev/packages/pub_semver/versions/2.2.0/license) | `LICENSE`: `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` |
| `qr` | `3.0.2` | BSD-3-Clause | [来源](https://pub.dev/packages/qr/versions/3.0.2/license) | `LICENSE`: `1d6c0bc8208cd835577eeb9195dc646f092728b62803abd60c404d984524abf7` |
| `qr_flutter` | `4.1.0` | BSD-3-Clause | [来源](https://pub.dev/packages/qr_flutter/versions/4.1.0/license) | `LICENSE`: `1bc86cb2619634e54a97f88dd9c11fd99afcacd52c25bdf6f84c2700b4174203` |
| `re_editor` | `0.8.0` | MIT | [来源](https://pub.dev/packages/re_editor/versions/0.8.0/license) | `LICENSE`: `5d37eaa3f35293d2141f08ffeb897040380eeb25016a5a17f71200a56bf44767` |
| `re_highlight` | `0.0.3` | MIT | [来源](https://pub.dev/packages/re_highlight/versions/0.0.3/license) | `LICENSE`: `5d37eaa3f35293d2141f08ffeb897040380eeb25016a5a17f71200a56bf44767` |
| `record` | `6.2.1` | BSD-3-Clause | [来源](https://pub.dev/packages/record/versions/6.2.1/license) | `LICENSE`: `5a21ee0d2585baccfde18aeb045037701172460213db723e9d189ca1922aaf79` |
| `record_android` | `1.5.2` | BSD-3-Clause | [来源](https://pub.dev/packages/record_android/versions/1.5.2/license) | `LICENSE`: `5a21ee0d2585baccfde18aeb045037701172460213db723e9d189ca1922aaf79` |
| `record_ios` | `1.2.1` | BSD-3-Clause | [来源](https://pub.dev/packages/record_ios/versions/1.2.1/license) | `LICENSE`: `5a21ee0d2585baccfde18aeb045037701172460213db723e9d189ca1922aaf79` |
| `record_linux` | `1.3.1` | BSD-3-Clause | [来源](https://pub.dev/packages/record_linux/versions/1.3.1/license) | `LICENSE`: `5a21ee0d2585baccfde18aeb045037701172460213db723e9d189ca1922aaf79` |
| `record_macos` | `1.2.2` | BSD-3-Clause | [来源](https://pub.dev/packages/record_macos/versions/1.2.2/license) | `LICENSE`: `5a21ee0d2585baccfde18aeb045037701172460213db723e9d189ca1922aaf79` |
| `record_platform_interface` | `1.6.0` | BSD-3-Clause | [来源](https://pub.dev/packages/record_platform_interface/versions/1.6.0/license) | `LICENSE`: `5a21ee0d2585baccfde18aeb045037701172460213db723e9d189ca1922aaf79` |
| `record_use` | `0.6.0` | BSD-3-Clause | [来源](https://pub.dev/packages/record_use/versions/0.6.0/license) | `LICENSE`: `1cda25a8de6880c5338de0b4a06ee89e8537c213eb1379c16a4c035bfd198b5c` |
| `record_web` | `1.3.0` | BSD-3-Clause | [来源](https://pub.dev/packages/record_web/versions/1.3.0/license) | `LICENSE`: `5a21ee0d2585baccfde18aeb045037701172460213db723e9d189ca1922aaf79` |
| `record_windows` | `1.0.7` | BSD-3-Clause | [来源](https://pub.dev/packages/record_windows/versions/1.0.7/license) | `LICENSE`: `b0cbe4a6717dc8286d44792bd905fdc49f179b80af8d1543e4194e61766803a3` |
| `riverpod` | `3.3.2` | MIT | [来源](https://pub.dev/packages/riverpod/versions/3.3.2/license) | `LICENSE`: `757d9c09a9a2a701144328c0fd596234ea287ff62952b39cd22f9ad4caed1171` |
| `rough_flutter` | `0.1.2` | MIT | [来源](https://pub.dev/packages/rough_flutter/versions/0.1.2/license) | `LICENSE`: `834714a46e14d06fbb6e55c33cbe0121b820182c99147a7b8737faa669055c76` |
| `share_plus` | `12.0.2` | BSD-3-Clause | [来源](https://pub.dev/packages/share_plus/versions/12.0.2/license) | `LICENSE`: `eb9741a672906ebd01fd9b3bef38f6c82eff250e91149cf404539ee7981079fd` |
| `share_plus_platform_interface` | `6.1.0` | BSD-3-Clause | [来源](https://pub.dev/packages/share_plus_platform_interface/versions/6.1.0/license) | `LICENSE`: `3b38d48befd0af70b892e13d10c9e34679416c24a9277f962629951c64d71f4c` |
| `shelf` | `1.4.2` | BSD-3-Clause | [来源](https://pub.dev/packages/shelf/versions/1.4.2/license) | `LICENSE`: `ff0b91d4f3c32b25cb6ec84985e8da89b0ba2a2b2f7eef353cda5e5423a20390` |
| `shelf_packages_handler` | `3.0.2` | BSD-3-Clause | [来源](https://pub.dev/packages/shelf_packages_handler/versions/3.0.2/license) | `LICENSE`: `b71519245009a3b8f126196a5408ec031e216e8e0d985085958c6543f82a8a2a` |
| `shelf_static` | `1.1.3` | BSD-3-Clause | [来源](https://pub.dev/packages/shelf_static/versions/1.1.3/license) | `LICENSE`: `ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888` |
| `shelf_web_socket` | `3.0.0` | BSD-3-Clause | [来源](https://pub.dev/packages/shelf_web_socket/versions/3.0.0/license) | `LICENSE`: `ff0b91d4f3c32b25cb6ec84985e8da89b0ba2a2b2f7eef353cda5e5423a20390` |
| `sherpa_onnx` | `1.13.4` | Apache-2.0 | [来源](https://pub.dev/packages/sherpa_onnx/versions/1.13.4/license) | `LICENSE`: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `sherpa_onnx_android_arm64` | `1.13.4` | Apache-2.0 | [来源](https://pub.dev/packages/sherpa_onnx_android_arm64/versions/1.13.4/license) | `LICENSE`: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `sherpa_onnx_android_armeabi` | `1.13.4` | Apache-2.0 | [来源](https://pub.dev/packages/sherpa_onnx_android_armeabi/versions/1.13.4/license) | `LICENSE`: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `sherpa_onnx_android_x86` | `1.13.4` | Apache-2.0 | [来源](https://pub.dev/packages/sherpa_onnx_android_x86/versions/1.13.4/license) | `LICENSE`: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `sherpa_onnx_android_x86_64` | `1.13.4` | Apache-2.0 | [来源](https://pub.dev/packages/sherpa_onnx_android_x86_64/versions/1.13.4/license) | `LICENSE`: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `sherpa_onnx_ios` | `1.13.4` | Apache-2.0 | [来源](https://pub.dev/packages/sherpa_onnx_ios/versions/1.13.4/license) | `LICENSE`: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `sherpa_onnx_linux` | `1.13.4` | Apache-2.0 | [来源](https://pub.dev/packages/sherpa_onnx_linux/versions/1.13.4/license) | `LICENSE`: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `sherpa_onnx_macos` | `1.13.4` | Apache-2.0 | [来源](https://pub.dev/packages/sherpa_onnx_macos/versions/1.13.4/license) | `LICENSE`: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `sherpa_onnx_windows` | `1.13.4` | Apache-2.0 | [来源](https://pub.dev/packages/sherpa_onnx_windows/versions/1.13.4/license) | `LICENSE`: `3ddf9be5c28fe27dad143a5dc76eea25222ad1dd68934a047064e56ed2fa40c5` |
| `sky_engine` | `0.0.0` | 混合组件通知（含 MPL-2.0 等） | [来源](https://github.com/flutter/flutter/blob/3.41.10/LICENSE) | `license`: `1d531df6b9d1142fa3f6abc518cfab21adc6570ae11631c40a7ba366c93d2eaa` |
| `socket_io_client` | `3.1.6` | MIT | [来源](https://pub.dev/packages/socket_io_client/versions/3.1.6/license) | `LICENSE`: `65149e40855a4595bca1bacafb5451420afc2b8021a53c787a562f717237e9de` |
| `socket_io_common` | `3.1.1` | MIT | [来源](https://pub.dev/packages/socket_io_common/versions/3.1.1/license) | `LICENSE`: `65149e40855a4595bca1bacafb5451420afc2b8021a53c787a562f717237e9de` |
| `source_map_stack_trace` | `2.1.2` | BSD-3-Clause | [来源](https://pub.dev/packages/source_map_stack_trace/versions/2.1.2/license) | `LICENSE`: `ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888` |
| `source_maps` | `0.10.13` | BSD-3-Clause | [来源](https://pub.dev/packages/source_maps/versions/0.10.13/license) | `LICENSE`: `ff0b91d4f3c32b25cb6ec84985e8da89b0ba2a2b2f7eef353cda5e5423a20390` |
| `source_span` | `1.10.2` | BSD-3-Clause | [来源](https://pub.dev/packages/source_span/versions/1.10.2/license) | `LICENSE`: `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` |
| `sqflite` | `2.4.2+1` | BSD | [来源](https://pub.dev/packages/sqflite/versions/2.4.2+1/license) | `LICENSE`: `c81f9454cf3107c116bc3c1fd22b7d751523a2b11e17cf90c0db3327d3c9e0da` |
| `sqflite_android` | `2.4.2+3` | BSD | [来源](https://pub.dev/packages/sqflite_android/versions/2.4.2+3/license) | `LICENSE`: `c81f9454cf3107c116bc3c1fd22b7d751523a2b11e17cf90c0db3327d3c9e0da` |
| `sqflite_common` | `2.5.8` | BSD | [来源](https://pub.dev/packages/sqflite_common/versions/2.5.8/license) | `LICENSE`: `c81f9454cf3107c116bc3c1fd22b7d751523a2b11e17cf90c0db3327d3c9e0da` |
| `sqflite_common_ffi` | `2.4.0+3` | BSD | [来源](https://pub.dev/packages/sqflite_common_ffi/versions/2.4.0+3/license) | `LICENSE`: `c81f9454cf3107c116bc3c1fd22b7d751523a2b11e17cf90c0db3327d3c9e0da` |
| `sqflite_common_ffi_web` | `1.1.1` | BSD | [来源](https://pub.dev/packages/sqflite_common_ffi_web/versions/1.1.1/license) | `LICENSE`: `8e7977eb23fb4080e6231bbb06665aad39dfc4d6607a1abda497c999e60286c6` |
| `sqflite_darwin` | `2.4.2` | BSD | [来源](https://pub.dev/packages/sqflite_darwin/versions/2.4.2/license) | `LICENSE`: `c81f9454cf3107c116bc3c1fd22b7d751523a2b11e17cf90c0db3327d3c9e0da` |
| `sqflite_platform_interface` | `2.4.0` | BSD | [来源](https://pub.dev/packages/sqflite_platform_interface/versions/2.4.0/license) | `LICENSE`: `c81f9454cf3107c116bc3c1fd22b7d751523a2b11e17cf90c0db3327d3c9e0da` |
| `sqlite3` | `3.3.4` | MIT | [来源](https://pub.dev/packages/sqlite3/versions/3.3.4/license) | `LICENSE`: `67e5d73a3a0c6e41f33d688a672b1161bf7f16e04da9ae48a7a14f1ba7436a4d` |
| `stack_trace` | `1.12.1` | BSD-3-Clause | [来源](https://pub.dev/packages/stack_trace/versions/1.12.1/license) | `LICENSE`: `ff0b91d4f3c32b25cb6ec84985e8da89b0ba2a2b2f7eef353cda5e5423a20390` |
| `state_notifier` | `1.0.0` | MIT | [来源](https://pub.dev/packages/state_notifier/versions/1.0.0/license) | `LICENSE`: `757d9c09a9a2a701144328c0fd596234ea287ff62952b39cd22f9ad4caed1171` |
| `stream_channel` | `2.1.4` | BSD-3-Clause | [来源](https://pub.dev/packages/stream_channel/versions/2.1.4/license) | `LICENSE`: `ff15faa32a2e638107b7789592b14426162a75ba620044ee2340a20ec6ce5e73` |
| `string_scanner` | `1.4.1` | BSD-3-Clause | [来源](https://pub.dev/packages/string_scanner/versions/1.4.1/license) | `LICENSE`: `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` |
| `super_clipboard` | `0.9.1` | MIT | [来源](https://pub.dev/packages/super_clipboard/versions/0.9.1/license) | `LICENSE`: `27054bee8f3f281dafb401a3f309b986b6f071c2a0bf50380ee1b2e0c6ceb6a7` |
| `super_native_extensions` | `0.9.1` | MIT | [来源](https://pub.dev/packages/super_native_extensions/versions/0.9.1/license) | `LICENSE`: `27054bee8f3f281dafb401a3f309b986b6f071c2a0bf50380ee1b2e0c6ceb6a7` |
| `sync_http` | `0.3.1` | BSD-3-Clause | [来源](https://pub.dev/packages/sync_http/versions/0.3.1/license) | `LICENSE`: `b9b748d4dd6f725387bf69e96df4e4ebff167ae83547954242a731504d037644` |
| `synchronized` | `3.4.0+1` | MIT | [来源](https://pub.dev/packages/synchronized/versions/3.4.0+1/license) | `LICENSE`: `6d07c6bb60afb906049d507e19fcc4c6b59e35c0dd0f8a7302e87b3fb0576900` |
| `term_glyph` | `1.2.2` | BSD-3-Clause | [来源](https://pub.dev/packages/term_glyph/versions/1.2.2/license) | `LICENSE`: `ea97a7558a7bd7cee4e2355f7529e3cbebb0dcbb546ddb9a90f10c9eb6b08da5` |
| `test` | `1.30.0` | BSD-3-Clause | [来源](https://pub.dev/packages/test/versions/1.30.0/license) | `LICENSE`: `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` |
| `test_api` | `0.7.10` | BSD-3-Clause | [来源](https://pub.dev/packages/test_api/versions/0.7.10/license) | `LICENSE`: `ff1b9f0df9036c04be424b1e3ce12789bea880ad5ffc3a48e069ae2d40a087a4` |
| `test_core` | `0.6.16` | BSD-3-Clause | [来源](https://pub.dev/packages/test_core/versions/0.6.16/license) | `LICENSE`: `ff1b9f0df9036c04be424b1e3ce12789bea880ad5ffc3a48e069ae2d40a087a4` |
| `tuple` | `2.0.2` | BSD | [来源](https://pub.dev/packages/tuple/versions/2.0.2/license) | `LICENSE`: `9bc3a4d6be8548b2a59e7875f0ba53e7d2ad25e2feb652213ff05c2fd06f1c91` |
| `typed_data` | `1.4.0` | BSD-3-Clause | [来源](https://pub.dev/packages/typed_data/versions/1.4.0/license) | `LICENSE`: `ff15faa32a2e638107b7789592b14426162a75ba620044ee2340a20ec6ce5e73` |
| `universal_platform` | `1.1.0` | MIT | [来源](https://pub.dev/packages/universal_platform/versions/1.1.0/license) | `LICENSE`: `8a135e09d6288f03171b04f07f00eb5ee04e54f2f5e9c9b952f6adbd1de48c3f` |
| `url_launcher` | `6.3.2` | BSD-3-Clause | [来源](https://pub.dev/packages/url_launcher/versions/6.3.2/license) | `LICENSE`: `89519eca6f7b9529b35bdddd623a58c3af06a88c458dbd6531ddb4675acf75a9` |
| `url_launcher_android` | `6.3.30` | BSD-3-Clause | [来源](https://pub.dev/packages/url_launcher_android/versions/6.3.30/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `url_launcher_ios` | `6.4.1` | BSD-3-Clause | [来源](https://pub.dev/packages/url_launcher_ios/versions/6.4.1/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `url_launcher_linux` | `3.2.2` | BSD-3-Clause | [来源](https://pub.dev/packages/url_launcher_linux/versions/3.2.2/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `url_launcher_macos` | `3.2.5` | BSD-3-Clause | [来源](https://pub.dev/packages/url_launcher_macos/versions/3.2.5/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `url_launcher_platform_interface` | `2.3.2` | BSD-3-Clause | [来源](https://pub.dev/packages/url_launcher_platform_interface/versions/2.3.2/license) | `LICENSE`: `89519eca6f7b9529b35bdddd623a58c3af06a88c458dbd6531ddb4675acf75a9` |
| `url_launcher_web` | `2.4.3` | BSD-3-Clause | [来源](https://pub.dev/packages/url_launcher_web/versions/2.4.3/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `url_launcher_windows` | `3.1.5` | BSD-3-Clause | [来源](https://pub.dev/packages/url_launcher_windows/versions/3.1.5/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `uuid` | `4.5.3` | MIT | [来源](https://pub.dev/packages/uuid/versions/4.5.3/license) | `LICENSE`: `ad3e5523e51004e94ba9ce728805b1b4242dbccdb65e62b523800e35a8a7cfdc` |
| `vector_graphics` | `1.2.2` | BSD-3-Clause | [来源](https://pub.dev/packages/vector_graphics/versions/1.2.2/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `vector_graphics_codec` | `1.1.13` | BSD-3-Clause | [来源](https://pub.dev/packages/vector_graphics_codec/versions/1.1.13/license) | `LICENSE`: `89519eca6f7b9529b35bdddd623a58c3af06a88c458dbd6531ddb4675acf75a9` |
| `vector_graphics_compiler` | `1.2.6` | BSD-3-Clause | [来源](https://pub.dev/packages/vector_graphics_compiler/versions/1.2.6/license) | `LICENSE`: `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` |
| `vector_math` | `2.2.0` | BSD-3-Clause, Zlib | [来源](https://pub.dev/packages/vector_math/versions/2.2.0/license) | `LICENSE`: `b5d856a1e27e9ebea4957fc3526f1c65782a04894b113c6b3b0fb1321dbdec55` |
| `vm_service` | `15.2.0` | BSD-3-Clause | [来源](https://pub.dev/packages/vm_service/versions/15.2.0/license) | `LICENSE`: `ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888` |
| `watcher` | `1.2.1` | BSD-3-Clause | [来源](https://pub.dev/packages/watcher/versions/1.2.1/license) | `LICENSE`: `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` |
| `web` | `1.1.1` | BSD-3-Clause | [来源](https://pub.dev/packages/web/versions/1.1.1/license) | `LICENSE`: `aa913ff50d7542eb8cc35b9f48a80928ac6819ba9057f85d424655e3e8dc271c` |
| `web_socket` | `1.0.1` | BSD-3-Clause | [来源](https://pub.dev/packages/web_socket/versions/1.0.1/license) | `LICENSE`: `cbe822ef3446af4366b2b82c48b0979d0b12865edfe74c22b9aa617fc362d6e0` |
| `web_socket_channel` | `3.0.3` | BSD-3-Clause | [来源](https://pub.dev/packages/web_socket_channel/versions/3.0.3/license) | `LICENSE`: `a4b5d7d31626e90b77e8696f1c47643aa31f52e17c1907c1ab60b068110e6e10` |
| `webdriver` | `3.1.0` | Apache-2.0 | [来源](https://pub.dev/packages/webdriver/versions/3.1.0/license) | `LICENSE`: `74cb46b123c9fa918ea8e0a0f5be736a1cd661edf145ccc723dc7ce30324ebab` |
| `webkit_inspection_protocol` | `1.2.1` | BSD-3-Clause | [来源](https://pub.dev/packages/webkit_inspection_protocol/versions/1.2.1/license) | `LICENSE`: `eb9a6b9672316612439514f10b5d3b24bcd140313c96a73c370bb7b07897a8cd` |
| `win32` | `5.15.0` | BSD-3-Clause | [来源](https://pub.dev/packages/win32/versions/5.15.0/license) | `LICENSE`: `87ef8bccdd619f2345ba5b9026cf1d6cccb305e36ab83849a8a3af9293abde7e` |
| `win32_registry` | `2.1.0` | BSD-3-Clause | [来源](https://pub.dev/packages/win32_registry/versions/2.1.0/license) | `LICENSE`: `8564d1c5caab56132f0e6bc39cea532c723956e8c389d9be867388ee0b2fcb06` |
| `xdg_directories` | `1.1.0` | BSD-3-Clause | [来源](https://pub.dev/packages/xdg_directories/versions/1.1.0/license) | `LICENSE`: `89519eca6f7b9529b35bdddd623a58c3af06a88c458dbd6531ddb4675acf75a9` |
| `xml` | `7.0.1` | MIT | [来源](https://pub.dev/packages/xml/versions/7.0.1/license) | `LICENSE`: `0be767174b97278f17da4923a74169e8645631f03ea3d8482ec3523c9b1a0dd3` |
| `yaml` | `3.1.3` | MIT | [来源](https://pub.dev/packages/yaml/versions/3.1.3/license) | `LICENSE`: `d47b93335401b052d79a2f5a3710e4cf7b5aed782faedf84d40fbdd6eb934ec7` |

## Go 声明依赖与本地替换

| 组件 | 锁定版本 | 原始许可识别 | 核对来源 | 许可文本 SHA-256 |
| --- | --- | --- | --- | --- |
| `github.com/andybalholm/brotli`（Linux 服务） | `v1.2.0` | MIT | [来源](https://pkg.go.dev/github.com/andybalholm/brotli@v1.2.0?tab=licenses) | `LICENSE`: `3d180008e36922a4e8daec11c34c7af264fed5962d07924aea928c38e8663c94` |
| `github.com/cespare/xxhash/v2`（Linux 服务） | `v2.3.0` | MIT | [来源](https://pkg.go.dev/github.com/cespare/xxhash/v2@v2.3.0?tab=licenses) | `LICENSE.txt`: `f566a9f97bacdaf00d9f21dd991e81dc11201c4e016c86b470799429a1c9a79c` |
| `github.com/dustin/go-humanize`（Linux 服务） | `v1.0.1` | MIT | [来源](https://pkg.go.dev/github.com/dustin/go-humanize@v1.0.1?tab=licenses) | `LICENSE`: `a973b4498c13eb74baa2a8e5c351426a6826f2fcdd909916dbe53ee2e755fd71` |
| `github.com/google/uuid`（Linux 服务） | `v1.6.0` | BSD-3-Clause | [来源](https://pkg.go.dev/github.com/google/uuid@v1.6.0?tab=licenses) | `LICENSE`: `0a8d61ed3cbfd5312326e8126c31ce9c627a283adc99131b56896d29ada04b2d` |
| `github.com/gookit/color`（Linux 服务） | `v1.5.4` | MIT | [来源](https://pkg.go.dev/github.com/gookit/color@v1.5.4?tab=licenses) | `LICENSE`: `42c8d055a76a6a91e8f7102a106cd5929592d193aab7d43cdd816a93b24fa218` |
| `github.com/gorilla/websocket`（Linux 服务） | `v1.5.3` | BSD | [来源](https://pkg.go.dev/github.com/gorilla/websocket@v1.5.3?tab=licenses) | `LICENSE`: `2be1b548b0387ca8948e1bb9434e709126904d15f622cc2d0d8e7f186e4d122d` |
| `github.com/jackc/pgpassfile`（Linux 服务） | `v1.0.0` | MIT | [来源](https://pkg.go.dev/github.com/jackc/pgpassfile@v1.0.0?tab=licenses) | `LICENSE`: `adb1663fda031df8f4344aa68f299fd87d80353e31339406742ded21dae65702` |
| `github.com/jackc/pgservicefile`（Linux 服务） | `v0.0.0-20221227161230-091c0ba34f0a` | MIT | [来源](https://pkg.go.dev/github.com/jackc/pgservicefile@v0.0.0-20221227161230-091c0ba34f0a?tab=licenses) | `LICENSE`: `fc505773403fe869ed64cc2235cdd13988a427bb7e3a7e7004a3f4b27420f8fc` |
| `github.com/jackc/pgx/v5`（Linux 服务） | `v5.4.3` | MIT | [来源](https://pkg.go.dev/github.com/jackc/pgx/v5@v5.4.3?tab=licenses) | `LICENSE`: `467f95e074fe23079a5623ed652619682692041b8551da27e3c2ddb9659a1507` |
| `github.com/jackc/puddle/v2`（Linux 服务） | `v2.2.1` | MIT | [来源](https://pkg.go.dev/github.com/jackc/puddle/v2@v2.2.1?tab=licenses) | `LICENSE`: `2d50e98a4900b4d6457a38d39c1432fdc156fc2f7b365f2e33ec9344acbb0057` |
| `github.com/joho/godotenv`（Linux 服务） | `v1.5.1` | MIT | [来源](https://pkg.go.dev/github.com/joho/godotenv@v1.5.1?tab=licenses) | `LICENCE`: `4334bf49b7e1a6736ce1b21814d5cce392000204d059ee6a845eeb966e7a1e31` |
| `github.com/klauspost/compress`（Linux 服务） | `v1.18.6` | Apache-2.0, MIT, BSD-3-Clause | [来源](https://pkg.go.dev/github.com/klauspost/compress@v1.18.6?tab=licenses) | `LICENSE`: `0d9e582ee4bff57bf1189c9e514e6da7ce277f9cd3bc2d488b22fbb39a6d87cf` |
| `github.com/klauspost/cpuid/v2`（Linux 服务） | `v2.2.11` | MIT | [来源](https://pkg.go.dev/github.com/klauspost/cpuid/v2@v2.2.11?tab=licenses) | `LICENSE`: `5d966570d7a442d4e969892860a914e542c97f262c873baee8f0aa48e1f40212` |
| `github.com/klauspost/crc32`（Linux 服务） | `v1.3.0` | BSD-3-Clause | [来源](https://pkg.go.dev/github.com/klauspost/crc32@v1.3.0?tab=licenses) | `LICENSE`: `dd26a7abddd02e2d0aba97805b31f248ef7835d9e10da289b22e3b8ab78b324d` |
| `github.com/kr/text` | `v0.2.0` | MIT | [来源](https://github.com/kr/text/tree/v0.2.0) | `License`: `283c28b781bc7487bd7bcaf453cbd811f5ee8d7ce625cfcf8dcacae6ba1f4bb5` |
| `github.com/minio/crc64nvme`（Linux 服务） | `v1.1.1` | Apache-2.0 | [来源](https://pkg.go.dev/github.com/minio/crc64nvme@v1.1.1?tab=licenses) | `LICENSE`: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `github.com/minio/md5-simd`（Linux 服务） | `v1.1.2` | Apache-2.0, BSD-3-Clause | [来源](https://pkg.go.dev/github.com/minio/md5-simd@v1.1.2?tab=licenses) | `LICENSE`: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`<br>`LICENSE.Golang`: `2d36597f7117c38b006835ae7f537487207d8ec407aa9d9980794b2030cbc067` |
| `github.com/minio/minio-go/v7`（Linux 服务） | `v7.2.1` | Apache-2.0 | [来源](https://pkg.go.dev/github.com/minio/minio-go/v7@v7.2.1?tab=licenses) | `LICENSE`: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`<br>`NOTICE`: `570af5b6ac7fc91a78459073098200036e63d60a98ec92db5ed97d22d714d09e` |
| `github.com/philhofer/fwd`（Linux 服务） | `v1.2.0` | MIT | [来源](https://pkg.go.dev/github.com/philhofer/fwd@v1.2.0?tab=licenses) | `LICENSE.md`: `430da36bd967b28fc662f05e9245306da10941e93911052114a20ef10e4410f8` |
| `github.com/quic-go/qpack`（Linux 服务） | `v0.5.1` | MIT | [来源](https://pkg.go.dev/github.com/quic-go/qpack@v0.5.1?tab=licenses) | `LICENSE.md`: `1b6a897efd39b20b3cdce8cd306160d115dbded39d855ceeffe21dc11e4d53df` |
| `github.com/quic-go/quic-go`（Linux 服务） | `v0.53.0` | MIT | [来源](https://pkg.go.dev/github.com/quic-go/quic-go@v0.53.0?tab=licenses) | `LICENSE`: `77d0b7b53e8abb84cf4dd3f9945a7fdf27044240d2e8023966a721a9a46fe96e` |
| `github.com/rs/xid`（Linux 服务） | `v1.6.0` | MIT | [来源](https://pkg.go.dev/github.com/rs/xid@v1.6.0?tab=licenses) | `LICENSE`: `c480873f0ff2b7e2c539bdd84fb4da4178d8d02479c94924f7bffeafb7add358` |
| `github.com/tinylib/msgp`（Linux 服务） | `v1.6.1` | MIT | [来源](https://pkg.go.dev/github.com/tinylib/msgp@v1.6.1?tab=licenses) | `LICENSE`: `17df22e31ef6a84f70909eed5185f41443a03dd05b14e8dec319d5c2bd7d7b3b` |
| `github.com/vmihailenco/msgpack/v5`（Linux 服务） | `v5.4.1` | BSD | [来源](https://pkg.go.dev/github.com/vmihailenco/msgpack/v5@v5.4.1?tab=licenses) | `LICENSE`: `1530185dd39cdde7cb2f786a7a5fcf8bc34368b6ae73c15e72bafe88fd80b9a2` |
| `github.com/vmihailenco/tagparser/v2`（Linux 服务） | `v2.0.0` | BSD | [来源](https://pkg.go.dev/github.com/vmihailenco/tagparser/v2@v2.0.0?tab=licenses) | `LICENSE`: `0f02aac22084ef463aa5f42f566feeec6aa4c99653519744a8c25cb079da5b5d` |
| `github.com/wneessen/go-mail`（Linux 服务） | `v0.8.0` | MIT | [来源](https://pkg.go.dev/github.com/wneessen/go-mail@v0.8.0?tab=licenses) | `LICENSE`: `2927707b5b4e9d569831dfcb81b43a53da5a2d57fc6564e3f43b4580ae05a692` |
| `github.com/xo/terminfo`（Linux 服务） | `v0.0.0-20220910002029-abceb7e1c41e` | MIT | [来源](https://pkg.go.dev/github.com/xo/terminfo@v0.0.0-20220910002029-abceb7e1c41e?tab=licenses) | `LICENSE`: `1f5f51151ba96f0492ce288bd007242f924fdad9f04002e175e951644340a891` |
| `github.com/zeebo/xxh3`（Linux 服务） | `v1.1.0` | BSD | [来源](https://pkg.go.dev/github.com/zeebo/xxh3@v1.1.0?tab=licenses) | `LICENSE`: `f19854b341534d1f2314c0c70d9cd2bb4fa1f7c86fffdc4444ca33cccce412ba` |
| `github.com/zishang520/engine.io-go-parser`（Linux 服务） | `v1.3.2` | MIT | [来源](https://pkg.go.dev/github.com/zishang520/engine.io-go-parser@v1.3.2?tab=licenses) | `LICENSE`: `f3e3dd47d9ec226220819c0208cf4f2db4261bf42f16ba2a22ddbf783b016ebb` |
| `github.com/zishang520/engine.io/v2`（Linux 服务） | `v2.5.0` | MIT | [来源](../../../FlowMuse-Server/third_party/engine.io) | `LICENSE`: `c78c60e13d23bad5d44711f02e82babcf48a74b7ebc38f3144762e35b7a751e1` |
| `github.com/zishang520/socket.io-go-parser/v2`（Linux 服务） | `v2.5.0` | MIT | [来源](https://pkg.go.dev/github.com/zishang520/socket.io-go-parser/v2@v2.5.0?tab=licenses) | `LICENSE`: `f3e3dd47d9ec226220819c0208cf4f2db4261bf42f16ba2a22ddbf783b016ebb` |
| `github.com/zishang520/socket.io/v2`（Linux 服务） | `v2.5.0` | MIT | [来源](https://pkg.go.dev/github.com/zishang520/socket.io/v2@v2.5.0?tab=licenses) | `LICENSE`: `f3e3dd47d9ec226220819c0208cf4f2db4261bf42f16ba2a22ddbf783b016ebb` |
| `github.com/zishang520/webtransport-go`（Linux 服务） | `v0.9.1` | MIT | [来源](https://pkg.go.dev/github.com/zishang520/webtransport-go@v0.9.1?tab=licenses) | `LICENSE`: `83fcbe9e2a58019f63c1eb3dbccd74ec735bf69a750822bf4a0a17a1d174672c` |
| `go.uber.org/mock` | `v0.5.0` | Apache-2.0 | [来源](https://github.com/uber/mock/tree/a9c44d91ce00ef09603d3822452a4f9c8fefd278) | `LICENSE`: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `go.yaml.in/yaml/v3`（Linux 服务） | `v3.0.4` | Apache-2.0, MIT | [来源](https://pkg.go.dev/go.yaml.in/yaml/v3@v3.0.4?tab=licenses) | `LICENSE`: `d18f6323b71b0b768bb5e9616e36da390fbd39369a81807cca352de4e4e6aa0b`<br>`NOTICE`: `f6c2dd3a67b576eafb89b80200b8b1627230bf3821a0c14cb99a22ac19107d00` |
| `golang.org/x/crypto`（Linux 服务） | `v0.53.0` | BSD-3-Clause | [来源](https://pkg.go.dev/golang.org/x/crypto@v0.53.0?tab=licenses) | `LICENSE`: `911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad` |
| `golang.org/x/mod` | `v0.36.0` | BSD-3-Clause | [来源](https://github.com/golang/mod/tree/643da9ba74f1165d8cae1505d453b3de3cf21b7b) | `LICENSE`: `911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad` |
| `golang.org/x/net`（Linux 服务） | `v0.55.0` | BSD-3-Clause | [来源](https://pkg.go.dev/golang.org/x/net@v0.55.0?tab=licenses) | `LICENSE`: `911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad` |
| `golang.org/x/sync`（Linux 服务） | `v0.21.0` | BSD-3-Clause | [来源](https://pkg.go.dev/golang.org/x/sync@v0.21.0?tab=licenses) | `LICENSE`: `911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad` |
| `golang.org/x/sys`（Linux 服务） | `v0.46.0` | BSD-3-Clause | [来源](https://pkg.go.dev/golang.org/x/sys@v0.46.0?tab=licenses) | `LICENSE`: `911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad` |
| `golang.org/x/text`（Linux 服务） | `v0.38.0` | BSD-3-Clause | [来源](https://pkg.go.dev/golang.org/x/text@v0.38.0?tab=licenses) | `LICENSE`: `911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad` |
| `golang.org/x/tools` | `v0.45.0` | BSD-3-Clause | [来源](https://github.com/golang/tools/tree/2aabba0e4be44cc8f254ced118a7156d04bbc9f3) | `LICENSE`: `911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad` |
| `gopkg.in/ini.v1`（Linux 服务） | `v1.67.2` | Apache-2.0 | [来源](https://pkg.go.dev/gopkg.in/ini.v1@v1.67.2?tab=licenses) | `LICENSE`: `f6918bd93ffe07f4b2c61b8287c32cb3122e08aed0be50f1c7d0eddc87877a8f` |

## 发行通知与维护

项目原创部分采用根 `LICENSE` 中的官方 PolyForm Noncommercial 1.0.0 原文；App/Server 的 `NOTICES` 分开携带该正文、项目通知与普通工具使用补充许可，并区分上游文本。Flutter 的原始依赖/SDK 通知继续由标准工具链收集，不被此文件替代。Go 标准库许可单独保留；此次核对使用本机 Go 1.25.6 的 BSD 文本，正式发行还须核对实际构建工具链和交付物。

许可文本哈希只用于核对所读取文本，不是整包文件或二进制来源的校验，也不是作者身份或授权能力证明。SDK 合并通知的各子组件仍依其各自许可，不能把项目非商业许可的限制套给它们。
