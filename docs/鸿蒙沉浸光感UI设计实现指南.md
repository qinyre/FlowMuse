# FlowMuse 鸿蒙 UI Design Kit 与沉浸光感设计实现指南

> **来源**：华为开发者文档《沉浸光感最佳实践》、`UI Design Kit 简介`、项目 `reference-docs/` 中的 HarmonyOS UI Design Kit 与 ArkUI 文档。  
> **适用对象**：FlowMuse 鸿蒙端 UI 原生化/专项优化设计参考。当前项目主体是 Flutter，多端代码在 `lib/`，鸿蒙工程在 `ohos/`；本文用于指导后续 ArkUI/HDS 组件落地、桥接或重构。  
> **关键版本**：UI Design Kit 5.1.0(18)+、6.0.0(20)+、6.1.0(23)+；ArkUI 沉浸光感 `ImmersiveMaterial` 从 API 26.0.0 开始。  
> **整理日期**：2026-07-07。

---

## 1. 设计目标

FlowMuse 是知识整理与白板创作工具，界面应优先保证阅读、检索、编辑效率。鸿蒙沉浸光感 UI 不是把所有区域做成半透明，而是把导航、页签、浮动工具栏、即时反馈和弹层这些“浮在内容之上”的区域做得更轻、更有空间层次。

落地目标：

| 目标 | 说明 | FlowMuse 对应位置 |
| --- | --- | --- |
| 内容优先 | 资料、笔记、白板画布保持清晰稳定，光感只服务于层级表达。 | 资料库列表、白板画布、搜索结果。 |
| 系统一致 | 优先使用 HDS 组件和系统 Symbol，少手写毛玻璃、阴影、按钮反馈。 | 底部页签、侧边栏、列表卡片、反馈栏。 |
| 自适应设备 | 手机用底部悬浮页签，平板/PC 用侧边栏和多窗入口。 | `AppShell`、`LibrarySidebar`、`WhiteboardPage`。 |
| 克制光效 | 点光、流光、按压阴影只用于主操作和当前焦点，不作为背景装饰泛滥。 | 新建笔记、选中白板工具、同步/导入状态。 |
| 可降级 | 模拟器、低算力设备、非中国大陆地区或 Flutter 容器内无法使用 HDS 时，有普通 ArkUI/Flutter 样式兜底。 | `ohos/` 原生页面或平台视图。 |

---

## 2. 组件选型总览

| FlowMuse 区域 | 推荐鸿蒙组件/能力 | 使用策略 |
| --- | --- | --- |
| 应用根导航 | `HdsNavigation` / `HdsNavDestination` | 作为 ArkUI 原生页面根容器，标题栏启用动态模糊、渐变模糊和沉浸材质。 |
| 手机一级导航 | `HdsTabs` + `barFloatingStyle` | 底部悬浮页签承载“资料库 / 搜索 / 文件夹 / 设置”。启用 `barOverlap(true)`。 |
| 手机迷你状态栏 | `HdsTabs` 的 `miniBar` | 用于白板会话、同步、录音笔记、导入任务等持续状态，不放普通说明文字。 |
| 平板/PC 主导航 | `HdsSideBar` + `HdsSideMenu` | 替代当前 Flutter 左侧栏形态，支持嵌入/覆盖两种模式和一级/二级菜单。 |
| 标题区搜索/筛选 | `HdsNavigation` 的 `stackBuilder` / `bottomBuilder` | 搜索框、分段筛选、排序入口放在标题栏扩展区，随滚动动态隐藏。 |
| 列表与卡片 | `HdsListItemCard` / `HdsListItem` | 笔记本、笔记、文件夹条目使用系统卡片样式；删除/归档用横滑操作。 |
| 白板工具栏 | `HdsActionBar` + `ImmersiveMaterial` | 多工具按钮用核心操作栏；浮动小工具用 `ULTRA_THIN` 沉浸材质。 |
| 轻量反馈 | `HdsSnackBar` | 保存成功、删除撤销、同步失败重试、导入完成等非模态反馈。 |
| 弹层/菜单/半模态 | ArkUI `systemMaterial` / `bindSheet` + `HdsNavigationTitleMode.MODAL` | 新建笔记、移动到文件夹、批量操作等使用厚一点的系统材质。 |
| 多窗口 | `MultiWindowEntryInAPP` | 在支持设备上提供“打开白板到新窗口 / 资料库与白板并行”。 |
| 图标 | 系统 `SymbolGlyph`、自定义 Symbol、分层图标处理 | 功能图标优先 Symbol；应用图标和品牌图形使用 HDS 图标处理。 |
| 视觉增强 | `hdsEffect` 点光、按压阴影、边缘流光、背景流光 | 只用于强调可操作对象、当前选中状态或短时任务状态。 |

---

## 3. 沉浸光感设计原则

### 3.1 使用边界

沉浸光感适合“浮在内容上”的组件：

- 顶部标题栏、返回按钮、菜单按钮。
- 底部悬浮页签、MiniBar、白板浮动工具栏。
- 半模态、弹窗、菜单、Toast、Popup。
- 当前选中工具、主操作按钮、需要触摸反馈的胶囊控件。

不建议用于：

- 长列表主体背景。
- 正文阅读区、笔记编辑器背景。
- 密集表单的每一行。
- 长时间循环的大面积背景流光。

### 3.2 材质层级建议

ArkUI `ImmersiveMaterial` 提供五种样式，FlowMuse 按以下规则选：

| 样式 | 官方语义 | FlowMuse 推荐场景 |
| --- | --- | --- |
| `ULTRA_THIN` | 超薄，高透明 | 白板浮动工具栏、底部悬浮页签、小型胶囊按钮。 |
| `THIN` | 薄，较透明 | 搜索框、筛选条、MiniBar 折叠态。 |
| `REGULAR` | 常规厚度 | 普通卡片外层、批量操作条、状态条。 |
| `THICK` | 强模糊 | 右键/更多菜单、选择器、悬浮面板。 |
| `ULTRA_THICK` | 很强模糊 | 弹窗、确认框、重要半模态。 |

HDS 组件级沉浸光感优先使用：

```typescript
systemMaterialEffect: {
  materialType: hdsMaterial.MaterialType.ADAPTIVE,
  materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
}
```

只有在品牌级视觉需要更强质感时，才手动选择 `IMMERSIVE + EXQUISITE/GENTLE`，且必须先调用 `getSystemMaterialTypes()` 判断设备能力。

