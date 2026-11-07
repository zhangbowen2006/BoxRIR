import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
export const sha256=data=>createHash('sha256').update(data).digest('hex');

/** Exclusive directory claim; completion manifest is the last payload written.
 * Roll back only files created by this invocation. Power loss may leave the
 * explicit incomplete marker; no result is complete while that marker exists.
 */
export function publishBundle(directory,files,metadata) {
  directory=path.resolve(directory);
  const entries=[['.boxrir-incomplete','Incomplete BoxRIR result. Do not consume.\n'],...files];
  const names=entries.map(([name])=>name);
  if(new Set(names).size!==names.length || names.some(name=>path.basename(name)!==name || ['.','..','run-manifest.json'].includes(name))) throw Error('Invalid bundle file name');
  fs.mkdirSync(path.dirname(directory),{recursive:true});
  try { fs.mkdirSync(directory); }
  catch(error) { if(error.code==='EEXIST') throw Error('Output directory already exists: '+directory); throw error; }
  const owner=fs.lstatSync(directory),created=[];
  const identity=(a,b)=>a.dev===b.dev && a.ino===b.ino;
  function write(name,data) {
    const file=path.join(directory,name),fd=fs.openSync(file,'wx');
    created.push({file,stat:fs.fstatSync(fd)});
    try {fs.writeFileSync(fd,data);fs.fsyncSync(fd);} finally {fs.closeSync(fd);}
  }
  try {
    for(const [name,data] of entries) write(name,data);
    const manifest={schema_version:1,state:'complete',...metadata,files:Object.fromEntries(files.map(([name,data])=>[name,{bytes:Buffer.byteLength(data),sha256:sha256(data)}]))};
    write('run-manifest.json',JSON.stringify(manifest,null,2)+'\n');
    fs.unlinkSync(path.join(directory,'.boxrir-incomplete'));
    return manifest;
  } catch(error) {
    let rollbackFailed=false;
    try {
      if(!identity(fs.lstatSync(directory),owner)) throw Error('Output directory identity changed');
      for(const {file,stat} of created.toReversed()) {
        if(fs.existsSync(file) && identity(fs.lstatSync(file),stat)) fs.unlinkSync(file);
        else rollbackFailed=true;
      }
      // An unexpected file is never removed; rmdir only succeeds when empty.
      fs.rmdirSync(directory);
    } catch {rollbackFailed=true;}
    throw new Error(`Output write failed${rollbackFailed?'; rollback incomplete, inspect the output directory':''}: ${error.message}`,{cause:error});
  }
}
