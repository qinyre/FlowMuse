# 鸿蒙输入框重复唤起软键盘修复计划

## Context

- 从最新 `origin/main` 创建 `feature/ohos-keyboard-focus-recovery`。
- 鸿蒙平板上，系统收回键盘后 Flutter 输入框仍可能持有焦点；再次点击时旧输入连接未重新建立。
- 新建笔记标题、AI 助手输入框已有“失焦 → 50ms 后重聚焦”的局部处理。已删除分支的 `d2ed56be` 曾验证普通 `TextField` 的同类处理，但尚未并入主分支，且未覆盖白板底层 `EditableText`。

## 需求

1. 鸿蒙端所有文字输入入口在收回键盘后可再次点击唤起，包括登录、重命名、搜索、对话和白板编辑。
2. 不因焦点重建提交或丢失正在编辑的白板文字、画框标签；切换输入框、拖动、长按与点击空白处维持原行为。
3. Android、iOS、桌面和 Web 不改变输入行为；不改白板数据格式或协作协议。

## 实现方案

- 在应用层鸿蒙适配入口安装一次焦点恢复监听。普通点击命中当前已聚焦 `EditableText` 时，待字段自身的点击回调结束后重新确认焦点，再失焦并延迟 50ms 重聚焦，重建输入连接。已有局部处理的字段自行先失焦，全局监听不重复处理。
- 监听仅处理点击，不处理拖动、长按、其他控件或已切换焦点的字段；延迟恢复前再次交互时取消旧恢复，避免焦点被抢回。
- 白板内联文字与画框标签在这段短暂失焦期间暂停“失焦即提交”，恢复或取消后解除暂停。
- 复用 Flutter 焦点和指针 API，不新增依赖或原生通道。

## 关键文件

- `FlowMuse-App/lib/app/flow_muse_app.dart` 与应用层鸿蒙适配入口
- `FlowMuse-App/lib/shared/widgets/keyboard_focus_recovery.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/text_editing_overlay.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`
- `FlowMuse-App/test/shared/widgets/keyboard_focus_recovery_test.dart`

## 验证方案

1. Widget 测试模拟键盘隐藏后重复点击普通输入框、搜索框、底层 `EditableText`；验证焦点重新建立。
2. 验证拖动、长按、点击别处、快速切换字段不触发错误恢复，白板失焦提交在恢复过程中不执行。
3. 运行 `flutter analyze`、相关测试、全量 `flutter test` 和 `flutter build hap`。
4. 鸿蒙真机按“打开键盘 → 系统收回 → 再点同一字段”回归登录、搜索、笔记本/标签命名、白板文字与画框标签；构建和 Widget 测试不能代替真机验收。

## 实施步骤

- [x] 勘察主分支、工作区、已有局部修复、历史分支和全部输入入口。
- [x] 实现鸿蒙端统一焦点恢复和编辑器提交保护。
- [x] 补充测试并完成静态检查、全量测试与鸿蒙构建。
- [x] 记录真机验收范围和剩余限制。

## 验证记录

- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --reporter compact`：1779 个通过，6 个既有跳过。随后补充长按与光标保持断言，定向运行 `keyboard_focus_recovery_test.dart` 和 `editor_canvas_test.dart`，12 个通过；新增用例覆盖普通输入框、搜索框、底层 `EditableText`、拖动、长按、切换焦点、已有局部修复和两类白板编辑器。
- `flutter build hap --no-pub`：先因当前终端缺少 `java` 命令而失败；进程内设置 `JAVA_HOME` 指向本机 JDK 17 并补全 PATH 后构建成功，产出 `entry-default-signed.hap`。
- 鸿蒙真机尚未执行交互验收。需在平板上分别重复“点输入框 → 收回键盘 → 再点同一输入框”，重点覆盖登录、资料库重命名、搜索、聊天、白板文字与画框标签；检查光标位置和未提交内容保持不变。Widget 测试模拟的是焦点与输入连接生命周期，无法证明设备输入法行为。
