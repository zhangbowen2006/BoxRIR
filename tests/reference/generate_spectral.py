"""Independent first-order geometry + SciPy FIR/convolution oracle.

Does not import or call BoxRIR. Atmospheric equations call pinned upstream code
with explicitly percentage-valued RH; this is numerical parity, not certification.
"""
import base64, hashlib, importlib.util, json, math, urllib.request
from pathlib import Path
import numpy as np
from scipy.signal import firwin, fftconvolve

ROOT=Path(__file__).resolve().parents[2]
CENTERS=np.array([125.,250.,500.,1000.,2000.,4000.])
def atmosphere_module():
    manifest=json.loads((ROOT/'docs/provenance/python-acoustics.json').read_text())
    record=manifest['files']['acoustics/standards/iso_9613_1_1993.py']
    source=ROOT/'generated/atmosphere-reference/iso_9613_1_1993.py'
    source.parent.mkdir(parents=True,exist_ok=True)
    if not source.exists():
        source.write_bytes(urllib.request.urlopen(record['url'],timeout=30).read())
    assert hashlib.sha256(source.read_bytes()).hexdigest()==record['sha256']
    spec=importlib.util.spec_from_file_location('pinned_acoustics',source)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module

def air_loss(conditions):
    code=atmosphere_module()
    temperature=conditions['temperature_c']+273.15
    pressure=conditions.get('pressure_kpa',101.325)
    h=code.molar_concentration_water_vapour(conditions['relative_humidity_percent'],code.saturation_pressure(temperature),pressure)
    oxygen=code.relaxation_frequency_oxygen(pressure,h)
    nitrogen=code.relaxation_frequency_nitrogen(pressure,temperature,h)
    return code.attenuation_coefficient(pressure,temperature,101.325,293.15,nitrogen,oxygen,CENTERS)

def independent_rir(scene):
    fs=scene['sample_rate'];half=scene.get('half_width',16);bank_half=scene.get('band_filter_half_width',256)
    frames=math.ceil(fs*scene['duration_ms']/1000);base_frames=frames+2*half
    material=np.asarray(scene['band_absorption']);speed=scene.get('speed',343)
    air=air_loss(scene['atmosphere']) if 'atmosphere' in scene else np.asarray(scene.get('air_db_per_m',[0]*6))
    low=[firwin(2*bank_half+1,float(f),fs=fs,window='hamming',scale=True) for f in np.sqrt(CENTERS[:-1]*CENTERS[1:])]
    delta=np.zeros(2*bank_half+1);delta[bank_half]=1
    filters=[low[0]]+[low[i]-low[i-1] for i in range(1,5)]+[delta-low[-1]]
    # First-order analytic plane images, no BoxRIR mirror-index implementation.
    images=[(np.asarray(scene['source'],float),None)]
    assert scene['max_order'] in (0,1)
    if scene['max_order']==1:
        for axis,length in enumerate(scene['room']):
            for side in (0,1):
                image=np.asarray(scene['source'],float).copy();image[axis]=2*side*length-image[axis]
                images.append((image,2*axis+side))
    result=[]
    for receiver in scene['receivers']:
        bands=np.zeros((6,base_frames))
        for image,wall in images:
            distance=np.linalg.norm(image-receiver);arrival=distance/speed*fs
            if arrival>=frames:continue
            gain=np.exp(-math.log(10)*air*distance/20)/(4*math.pi*distance)
            if wall is not None:gain*=np.sqrt(1-material[wall])
            position=math.floor(arrival);fraction=arrival-position
            t=np.arange(-half,half+1,dtype=float)-fraction
            taps=np.sinc(t)*.5*(1+np.cos(np.pi*t/half));taps[np.abs(t)>half]=0;taps/=taps.sum()
            bands[:,position:position+len(taps)]+=gain[:,None]*taps
        result.append(sum(fftconvolve(band,kernel) for band,kernel in zip(bands,filters)))
    return np.asarray(result),air

if __name__=='__main__':
    cases=[]
    base=dict(model='octave_bands',room=[6.,4.,3.],source=[1.37,1.21,1.13],receivers=[[3.82,2.31,1.74],[2.43,1.57,1.42]],sample_rate=16000,max_order=1,duration_ms=25,band_absorption=[[.1,.2,.3,.4,.5,.6]]*6)
    for index in range(12):
        scene={**base,'max_order':index%2}
        scene['band_absorption']=(np.full((6,6),.2) if index==0 else np.random.default_rng(20261109+index).uniform(0,1,(6,6))).tolist()
        if index%3==0:scene['atmosphere']=dict(temperature_c=[-20,20,50,0][index//3],relative_humidity_percent=50,pressure_kpa=101.325)
        elif index%3==1:scene['air_db_per_m']=[0.,.01,.02,.03,.04,.05]
        if index>=8:scene.update(sample_rate=[32000,44100,48000,96000][index-8],duration_ms=10)
        expected,air=independent_rir(scene)
        raw=np.asarray(expected,dtype='<f8').tobytes()
        cases.append(dict(name=f'spectral-{index:02d}',scene=scene,channels=len(expected),frames=expected.shape[1],float64_le=base64.b64encode(raw).decode(),sha256=hashlib.sha256(raw).hexdigest(),air_db_per_m=air.tolist()))
    atmospheric=[]
    for temperature in (-20,0,20,50):
        for humidity in (10,50,100):
            for pressure in (80.,101.325,110.):
                conditions=dict(temperature_c=temperature,relative_humidity_percent=humidity,pressure_kpa=pressure)
                atmospheric.append(dict(input=conditions,expected=air_loss(conditions).tolist()))
    data=dict(reference='SciPy firwin + fftconvolve, first-order analytic geometry, pinned Python Acoustics air equations',cases=cases,atmosphere=atmospheric)
    text=json.dumps(data,indent=2)+'\n'
    (ROOT/'tests/reference/spectral.json').write_text(text,encoding='utf-8',newline='\n')
    (ROOT/'cmd/reference-parity/spectral-fixtures.mbt').write_text('// GENERATED independent test data, not implementation LOC.\n///|\nlet spectral_fixture_text : String =\n'+'\n'.join('  #|'+line for line in text.splitlines())+'\n',encoding='utf-8',newline='\n')
    print(json.dumps(dict(cases=len(cases),samples=sum(c['channels']*c['frames'] for c in cases),atmospheric_cases=len(atmospheric),at_20C_50percent=air_loss(dict(temperature_c=20,relative_humidity_percent=50)).tolist())))
