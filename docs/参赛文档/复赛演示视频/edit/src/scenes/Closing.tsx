import {AbsoluteFill, Img, Interactive, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import timeline from '../../../timeline.json';

export const Closing = () => {
  const {fps} = useVideoConfig();
  const frame = useCurrentFrame() * 30 / fps;
  return <AbsoluteFill style={{backgroundColor: '#FAFAF9', padding: '130px 120px 170px', display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: 50}}>
    <div style={{display: 'flex', alignItems: 'center', gap: 35}}><Img src={staticFile('logo.png')} style={{width: 145, height: 145, borderRadius: 34}} /><span style={{fontSize: 80, fontWeight: 700}}>FlowMuse<span style={{color: '#059669'}}>.</span><span style={{fontSize: 40, marginLeft: 30, fontWeight: 400}}>流形白板</span></span></div>
    <Interactive.Div name="结束语" style={{fontSize: 102, fontWeight: 700, lineHeight: 1.4, maxWidth: 1630, opacity: interpolate(frame, [6, 26], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}), translate: interpolate(frame, [6, 26], ['0px 26px', '0px 0px'], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>自由书写，清晰整理，<span style={{color: '#059669'}}>一起共创。</span></Interactive.Div>
    <div style={{display: 'flex', gap: 45, alignItems: 'center', color: '#57534E', fontSize: 35}}><span>手写记录</span><span>→</span><span>AI 辅助整理</span><span>→</span><span>多端协作</span></div>
    <div style={{height: 2, backgroundColor: '#E7E5E4'}} />
    <div style={{fontSize: 28, color: '#57534E'}}>2026 鸿蒙高校创新赛{timeline.team ? ` · ${timeline.team}` : ''}</div>
  </AbsoluteFill>;
};
