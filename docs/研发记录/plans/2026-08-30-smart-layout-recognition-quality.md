# 智能排版第七轮：识别质量治理（真机走查：标题丢失与转写误读）

日期：2026-08-30　分支：`feature/smart-layout-som-echo-fix`
来源：用户真机截图——"图1"被拆成"冬"+"1"两块、"睡着的懒羊羊"误读为"开着的"（竖排）、
标题 0 处（"薛之谦与懒羊羊"掉进底部正文行）、3 处红区碎片，底部一行挤 6 段小字。

## Context

复盘：版式引擎按设计执行（图注归图、孤行居中、贪心装行），烂在**识别输入**——
VLM 把短语拆项、形近字误读、漏标标题、竖排误读。垃圾进垃圾出，版式必然乱。

## 需求

1. 服务端 VLM 提示词治理：短语拆框必须合并成一项；title 按位置指引（顶部独立短句）；
   "图N"式短标明确为 caption 并配对；竖排按从上到下逐字读；逐字忠实不缺漏。
2. 客户端标题兜底：VLM 未给 title 时，把最上方短散文本（去空白 ≤12 字，页面有结构）
   提升为标题——层级不因漏标而崩。
3. 确认条文案：存在红区时不再显示"全部内容识别把握良好"（与红区提示自相矛盾）。

## 实现方案

- `FlowMuse-Server/internal/recognition/vision_layout.go`：两个 prompt 常量增补
  （工作方式合并规则、title/caption/vertical 定义细化、转写补全要求）；既有断言
  （"严禁出现在"/"严禁转写进结果"）不动，新增关键短语断言。
- `markdraw_controller.dart` 装配区：looseTexts 就绪后、content 构造前做标题兜底
  （`titleUnit == null` 时取 `looseTexts.first`，去空白 ≤12 字且
  `pairs.length + looseTexts.length ≥ 3` 才提升）。
- `smart_layout_dialogs.dart`：低置信为 0 且有红区时隐藏"全部良好"行。
- 测试：控制器标题兜底正反例；确认条红区态；服务端 prompt 关键短语。

## 验证方案

- 服务端：`go test ./internal/recognition/` + `go vet ./...`。
- 客户端：`flutter analyze` 无新增 error；白板目录 + 全量 `flutter test`。
- **服务端提示词改动需要重新部署后端才生效**（提交/MR 如实记录）。
- 文档同步：`docs/项目说明/项目需求.md` 追加第七轮条目。