### 3.3 颜色与品牌调性

当前 FlowMuse Flutter 主题使用浅色、低饱和绿色与 8vp 左右的圆角。鸿蒙原生化时建议延续：

- 主色：保留自然绿作为激活态、主要按钮和选中图标颜色。
- 背景：资料库/设置维持高可读浅背景，白板画布维持中性底色。
- 材质赋色：只给浮层轻微混合品牌色，避免把整页变成绿色玻璃。
- 圆角：普通卡片 8vp；悬浮页签/MiniBar/工具胶囊可使用更圆的胶囊形态。

---

## 4. 沉浸光感接入方式

### 4.1 ArkUI 应用级开启

若后续有 ArkUI 原生入口，并且 `targetAPIVersion >= 26.0.0`，可在 `ohos/entry/src/main/module.json5` 的 entry module 中开启：

```json5
{
  "module": {
    "name": "entry",
    "type": "entry",
    "metadata": [{
      "name": "ohos.arkui.UIMaterial.state",
      "value": "enable"
    }]
  }
}
```

配置值：

| 值 | 语义 | 建议 |
| --- | --- | --- |
| `default` | 跟随系统默认策略 | 保守上线可先用。 |
| `enable` | 应用内启用沉浸式系统材质 | 鸿蒙原生 UI 成熟后使用。 |
| `disable` | 应用内关闭 | 性能问题、兼容问题或灰度回退时使用。 |

### 4.2 ArkUI 组件级开启

通用浮层可直接使用 `systemMaterial`：

```typescript
import { uiMaterial } from '@kit.ArkUI';

@Builder
function FlowMuseFloatingTool(content: string) {
  Row() {
    Text(content)
  }
  .height(48)
  .padding({ left: 16, right: 16 })
  .borderRadius(24)
  .justifyContent(FlexAlign.Center)
  .systemMaterial(new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
    interactive: true,
    lightEffect: { color: undefined },
    colorInvert: true
  }))
}
```

使用规则：

- `systemMaterial` 尽量放在 `backgroundColor`、`border`、`shadow` 等样式属性之后，避免被后续样式覆盖。
- 不要同时大量叠加 `backdropBlur`、手写阴影、边框和 `systemMaterial`，除非明确需要覆盖系统材质。
- 需要关闭单个组件材质时使用 `uiMaterial.Material.empty`。
- `colorInvert` 依赖资源色自动反色，文本、图标颜色优先使用 `$r('sys.color...')` 或应用资源色，而不是写死纯色。

### 4.3 弹窗、Toast、Popup、Sheet、Menu

弹层类组件优先使用自身的 `systemMaterial` 参数，使它们与系统弹层风格一致：

```typescript
import { uiMaterial } from '@kit.ArkUI';

promptAction.showToast({
  message: '已保存',
  duration: 2000,
  systemMaterial: new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THICK,
    colorInvert: true
  })
});
```

FlowMuse 使用建议：

- 保存成功、复制链接：Toast 或 `HdsSnackBar`，不打断当前工作。
- 删除笔记：`HdsSnackBar` + 撤销，比确认弹窗更轻。
- 移动到文件夹、批量导出：半模态 Sheet，内部使用 `HdsNavigationTitleMode.MODAL`。
- 危险操作确认：Dialog 使用 `ULTRA_THICK`，按钮清晰，不依赖透明背景传达风险。

### 4.4 HDS 组件级沉浸材质

HDS 当前重点支持 `HdsNavigation/HdsNavDestination` 标题栏与 `HdsTabs` 底部悬浮页签的沉浸光感：

```typescript
import {
  HdsNavigation,
  HdsTabs,
  HdsTabsController,
  HdsNavigationTitleMode,
  ScrollEffectType,
  hdsMaterial
} from '@kit.UIDesignKit';

@Entry
@Component
struct FlowMuseHome {
  private tabsController: HdsTabsController = new HdsTabsController();
  private listScroller: Scroller = new Scroller();

  build() {
    HdsNavigation() {
      HdsTabs({ controller: this.tabsController }) {
        // TabContent: Library / Search / Folders / Settings
      }
      .barOverlap(true)
      .vertical(false)
      .barPosition(BarPosition.End)
      .barFloatingStyle({
        barBottomMargin: 28,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
    }
    .titleBar({
      content: {
        title: { mainTitle: 'FlowMuse' }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    })
    .bindToScrollable([this.listScroller])
    .titleMode(HdsNavigationTitleMode.MINI)
  }
}
```

自定义材质等级时要先查询能力：

```typescript
@State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.EXQUISITE;

aboutToAppear(): void {
  const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
  if (types.indexOf(hdsMaterial.MaterialType.IMMERSIVE) < 0) {
    this.materialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  }
}
```

---

## 5. HdsNavigation / HdsNavDestination

### 5.1 适用场景

`HdsNavigation` 适合作为鸿蒙原生页面根视图容器，`HdsNavDestination` 适合作为子页面根容器。FlowMuse 可用于：

- 资料库首页：标题、搜索、排序、更多菜单。
- 搜索页：标题栏下方放搜索框和筛选条件。
- 文件夹页：标题区显示当前文件夹、操作菜单和新建按钮。
- 白板页：标题栏可动态隐藏，把空间让给画布。
- 设置页：普通列表页，使用通用模糊即可。

### 5.2 动态模糊标题栏

动态模糊有三类：

| 类型 | 适用场景 | FlowMuse 建议 |
| --- | --- | --- |
| `COMMON_BLUR` | 非沉浸列表页，标题栏与内容明确分隔 | 设置页、普通文件夹列表。 |
| `TRANSITION_BLUR` | 沉浸图文页，滚动时标题内容/颜色变化 | 笔记详情封面页、导入预览页。 |
| `GRADIENT_BLUR` | 空间渐变模糊，强调沉浸感 | 资料库首页、白板页顶部、搜索结果页。 |

典型配置：

```typescript
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';

@Component
struct LibraryNavigationPage {
  private scroller: Scroller = new Scroller();

  build() {
    HdsNavigation() {
      List({ scroller: this.scroller }) {
        // HdsListItemCard / HdsListItem
      }
      .clip(false)
      .cachedCount(3, true)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .titleBar({
      enableComponentSafeArea: true,
      content: {
        title: { mainTitle: '全部笔记' }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(24)
        }
      }
    })
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
  }
}
```

注意：

