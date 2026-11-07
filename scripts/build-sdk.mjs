import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {root,cleanProduct,licenses,run} from './build-support.mjs';
import {version} from '../sdk/version.mjs';

export function buildSDK() {
  for(const target of ['js','wasm-gc']) run('moon',['build','--target',target,'--release','--deny-warn']);
  const destination=cleanProduct('sdk');
  for(const file of ['client.mjs','client.d.mts','version.mjs']) fs.copyFileSync(path.join(root,'sdk',file),path.join(destination,file));
  fs.copyFileSync(path.join(root,'_build/js/release/build/bridge/bridge.js'),path.join(destination,'bridge.js'));
  fs.copyFileSync(path.join(root,'_build/wasm-gc/release/build/bridge/bridge.wasm'),path.join(destination,'boxrir.wasm'));
  licenses(destination);
  const git=(args)=>spawnSync('git',args,{cwd:root,encoding:'utf8'}).stdout?.trim() || null;
  fs.writeFileSync(path.join(destination,'build-info.json'),JSON.stringify({version,source_revision:git(['rev-parse','HEAD']),working_tree_dirty:!!git(['status','--porcelain']),targets:['js','wasm-gc']},null,2)+'\n');
  return destination;
}
if(process.argv[1] && import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href) console.log(buildSDK());
