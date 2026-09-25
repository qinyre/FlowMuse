import {Composition} from 'remotion';
import {DemoVideo} from './Video';

export const Root = () => <>
  <Composition id="FlowMusePreview" component={DemoVideo} durationInFrames={4320} fps={15} width={1920} height={1080} defaultProps={{preview: true}} />
  <Composition id="FlowMuseClean" component={DemoVideo} durationInFrames={8640} fps={30} width={1920} height={1080} defaultProps={{preview: false}} />
</>;
