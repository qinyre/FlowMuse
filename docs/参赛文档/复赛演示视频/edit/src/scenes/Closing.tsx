import {AbsoluteFill, Easing, Img, interpolate, Sequence, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import timeline from '../../../timeline.json';
import {ProofShot} from './ProofShot';

const BrandClose = () => {
  const {fps} = useVideoConfig();
  const t = useCurrentFrame() / fps;
  const enter = (delay: number) => interpolate(t, [delay, delay + .9], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.out(Easing.cubic)});
  const drawn = interpolate(t, [.2, 1.4], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return <AbsoluteFill style={{backgroundColor: '#F6F5F0', color: '#171A18', overflow: 'hidden'}}>
    <div style={{position: 'absolute', left: 106, top: 108, fontSize: 29, color: '#536259'}}>一起写下的，成为我们的。</div>
    <svg viewBox="0 0 1920 1080" width="1920" height="1080" style={{position: 'absolute', inset: 0}} aria-hidden="true">
      <path d="M1357 252 C1506 161 1705 309 1588 399 C1469 478 1335 359 1435 313 C1537 268 1555 402 1462 456 C1415 486 1372 493 1372 544 L1372 686 L1728 686 L1728 424 L1667 363 L1520 363 M1667 363 V424 H1728 M1430 530 H1667 M1430 579 H1667 M1430 628 H1587" fill="none" stroke="#171A18" strokeWidth="7" strokeLinecap="round" pathLength="1" strokeDasharray="1" strokeDashoffset={drawn} />
      <path d="M111 644 C359 628 631 655 1097 638" fill="none" stroke="#42DD91" strokeWidth="21" strokeLinecap="round" pathLength="1" strokeDasharray="1" strokeDashoffset={drawn} />
    </svg>
    <div style={{position: 'absolute', left: 99, top: 245, fontSize: 139, fontWeight: 500, lineHeight: 1.42, letterSpacing: -4}}>
      {['把想法，', '留在同一页。'].map((line, i) => <div key={line} style={{opacity: enter(i * .1), translate: `${(1 - enter(i * .1)) * -38}px 0`}}>{line}</div>)}
    </div>
    <div style={{position: 'absolute', left: 106, top: 790, display: 'flex', alignItems: 'center', gap: 25, opacity: enter(.25)}}><Img src={staticFile('logo.png')} style={{width: 69, height: 69, borderRadius: 14}} /><span style={{fontSize: 76, fontWeight: 700, letterSpacing: -3}}>FlowMuse</span><span style={{fontSize: 27, color: '#536259', marginLeft: 10}}>流形白板</span></div>
    <div style={{position: 'absolute', right: 108, top: 751, width: 600, padding: '23px 36px', backgroundColor: '#42DD91', opacity: enter(.35)}}><div style={{fontSize: 51, fontWeight: 500}}>{timeline.team}</div><div style={{fontSize: 24, marginTop: 8}}>2026 鸿蒙高校创新赛</div></div>
  </AbsoluteFill>;
};

export const Closing = ({duration = 8}: {duration?: number}) => {
  const {fps} = useVideoConfig();
  const recap = Math.round(Math.min(4, Math.max(0, duration - 3)) * fps);
  const cut = Math.floor(recap / 3);
  if (cut < 1) return <BrandClose />;
  return <AbsoluteFill>
    <Sequence durationInFrames={cut}><ProofShot id="brushes" title={'留下笔迹，'} closing /></Sequence>
    <Sequence from={cut} durationInFrames={cut}><ProofShot id="layout" title={'整理成页，'} closing /></Sequence>
    <Sequence from={cut * 2} durationInFrames={recap - cut * 2}><ProofShot id="collab" title={'共同完善。'} closing /></Sequence>
    <Sequence from={recap}><BrandClose /></Sequence>
  </AbsoluteFill>;
};
