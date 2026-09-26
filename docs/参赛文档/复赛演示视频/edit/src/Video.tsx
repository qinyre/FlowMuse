import {Fragment} from 'react';
import {AbsoluteFill, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {Audio} from '@remotion/media';
import {loadFont} from '@remotion/fonts';
import {TransitionSeries, linearTiming} from '@remotion/transitions';
import {fade} from '@remotion/transitions/fade';
import {wipe} from '@remotion/transitions/wipe';
import type {Caption} from '@remotion/captions';
import timeline from '../../timeline.json';
import media from './media.generated.json';
import captions from './captions.generated.json';
import {Opening} from './scenes/Opening';
import {Footage} from './scenes/Footage';
import {Closing} from './scenes/Closing';
import {Soundtrack} from './Soundtrack';

void loadFont({family: 'DM Sans', url: staticFile('dm-sans-latin-400-normal.woff2'), weight: '400'});
void loadFont({family: 'DM Sans', url: staticFile('dm-sans-latin-700-normal.woff2'), weight: '700'});

export const DemoVideo = ({preview}: {preview: boolean}) => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const transitionFrames = Math.round(fps * 0.4);
  if (!preview && !media.ready) throw new Error('素材尚未齐全，请先查看 FlowMusePreview。补齐录屏、配音和队名后运行 npm run check:final。');
  const cue = (captions as Caption[]).find(c => frame / fps * 1000 >= c.startMs && frame / fps * 1000 < c.endMs);
  return <AbsoluteFill style={{backgroundColor: '#F6F5F0', color: '#171A18', fontFamily: '"DM Sans", "MiSans", "Microsoft YaHei", sans-serif'}}>
    <TransitionSeries>
      {timeline.scenes.map((scene, i) => <Fragment key={scene.id}>
        {i > 0 && (scene.id === 'layout' || scene.id === 'openness' ? <TransitionSeries.Transition presentation={wipe({direction: 'from-left'})} timing={linearTiming({durationInFrames: transitionFrames})} /> : <TransitionSeries.Transition presentation={fade()} timing={linearTiming({durationInFrames: transitionFrames})} />)}
        <TransitionSeries.Sequence durationInFrames={scene.duration * fps + (i < timeline.scenes.length - 1 ? transitionFrames : 0)} name={scene.title}>
          {scene.id === 'opening' ? <Opening duration={scene.duration + .4} /> : scene.id === 'closing' ? <Closing duration={scene.duration} /> : <Footage scene={scene} />}
        </TransitionSeries.Sequence>
      </Fragment>)}
    </TransitionSeries>
    {media.narration && <Audio src={staticFile(media.narration)} />}
    <Soundtrack narration={Boolean(media.narration)} />
    {preview && <>
      <div style={{position: 'absolute', top: 24, right: 35, fontSize: 22, letterSpacing: 1, color: '#536259', backgroundColor: '#F6F5F0F5', border: '1px solid #D9DFD6', borderRadius: 3, padding: '9px 15px'}}>分镜预演 · {media.narration ? '旁白字幕草案' : '尚未录音'}</div>
      {cue && <div style={{position: 'absolute', bottom: 44, left: 125, right: 125, display: 'flex', justifyContent: 'center'}}><div style={{fontSize: 36, lineHeight: 1.5, textAlign: 'center', color: '#171A18', backgroundColor: '#F6F5F0F5', borderTop: '2px solid #D9DFD6', padding: '15px 30px', maxWidth: 1610}}>{cue.text}</div></div>}
      <div style={{position: 'absolute', bottom: 0, left: 0, height: 3, backgroundColor: '#087D5D', width: `${frame / (durationInFrames - 1) * 100}%`}} />
    </>}
  </AbsoluteFill>;
};