- 需要把可滚动容器通过 `.bindToScrollable([scroller])` 绑定给导航。
- 内容想穿透到标题栏下方时，滚动容器要 `.clip(false)`。
- 列表穿透标题栏时配置 `.cachedCount(3, true)`，避免预加载不足导致穿透区域空白。

### 5.3 标题栏动态隐藏

白板、阅读页、搜索结果页可以在用户向上滚动时隐藏标题栏：

```typescript
.dynamicHideTitleBar({
  hideTitleArea: true,
  hideBottomBuilder: true,
  hideStatusBar: true,
  mode: HideMode.SCROLL_UP_TO,
  hideOffset: 80
})
.bindToScrollable([this.scroller])
```

FlowMuse 建议：

- 白板页：隐藏标题区与状态栏，但保留必要的返回/退出手势或浮动按钮。
- 搜索结果：向下查看结果时隐藏筛选条，回滑顶部再显示。
- 设置页：不建议隐藏，保持稳定路径感。

### 5.4 自定义标题区

标题栏支持 `stackBuilder` 和 `bottomBuilder`，用于放搜索框、分段控件、标签筛选或页内 Tabs：

```typescript
.titleBar({
  content: {
    title: { mainTitle: '资料库' },
    stackBuilder: () => this.titleActionsBuilder(),
    bottomBuilder: () => this.libraryFilterBuilder()
  }
})
```

使用规则：

- `stackBuilder` 放右侧动作：新建、排序、更多。
- `bottomBuilder` 放横向筛选：全部/最近/收藏/标签。
- 不要在标题栏里放复杂列表、动画大图或高频重绘组件。
- 标题区控件应有清晰焦点、hover、press 状态，PC/2in1 要可键盘访问。

### 5.5 半模态导航

半模态内使用导航时，设置 `HdsNavigationTitleMode.MODAL`：

```typescript
@Builder
function MoveToFolderSheet() {
  HdsNavigation() {
    // 文件夹选择列表
  }
  .titleMode(HdsNavigationTitleMode.MODAL)
  .titleBar({
    content: {
      title: { mainTitle: '移动到文件夹' },
      menu: {
        value: [{
          content: {
            label: '关闭',
            icon: $r('sys.symbol.xmark')
          }
        }]
      }
    }
  })
}

.bindSheet($$this.showMoveSheet, this.MoveToFolderSheet(), {
  showClose: false
})
```

建议使用 HDS Navigation 的菜单关闭按钮，避免系统 Sheet 关闭按钮与标题栏关闭按钮重复。

---

## 6. HdsTabs 底部页签、悬浮导航与 MiniBar

### 6.1 基础底部页签

手机端一级导航建议使用 `HdsTabs`，承载：

- 资料库。
- 搜索。
- 文件夹。
- 设置。

推荐结构：

```typescript
import { HdsTabs, HdsTabsController } from '@kit.UIDesignKit';

@Component
struct FlowMuseTabs {
  private controller: HdsTabsController = new HdsTabsController();

  build() {
    HdsTabs({ controller: this.controller }) {
      TabContent() {
        LibraryPage()
      }
      .tabBar(new BottomTabBarStyle($r('sys.symbol.doc_text'), '资料库'))

      TabContent() {
        SearchPage()
      }
      .tabBar(new BottomTabBarStyle($r('sys.symbol.magnifyingglass'), '搜索'))

      TabContent() {
        FoldersPage()
      }
      .tabBar(new BottomTabBarStyle($r('sys.symbol.folder'), '文件夹'))

      TabContent() {
        SettingsPage()
      }
      .tabBar(new BottomTabBarStyle($r('sys.symbol.gearshape'), '设置'))
    }
    .barPosition(BarPosition.End)
    .vertical(false)
    .barOverlap(true)
  }
}
```

### 6.2 悬浮页签栏

UI Design Kit 6.1.0(23)+ 支持 `barFloatingStyle`：

```typescript
.barFloatingStyle({
  barWidth: {
    smallWidth: 220,
    mediumWidth: 320,
    largeWidth: 420
  },
  barBottomMargin: 28,
  gradientMask: {
    maskColor: '#66F1F3F5',
    maskHeight: 92
  },
  systemMaterialEffect: {
    materialType: hdsMaterial.MaterialType.ADAPTIVE,
    materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
  }
})
```

约束：

- 必须 `.barPosition(BarPosition.End)`。
- 必须 `.vertical(false)`。
- 必须 `.barOverlap(true)`，让 TabBar 浮在内容上。
- 当前悬浮样式支持 `BottomTabBarStyle` 和 `CustomBuilder`。

FlowMuse 设计建议：

- 底部页签宽度不要铺满屏，使用 `smallWidth/mediumWidth/largeWidth` 做自适应胶囊。
- 页签下方保留 `28vp` 左右底部距离，避开手势区域。
- 列表底部增加内容 padding，防止最后一条笔记被悬浮页签遮挡。
- 对资料库/搜索这种列表页，底部渐变遮罩可以减轻页签遮挡感。

### 6.3 MiniBar 沉浸式迷你栏

MiniBar 是 `barFloatingStyle` 中的自定义区域，与页签栏等高且水平对齐，支持折叠和展开样式。它适合承载“正在进行”的轻量任务，而不是普通导航项。

FlowMuse 推荐用途：

| 状态 | MiniBar 内容 | 点击行为 |
| --- | --- | --- |
| 白板会话未关闭 | 白板缩略图/名称/继续按钮 | 回到白板。 |
| 正在同步 | 同步图标/进度/错误状态 | 打开同步详情或重试。 |
| 正在导入 | 文件名/进度/暂停或取消 | 打开导入队列。 |
| 音频笔记录制 | 录制时长/暂停按钮 | 展开录音控制面板。 |

示例：

```typescript
@Builder
function flowMuseMiniBarBuilder() {
  Row() {
    Image($r('app.media.whiteboard_thumb'))
      .width(40)
      .height(40)
      .borderRadius(20)

    Text('白板进行中')
      .fontSize(14)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .layoutWeight(1)

    SymbolGlyph($r('sys.symbol.play_fill'))
      .fontSize(22)
  }
  .height(56)
  .padding({ left: 8, right: 12 })
}

.barFloatingStyle({
  barBottomMargin: 28,
  systemMaterialEffect: {
    materialType: hdsMaterial.MaterialType.ADAPTIVE,
    materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
  },
  miniBar: {
    miniBarBuilder: () => this.flowMuseMiniBarBuilder()
  }
})
```

