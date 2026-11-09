import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

export function sourceProvenance(directory) {
  const unknown={source_revision:null,working_tree_dirty:null,provenance:'unknown'};
  const git=args=>spawnSync('git',args,{cwd:directory,encoding:'utf8',windowsHide:true});
  const top=git(['rev-parse','--show-toplevel']);
  if(top.status!==0 || !top.stdout?.trim())return unknown;
  if(fs.realpathSync(top.stdout.trim())!==fs.realpathSync(path.resolve(directory)))return unknown;
  const head=git(['rev-parse','HEAD']),status=git(['status','--porcelain']);
  if(head.status!==0 || status.status!==0)return unknown;
  return {source_revision:head.stdout.trim(),working_tree_dirty:status.stdout.trim().length>0,provenance:'git'};
}
