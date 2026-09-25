import {bundle} from '@remotion/bundler';
import {openBrowser, renderStill, selectComposition} from '@remotion/renderer';
import {resolve} from 'node:path';
import {mkdirSync} from 'node:fs';

const serveUrl = await bundle({entryPoint: resolve('src/index.ts')});
const browser = await openBrowser('chrome', {browserExecutable: 'C:/Program Files/Google/Chrome/Application/chrome.exe'});
try {
  const inputProps = {preview: true};
  const composition = await selectComposition({serveUrl, id: 'FlowMusePreview', inputProps, puppeteerInstance: browser});
  mkdirSync('../output/stills', {recursive: true});
  for (const seconds of [5, 16, 46, 80, 125, 168, 221, 246, 275, 284]) {
    await renderStill({serveUrl, composition, inputProps, frame: seconds * composition.fps, output: `../output/stills/${seconds}.png`, puppeteerInstance: browser});
    console.log(`已渲染 ${seconds}s`);
  }
} finally {
  await browser.close({silent: true});
}
