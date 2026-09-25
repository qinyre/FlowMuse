import {Config} from '@remotion/cli/config';
import {existsSync} from 'node:fs';

const localChrome = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
if (existsSync(localChrome)) Config.setBrowserExecutable(localChrome);
Config.setConcurrency(3);
