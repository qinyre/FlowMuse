import {Video} from '@remotion/media';
import {AbsoluteFill, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import timeline from '../../../timeline.json';
import media from '../media.generated.json';

export const Footage = ({scene}: {scene: typeof timeline.scenes[number]}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const active = Math.max(0, scene.steps.findLastIndex(step => frame >= step.at * fps));
  const clip = (media.clips as Record<string, string | null>)[scene.id];
  if (clip) return <AbsoluteFill style={{backgroundColor: '#FAFAF9'}}>
    <Video src={staticFile(clip)} muted style={{width: '100%', height: '100%', objectFit: 'contain'}} />
    <div style={{position: 'absolute', top: 42, left: 70, borderRadius: 12, padding: '14px 24px', backgroundColor: '#FAFAF9F2', fontSize: 28, color: '#1C1917', opacity: interpolate(frame / fps, [0, 0.4, 2.67, 3.33], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>{scene.title}</div>
  </AbsoluteFill>;
  return <AbsoluteFill style={{backgroundColor: '#FAFAF9', padding: '95px 115px 175px', display: 'flex', flexDirection: 'column', gap: 40}}>
    <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', borderBottom: '2px solid #E7E5E4', paddingBottom: 27}}>
      <div style={{fontSize: 32, color: '#059669', fontWeight: 600}}>{scene.title}</div>
      <div style={{fontSize: 25, color: '#57534E'}}>实机录屏位置 · {scene.duration} 秒</div>
    </div>
    <div style={{display: 'flex', gap: 80, flex: 1, minHeight: 0, alignItems: 'center'}}>
      <div style={{width: 580, flexShrink: 0}}>
        <div style={{fontSize: 90, lineHeight: 1.4, fontWeight: 700, letterSpacing: -2, whiteSpace: 'pre-line'}}>{scene.headline}</div>
        <div style={{fontSize: 32, lineHeight: 1.65, color: '#57534E', marginTop: 35}}>{scene.description}</div>
        <div style={{display: 'flex', gap: 12, marginTop: 48}}>{scene.steps.map((step, i) => <div key={step.at} style={{height: 5, flex: 1, backgroundColor: i <= active ? '#059669' : '#E7E5E4'}} />)}</div>
      </div>
      <div style={{flex: 1, border: '2px solid #E7E5E4', borderRadius: 28, padding: '45px 52px', backgroundColor: '#FFFFFF', minHeight: 510, display: 'flex', flexDirection: 'column', gap: 26}}>
        <div style={{display: 'flex', alignItems: 'baseline', gap: 22}}><span style={{fontSize: 76, color: '#059669', fontWeight: 300}}>0{active + 1}</span><span style={{fontSize: 26, color: '#57534E'}}>待录制 · 当前操作</span></div>
        <div style={{fontSize: 54, lineHeight: 1.25, fontWeight: 600}}>{scene.steps[active].label}</div>
        <div style={{fontSize: 32, lineHeight: 1.7, color: '#57534E', flex: 1}}>{scene.steps[active].detail}</div>
        <div style={{borderTop: '2px solid #E7E5E4', paddingTop: 22, fontSize: 24, color: '#57534E'}}>录制后替换：{scene.file}</div>
      </div>
    </div>
  </AbsoluteFill>;
};
