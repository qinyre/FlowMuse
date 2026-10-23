# 鸿蒙 App 内原生扫码入房

## Context

Android/Web 已实现二维码分享与扫码入房。本轮为鸿蒙补齐 App 内扫码，复用已有邀请格式、解析器和加入流程。

## 需求

- 打开 FlowMuse 的“加入房间→扫码加入房间”，调用鸿蒙 Scan Kit 默认扫码界面。
- 支持取消、权限拒绝、能力不可用、无效二维码和超长内容；失败时保留粘贴入口。
- 只解析房间数据，不打开扫码获得的任意 URL，不输出扫码原文或密钥。
- 用户已明确只要求 App 内原生扫码；系统相机唤起、App Linking、域名关联与外部 Want 不在本轮范围，相关实现和配置全部移除。

## 实现方案

1. 在 `app/adapters/room_qr_scanner_platform.dart` 收敛平台选择。Android/Web 保持既有扫码实现，鸿蒙调用原生通道。
2. `flow_muse/room_qr_scanner.scan` 调用 `scanBarcode.startScanForResult`，仅识别二维码，可从相册识别。返回原始字符串或取消时的 null，固定错误码处理失败。
3. Dart 使用 `CollaborationRoom.parse` 校验后交给既有 `JoinRoomDialog`；不修改白板页面生命周期、路由、协作协议或数据库。
4. 更新通道索引、需求、接口和验收记录。

## 关键文件

- `FlowMuse-App/lib/app/adapters/room_qr_scanner_platform.dart`。
- `collaboration/services/room_qr_scanner_io.dart`、`room_qr_scanner_channel_ohos.dart`。
- `ohos/entry/src/main/ets/channels/RoomQrScannerChannel.ets`、`EntryAbility.ets`。
- `ohos/entry/src/main/module.json5` 和相机权限用途文案。

## 验证方案

先跑扫码通道和加入弹窗测试，再跑全量 `flutter test --no-pub`、`flutter analyze --no-pub` 与 `flutter build hap --debug --no-pub`。检查最终 HAP 仅增加扫码通道和相机权限，不包含本轮 App Linking 声明。真机扫码、相机授权及后台恢复需连接设备后验证。

## API 依据

[Scan Kit 默认界面扫码](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V14/scan-scanbarcode-V14)，并核对本机 SDK 的 `@hms.core.scan.scanBarcode.d.ts` / `scanCore.d.ts`：`QR_CODE`、`originalValue`、取消码 1000500002。

## 实施结果

已收敛为 App 内原生扫码，移除系统相机唤起相关代码和配置。23 项相关测试、全量 1864 项测试（5 项既有跳过）、静态检查及鸿蒙调试 HAP 构建均通过。最终 HAP 无 App Linking skill；已覆盖安装到 SLG-W50 鸿蒙平板并启动，用户确认真机测试成功。详见 [验收记录](../research/2026-10-23-harmony-qr-validation.md)。
