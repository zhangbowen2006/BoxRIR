"""Run only AFTER publication: consume the exact registry release, no workspace."""
import hashlib, io, json, os, re, subprocess, sys, tempfile, urllib.request, zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
manifest=(root/'moon.mod').read_text(encoding='utf-8')
module=re.search(r'^name\s*=\s*"([^"]+)"',manifest,re.M)[1]
version=re.search(r'^version\s*=\s*"([^"]+)"',manifest,re.M)[1]
parent=root/'generated/registry-consumer';parent.mkdir(parents=True,exist_ok=True)
assert not os.environ.get('MOONCAKES_REGISTRY'), 'verify the default official registry explicitly'
folder=Path(tempfile.mkdtemp(prefix='registry-',dir=parent))
assert not any((ancestor/'moon.work').exists() for ancestor in (folder,*folder.parents))
(folder/'moon.mod').write_text('name = "boxrir_registry/consumer"\n',encoding='utf-8')
(folder/'moon.pkg').write_text('import { "'+module+'" @boxrir, "'+module+'/io" @wav } for "test"\n',encoding='utf-8')
(folder/'consumer_test.mbt').write_text((root/'scripts/consumer-tests.mbt.txt').read_text(encoding='utf-8'),encoding='utf-8')
subprocess.run(['moon','add',module+'@'+version],cwd=folder,check=True)
installed=folder/'.mooncakes'/module
assert installed.exists(), 'registry dependency must be downloaded into the consumer dependency directory'
installed_manifest=(installed/'moon.mod').read_text(encoding='utf-8')
assert re.search(r'^version\s*=\s*"([^"]+)"',installed_manifest,re.M)[1]==version
assert re.search(r'^name\s*=\s*"([^"]+)"',installed_manifest,re.M)[1]==module
assert installed.resolve()!=root.resolve(), 'must not resolve the working source checkout'
index=Path(os.environ.get('MOON_HOME',str(Path.home()/'.moon')))/'registry/index/user'/(module+'.index')
record=next(row for line in index.read_text(encoding='utf-8').splitlines() if (row:=json.loads(line)).get('version')==version)
assert not record.get('yanked',False)
archive_url='https://download.mooncakes.io/user/'+module+'/'+version+'.zip'
archive_bytes=urllib.request.urlopen(archive_url,timeout=60).read()
assert hashlib.sha256(archive_bytes).hexdigest()==record['checksum'], 'anonymous archive must match exact registry checksum'
cached_archive=index.parents[3]/'cache'/module/(version+'.zip')
assert hashlib.sha256(cached_archive.read_bytes()).hexdigest()==record['checksum'], 'installed cache must match registry'
with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
    for name in archive.namelist():
        if not name.endswith('/'):
            assert archive.read(name)==(installed/name).read_bytes(), name
checks=[]
targets=['js','wasm','wasm-gc']+(['native'] if sys.platform=='linux' else [])
for target in targets:
    subprocess.run(['moon','test','--target',target,'--deny-warn'],cwd=folder,check=True)
    checks.append({'target':target,'consumer_tests':4,'passed':True})
result={'module':module,'version':version,'source':'exact Mooncakes registry dependency; no local workspace','registry_checksum':record['checksum'],'anonymous_archive_url':archive_url,'anonymous_archive_checksum_verified':True,'installed_core_matches_archive':True,'downloaded_manifest_verified':True,'checks':checks}
(parent/'verification.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result))
