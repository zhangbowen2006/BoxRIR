import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {describe_json} from '../_build/js/release/build/bridge/bridge.js';
const compare=(a,b)=>a.order-b.order||a.image[0]-b.image[0]||a.image[1]-b.image[1]||a.image[2]-b.image[2];
const near=(a,b,abs,rel)=>Math.abs(a-b)<=abs+rel*Math.abs(b);
for(const [filename,kind] of [['pyroomacoustics-0.10.1.json','upstream'],['bfs-images.json','bfs']]){
  const data=JSON.parse(fs.readFileSync(new URL('./reference/'+filename,import.meta.url)));
  test(`${kind} image-source differential: ${data.cases.length} scenes`,()=>{
    for(const fixture of data.cases){
      const result=JSON.parse(describe_json(JSON.stringify(fixture.scene)));
      assert.equal(result.ok,true,result.error);
      const actual=result.images.toSorted(compare),expected=fixture.expected_images.toSorted(compare);
      assert.equal(actual.length,expected.length);
      for(let i=0;i<actual.length;i++){
        assert.equal(actual[i].order,expected[i].order);
        for(let axis=0;axis<3;axis++)assert.ok(near(actual[i].image[axis],expected[i].image[axis],kind==='bfs'?0:2e-5,kind==='bfs'?0:2e-7),JSON.stringify({i,actual:actual[i],expected:expected[i]}));
        if(kind==='bfs')assert.deepEqual(actual[i].bounces,expected[i].bounces);
        else assert.ok(near(actual[i].reflection,expected[i].reflection,1e-7,2e-6));
      }
    }
  });
}
