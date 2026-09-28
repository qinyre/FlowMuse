# FlowMuse 复赛演示视频

最新交付为 [无配音、三端完整画面版](output/FlowMuse-无配音-三端完整画面.mp4)：以v5.3无声版为基础，去掉右上角审片标识，并修正三端共创画面的裁切。片头、协作正文与片尾均按原比例完整展示原始三端合成画面，保留素材自带的平台标签，将界面外的黑色空白改为模板浅灰绿底；字幕和时码沿用v5.3，**4分30秒，1920×1080、30 fps，无音轨**。此前的 [去标识版](output/history/FlowMuse-无配音-无审片标识.mp4) 和原v5.3文件保留。

旁白工程仍保留 **v6**，队名 **青天小老爷**。已接入八段录屏和用户提供的35段TTS，保持 **4分30秒，1920×1080、30 fps**。字幕按音频落点更新，句末不显示句号、句内句号转为换行，保留逗号和顿号；旁白稿保留正常标点。仅有人声，无背景音乐和提示音。此前导出的v6文件仍带审片标识，正式提交前仍须完整审听。

观看 [完整实录审片 v6（旁白、无音乐）](output/FlowMuse-实录审片-v6-旁白.mp4)。录屏外采用浅灰绿底色，白色应用界面增加细边框与轻阴影；外框固定，局部放大在框内进行。品牌保留纸白、石墨黑与鲜绿。真实排版、三端协作贯穿开场与片尾，字幕放在独立底栏，笔迹、识别、排版及取色操作适度放大。三端协作来自同一合成源的同一时码，保留原速。

旁白采用 [35段完整讲解稿 v6](旁白录制稿-v6.md)（860字符）。`edit/narration-v6.json` 的 `start/end` 保留原稿镜头窗口，`audio.start/trim` 保存实际落点和源音频裁切区间。只裁首尾静音并统一响度，不改变语速或句内停顿。第29段Excalidraw读音仍需人工确认；用户提供的ASR结果不是审听结论。

## 时间轴与取舍

| 成片位置 | 内容 | 净时长 |
|---|---|---:|
| 00:00–00:08 | 排版／协作成果与品牌 | 8秒 |
| 00:08–00:36 | 笔记本、标签、画布、PDF导入与搜索 | 28秒 |
| 00:36–01:08 | 标题、铅笔结构、正文与荧光标记 | 32秒 |
| 01:08–01:35 | 手写转字、边写边排、语音落地 | 27秒 |
| 01:35–02:15 | 排版候选、原稿对照、应用、撤销与重做 | 40秒 |
| 02:15–02:51 | AI总结确认写回与思维导图 | 36秒 |
| 02:51–03:35 | 好友邀请、Android／Web／鸿蒙共创与聚焦 | 44秒 |
| 03:35–04:00 | 图形文本更新、分享文件、重新打开编辑 | 25秒 |
| 04:00–04:22 | 桌面卡片、华为账号状态、系统取色书写 | 22秒 |
| 04:22–04:30 | 真实成果回顾与团队署名 | 8秒 |

实际素材包含不同讲义和演示笔记，按学习流程串联，没有把它们说成同一份文档。旁白已删除素材未完整演示的压感实验、笔刷参数恢复、排版块角色调整、公式检查、增添导图节点、反向文本编辑和素材库等承诺。功能能力盘点仍见 [功能盘点与镜头取舍](功能盘点与镜头取舍.md)，本版上屏内容以 [实录剪辑与旁白草案](录制脚本.md) 为准。

AI生成与排版等待已缩短并标注；真实结果留帧供观看。协作邀请段剪除含房间号及链接的弹窗。原素材部分带模糊过渡、分屏和时间压缩，这些限制记录在 [素材审看与剪辑计划](../../研发记录/plans/2026-09-27-demo-video-footage-edit.md)。

## 本地预览与重建

工程面向 Windows x64，复用已有 Node.js、Chrome、Remotion 和 FFmpeg，不需要新依赖。八段原片放在 `D:/Program/HarmonyOS/flowmuse-demo-video/视频素材`，总长350.671秒，保持原样。

