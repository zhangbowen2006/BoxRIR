import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {sourceProvenance} from '../scripts/provenance.mjs';
test('unpacked or nested sources never inherit the parent repository identity',()=>{
  const folder=fs.mkdtempSync(path.resolve('generated/provenance-test-'));
  const result=sourceProvenance(folder);
  assert.deepEqual(result,{source_revision:null,working_tree_dirty:null,provenance:'unknown'});
  const real=sourceProvenance(path.resolve('.'));assert.equal(real.provenance,'git');assert.match(real.source_revision,/^[a-f0-9]{40}$/);
});
