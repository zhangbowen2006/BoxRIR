"""Independent finite-wall visibility oracle using pyroomacoustics public APIs.

Synthetic fixtures; no measured rooms. Run with pyroomacoustics==0.10.1.
This script never uses BoxRIR's plane reflection or backtrace implementation.
"""
import json
from pathlib import Path
import numpy as np
import pyroomacoustics as pra

assert pra.__version__ == '0.10.1'
shapes = [
    ('rectangle', [[0, 0], [6, 0], [6, 4], [0, 4]]),
    ('trapezoid', [[0, 0], [6, 0], [5, 4], [0, 4]]),
    ('triangle', [[0, 0], [7, 0], [0, 6]]),
    ('pentagon', [[0, 0], [5, 0], [7, 3], [4, 6], [0, 4]]),
]
cases = []
for name, vertices in shapes:
    for order in range(5):
        wall_count = len(vertices)
        absorption = [0.11 + 0.07 * i for i in range(wall_count + 2)]
        corners = np.asarray(vertices, dtype=float).T
        room = pra.Room.from_corners(corners, fs=16000, max_order=order,
                                     materials=[pra.Material(a) for a in absorption[:wall_count]])
        room.extrude(3.0, materials={'floor': pra.Material(absorption[-2]), 'ceiling': pra.Material(absorption[-1])})
        source = [1.37, 1.21, 1.13]
        receivers = [[2.82, 2.31, 1.74], [2.43, 1.57, 1.42]]
        room.add_source(source)
        room.add_microphone_array(np.asarray(receivers).T)
        room.image_source_model()
        sound = room.sources[0]
        expected = []
        for receiver in range(len(receivers)):
            for i in range(sound.images.shape[1]):
                if room.visibility[0][receiver, i]:
                    expected.append({'receiver': receiver, 'order': int(sound.orders[i]),
                                     'image': sound.images[:, i].astype(float).tolist(),
                                     'reflection': float(sound.damping[0, i])})
        scene = {'footprint': vertices, 'height': 3, 'source': source, 'receivers': receivers,
                 'absorption': absorption, 'sample_rate': 16000, 'max_order': order, 'duration_ms': 200}
        cases.append({'name': name + '-order-' + str(order), 'scene': scene, 'expected_paths': expected})
report = {'reference': 'pyroomacoustics', 'version': pra.__version__, 'numpy': np.__version__,
          'scope': 'image geometry, reflection damping and finite-face microphone visibility; not waveform or field accuracy', 'cases': cases}
target = Path(__file__).with_name('prism-pyroomacoustics-0.10.1.json')
target.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
print(json.dumps({'cases': len(cases), 'paths': sum(len(c['expected_paths']) for c in cases)}))
