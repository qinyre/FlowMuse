import {bundle} from '@remotion/bundler';
import {openBrowser, renderStill, selectComposition} from '@remotion/renderer';
import {resolve} from 'node:path';
import {mkdirSync, readFileSync} from 'node:fs';

const serveUrl = await bundle({entryPoint: resolve('src/index.ts')});
const browser = await openBrowser('chrome', {browserExecutable: 'C:/Program Files/Google/Chrome/Application/chrome.exe'});
try {
  const inputProps = {preview: true};
  const sample = process.argv.includes('--sample');
  const composition = await selectComposition({serveUrl, id: sample ? 'FlowMuseStyleSample' : 'FlowMusePreview', inputProps, puppeteerInstance: browser});
  mkdirSync('../output/stills', {recursive: true});
  let start = 0;
  const scenes = JSON.parse(readFileSync('../timeline.json', 'utf8')).scenes;
  const secondsToReview = scenes.flatMap(scene => {
    const offsets = scene.id === 'opening' ? [1, 4.5, 8]
      : scene.id === 'closing' ? [.6, 2, 3.3, 6]
      : scene.id === 'layout' ? [...scene.steps.map(step => step.at + 3), scene.duration - 2.5]
      : [scene.duration / 2];
    const seconds = offsets.filter(at => at < scene.duration).map(at => start + at);
    start += scene.duration;
    return seconds;
  });
  for (const seconds of sample ? [1, 3, 5.5, 10, 17, 24, 28, 30.5] : secondsToReview) {
    await renderStill({serveUrl, composition, inputProps, frame: Math.floor(seconds * composition.fps), output: `../output/stills/v4-${sample ? 'sample-' : ''}${seconds}.png`, puppeteerInstance: browser});
    console.log(`已渲染 ${seconds}s`);
  }
} finally {
  await browser.close({silent: true});
}
