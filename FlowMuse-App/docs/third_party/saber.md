# Saber 迁移说明

FlowMuse 白板手写笔迹几何、笔形参数、高亮叠加、shapePen 识别、激光笔视觉和 Saber-first ink 主模型参考并移植自 Saber。

- 项目：Saber
- 仓库：https://github.com/saber-notes/saber
- 本地参考提交：4af5d81a perf: limit isolate worker count to 2
- 许可证：GNU General Public License v3.0
- 迁移范围：`packages/sbn/lib/tool_id.dart`、`lib/components/canvas/_stroke.dart`、`lib/components/canvas/_circle_stroke.dart`、`lib/components/canvas/_rectangle_stroke.dart`、`lib/components/canvas/_canvas_painter.dart`、`lib/data/tools/pen.dart`、`lib/data/tools/pencil.dart`、`lib/data/tools/highlighter.dart`、`lib/data/tools/eraser.dart`、`lib/data/tools/shape_pen.dart`、`lib/data/tools/select.dart`、`lib/data/tools/laser_pointer.dart`

FlowMuse 的手写主模型迁移为 Saber stroke 体系；Excalidraw JSON 保留为导入导出兼容层。未迁移 Saber 的 `.sbn/.sbn2` 文档格式、文件系统同步、Nextcloud、Quill 或整页编辑器外壳。
