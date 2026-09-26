import {Composition} from 'remotion';
import {DemoVideo} from './Video';
import {CinematicSample} from './CinematicSample';
import timeline from '../../timeline.json';

const duration = timeline.scenes.reduce((sum, scene) => sum + scene.duration, 0);

export const Root = () => <>
  <Composition id="FlowMuseStyleSample" component={CinematicSample} durationInFrames={960} fps={30} width={1920} height={1080} />
  <Composition id="FlowMusePreview" component={DemoVideo} durationInFrames={duration * 15} fps={15} width={1920} height={1080} defaultProps={{preview: true}} />
  <Composition id="FlowMuseClean" component={DemoVideo} durationInFrames={duration * 30} fps={30} width={1920} height={1080} defaultProps={{preview: false}} />
</>;
