import fs from 'node:fs';import path from 'node:path';
const destination=path.resolve('_build/demo');fs.mkdirSync(path.join(destination,'examples'),{recursive:true});
for(const name of ['index.html','app.mjs','worker.mjs'])fs.copyFileSync('web/'+name,path.join(destination,name));
fs.copyFileSync('_build/js/release/build/bridge/bridge.js',path.join(destination,'bridge.js'));
for(const name of ['stereo.json','wall-before.json','wall-after.json','array.json','probe.wav'])fs.copyFileSync('examples/'+name,path.join(destination,'examples',name));
console.log(destination);
