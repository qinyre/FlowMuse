import {Audio} from '@remotion/media';
import {interpolate, Sequence, staticFile, useVideoConfig} from 'remotion';
import timeline from '../../timeline.json';

export const Soundtrack = ({sample = false, narration = false}: {sample?: boolean; narration?: boolean}) => {
  const {fps, durationInFrames} = useVideoConfig();
  let start = 0;
  const reveals = sample ? [4, 14, 29] : timeline.scenes.flatMap(scene => {
    const at = start;
    start += scene.duration;
    return scene.id === 'opening' ? [Math.min(6, Math.max(0, scene.duration - 3))] : ['layout', 'collab', 'closing'].includes(scene.id) ? [at] : [];
  });
  return <>
    <Audio src={staticFile('audio/emerald-ambient-demo.wav')} loop loopVolumeCurveBehavior="extend" volume={frame => interpolate(frame, [0, 1.2 * fps, durationInFrames - 1.5 * fps, durationInFrames - 1], [0, narration ? .2 : .4, narration ? .2 : .4, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
    {reveals.map(at => <Sequence key={at} from={Math.round(at * fps)} durationInFrames={Math.round(1.4 * fps)} layout="none"><Audio src={staticFile('audio/soft-reveal-demo.wav')} volume={.12} /></Sequence>)}
  </>;
};