### 6.4 分割线动态显隐

`HdsTabs` 支持分割线常显、常隐、跟随滚动：

```typescript
private controller: HdsTabsController = new HdsTabsController();
private listScroller0: ListScroller = new ListScroller();
private listScroller1: ListScroller = new ListScroller();

aboutToAppear(): void {
  this.controller.bindScroller(0, this.listScroller0);
  this.controller.bindScroller(1, this.listScroller1);
}

aboutToDisappear(): void {
  this.controller.unbindScroller(this.listScroller0);
  this.controller.unbindScroller(this.listScroller1);
}

HdsTabs({ controller: this.controller }) {
  TabContent() {
    List({ scroller: this.listScroller0 }) {
      // 资料库列表
    }
  }
  .tabBar(new BottomTabBarStyle($r('sys.symbol.doc_text'), '资料库'))

  TabContent() {
    List({ scroller: this.listScroller1 }) {
      // 搜索结果列表
    }
  }
  .tabBar(new BottomTabBarStyle($r('sys.symbol.magnifyingglass'), '搜索'))
}
.barOverlap(true)
.barPosition(BarPosition.End)
.vertical(false)
.divider({
  mode: DividerMode.FOLLOW_SCROLL,
  style: {
    color: $r('sys.color.ohos_id_color_divider'),
    strokeWidth: 1,
    startMargin: 0,
    endMargin: 0
  }
})
```

建议：

- 资料库列表：跟随滚动显示，列表内容进入底部页签背后时显示分割线。
- 白板页：常隐，让画布更沉浸。
- 设置页：可常显，保证结构清晰。

### 6.5 背景模糊样式

底部页签可配置模糊/遮罩：

```typescript
.barBackgroundStyle({
  maskColor: '#66F1F3F5',
  maskHeight: 92
})
```

注意不要同时设置原生 Tabs 的 `barBackgroundBlurStyle`、`barBackgroundEffect`、`barBackgroundColor` 后又期待 HDS 默认模糊保持不变。这些属性可能影响 HDS 页签的默认背景模糊行为。

### 6.6 图标出血样式

当选中图标需要更强视觉识别时，可使用 `bleedIconStyle`，图标最多超出 TabBar 约 `4vp`：

```typescript
.bleedIconStyle(() => this.tabBuilder())
```

FlowMuse 可用于：

- 当前选中“白板/资料库”主入口的轻微放大。
- 同步异常时的红点/徽标突出。

不建议每个 Tab 都出血，否则会削弱导航稳定感。

### 6.7 侧向页签半屏居中

大屏或折叠屏可以使用垂直页签：

```typescript
.vertical(true)
.barMode(ExtendBarMode.HALF_SCREEN_FIXED)
```

建议只在窄侧边栏模式中使用，例如平板横屏左侧只显示图标时。若已有 `HdsSideBar + HdsSideMenu`，不要再叠加一套垂直 Tabs 造成重复导航。

---

## 7. HdsSideBar 与 HdsSideMenu

### 7.1 HdsSideBar 嵌入模式

嵌入模式适合平板、PC、2in1 的主界面，对应当前 `LibrarySidebar` 的长期目标：

```typescript
import { HdsSideBar } from '@kit.UIDesignKit';

HdsSideBar({
  sideBarContainerType: SideBarContainerType.Embed,
  sideBarPanelBuilder: () => this.sideBarBuilder(),
  contentPanelBuilder: () => this.contentBuilder(),
  isShowSideBar: this.isShowSideBar,
  $isShowSideBar: (isShowSideBar: boolean) => {
    this.isShowSideBar = isShowSideBar;
  }
})
```

FlowMuse 左侧栏建议结构：

- 顶部：账号/Pro 状态、侧边栏收起、设置、商店。
- 主菜单：全部笔记、搜索、文件夹、标签、回收站。
- 二级区域：文件夹树、标签列表。
- 底部：存储/同步/多窗口入口。

### 7.2 HdsSideBar 覆盖模式

覆盖模式适合手机横屏、平板窄窗或临时抽屉：

```typescript
HdsSideBar({
  sideBarContainerType: SideBarContainerType.Overlay,
  sideBarPanelBuilder: () => this.sideBarBuilder(),
  contentPanelBuilder: () => this.contentBuilder(),
  autoHide: true,
  contentAreaMask: true,
  isShowSideBar: this.isShowSideBar,
  $isShowSideBar: (isShowSideBar: boolean) => {
    this.isShowSideBar = isShowSideBar;
  }
})
```

建议：

- `< 820vp` 或紧凑窗口使用覆盖模式。
- 打开侧边栏时内容区加遮罩，点击内容区自动关闭。
- 资料编辑/白板绘制中不要突然自动展开侧栏。

### 7.3 HdsSideMenu 一级/二级菜单

`HdsSideMenu` 适合替换手写列表菜单，支持一二级菜单和消息红点：

```typescript
import {
  HdsSideMenu,
  HdsSideMenuMainItem,
  HdsSideMenuSubItem,
  HdsSideMenuBadgeParam
} from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';

HdsSideMenu({
  items: [
    new HdsSideMenuMainItem({
      label: '全部笔记',
      symbol: new SymbolGlyphModifier($r('sys.symbol.doc_text'))
    }),
    new HdsSideMenuMainItem({
      label: '文件夹',
      icon: $r('sys.symbol.folder'),
      hdsSideMenuSubItem: [
        new HdsSideMenuSubItem({ label: '课程资料' }),
        new HdsSideMenuSubItem({
          label: '灵感草稿',
          badge: { count: 2 } as HdsSideMenuBadgeParam
        })
      ]
    })
  ],
  selectedIndex: this.selectedIndex,
  $selectedIndex: (selectedIndex: number) => {
    this.selectedIndex = selectedIndex;
  }
})
```

FlowMuse 菜单映射：

| 当前 Flutter 侧栏项 | HDS 建议 |
| --- | --- |
| 全部笔记 | `HdsSideMenuMainItem`，选中后进入资料库。 |
| 搜索 | 主菜单项，也可在标题区提供搜索框。 |
| 未分类、未标签、回收站 | 主菜单项或“智能分类”分组下的二级菜单。 |
| 文件夹 | 主菜单项 + 子项列表。 |
| 标签 | 主菜单项 + 子项或筛选入口。 |
| 新建文件夹/标签 | 菜单右侧操作或标题栏 `menu`。 |

