# 笔记/笔记本/标签下拉菜单功能实现计划

## Context

用户需要为笔记、笔记本、标签添加下拉菜单功能，以便在不进入编辑模式的情况下快速执行常用操作。这将提升应用的交互效率，让用户能够更方便地管理笔记和集合。

## 需求总结

### 笔记下拉菜单
- **重命名**：弹出重命名输入框
- **移动至**：选择笔记本（带"未归入笔记本"选项 + 笔记本列表 + "新建笔记本"按钮，有取消/完成按钮）
- **选择标签**：多选标签（顶部"未标签"选项，选择后不能选其他标签）
- **删除**：移到回收站

### 笔记本/标签下拉菜单
- **编辑**：跳转到编辑页面（复用新建页面，修改文字）
- **删除**：把里面的笔记放回"未归入笔记本"/"未标签"，然后删除

## 实现方案

### 1. 创建笔记下拉菜单组件

**文件**: `lib/features/library/widgets/note_actions.dart` (新建)

```dart
// 笔记操作菜单组件
class NoteActionsMenu extends StatelessWidget {
  // 菜单项：重命名、移动至、选择标签、删除
}

// 移动至对话框
class MoveToNotebookDialog extends StatefulWidget {
  // 显示笔记本列表 + 新建笔记本按钮
  // 顶部：未归入笔记本选项（单选）
  // 底部：取消、完成按钮
}

// 选择标签对话框
class SelectTagsDialog extends StatefulWidget {
  // 顶部：未标签选项（选择后不能选其他标签）
  // 下面：多选标签列表（不包括"未标签"）
  // 底部：取消、完成按钮
}
```

**交互说明**：
- **移动至**：单选模式，顶部"未归入笔记本"与其他笔记本分隔
- **选择标签**：多选模式，顶部"未标签"选项（选择后清空其他选择，不能再选其他标签）

### 2. 修改 NoteCard 组件

**文件**: `lib/features/library/widgets/note_card.dart`

- 添加 `onActionsTap` 回调参数
- 点击下拉箭头时触发菜单

### 3. 修改 LibraryContent 集成笔记菜单

**文件**: `lib/features/library/widgets/library_content.dart`

- 在 `_LibraryItemsContent` 中传递 `onActionsTap` 回调
- 实现笔记的重命名、移动、标签、删除逻辑

### 4. 创建编辑页面组件

**文件**: `lib/features/library/widgets/edit_collection_page.dart` (新建)

- 复用 `CreateCollectionPage` 的布局
- 修改标题文字（"新建笔记本" → "编辑笔记本"）
- 修改按钮文字（"创建" → "保存"）
- 支持传入现有的名称、颜色、封面

### 5. 添加编辑页面路由

**文件**: `lib/app/app_router.dart`

```dart
static const editCollection = '/edit-collection';

GoRoute(
  path: AppRoutes.editCollection,
  pageBuilder: (context, state) {
    final params = state.extra as EditCollectionParams;
    return _modalPage(state, EditCollectionPage(params: params));
  },
),
```

### 6. 修改笔记本/标签下拉菜单

**文件**: `lib/features/notebooks/views/notebooks_page.dart`
**文件**: `lib/features/tags/views/tags_page.dart`

- 在 `_CollectionActions` 中添加"编辑"选项
- 点击编辑时跳转到编辑页面
- 删除时将笔记移回"未归入笔记本"/"未标签"

### 7. 更新 View Model

**文件**: `lib/features/notebooks/view_models/notebooks_view_model.dart`
**文件**: `lib/features/tags/view_models/tags_view_model.dart`

- 添加 `editNotebook` / `editTag` 方法
- 修改 `deleteNotebook` / `deleteTag` 方法，删除前将笔记移回默认分类

## 关键文件

| 文件 | 操作 |
|------|------|
| `lib/features/library/widgets/note_actions.dart` | 新建 - 笔记操作菜单 |
| `lib/features/library/widgets/note_card.dart` | 修改 - 添加 onActionsTap |
| `lib/features/library/widgets/library_content.dart` | 修改 - 集成笔记菜单 |
| `lib/features/library/widgets/edit_collection_page.dart` | 新建 - 编辑页面 |
| `lib/app/app_router.dart` | 修改 - 添加编辑路由 |
| `lib/features/notebooks/views/notebooks_page.dart` | 修改 - 添加编辑选项 |
| `lib/features/tags/views/tags_page.dart` | 修改 - 添加编辑选项 |
| `lib/features/notebooks/view_models/notebooks_view_model.dart` | 修改 - 添加编辑方法 |
| `lib/features/tags/view_models/tags_view_model.dart` | 修改 - 添加编辑方法 |
| `lib/features/library/repositories/library_repository.dart` | 修改 - 添加移动笔记到默认分类方法 |

## 验证方案

1. **笔记下拉菜单测试**
   - 点击笔记卡片的下拉箭头，验证菜单弹出
   - 测试重命名功能：输入新名称后保存
   - 测试移动功能：选择笔记本后点击完成
   - 测试标签功能：多选标签后点击完成
   - 测试删除功能：验证笔记移到回收站

2. **笔记本下拉菜单测试**
   - 点击笔记本卡片的下拉箭头，验证菜单包含编辑和删除
   - 测试编辑功能：跳转到编辑页面，修改后保存
   - 测试删除功能：验证笔记被移回"未归入笔记本"

3. **标签下拉菜单测试**
   - 点击标签卡片的下拉箭头，验证菜单包含编辑和删除
   - 测试编辑功能：跳转到编辑页面，修改后保存
   - 测试删除功能：验证笔记被移回"未标签"

## 实施步骤

1. 创建 `NoteActionsMenu` 组件
2. 修改 `NoteCard` 添加回调
3. 在 `LibraryContent` 中集成菜单逻辑
4. 创建 `EditCollectionPage` 组件
5. 添加编辑页面路由
6. 修改笔记本/标签页面的下拉菜单
7. 更新 View Model 方法
8. 测试所有功能
