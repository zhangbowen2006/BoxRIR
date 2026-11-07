import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {root,cleanProduct,licenses} from './build-support.mjs';
import {buildSDK} from './build-sdk.mjs';
import {version} from '../sdk/version.mjs';
const sdk=buildSDK(), destination=cleanProduct('distribution');
fs.cpSync(sdk,path.join(destination,'sdk'),{recursive:true});
fs.cpSync(path.join(root,'bin'),path.join(destination,'bin'),{recursive:true});
fs.cpSync(path.join(root,'examples'),path.join(destination,'examples'),{recursive:true});
licenses(destination);
fs.copyFileSync(path.join(root,'docs/RUNTIME.md'),path.join(destination,'README.md'));
fs.writeFileSync(path.join(destination,'package.json'),JSON.stringify({name:'@boxrir/runtime',version,type:'module',private:true,engines:{node:'>=24'},exports:{'.':{types:'./sdk/client.d.mts',import:'./sdk/client.mjs'}}},null,2)+'\n');
const hashes={};
function visit(dir){for(const entry of fs.readdirSync(dir,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name))){const file=path.join(dir,entry.name);if(entry.isDirectory())visit(file);else hashes[path.relative(destination,file).split(path.sep).join('/')]=createHash('sha256').update(fs.readFileSync(file)).digest('hex');}}
visit(destination);
fs.writeFileSync(path.join(destination,'SHA256SUMS.json'),JSON.stringify(hashes,null,2)+'\n');
console.log(destination);