---

## 8. HdsListItem 与 HdsListItemCard

### 8.1 列表卡片

资料库列表建议用 `HdsListItemCard` 保持系统卡片质感：

```typescript
import {
  HdsListItemCard,
  PrefixImage,
  SuffixSwitch
} from '@kit.UIDesignKit';

HdsListItemCard({
  prefixItem: new PrefixImage({
    image: $r('app.media.notebook_cover'),
    onClick: () => {
      this.previewNotebook();
    }
  }),
  textItem: {
    primaryText: {
      text: '课程复习笔记'
    },
    secondaryText: {
      text: '12 篇笔记'
    },
    description: {
      text: '今天 14:20 更新'
    }
  },
  suffixItem: new SuffixSwitch({
    isCheck: this.isPinned,
    onChange: (isCheck: boolean) => {
      this.isPinned = isCheck;
    }
  }),
  onClick: () => {
    this.openNotebook();
  }
})
```

FlowMuse 列表字段建议：

| 内容类型 | 前缀 | 主标题 | 副标题/描述 | 后缀 |
| --- | --- | --- | --- | --- |
| 笔记本 | 封面/文件夹图标 | 笔记本名 | 笔记数量、更新时间 | 更多/置顶状态。 |
| 笔记 | 文档/白板/音频图标 | 笔记标题 | 摘要、标签、更新时间 | 收藏/同步状态。 |
| 文件夹 | 文件夹 Symbol | 文件夹名 | 子项数量 | 展开/更多。 |
| 搜索结果 | 类型图标 | 命中标题 | 命中片段 | 所属文件夹。 |

### 8.2 横滑操作

`HdsListItem` 支持内置横滑删除/操作：

```typescript
import { SymbolGlyphModifier } from '@kit.ArkUI';

HdsListItem({
  hdsListItemCard: this.noteCardBuilder(),
  swipeActionOptions: {
    icons: [
      {
        icon: new SymbolGlyphModifier($r('sys.symbol.pin')),
        onAction: () => this.pinNote()
      },
      {
        icon: new SymbolGlyphModifier($r('sys.symbol.square_and_arrow_up')),
        onAction: () => this.shareNote()
      }
    ],
    deleteIconOptions: {
      backgroundColor: Color.Red,
      iconColor: Color.White,
      onAction: () => this.deleteNote()
    },
    fullDeleteOptions: {
      isFullDelete: true,
      onFullDeleteAction: () => this.deleteNote()
    }
  }
})
```

FlowMuse 操作建议：

- 笔记：置顶、移动、分享、删除。
- 笔记本：重命名、导出、删除。
- 文件夹：新建子文件夹、重命名、删除。
- 删除后优先显示 `HdsSnackBar` 撤销，不立即弹窗。

### 8.3 列表与动态模糊配合

列表页使用 HDS 导航动态模糊时：

- 列表滚动容器使用同一个 `Scroller` 绑定给 `HdsNavigation`。
- 页签悬浮时底部增加安全区和页签高度 padding。
- 长列表不建议给每张卡都加沉浸材质，卡片应保持清晰、稳定、可快速扫描。

---

## 9. HdsActionBar 核心操作栏

### 9.1 有主按钮操作栏

适合白板工具栏或批量操作入口：

```typescript
import {
  HdsActionBar,
  ActionBarButton,
  ActionBarStyle
} from '@kit.UIDesignKit';

HdsActionBar({
  startButtons: [
    new ActionBarButton({
      baseIcon: $r('sys.symbol.hand_raised'),
      hoverTips: '平移',
      onClick: () => this.selectTool('pan')
    }),
    new ActionBarButton({
      baseIcon: $r('sys.symbol.cursorarrow'),
      hoverTips: '选择',
      onClick: () => this.selectTool('select')
    })
  ],
  endButtons: [
    new ActionBarButton({
      baseIcon: $r('sys.symbol.textformat'),
      hoverTips: '文本',
      onClick: () => this.selectTool('text')
    })
  ],
  primaryButton: new ActionBarButton({
    baseIcon: $r('sys.symbol.plus'),
    altIcon: $r('sys.symbol.xmark'),
    hoverTips: '工具',
    onClick: () => this.toggleTools()
  }),
  actionBarStyle: new ActionBarStyle({
    isPrimaryIconChanged: this.isPrimaryIconChanged
  }),
  isExpand: this.isToolExpanded
})
```

FlowMuse 白板建议分组：

- 主按钮：展开/收起工具。
- 左侧：平移、选择、锁定。
- 右侧：形状、画笔、文本、图片。
- 次级面板：颜色、线宽、透明度、层级。

### 9.2 无主按钮操作栏

适合资料库批量选择、搜索结果多选：

```typescript
HdsActionBar({
  startButtons: [
    new ActionBarButton({
      baseIcon: $r('sys.symbol.folder'),
      hoverTips: '移动',
      onClick: () => this.moveSelectedNotes()
    }),
    new ActionBarButton({
      baseIcon: $r('sys.symbol.tag'),
      hoverTips: '标签',
      onClick: () => this.tagSelectedNotes()
    })
  ],
  endButtons: [
    new ActionBarButton({
      baseIcon: $r('sys.symbol.trash'),
      hoverTips: '删除',
      onClick: () => this.deleteSelectedNotes()
    })
  ]
})
```

使用建议：

- 操作数量不要超过用户一眼能判断的范围。
- 危险操作放右侧或末尾，并使用清晰图标和确认/撤销机制。
- 与 `ImmersiveMaterial(ULTRA_THIN)` 组合时，保证图标对比度和触控面积。

---

## 10. HdsSnackBar 即时操作

### 10.1 定时通知

适合自动消失的轻量反馈：

```typescript
import {
  HdsSnackBar,
  SnackBarIconOptions,
  SnackBarMessageOptions,
  SnackBarOperationOptions,
  SnackBarStyleOptions,
  SnackBarOperationType
} from '@kit.UIDesignKit';

uiContext: UIContext = this.getUIContext();
hdsSnackBar: HdsSnackBar = new HdsSnackBar(this.uiContext);

icon: SnackBarIconOptions = {
  icon: $r('sys.symbol.checkmark_circle')
};

message: SnackBarMessageOptions = {
  title: '已保存',
  content: '笔记内容已自动保存'
};

operation: SnackBarOperationOptions = {
  operationType: SnackBarOperationType.TEXT_WITH_ARROW,
  content: '查看',
  arrowButtonId: 'snackbar_view_note'
};

style: SnackBarStyleOptions = {
  nextFocusId: 'save_button',
  duration: 5000
};

this.hdsSnackBar.show(this.icon, this.message, this.operation, this.style);
```