```powershell
Set-Location 'docs/参赛文档/复赛演示视频/edit'
npm ci
# 只验证切点、文件与时长：
npm run cut -- 'D:/Program/HarmonyOS/flowmuse-demo-video/视频素材' --check
# 从原片重建八段剪辑副本，不覆盖原片：
npm run cut -- 'D:/Program/HarmonyOS/flowmuse-demo-video/视频素材'
npm run check
npm start
```

Studio 选择 `FlowMuseReview` 查看1080p30实录审片；`FlowMusePreview` 是15fps快速预览。`FlowMuseStyleSample` 仍是旧版历史截图风格参考，不属于v5实录交付。

[edit/cuts-v5.json](edit/cuts-v5.json) 每个切段为 `[原片起秒, 原片止秒, 可选尾帧停留秒]`。按源时间戳取段并标准化为30fps，不改变动作速度；各段另带0.4秒转场尾帧。脚本检查范围、净时长、输出帧数、帧率与尺寸，源文件哈希和时码映射保存到本地 `output/cuts-v5/manifest.json`。

剪辑副本位于 `edit/public/footage/*-v5.mp4`。它们与时间轴一起使用，可直接预览；原始录像和配音不入库。`timeline.json` 的 `duration` 是各章剪后净秒数，可继续调整。修改切点或时长后，同步校准该章 `steps.at` 和 `cues`；后续章节与字幕自动顺延，无需录屏卡秒。脚本自动更新 `录制脚本.md` 与 `旁白草案.srt`。

## 导出与配音

```powershell
npm run render:review
# 可选：720p15快速预览
npm run render:preview
# 只重查选定成片秒数的画面
node scripts/review.mjs 3 108.7 208.7 260
```

`render:review` 输出 `output/FlowMuse-实录审片-v6-旁白.mp4`。原始录屏的AAC音轨均接近静音底限，没有可用口述声；视频中的语音识别操作不等于录到了现场人声。当前正片只接入独立旁白。历史样片的音源记录见 [音频来源记录](edit/public/audio/SOURCES-LICENSE.md)。

预览、审片和无字幕版均先渲染无声画面，再由 `scripts/mux-narration.mjs` 流复制画面并将旁白母带编码为AAC。该步骤避免本机Remotion音频导出的2048采样点（42.667毫秒）偏移，并在替换输出前验证音轨与母带的零偏移相关度；可单独运行 `node scripts/mux-narration.mjs ../output/FlowMuse-实录审片-v6-旁白.mp4 --check` 复核。

35段原声位于 `D:/Program/HarmonyOS/flowmuse-demo-video/narration-work-v6`，总长216.590375秒；去掉多余首尾空白后占196.77秒，其余保留画面观察时间。每段采用FFmpeg双遍响度归一，目标−18 LUFS、峰值上限−2 dBTP，片段边缘5毫秒淡入淡出，最后一句269.41秒结束。生成的270秒 `edit/public/narration.wav` 仍被Git忽略，换机器需带上源目录或该母带；源文件保留不动。旧 `narration-work` 只有28段旧稿，不能用于本版。

```powershell
# 校验段号、来源文案、采样率、裁切、字幕与章节范围：
npm run narration -- 'D:/Program/HarmonyOS/flowmuse-demo-video/narration-work-v6' --check
# 重建旁白母带；先修改 narration-v6.json 的落点／裁切和对应 timeline.json cues：
npm run narration -- 'D:/Program/HarmonyOS/flowmuse-demo-video/narration-work-v6'
npm run check
```

