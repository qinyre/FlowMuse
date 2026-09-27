import {Video} from '@remotion/media';
import {staticFile, useCurrentFrame, useVideoConfig} from 'remotion';

const screenEdge = {borderRadius: 10, outline: '2px solid #9AAF9F', boxShadow: '0 14px 32px #203C2926, 0 2px 5px #203C2914'};

// Every collaboration view reads the same timestamp of the supplied composite.
export const RecordedClip = ({id, clip, start = 0, width = 1720, height = 842, zoom = 1, origin = '50% 45%'}: {id: string; clip: string; start?: number; width?: number; height?: number; zoom?: number; origin?: string}) => {
  const {fps} = useVideoConfig();
  const seconds = useCurrentFrame() / fps + start;
  const video = {src: staticFile(clip), trimBefore: Math.round(start * fps), muted: true};
  if (id !== 'collab' || seconds < 12.1) {
    const ratio = id === 'collab' ? 1528 / 1080 : ['library', 'ai'].includes(id) ? 1280 / 842 : 1642 / 1080;
    const fittedWidth = Math.min(width, height * ratio);
    return <div style={{...screenEdge, position: 'absolute', left: '50%', top: '50%', translate: '-50% -50%', width: fittedWidth, height: fittedWidth / ratio, overflow: 'hidden', backgroundColor: '#FFFFFF'}}>
      <div style={{position: 'absolute', inset: 0, scale: zoom, transformOrigin: origin}}><Video {...video} objectFit="contain" style={{width: '100%', height: '100%'}} /></div>
    </div>;
  }
  const writing = seconds >= 17.7;
  const views = [
    {name: '鸿蒙 HarmonyOS', x: 0, y: 144, w: 1000, h: 558, crop: [298, 540, 842, 470]},
    {name: 'Android', x: 1040, y: 46, w: 680, h: 340, crop: writing ? [135, 80, 576, 355] : [0, 0, 714, 438]},
    {name: 'Web', x: 1040, y: 470, w: 680, h: 340, crop: writing ? [800, 80, 695, 355] : [720, 0, 808, 438]},
  ];
  return <div style={{position: 'absolute', width: 1720, height: 842, top: '50%', left: 0, transform: `translateY(-50%) scale(${width / 1720})`, transformOrigin: 'left center'}}>
    {views.map(({name, x, y, w, h, crop: [cx, cy, cw, ch]}) => {
      const scale = Math.min(w / cw, h / ch);
      return <div key={name} style={{position: 'absolute', left: x, top: y, width: w, height: h}}>
        <div style={{position: 'absolute', top: -43, fontSize: 27, color: '#087D5D', fontWeight: 700}}>{name}<span style={{display: 'inline-block', marginLeft: 18, width: 34, height: 4, backgroundColor: '#42DD91', verticalAlign: 'middle'}} /></div>
        <div style={{...screenEdge, position: 'absolute', inset: 0, overflow: 'hidden', backgroundColor: '#FCF8EF'}}>
          <div style={{position: 'absolute', left: (w - cw * scale) / 2, top: (h - ch * scale) / 2, width: cw * scale, height: ch * scale, overflow: 'hidden'}}><Video {...video} style={{position: 'absolute', maxWidth: 'none', width: 1528 * scale, height: 1080 * scale, left: -cx * scale, top: -cy * scale}} /></div>
        </div>
      </div>;
    })}
  </div>;
};