FlowMuse 使用场景：

- 自动保存完成。
- 导入完成，可点击查看。
- 复制链接成功。
- 移动到文件夹成功。

### 10.2 常驻通知

`duration: -1` 可常驻，用于必须由用户处理或确认的状态：

```typescript
syncErrorIcon: SnackBarIconOptions = {
  icon: $r('sys.symbol.exclamationmark_triangle')
};

syncErrorMessage: SnackBarMessageOptions = {
  title: '同步失败',
  content: '请检查网络后重试'
};

syncErrorOperation: SnackBarOperationOptions = {
  operationType: SnackBarOperationType.TEXT_WITH_CLOSE,
  content: '重试',
  textButtonId: 'snackbar_retry_sync'
};

syncErrorStyle: SnackBarStyleOptions = {
  nextFocusId: 'sync_button',
  duration: -1
};

this.hdsSnackBar.show(
  this.syncErrorIcon,
  this.syncErrorMessage,
  this.syncErrorOperation,
  this.syncErrorStyle
);
```

使用规则：

- 成功类反馈自动消失。
- 失败、离线、冲突类反馈可常驻。
- 删除操作优先“已删除 + 撤销”，比二次确认更顺手。
- 设置 `arrowButtonId`、`textButtonId`、`nextFocusId`，保证键盘/遥控器焦点可达。

---

## 11. HDS 视觉效果

### 11.1 点光源

点光源用于强调触摸焦点或当前选中项：

```typescript
import { hdsEffect } from '@kit.UIDesignKit';

Button('新建')
  .visualEffect(new hdsEffect.HdsEffectBuilder()
    .pointLight({
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
      options: {
        color: Color.White,
        intensity: 10,
        height: 150
      }
    })
    .buildEffect())
```

约束：

- 单个组件最多被 12 个光源照亮。
- 不要给列表中的每个条目同时加点光。
- FlowMuse 建议只用于“新建笔记”“当前白板工具”“MiniBar 当前任务”。

### 11.2 按压阴影

按压阴影增强按钮触感：

```typescript
@State pressShadowType: hdsEffect.PressShadowType = hdsEffect.PressShadowType.NONE;

Button('创建')
  .stateEffect(false)
  .visualEffect(new hdsEffect.HdsEffectBuilder()
    .pressShadow(this.pressShadowType)
    .buildEffect())
  .onTouch((event: TouchEvent) => {
    if (event.type === TouchType.Down) {
      this.pressShadowType = hdsEffect.PressShadowType.BLEND_GRADIENT;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.pressShadowType = hdsEffect.PressShadowType.NONE;
    }
  })
```

建议：

- 主按钮可用 `BLEND_GRADIENT`。
- 普通按钮用默认状态效果或 `BLEND_WHITE`。
- 密集工具按钮不要全部使用强按压阴影，避免视觉噪声。

### 11.3 双边边缘流光

适合胶囊组件边缘流动，例如 MiniBar 正在同步：

```typescript
@State controller: hdsEffect.EffectController = new hdsEffect.EffectController();

Row() {
  Text('正在同步')
}
.visualEffect(new hdsEffect.HdsEffectBuilder()
  .shaderEffect({
    effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
    animation: {
      duration: 4000,
      iterations: -1,
      autoPlay: true
    },
    controller: this.controller,
    params: {
      firstEdgeFlowLight: {
        startPos: 0,
        endPos: 0.5,
        color: '#40A06B'
      },
      secondEdgeFlowLight: {
        startPos: 0.5,
        endPos: 1,
        color: '#80CFA0'
      }
    }
  })
  .buildEffect())
```

建议只在短时任务中使用；任务结束后停止动画。

### 11.4 背景流光与遮罩流光

背景流光适合启动页、导入完成庆祝、白板协作连接中等短时视觉，不适合长期铺满主界面：

```typescript
.visualEffect(new hdsEffect.HdsEffectBuilder()
  .shaderEffect({
    effectType: hdsEffect.EffectType.UV_BACKGROUND_FLOW_LIGHT,
    animation: {
      duration: 6000,
      iterations: -1,
      autoPlay: true
    }
  })
  .buildEffect())
```

带背景遮罩的双边流光可用于屏幕边缘或胶囊容器，但要控制面积和时长，避免影响阅读。

---

## 12. 图标处理与 Symbol

### 12.1 系统 SymbolGlyph

功能图标优先使用系统 Symbol：

```typescript
SymbolGlyph($r('sys.symbol.folder'))
  .fontSize(24)
  .fontColor([$r('sys.color.icon_primary')])
```

优势：

- 与 HarmonyOS 系统图标风格一致。
- 支持多色渲染、动效和资源色适配。
- 在沉浸材质上更容易使用自动反色能力。

FlowMuse 图标建议：

| 功能 | 推荐 Symbol 语义 |
| --- | --- |
| 资料库 | 文档/笔记。 |
| 搜索 | 放大镜。 |
| 文件夹 | 文件夹。 |
| 设置 | 齿轮。 |
| 白板工具 | 手、光标、形状、画笔、文本、图片。 |
| 同步 | 循环箭头/云。 |
| 删除 | 垃圾桶。 |

### 12.2 自定义 Symbol

如果系统 Symbol 无法覆盖 FlowMuse 专属图标，可注册自定义 Symbol：

```typescript
import { symbolRegister } from '@kit.ArkUI';

symbolRegister.registerSymbol(
  $rawfile('symbol/flowmuse_symbol.ttf'),
  $rawfile('symbol/flowmuse_symbol.json')
);

SymbolGlyph($r('app.string.symbol_flowmuse_whiteboard'))
  .fontSize(24)
```

资源放置：

- TTF 与 JSON：`ohos/entry/src/main/resources/rawfile/symbol/`。
- Unicode 字符串：`string.json`。

限制：

- 仅支持注册 1 组图标资源与动效参数资源。
- 最多支持 10 个自定义图标与动效参数资源。
- 因此只放 FlowMuse 真正有品牌识别需求的图标，例如白板、知识图谱、AI 摘要入口。

### 12.3 分层图标处理

应用图标或复杂品牌图形可使用 HDS 分层图标处理：

