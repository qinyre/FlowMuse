import {AbsoluteFill, Easing, Img, Interactive, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {TransitionSeries, linearTiming} from '@remotion/transitions';
import {fade} from '@remotion/transitions/fade';
import {Opening} from './scenes/Opening';
import {Closing} from './scenes/Closing';
import {Soundtrack} from './Soundtrack';

const Brushes = () => {
  const frame = useCurrentFrame();
  return <AbsoluteFill style={{backgroundColor: '#F6F5F0', color: '#171A18'}}>
    <div style={{position: 'absolute', left: 96, top: 100, fontSize: 23, letterSpacing: 3, color: '#087D5D'}}>NATURAL INK / 自然书写</div>
    <Interactive.Div name="写下来" style={{position: 'absolute', left: 85, top: 208, fontSize: 126, fontWeight: 700, letterSpacing: -7, lineHeight: 1.15, opacity: interpolate(frame, [0, 18], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}), translate: interpolate(frame, [0, 24], ['-34px 0px', '0px 0px'], {easing: Easing.bezier(0.16, 1, 0.3, 1), extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>写下来。</Interactive.Div>
    <svg width="520" height="58" viewBox="0 0 520 58" style={{position: 'absolute', left: 90, top: 351, overflow: 'visible'}} aria-label="标题手绘下划线">
      <path d="M8 31 C121 19 293 40 493 22" fill="none" stroke="#42DD91" strokeWidth="17" strokeLinecap="round" pathLength="1" strokeDasharray="1" strokeDashoffset={interpolate(frame, [16, 42], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
    </svg>
    <Interactive.Div name="笔刷说明" style={{position: 'absolute', left: 99, top: 438, width: 495, fontSize: 32, lineHeight: 1.65, opacity: interpolate(frame, [20, 40], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>每一种笔，<br />留下自己的质感。</Interactive.Div>
    <div style={{position: 'absolute', left: 102, top: 593, width: 450, borderTop: '2px solid #D9DFD6', paddingTop: 26, color: '#087D5D', fontSize: 27, lineHeight: 1.9}}>铅笔 / 圆珠笔 / 钢笔<br />毛笔 / 荧光笔</div>
    <svg width="490" height="140" viewBox="0 0 490 140" style={{position: 'absolute', left: 100, top: 741}} aria-label="笔触概念示意">
      <path d="M9 66 C56 5 104 133 158 70 S230 16 261 54 S314 105 354 63 S403 9 468 51" fill="none" stroke="#171A18" strokeWidth="6" strokeLinecap="round" pathLength="1" strokeDasharray="1" strokeDashoffset={interpolate(frame, [44, 104], [1, 0], {easing: Easing.inOut(Easing.quad), extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
      <text x="9" y="129" fill="#087D5D" fontSize="21">笔触概念示意</text>
    </svg>
    <Interactive.Div name="笔刷真实画面局部" style={{position: 'absolute', left: 654, top: 112, width: 1180, height: 750, border: '2px solid #D9DFD6', backgroundColor: '#FFFFFF', overflow: 'hidden', clipPath: `inset(0 0 0 ${interpolate(frame, [0, 26], [100, 0], {easing: Easing.bezier(0.16, 1, 0.3, 1), extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}%)`}}>
      <Img src={staticFile('style-screens/brush-palette.png')} style={{position: 'absolute', left: 0, top: -59, width: 1180, height: 833.87}} />
    </Interactive.Div>
    <div style={{position: 'absolute', left: 656, top: 883, fontSize: 22, color: '#087D5D'}}>历史实机截图 · Android · 2026.09.22 · 局部放大</div>
  </AbsoluteFill>;
};

const SmartLayout = () => {
  const frame = useCurrentFrame();
  return <AbsoluteFill style={{backgroundColor: '#F6F5F0', color: '#171A18'}}>
    <div style={{position: 'absolute', left: 99, top: 84, fontSize: 23, letterSpacing: 3, color: '#087D5D'}}>SMART LAYOUT / V3 智能排版</div>
    <Interactive.Div name="排整齐" style={{position: 'absolute', left: 85, top: 131, fontSize: 126, lineHeight: 1.15, fontWeight: 700, letterSpacing: -7, opacity: interpolate(frame, [0, 18], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}), translate: interpolate(frame, [0, 26], ['0px -30px', '0px 0px'], {easing: Easing.bezier(0.16, 1, 0.3, 1), extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>排整齐。</Interactive.Div>
    <Interactive.Div name="预览决策说明" style={{position: 'absolute', right: 102, top: 163, fontSize: 32, lineHeight: 1.65, textAlign: 'right', opacity: interpolate(frame, [14, 34], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>先看真实预览，<br /><span style={{color: '#087D5D'}}>确认之后，再应用。</span></Interactive.Div>
    <div style={{position: 'absolute', left: 96, right: 96, top: 287, height: 2, backgroundColor: '#D9DFD6'}} />
    <Interactive.Div name="原稿与预览真实界面" style={{position: 'absolute', left: 192, top: 315, width: 1536, height: 560, border: '2px solid #D9DFD6', overflow: 'hidden', backgroundColor: '#FFFFFF', opacity: interpolate(frame, [4, 24], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}), translate: interpolate(frame, [4, 30], ['0px 40px', '0px 0px'], {easing: Easing.bezier(0.16, 1, 0.3, 1), extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>
      <Img src={staticFile('style-screens/smart-layout-v3.png')} style={{position: 'absolute', left: 0, top: -140.8, width: 1536, height: 1152}} />
    </Interactive.Div>
    <svg width="1616" height="594" viewBox="0 0 1616 594" style={{position: 'absolute', left: 152, top: 298, pointerEvents: 'none', opacity: interpolate(frame, [28, 38, 84, 108], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}} aria-label="后期对照区域标记">
      <path d="M27 67 V17 H87 M1529 17 H1589 V67 M27 527 V577 H87 M1529 577 H1589 V527" fill="none" stroke="#42DD91" strokeWidth="7" strokeLinecap="square" pathLength="1" strokeDasharray="1" strokeDashoffset={interpolate(frame, [28, 57], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
    </svg>
    <div style={{position: 'absolute', left: 193, top: 889, color: '#087D5D', fontSize: 22}}>历史界面截图 · 2026.09.20 · 原稿／预览局部</div>
    <div style={{position: 'absolute', right: 193, top: 889, color: '#087D5D', fontSize: 22, opacity: interpolate(frame, [28, 38, 84, 108], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>绿色角标为后期强调</div>
  </AbsoluteFill>;
};

const Collaboration = () => {
  const frame = useCurrentFrame();
  return <AbsoluteFill style={{backgroundColor: '#F6F5F0', color: '#171A18'}}>
    <div style={{position: 'absolute', left: 97, top: 91, color: '#087D5D', fontSize: 23, letterSpacing: 3}}>COLLABORATION / 同页共创</div>
    <Interactive.Div name="协作邀请真实界面" style={{position: 'absolute', left: 94, top: 149, width: 760, height: 724.3, overflow: 'hidden', border: '1px solid #D9DFD6', borderRadius: 46, backgroundColor: '#FFFFFF', opacity: interpolate(frame, [0, 19], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}), translate: interpolate(frame, [0, 27], ['-45px 0px', '0px 0px'], {easing: Easing.bezier(0.16, 1, 0.3, 1), extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>
      <Img src={staticFile('style-screens/collaboration-invite.png')} style={{position: 'absolute', left: -594.36, top: -368.63, width: 1948.72, height: 1461.54}} />
    </Interactive.Div>
    <Interactive.Div name="一起改" style={{position: 'absolute', left: 977, top: 209, fontSize: 126, fontWeight: 700, lineHeight: 1.15, letterSpacing: -7, opacity: interpolate(frame, [8, 26], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}), translate: interpolate(frame, [8, 32], ['34px 0px', '0px 0px'], {easing: Easing.bezier(0.16, 1, 0.3, 1), extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>一起改。</Interactive.Div>
    <svg width="510" height="60" viewBox="0 0 510 60" style={{position: 'absolute', left: 983, top: 351}} aria-label="标题手绘下划线">
      <path d="M9 28 C143 43 323 13 489 28" fill="none" stroke="#42DD91" strokeWidth="17" strokeLinecap="round" pathLength="1" strokeDasharray="1" strokeDashoffset={interpolate(frame, [23, 47], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
    </svg>
    <Interactive.Div name="同页共创说明" style={{position: 'absolute', left: 996, top: 449, fontSize: 34, lineHeight: 1.7, opacity: interpolate(frame, [25, 43], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>从一次邀请，<br />到同一页上的共同补充。</Interactive.Div>
    <svg width="760" height="192" viewBox="0 0 760 192" style={{position: 'absolute', left: 996, top: 644}} aria-label="共创关系概念示意">
      <circle cx="58" cy="62" r="44" fill="#F6F5F0" stroke="#171A18" strokeWidth="3" />
      <text x="58" y="74" textAnchor="middle" fontSize="32" fill="#171A18">我</text>
      <path d="M116 62 H601" fill="none" stroke="#171A18" strokeWidth="3" pathLength="1" strokeDasharray="1" strokeDashoffset={interpolate(frame, [45, 79], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
      <path d="M584 50 L601 62 L584 74" fill="none" stroke="#171A18" strokeWidth="3" opacity={interpolate(frame, [76, 82], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
      <rect x="270" y="36" width="182" height="52" fill="#42DD91" opacity={interpolate(frame, [61, 80], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
      <text x="361" y="74" textAnchor="middle" fontSize="32" fill="#171A18" opacity={interpolate(frame, [66, 84], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}>同一页</text>
      <circle cx="678" cy="62" r="44" fill="#42DD91" stroke="#171A18" strokeWidth="3" opacity={interpolate(frame, [74, 90], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
      <text x="678" y="73" textAnchor="middle" fontSize="27" fill="#171A18" opacity={interpolate(frame, [80, 95], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}>同伴</text>
      <text x="7" y="171" fontSize="22" fill="#087D5D">共创关系示意 · 实际同步待实录</text>
    </svg>
    <div style={{position: 'absolute', left: 96, top: 884, fontSize: 22, color: '#087D5D'}}>组件测试截图 · 邀请弹窗局部放大</div>
  </AbsoluteFill>;
};

export const CinematicSample = () => <AbsoluteFill style={{backgroundColor: '#F6F5F0', color: '#171A18', fontFamily: '"DM Sans", "MiSans", "Microsoft YaHei", sans-serif'}}>
  <TransitionSeries>
    {/* 222 + 222 + 222 + 192 + 150 - 4 × 12 = 960 frames, 32 seconds. */}
    <TransitionSeries.Sequence durationInFrames={222} name="成果预告"><Opening duration={7.4} /></TransitionSeries.Sequence>
    <TransitionSeries.Transition presentation={fade()} timing={linearTiming({durationInFrames: 12})} />
    <TransitionSeries.Sequence durationInFrames={222} name="自然笔触"><Brushes /></TransitionSeries.Sequence>
    <TransitionSeries.Transition presentation={fade()} timing={linearTiming({durationInFrames: 12})} />
    <TransitionSeries.Sequence durationInFrames={222} name="V3 智能排版"><SmartLayout /></TransitionSeries.Sequence>
    <TransitionSeries.Transition presentation={fade()} timing={linearTiming({durationInFrames: 12})} />
    <TransitionSeries.Sequence durationInFrames={192} name="协作邀请"><Collaboration /></TransitionSeries.Sequence>
    <TransitionSeries.Transition presentation={fade()} timing={linearTiming({durationInFrames: 12})} />
    <TransitionSeries.Sequence durationInFrames={150} name="成果与队名"><Closing duration={5} /></TransitionSeries.Sequence>
  </TransitionSeries>
  <Soundtrack sample />
  <div style={{position: 'absolute', top: 28, right: 38, color: '#087D5D', backgroundColor: '#F6F5F0F5', border: '1px solid #D9DFD6', padding: '9px 15px', fontSize: 22}}>视觉样片 · 待替换实录</div>
</AbsoluteFill>;
