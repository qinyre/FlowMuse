import {Fragment} from 'react';
import {AbsoluteFill, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {Audio} from '@remotion/media';
import {loadFont} from '@remotion/fonts';
import {TransitionSeries, linearTiming} from '@remotion/transitions';
import {fade} from '@remotion/transitions/fade';
import type {Caption} from '@remotion/captions';
import timeline from '../../timeline.json';
import media from './media.generated.json';
import captions from './captions.generated.json';
import {Opening} from './scenes/Opening';
import {Footage} from './scenes/Footage';
import {Closing} from './scenes/Closing';

void loadFont({family: 'DM Sans', url: staticFile('dm-sans-latin-400-normal.woff2'), weight: '400'});
void loadFont({family: 'DM Sans', url: staticFile('dm-sans-latin-700-normal.woff2'), weight: '700'});

export const DemoVideo = ({preview}: {preview: boolean}) => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const transitionFrames = Math.round(fps * 0.4);
  if (!preview && !media.ready) throw new Error('素材尚未齐全，请先查看 FlowMusePreview。补齐录屏、配音和队名后运行 npm run check:final。');
  const cue = (captions as Caption[]).find(c => frame / fps * 1000 >= c.startMs && frame / fps * 1000 < c.endMs);
  return <AbsoluteFill style={{backgroundColor: '#FAFAF9', color: '#1C1917', fontFamily: '"DM Sans", "Microsoft YaHei", sans-serif'}}>
    <TransitionSeries>
      {timeline.scenes.map((scene, i) => <Fragment key={scene.id}>
        {i > 0 && <TransitionSeries.Transition presentation={fade()} timing={linearTiming({durationInFrames: transitionFrames})} />}
        <TransitionSeries.Sequence durationInFrames={scene.duration * fps + (i < timeline.scenes.length - 1 ? transitionFrames : 0)} name={scene.title}>
          {scene.id === 'opening' ? <Opening /> : scene.id === 'closing' ? <Closing /> : <Footage scene={scene} />}
        </TransitionSeries.Sequence>
      </Fragment>)}
    </TransitionSeries>
    {media.narration && <Audio src={staticFile(media.narration)} />}
    {preview && <>
      <div style={{position: 'absolute', top: 24, right: 35, fontSize: 22, letterSpacing: 1, color: '#57534E', backgroundColor: '#FAFAF9E8', border: '1px solid #E7E5E4', borderRadius: 7, padding: '9px 15px'}}>分镜预演 · {media.narration ? '旁白字幕草案' : '尚未录音'}</div>
      {cue && <div style={{position: 'absolute', bottom: 45, left: 125, right: 125, display: 'flex', justifyContent: 'center'}}><div style={{fontSize: 38, lineHeight: 1.5, textAlign: 'center', color: '#FFFFFF', backgroundColor: '#1C1917ED', borderRadius: 12, padding: '12px 28px', maxWidth: 1610}}>{cue.text}</div></div>}
      <div style={{position: 'absolute', bottom: 0, left: 0, height: 4, backgroundColor: '#059669', width: `${frame / (durationInFrames - 1) * 100}%`}} />
    </>}
  </AbsoluteFill>;
};
