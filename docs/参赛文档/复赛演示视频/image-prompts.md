# v2 图像生成记录

## 翡翠玻璃笔迹主视觉

- 生成方式：内置 `imagegen`，按文字提示生成新图；未指定或核实具体模型版本。
- 用途：电影感片头与片尾的品牌艺术背景，不是 FlowMuse 运行截图。
- 项目文件：`intro/hero-emerald-v2.png`、`edit/public/hero-emerald-v2.png`。
- 视觉方向：用户确认“翡翠墨色＋暖金，电影感”；标题、品牌字样与应用图标由视频工程另行叠加。

### Exact prompt

```text
Use case: stylized-concept. Asset type: cinematic brand hero background for a 16:9 product demo video for FlowMuse, a creative handwritten whiteboard application. Create a sophisticated premium 3D still, horizontal 16:9 composition. A single sculptural calligraphic ribbon made of translucent deep emerald glass flows in a graceful loose brushstroke loop, hovering over a few thin layered ivory paper sheets, a restrained warm champagne-gold specular edge within the glass; the gesture suggests the fluidity of writing without forming a readable letter or logo. Main sculptural subject on the RIGHT two-thirds, entering from the lower center and rising toward upper right. LEFT third should be very dark clean negative space for a large title that will be added separately. Dark forest green-black studio backdrop (#071C19), subtle soft emerald caustics on the surface, warm directional rim light, tactile folded paper, depth, editorial macro product photography, exquisitely controlled highlights, soft atmospheric depth, physically plausible high-end CGI, crisp focus on the ribbon and refined material detail. Palette emerald jade, ivory and very restrained champagne gold. Visually bold, sculptural and artistic, not a generic technology wallpaper. No text, no lettering, no UI screens, no device, no icons, no brand marks, no watermarks, no extra floating decorative objects, no particles, no cyberpunk neon, no glitter. Keep dark background around all edges so it blends into a dark video composition. Output a large landscape image suitable for 1920x1080 video.
```

## 样片界面素材

以下素材均来自仓库现有截图，未经生成模型重画或调色。复制后的 SHA256 与原文件一致。

| 样片文件 | 仓库来源 | 性质与使用边界 |
|---|---|---|
| `edit/public/style-screens/brush-palette.png` | `docs/研发记录/research/assets/freehand-20260922/brush-palette.png` | 历史 Android 正常发布包 QA 截图；显示“历史实机截图 · Android · 2026.09.22”。测试输入为合成 stylus 事件，不是本轮真人压感验证。 |
| `edit/public/style-screens/smart-layout-v3.png` | `docs/研发记录/evidence/smart-layout-v3/ux-20260920/review-1200.png` | 历史 V3 界面截图，只有三段测试文字；显示“历史界面截图 · 2026.09.20”。 |
| `edit/public/style-screens/collaboration-invite.png` | `docs/研发记录/research/assets/room-created-invite-wide.png` | 协作邀请入口组件测试截图；显示“组件测试截图”。不作为双端同步录像。 |
