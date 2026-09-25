import {Video} from '@remotion/media';
import {staticFile} from 'remotion';

export const Opening = () => <Video src={staticFile('intro.mp4')} muted style={{width: '100%', height: '100%'}} />;
