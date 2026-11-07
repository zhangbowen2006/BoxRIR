import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

export const root = fileURLToPath(new URL('../', import.meta.url));
// Cleanup is restricted to named build products. Refuse symlinked ancestors.
export function cleanProduct(name) {
  if (!['sdk','demo','distribution'].includes(name)) throw Error('Unknown build product');
  const build=path.resolve(root,'_build'), target=path.resolve(build,name);
  if (path.dirname(target)!==build || path.dirname(build)!==path.resolve(root)) throw Error('Unsafe build path');
  for (const entry of [root,build,target]) {
    if (fs.existsSync(entry) && fs.lstatSync(entry).isSymbolicLink()) throw Error('Refusing symlinked build path: '+entry);
  }
  fs.rmSync(target,{recursive:true,force:true});
  fs.mkdirSync(target,{recursive:true});
  return target;
}
export function run(program,args) {
  const result=spawnSync(program,args,{cwd:root,stdio:'inherit',shell:false});
  if (result.error) throw result.error;
  if (result.status!==0) throw Error(`${program} exited ${result.status}`);
}
export function licenses(destination) {
  for(const name of ['LICENSE','NOTICE']) fs.copyFileSync(path.join(root,name),path.join(destination,name));
  fs.cpSync(path.join(root,'docs/licenses'),path.join(destination,'licenses'),{recursive:true});
}
