import {Video} from '@remotion/media';
import {staticFile, useVideoConfig} from 'remotion';
import {TransitionSeries, linearTiming} from '@remotion/transitions';
import {fade} from '@remotion/transitions/fade';
import {ProofShot} from './ProofShot';

export const Opening = ({duration = 10.4}: {duration?: number}) => {
  const {fps} = useVideoConfig();
  const overlap = Math.round(.2 * fps);
  const beat = Math.round(Math.min(6, Math.max(0, duration - 3.4)) / 2 * fps);
  if (beat <= overlap) return <Video src={staticFile('intro-v4.mp4')} muted style={{width: '100%', height: '100%'}} />;
  return <TransitionSeries>
    <TransitionSeries.Sequence durationInFrames={beat + overlap}><ProofShot id="layout" title={'先看排版，\n再做决定。'} /></TransitionSeries.Sequence>
    <TransitionSeries.Transition presentation={fade()} timing={linearTiming({durationInFrames: overlap})} />
    <TransitionSeries.Sequence durationInFrames={beat + overlap}><ProofShot id="collab" title={'一起共创，\n看清贡献。'} /></TransitionSeries.Sequence>
    <TransitionSeries.Transition presentation={fade()} timing={linearTiming({durationInFrames: overlap})} />
    <TransitionSeries.Sequence durationInFrames={Math.round(duration * fps) - 2 * beat}><Video src={staticFile('intro-v4.mp4')} muted style={{width: '100%', height: '100%'}} /></TransitionSeries.Sequence>
  </TransitionSeries>;
};