```json
{
  "layered-image": {
    "background": "$media:background",
    "foreground": "$media:foreground"
  }
}
```

使用：

```typescript
import { hdsDrawable } from '@kit.UIDesignKit';

const icon = hdsDrawable.getHdsLayeredIcon(
  bundleName,
  descriptor,
  48,
  true
);
```

限制：

- 图标批量处理接口最大并发数为 10。
- 单次最大处理量 500 个。

---

## 13. MultiWindowEntryInAPP 应用内多窗

### 13.1 适用场景

FlowMuse 很适合多窗：

- 左侧窗口打开资料库，右侧窗口打开白板。
- 一个窗口查看笔记，另一个窗口编辑白板。
- 搜索结果与目标笔记并行。

若页面已经使用 `HdsNavigation` 提供多窗口入口，优先用导航内置能力；如果没有使用 HDS 导航，则使用 `MultiWindowEntryInAPP`。

### 13.2 基础用法

```typescript
import { MultiWindowEntryInAPP } from '@kit.UIDesignKit';

MultiWindowEntryInAPP({
  want: {
    bundleName: 'com.flowmuse.app',
    moduleName: 'entry',
    abilityName: 'EntryAbility'
  },
  style: {
    icon: $r('sys.symbol.rectangle_split_2x1'),
    text: '新窗口打开白板',
    backgroundColor: $r('sys.color.comp_background_tertiary')
  }
})
```

支持设备状态：

- 双折设备展开态。
- 三折设备双屏或三屏横屏。
- 平板横屏。

不支持的设备形态下，入口可能不可交互。UI 上应避免把关键操作只放在多窗入口里。

---

## 14. FlowMuse 页面落地方案

### 14.1 手机端结构

首屏使用 `HdsNavigation + HdsTabs`：

- `HdsTabs` 四个一级入口：资料库、搜索、文件夹、设置。
- `barFloatingStyle` 使用自适应沉浸材质。
- `miniBar` 显示当前白板、同步、录音、导入状态。
- 各 Tab 内部列表底部留出页签高度和安全区。

手机端不再常驻左侧栏，当前 Flutter `LibrarySidebar` 的内容改为：

- 资料库 Tab 内的筛选/分组。
- 覆盖式 `HdsSideBar` 抽屉。
- 标题栏更多菜单。

### 14.2 平板/PC 结构

主结构使用 `HdsSideBar + HdsSideMenu + HdsNavigation`：

- 左侧 `HdsSideBar` 使用嵌入模式。
- `HdsSideMenu` 承载一级菜单和文件夹/标签二级项。
- 内容区使用 `HdsNavigation` 管理标题栏、动态模糊和菜单。
- 窄窗时切换为覆盖式侧边栏或底部页签。
- 支持设备上添加 `MultiWindowEntryInAPP`，让白板和资料库并行。

### 14.3 资料库页

推荐能力：

- 标题栏：`HdsNavigation` + `GRADIENT_BLUR`。
- 标题扩展：`bottomBuilder` 放“全部 / 最近 / 收藏 / 标签”分段控件。
- 列表：`HdsListItemCard` 展示笔记本/笔记。
- 横滑：`HdsListItem` 支持置顶、移动、分享、删除。
- 反馈：删除后 `HdsSnackBar` 撤销。
- 大屏：左侧 `HdsSideMenu` 显示文件夹树。

### 14.4 搜索页

推荐能力：

- 搜索框放在 `HdsNavigation bottomBuilder`。
- 搜索结果列表用 `HdsListItemCard`。
- 结果滚动时可 `dynamicHideTitleBar` 隐藏筛选区。
- 搜索无结果不要用强光效，保持清晰空状态。
- 复制/跳转/筛选变更用 `HdsSnackBar` 或轻量 Toast。

### 14.5 文件夹页

推荐能力：

- `HdsSideMenu` 二级菜单承载文件夹树。
- 内容区列表用 `HdsListItemCard`。
- 新建文件夹用标题栏菜单或 `HdsActionBar` 主按钮。
- 移动笔记使用半模态 `HdsNavigationTitleMode.MODAL`。
- 删除文件夹使用常驻 `HdsSnackBar` 撤销。

### 14.6 白板页

推荐能力：

- 标题栏可动态隐藏，画布优先。
- 工具栏使用 `HdsActionBar`，包一层 `ImmersiveMaterial(ULTRA_THIN)`。
- 当前工具可用点光/按压阴影强调。
- 缩放控件使用小型胶囊材质，放在画布角落。
- 保存/同步状态进入 MiniBar，不遮挡画布中央。
- 白板页慎用背景流光，避免干扰图形和文字判断。

白板浮动工具栏参考：

```typescript
Row() {
  HdsActionBar({
    startButtons: this.basicToolButtons,
    endButtons: this.insertToolButtons,
    primaryButton: this.primaryToolButton,
    isExpand: this.isExpanded
  })
}
.padding(4)
.borderRadius(28)
.systemMaterial(new uiMaterial.ImmersiveMaterial({
  style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
  interactive: true,
  lightEffect: { color: undefined },
  colorInvert: true
}))
```

### 14.7 设置页

推荐能力：

- 使用 `HdsNavigation` 普通 `COMMON_BLUR`。
- 设置项用 `HdsListItemCard` 或普通 ArkUI List，不需要强沉浸。
- 危险操作如清空缓存、退出登录使用 `ULTRA_THICK` Dialog。
- 成功/失败反馈使用 `HdsSnackBar`。

---

## 15. 兼容性、限制与降级

### 15.1 UI Design Kit 区域与设备限制

| 能力 | 支持设备 | 备注 |
| --- | --- | --- |
| 图标处理 | Phone、Tablet、PC/2in1、TV | 批量处理有并发/数量限制。 |
| 组件导航 | Phone、Tablet、PC/2in1、TV | 横屏 Stack 模式下部分工具栏合并能力有限。 |
| 侧边栏/侧边栏菜单 | Phone、Tablet、PC/2in1、TV | 大屏优先使用。 |
| 底部页签 | Phone、Tablet、PC/2in1 | 手机一级导航优先。 |
| SnackBar/ActionBar | Phone、Tablet、PC/2in1、TV | 注意焦点和遥控器场景。 |
| 列表 | Phone、Tablet、PC/2in1、Wearable、TV | 可跨设备复用。 |
| 自定义 Symbol | Phone、Tablet、PC/2in1 | 注册数量有限。 |
| HDS 视效 | Phone、Tablet、PC/2in1 | 模拟器不支持沉浸视效。 |
| 应用内多窗 | Phone、Tablet | 依赖设备形态。 |
| 沉浸光感材质 | Phone、Tablet | HDS Navigation/Tabs 重点支持。 |

