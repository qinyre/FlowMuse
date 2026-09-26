# 音频来源与使用记录

2026-09-26，为 FlowMuse 翡翠墨色／暖金视频制作的**原创算法合成听感稿**。以下两个音频均由同目录 `synthesize-demo.py` 现场生成，未使用第三方录音、音色采样、下载歌曲或参考歌曲旋律；不要把它们标成 HeyGen 授权曲库或正式配乐成品。

| 文件 | 内容 | 来源 / 权利记录 |
|---|---|---|
| `emerald-ambient-demo.wav` | 32 秒、48 kHz、16-bit 立体声；Cmaj9 / Am9 / Fmaj9 / G6 四和弦软音垫、稀疏高音，无人声、无鼓 | 本项目 AI 辅助原创合成；无第三方音源许可依赖。脚本与生成文件一并交付项目使用、修改和重制，不额外宣称作品的独占版权。 |
| `soft-reveal-demo.wav` | 1.4 秒、48 kHz、16-bit 立体声；轻柔双音提示、短衰减 | 同上，全部正弦振荡器合成，无外部采样。 |

## 本次来源检查

- `hyperframes@0.8.78 media-use resolve --doctor`：19 个内置音效可用；HeyGen CLI / 登录不可用。FFmpeg / FFprobe 不在系统 PATH，但本项目已有本地二进制，本次使用它们检查音频。
- BGM `--candidates`：项目及全局缓存均无可复用候选。
- 检查了 `media-use/audio/assets/sfx/manifest.json` 和 `CREDITS.md`；后者将内置音效归于 Pixabay Content License，但没有逐素材页面与作者记录。本次**未复制、未使用**这些第三方音效。
- Pixabay 官方[许可摘要](https://pixabay.com/service/license-summary/)明确限制原内容的独立分发。考虑此工程需要入库共享，选择可由本地脚本复现的原创提示音，未把第三方原始 MP3 放入仓库。

## 混音默认值

- BGM 文件峰值约 **−6.94 dBFS**，RMS **−17.92 dBFS**。无旁白预演建议 Remotion `volume=0.4`；接入旁白后先降至 `0.20`，再按实际配音复核。
- 提示音文件峰值约 **−6.94 dBFS**，建议 `volume=0.12`。只放在少量章节结果或品牌揭示处，不给每次点击配提示音。
- BGM 保持 32 秒循环；首尾 0.3 秒已做循环接缝融合。循环文件不是首尾静音，时间轴必须对**整条音乐**做约 1.2 秒淡入／淡出；循环时使用 `loopVolumeCurveBehavior="extend"`，防止每 32 秒重做淡入。
- 数值检查见 `audio-check.json`：时长、PCM 格式、峰值、RMS、SHA-256、循环接缝与局部斜率误差。提示音首尾接近零；音乐接缝与邻接波形斜率连续，没有非预期跳变。
- 本轮完成程序与解码检查；最终听感须随画面、配音和播放设备一起审听，不能用峰值指标替代听感确认。

## 复现

使用已安装的 Python 3 与 NumPy（本次 NumPy 2.2.4）：

```powershell
python edit/public/audio/synthesize-demo.py
```

脚本只重建同目录下这两个 WAV 与 `audio-check.json`，自带时长、声道、峰值及接缝断言。四和弦循环是此次听感稿的明确简化；需要更长结构与配器时替换配乐，不继续堆复杂的合成器框架。
