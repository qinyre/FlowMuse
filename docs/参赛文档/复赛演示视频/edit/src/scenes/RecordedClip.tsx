import {Video} from '@remotion/media';
import {useId} from 'react';
import {staticFile, useCurrentFrame, useVideoConfig} from 'remotion';

const screenEdge = {borderRadius: 10, outline: '2px solid #9AAF9F', boxShadow: '0 14px 32px #203C2926, 0 2px 5px #203C2914'};
// Only the composite's unused margins may become transparent; the three app interiors are protected.
const margins = `data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1528 1080"><path fill="white" fill-rule="evenodd" d="M0 0H1528V1080H0Z M0 0H720V508H0Z M720 0H1464V518H720Z M298 526H1140V1080H298Z"/></svg>')}`;

// Keep the supplied collaboration composite intact so all three screens remain visible and synchronized.
export const RecordedClip = ({id, clip, start = 0, width = 1720, height = 842, zoom = 1, origin = '50% 45%'}: {id: string; clip: string; start?: number; width?: number; height?: number; zoom?: number; origin?: string}) => {
  const {fps} = useVideoConfig();
  const frame = useCurrentFrame();
  const composite = id === 'collab' && frame / fps + start >= 12.1;
  const matteId = `collab-matte-${useId().replaceAll(':', '')}`;
  const video = {src: staticFile(clip), trimBefore: Math.round(start * fps), muted: true};
  const ratio = id === 'collab' ? 1528 / 1080 : ['library', 'ai'].includes(id) ? 1280 / 842 : 1642 / 1080;
  const fittedWidth = Math.min(width, height * ratio);
  return <div style={{...screenEdge, position: 'absolute', left: '50%', top: '50%', translate: '-50% -50%', width: fittedWidth, height: fittedWidth / ratio, overflow: 'hidden', backgroundColor: id === 'collab' ? '#D6E1D9' : '#FFFFFF'}}>
    {composite && <svg width="0" height="0" aria-hidden="true"><defs><filter id={matteId} x="0%" y="0%" width="100%" height="100%" colorInterpolationFilters="sRGB">
      <feColorMatrix in="SourceGraphic" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  -85 -85 -85 0 5" result="black" />
      <feImage href={margins} x="0" y="0" width="100%" height="100%" preserveAspectRatio="none" result="margins" />
      <feComposite in="black" in2="margins" operator="in" result="matte" />
      <feComposite in="SourceGraphic" in2="matte" operator="out" />
    </filter></defs></svg>}
    <div style={{position: 'absolute', inset: 0, scale: id === 'collab' ? 1 : zoom, transformOrigin: origin}}><Video {...video} objectFit="contain" style={{width: '100%', height: '100%', filter: composite ? `url(#${matteId})` : undefined}} /></div>
  </div>;
};