UI Design Kit 当前仅支持中国境内（不含香港特别行政区、澳门特别行政区、中国台湾）。

### 15.2 模拟器限制

模拟器可用于开发，但不支持以下 HDS 沉浸视效：

- 点光源。
- 按压阴影。
- 双边边缘流光。
- 背景流光。
- 自带背景的双边流光。
- 沉浸光感材质。

因此验收沉浸光感必须真机复核。模拟器只能验证布局、导航、基础交互和降级样式。

### 15.3 低算力与材质降级

使用自定义沉浸材质时：

```typescript
const types = hdsMaterial.getSystemMaterialTypes();
const supportsImmersive =
  types.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0;

const level = supportsImmersive
  ? hdsMaterial.MaterialLevel.GENTLE
  : hdsMaterial.MaterialLevel.SMOOTH;
```

规则：

- 默认使用 `ADAPTIVE + ADAPTIVE`。
- 不支持 `IMMERSIVE` 时，降级到 `SMOOTH`。
- 长时间动画、背景流光、多个模糊浮层要支持关闭。

### 15.4 同层渲染注意

API 23 及之前，同层渲染场景（例如 Web 与 ArkUI 同层）中开启沉浸效果，可能导致控件变透明或显示异常。若 FlowMuse 后续在鸿蒙端使用 WebView/Flutter/ArkUI 混合承载，需要：

- 优先在原生 ArkUI 容器层使用 HDS 组件。
- 混合渲染区域避免强制叠加沉浸材质。
- 出现透明异常时关闭局部沉浸效果或关闭同层渲染。

### 15.5 Flutter 项目中的落地边界

当前 FlowMuse 主 UI 在 Flutter `lib/` 中，HDS/ArkUI API 不能直接在 Dart Widget 中调用。可选落地路径：

| 路径 | 适合阶段 | 说明 |
| --- | --- | --- |
| Flutter 仿 HDS 样式 | 短期 | 保持跨端 UI，一些光感用 Flutter 自绘/主题模拟，但不获得系统 HDS 组件能力。 |
| 鸿蒙原生壳层 | 中期 | 顶层导航、底部页签、SnackBar、系统弹层用 ArkUI/HDS，内容区承载 Flutter。 |
| 关键页面 ArkUI 原生化 | 长期 | 资料库、白板工具栏、设置等逐步用 ArkUI/HDS 重写，获得完整系统体验。 |

建议先从“原生壳层”开始：底部页签、侧边栏、标题栏和反馈栏最能体现鸿蒙特性，同时对业务内容侵入较小。

---

## 16. 设计与实现 Checklist

### 16.1 组件选型

```text
□ 手机一级导航是否使用 HdsTabs，而不是手写底栏？
□ 大屏是否使用 HdsSideBar/HdsSideMenu，而不是把手机底栏拉宽？
□ 列表是否优先使用 HdsListItemCard/HdsListItem？
□ 白板/批量操作是否使用 HdsActionBar？
□ 轻量反馈是否使用 HdsSnackBar？
□ 弹层是否使用系统材质或 HdsNavigation MODAL？
□ 多窗入口是否在支持设备上提供，但不作为唯一入口？
```

### 16.2 沉浸光感

```text
□ HDS 组件是否优先使用 ADAPTIVE + ADAPTIVE？
□ 自定义材质是否先调用 getSystemMaterialTypes()？
□ 浮层是否选择了合适 ImmersiveStyle？
□ 是否避免在列表主体和正文区域滥用透明材质？
□ 是否避免 systemMaterial 与手写背景/阴影/模糊互相覆盖？
□ 是否给低算力设备和模拟器准备普通样式？
```

### 16.3 交互与可访问性

```text
□ 底部悬浮页签是否避开手势安全区？
□ MiniBar 是否只承载持续任务，不放普通说明？
□ SnackBar 操作按钮是否设置 focus id？
□ PC/2in1 是否支持 hover、键盘焦点和快捷操作？
□ 删除等危险操作是否提供撤销或确认？
□ 白板工具按钮是否有清晰选中态和 tooltip/无障碍标签？
```

### 16.4 真机验证

```text
□ Phone 真机：底部页签、MiniBar、标题栏沉浸材质。
□ Tablet 真机：侧边栏嵌入/覆盖、多窗入口、横竖屏。
□ PC/2in1：键盘焦点、hover、窗口缩放。
□ 模拟器：布局和降级样式。
□ 低算力设备：材质降级、动画关闭、滚动帧率。
□ 深色/浅色：自动反色、文字对比度、图标可读性。
```

---

## 17. 快速落地优先级

### P0：先做鸿蒙壳层

1. 在鸿蒙原生入口设计 `HdsNavigation` 根容器。
2. 手机端接入 `HdsTabs` 悬浮页签：资料库、搜索、文件夹、设置。
3. 大屏接入 `HdsSideBar + HdsSideMenu`。
4. 接入 `HdsSnackBar` 统一反馈。

### P1：强化核心页面

1. 资料库列表改用 `HdsListItemCard/HdsListItem`。
2. 白板工具栏改用 `HdsActionBar + ImmersiveMaterial(ULTRA_THIN)`。
3. MiniBar 承载白板、同步、导入、录音状态。
4. 标题栏动态模糊和动态隐藏。

### P2：高级沉浸能力

1. 关键按钮点光和按压阴影。
2. MiniBar 同步/导入状态边缘流光。
3. 自定义 Symbol 注册 FlowMuse 专属图标。
4. 多窗口入口与白板/资料库并行。

---

## 18. 参考文档

- 华为开发者文档：《沉浸光感最佳实践》  
  https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-spatiality-immersive
- 华为开发者文档：《UI Design Kit 简介》  
  https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-introduction
- 华为开发者文档：《HDS 底部页签 - 设置页签栏的悬浮样式》  
  https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-tabs-bar-floating
- 华为开发者文档：《HDS 沉浸光感》  
  https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-component-material
- 华为开发者文档：《ArkUI 沉浸光感》  
  https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense
- 本项目本地镜像：`reference-docs/harmonyos-guides/应用框架/UI Design Kit（UI设计套件）/`
