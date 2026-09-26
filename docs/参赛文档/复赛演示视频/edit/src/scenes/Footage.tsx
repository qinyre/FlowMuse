import {Video} from '@remotion/media';
import {AbsoluteFill, Easing, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import timeline from '../../../timeline.json';
import media from '../media.generated.json';
import {FeatureVisual} from './FeatureVisual';

export const Footage = ({scene}: {scene: typeof timeline.scenes[number]}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const seconds = frame / fps;
  const active = Math.max(0, scene.steps.findLastIndex(step => seconds >= step.at));
  const step: {at: number; label: string; screenLabel?: string; badge?: string} = scene.steps[active];
  const stepDuration = (scene.steps[active + 1]?.at ?? scene.duration) - step.at;
  const stepSeconds = seconds - step.at;
  const clip = (media.clips as Record<string, string | null>)[scene.id];
  const chapter = String(timeline.scenes.findIndex(item => item.id === scene.id)).padStart(2, '0');
  const action = !clip && scene.id === 'layout' && active === 5 && stepSeconds >= stepDuration / 2 ? '重做，恢复排版结果' : step.screenLabel ?? step.label;
  // Leave each result's final two seconds clear; recording length never changes playback speed.
  const guideEnd = Math.max(0, Math.min(clip ? 3.6 : stepDuration, stepDuration - 2));
  const guideOpacity = guideEnd > 0 ? interpolate(stepSeconds, [0, .25], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}) * interpolate(stepSeconds, [Math.max(0, guideEnd - .3), guideEnd], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}) : 0;
  const reveal = interpolate(frame, [0, 1.1 * fps], [0, 1], {easing: Easing.bezier(.16, 1, .3, 1), extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const wide = ['brushes', 'layout', 'collab'].includes(scene.id);
  const mirrored = ['recognition', 'openness'].includes(scene.id);

  const guide = <div style={{position: 'absolute', left: 100, right: 100, bottom: 186, display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 35, opacity: guideOpacity}}>
    <div style={{display: 'flex', alignItems: 'center', gap: 21, minHeight: 75, padding: clip ? '12px 24px' : '0', backgroundColor: clip ? '#F6F5F0F2' : 'transparent', borderLeft: clip ? '4px solid #42DD91' : undefined}}>
      <span style={{fontSize: 30, color: '#087D5D', fontWeight: 700, fontVariantNumeric: 'tabular-nums'}}>{String(active + 1).padStart(2, '0')}<span style={{color: '#69736C', fontWeight: 400, fontSize: 25}}> / {String(scene.steps.length).padStart(2, '0')}</span></span>
      <span style={{fontSize: clip ? 31 : 34, fontWeight: 700, color: '#171A18'}}>{action}</span>
      {step.badge && <span style={{fontSize: 25, color: '#087D5D', borderLeft: '2px solid #D9DFD6', paddingLeft: 21}}>{step.badge}</span>}
    </div>
    {!clip && <div style={{display: 'flex', gap: 10}}>{scene.steps.map((item, i) => <div key={item.at} style={{height: 6, width: i === active ? 54 : 24, backgroundColor: i <= active ? '#171A18' : '#D9DFD6'}} />)}</div>}
  </div>;

  if (clip) return <AbsoluteFill style={{backgroundColor: '#F6F5F0'}}>
    <Video src={staticFile(clip)} muted style={{width: '100%', height: '100%', objectFit: 'contain'}} />
    <div style={{position: 'absolute', top: 42, left: 70, borderLeft: '4px solid #42DD91', padding: '13px 24px', backgroundColor: '#F6F5F0F2', fontSize: 26, color: '#171A18', opacity: interpolate(seconds, [0, .3, 2.6, 3], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>{scene.title}</div>
    {guide}
  </AbsoluteFill>;

  return <AbsoluteFill style={{backgroundColor: '#F6F5F0', color: '#171A18', overflow: 'hidden'}}>
    <div style={{position: 'absolute', left: 100, top: 141, right: 100, height: 2, backgroundColor: '#D9DFD6'}} />
    <div style={{position: 'absolute', top: 78, left: 100, display: 'flex', alignItems: 'center', gap: 20, fontSize: 28}}><span style={{backgroundColor: '#42DD91', color: '#171A18', fontWeight: 700, padding: '4px 11px'}}>{chapter}</span><span style={{color: '#58655E'}}>{scene.title.split(' / ')[1]}</span></div>
    <div style={{position: 'absolute', top: 88, right: 100, fontSize: 25, color: '#69736C'}}>概念分镜 · 待录屏</div>
    <div style={{position: 'absolute', left: mirrored ? 1230 : 100, top: wide ? 174 : scene.id === 'harmony' ? 266 : 252, width: wide ? 1720 : 575, opacity: reveal, translate: `0 ${(1 - reveal) * 26}px`, fontSize: wide ? 72 : 78, lineHeight: 1.3, fontWeight: 700, letterSpacing: -2, whiteSpace: wide ? 'normal' : 'pre-line'}}>{wide ? scene.headline.replace('\n', '') : scene.headline}</div>
    {!wide && <div style={{position: 'absolute', left: mirrored ? 1234 : 104, top: 486, width: 95, height: 13, backgroundColor: '#42DD91', rotate: '-3deg', scale: `${reveal} 1`, transformOrigin: 'left center'}} />}
    <div style={{position: 'absolute', left: wide ? 210 : mirrored ? 40 : 585, top: wide ? 264 : scene.id === 'harmony' ? 150 : 166, width: wide ? 1500 : mirrored ? 1185 : 1240, height: wide ? 610 : 646, opacity: reveal, translate: `0 ${(1 - reveal) * 36}px`, transform: scene.id === 'layout' && active !== 2 ? 'translateY(-16px) scale(1.16)' : undefined}}>
      <FeatureVisual id={scene.id} active={active} stepSeconds={stepSeconds} stepDuration={stepDuration} />
    </div>
    {guide}
  </AbsoluteFill>;
};
