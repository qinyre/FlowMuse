import {Video} from '@remotion/media';
import {AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import timeline from '../../../timeline.json';
import media from '../media.generated.json';
import {FeatureVisual} from './FeatureVisual';

// Reuse recorded results in the hook and recap; labelled references remain visible until recording.
export const ProofShot = ({id, title, closing = false}: {id: 'brushes' | 'layout' | 'collab'; title: string; closing?: boolean}) => {
  const {fps} = useVideoConfig();
  const frame = useCurrentFrame();
  const scene = timeline.scenes.find(s => s.id === id)!;
  const clip = (media.clips as Record<string, string | null>)[id];
  const step = id === 'brushes' ? 1 : id === 'layout' ? (closing ? 4 : 2) : 3;
  const start = Math.min(scene.steps[step].at + 2, Math.max(0, scene.duration - 4));
  const source = id === 'brushes' ? '历史实机截图 · Android · 2026.09.22' : id === 'layout' ? '历史界面截图 · 2026.09.20' : '协作流程示意 · 待实录';
  const arrival = interpolate(frame, [0, fps * .45], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.out(Easing.cubic)});
  return <AbsoluteFill style={{backgroundColor: '#F6F5F0', color: '#171A18', overflow: 'hidden'}}>
    <div style={{position: 'absolute', top: 110, left: 104, color: '#536259', fontSize: 28}}>{closing ? '从这一页，继续创作' : '一页笔记，可以走多远？'}</div>
    <div style={{position: 'absolute', left: 99, top: 272, width: 630, fontSize: 101, fontWeight: 500, lineHeight: 1.45, whiteSpace: 'pre-line', opacity: arrival, transform: `translateX(${(1 - arrival) * -28}px)`}}>{title}</div>
    <div style={{position: 'absolute', left: 108, top: 600, width: 410, height: 14, backgroundColor: '#42DD91', scale: `${arrival} 1`, transformOrigin: 'left'}} />
    <div style={{position: 'absolute', left: 720, top: 144, width: 1092, height: 728, display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden', transform: `translateY(${(1 - arrival) * 22}px)`, opacity: arrival}}>
      {clip ? <Video src={staticFile(clip)} trimBefore={Math.round(start * fps)} muted style={{width: '100%', height: '100%', objectFit: 'contain'}} /> : id === 'collab' ? <FeatureVisual id="collab" active={3} /> : <Img src={staticFile(`style-screens/${id === 'brushes' ? 'brush-palette' : 'smart-layout-v3'}.png`)} style={{width: '100%', height: '100%', objectFit: 'contain'}} />}
    </div>
    {!clip && <div style={{position: 'absolute', left: 735, top: 884, fontSize: 23, color: '#536259'}}>{source}</div>}
  </AbsoluteFill>;
};
