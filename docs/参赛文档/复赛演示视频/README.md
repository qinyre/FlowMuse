# FlowMuse 复赛演示视频

当前交付是**功能盘点、可拍摄脚本、可编辑分镜预演**。还没有实机录像、真人旁白与正式队名，所以预演中明确显示待录制位置，不能直接提交比赛。

先看 [功能盘点与镜头取舍](功能盘点与镜头取舍.md)，再看 [逐镜录制脚本](录制脚本.md)。总长 **4 分 48 秒**，八组实机镜头；V3 智能排版保留 60 秒。正式母版设置为 1920×1080、30 fps、H.264 MP4；[分镜预演](output/FlowMuse-分镜预演.mp4) 为 1280×720、15 fps，便于审片。

## 本地预览

当前制作脚本面向 Windows x64，需要 Node.js 和 Chrome。下面的目录切换命令均从仓库根目录执行；首次使用先安装锁定的依赖。

```powershell
Set-Location 'docs/参赛文档/复赛演示视频/edit'
npm ci
npm start
```

打开终端输出的地址，选择 `FlowMusePreview`。预演不带配音，底部是按脚本分配的旁白文字，并非语音识别结果。片头、转场和录制步骤已排好。

## 素材录制

按脚本分八段录制，不必一口气拍完。每段前后留 5 秒，原始素材可以比目标长。统一横屏；平板可以保留原始比例，后期完整缩放。所有实际同步镜头保持正常速度，AI 等待如剪短须标明。用演示账号和样例内容。

| 原始素材名称 | 成片分配 | 核心画面 |
|---|---:|---|
| `01-library-pdf.mp4` | 22 秒 | 分类搜索、分页／无界、PDF、多页导航 |
| `02-natural-ink.mp4` | 34 秒 | 五种笔刷、铅笔／毛笔、压感、叠涂、切笔恢复、手指操作 |
| `03-recognition-voice.mp4` | 24 秒 | 手写转字、边写边排、语音转字 |
| `04-smart-layout.mp4` | 60 秒 | 原稿、V3 真实预览、图文关系、结构纠错、应用与撤销 |
| `05-ai-mindmap.mp4` | 35 秒 | 视觉问答、追问、确认生成、导图继续编辑 |
| `06-social-collaboration.mp4` | 45 秒 | 好友私聊、直接邀请、双端同步、创建者聚焦 |
| `07-markdraw-export.mp4` | 30 秒 | 双向文本、图元素材库、激光笔、导出／本地备份 |
| `08-harmony.mp4` | 20 秒 | 桌面卡片、账号入口、真机 Pen Kit 取色 |

建议原始录像放在本目录 `raw/`（按需建立）。剪辑完成后，将对应的片段放进 `edit/public/footage/`。每段成片另保留 **0.4 秒**尾帧，供交叉溶解；检查脚本会拒绝过短素材。`timeline.json` 是镜头、时长、步骤和旁白草案的唯一编辑入口。修改后重新运行 `npm start` 或 `npm run check`。

正式队名填写 `timeline.json` 的 `team`。配音先按实际剪辑对齐为 288 秒（含静音段），保存为 `edit/public/narration.wav` 或 `narration.mp3`。现场语音输入操作声若需要保留，后期合并进这条母音轨；素材原声默认静音，避免双声。

## 三个插件在工程中的作用

- **HyperFrames**：`intro/` 中的品牌片头，GSAP 动画，已使用实际应用图标与官网配色。
- **Remotion**：`edit/` 中的完整时间轴、八段素材替换、转场、预演字幕和母版输出。模板下载失败后按官方标准入口创建最小工程，依赖锁定在 `package-lock.json`。
- **Yaps**：针对最终有旁白的母版自动转写、校对及烧录字幕。本轮插件 runner 返回本地 CLI 不可达，**尚未转写，也尚未生成 Yaps 字幕成片**。根据 Yaps 插件的 “Stop until local reachability is restored” 要求，自动字幕阶段暂缓。可[下载或更新 Yaps](https://yaps.ai/download)，在本机打开一次，再从本地 Codex 任务继续。无需另装 CLI 或手工配 PATH。

## 校验与导出

```powershell
Set-Location 'docs/参赛文档/复赛演示视频/edit'
npm run check
npm run render:preview
# 补齐八段录屏、旁白和正式队名后：
npm run check:final
npm run render:clean
```

`render:clean` 生成 `output/02-演示视频<队名>-无字幕审片.mp4`，不会带入预演水印和草案字幕。素材不全会明确失败。之后交给 Yaps，使用清爽的 minimal／cinema 样式，逐条校对 FlowMuse、鸿蒙、Markdraw 等术语，验证输出，再保存为正式文件 `02-演示视频<队名>.mp4`。这一步完成前不把预演命名为提交版。

重新渲染片头时，使用工程内随 npm 安装的 FFmpeg/FFprobe（未安装系统软件）：

```powershell
Set-Location 'docs/参赛文档/复赛演示视频/intro'
$env:PATH = (Resolve-Path '..\edit\node_modules\@ffmpeg-installer\win32-x64').Path + ';' + (Resolve-Path '..\edit\node_modules\@ffprobe-installer\win32-x64').Path + ';' + $env:PATH
npm run check
npx --yes hyperframes@0.8.75 render --output ../edit/public/intro.mp4 --fps 30 --quality high --workers 2
```

DM Sans 字体已随项目依赖保存，授权见 [DM-Sans-LICENSE.txt](DM-Sans-LICENSE.txt)；中文使用本机 Microsoft YaHei。换机器渲染须保证该字体可用，或替换为有授权的中文字体并重新检查排版。

## 规则依据

本地《2026“中国高校计算机大赛―人工智能创意赛”鸿蒙高校创新赛竞赛规程》第 5–6 页：复赛演示视频必交，5 分钟以内，MP4，命名为 `02-演示视频+参赛队伍名称`。288 秒预留 12 秒余量。官网本轮访问超时，以上按本地规程执行；提交前以报名系统最新通知为准。