处理清单、源哈希与响度测量保存在本地 `output/narration-v6/manifest.json`。分段字幕按保留的音频范围对齐，未做逐字ASR转写；第29段需在成片03:48附近确认英文名称，第35段队名以用户提供的ASR核对。详细记录见 [v6旁白接入](../../研发记录/plans/2026-09-27-demo-video-footage-edit.md#v6旁白接入)。

```powershell
npm run check:final
npm run render:clean
```

正式检查会拒绝缺配音或素材、时长不符及超过比赛时限的时间轴。`render:clean` 生成 `02-演示视频青天小老爷-无字幕审片.mp4`，保留已有输出，不静默覆盖；其后制作与校对最终字幕，再命名 `02-演示视频青天小老爷.mp4`。

## 插件与来源

- HyperFrames：复用 `intro/` 中纸面品牌动画和 `intro-v4.mp4`，本轮未改动或重新渲染片头。
- Remotion：实录时间轴、三端同源裁切、局部放大、底部字幕、转场与H.264／AAC输出。
- Yaps：本轮未调用。复用用户的分段稿和实测音频范围生成字幕；历史尝试的本地runner不可达，不能声称已产出Yaps字幕。

实录由用户提供，保留原UI与笔迹，不生成或重画功能结果。DM Sans授权见 [DM-Sans-LICENSE.txt](DM-Sans-LICENSE.txt)，中文使用本机MiSans，回退Microsoft YaHei；系统字体不分发。视觉说明见 [DESIGN.md](DESIGN.md)。

## 验证

v6成片已通过完整解码、音轨同步及关键帧检查：1920×1080、30fps、8100帧／270秒，H.264／AAC 48kHz立体声，25,750,883字节。与母带的零偏移相关度0.999921，编码后峰值−1.99dBFS；重新合并音轨前后的视频编码数据一致。35段原声与8段录屏的哈希保持一致；35条JSON／SRT字幕文案、时码和无句号要求已核对。类型／时间轴／正式素材检查均通过，存在偏移的旧导出会被同步检查拒绝。结果见本地 `output/verification-v6.json`。这些检查不代替人工审听，第29段英文名称读音仍待确认。

切点与输出片段校验、Remotion类型检查及时间轴回归已通过；关键帧检查覆盖十个章节，复核字幕安全区、协作裁切、取色书写与团队署名。v5.1另检查录屏外框及放大后的裁切；v5.2通过流复制移除音轨；v5.3重新渲染去句号字幕，时间轴仍为8100帧／270秒。35条字幕的JSON与SRT均已核对无句号，旁白原稿标点保留。各版验收见本地 `output/verification-v5.1.json`、`verification-v5.2.json`、`verification-v5.3.json`，完整记录见上述计划文档。

## 输出目录

- output 根目录：当前无配音完整画面版、对应 ZIP、v6 旁白版和 v5.3 制作底片，以及当前核验数据
- output/history：历代样片、预演与已被替代的实录版本
- output/history/review-files：历次审片日志和截图
- cuts-v5、narration-v6、collab-full-frame 等工作目录：保留制作清单及当前成片的核验资料

## 历史版本

保留 [v5.3无音乐版（待配音、字幕无句号）](output/FlowMuse-实录审片-v5.3-无音乐.mp4)。

保留 [v5.2无音乐版（字幕含句号）](output/history/FlowMuse-实录审片-v5.2-无音乐.mp4)。

保留 [v5.1含音乐实录](output/history/FlowMuse-实录审片-v5.1.mp4)，可与当前无音乐版对照。

保留 [v5纸白背景实录](output/history/FlowMuse-实录审片-v5.mp4)。更早的 [v4纸面样片](output/history/FlowMuse-纸面样片-v4.mp4)、[v4完整预演](output/history/FlowMuse-纸面预演-v4.mp4)、[v3叙事样片](output/history/FlowMuse-叙事样片-v3.mp4)、[v3完整预演](output/history/FlowMuse-叙事预演-v3.mp4)、[v2电影感样片](output/history/FlowMuse-电影感样片-v2.mp4)、[v2完整预演](output/history/FlowMuse-电影感预演-v2.mp4) 和 [最初分镜预演](output/history/FlowMuse-分镜预演.mp4) 含历史截图或功能示意，不代表本次实录。

## 提交约束

项目已有本地竞赛规程记录：复赛视频5分钟以内、MP4，按 `02-演示视频+参赛队伍名称` 命名。当前270秒，留30秒余量；提交时核对报名系统最新通知。本轮未重新查询规则。
