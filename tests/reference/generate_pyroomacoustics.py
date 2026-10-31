"""Regenerate synthetic image-source fixtures through pyroomacoustics public API.

Requires pyroomacoustics==0.10.1. This is a development oracle only. It does not
copy the MoonBit image formula and does not compare sampled RIR waveforms.
"""
from importlib.metadata import version
from pathlib import Path
import json
import random

import numpy as np
import pyroomacoustics as pra

REFERENCE_VERSION = "0.10.1"
SEED = 20261031
WALLS = ("west", "east", "south", "north", "floor", "ceiling")
ROOT = Path(__file__).resolve().parent


def reference(scene):
    materials = pra.make_materials(**dict(zip(WALLS, scene["absorption"])))
    room = pra.ShoeBox(
        scene["room"],
        fs=scene["sample_rate"],
        materials=materials,
        max_order=scene["max_order"],
        air_absorption=False,
        ray_tracing=False,
        use_rand_ism=False,
        min_phase=False,
    )
    room.set_sound_speed(scene["speed"])
    room.add_source(scene["source"])
    room.add_microphone_array(np.array(scene["receivers"], dtype=float).T)
    room.image_source_model()
    assert room.wall_names == list(WALLS), room.wall_names
    source = room.sources[0]
    assert source.images.shape[0] == 3
    assert source.damping.shape == (1, source.images.shape[1])
    images = [
        {
            "image": [float(source.images[axis, i]) for axis in range(3)],
            "order": int(source.orders[i]),
            "reflection": float(source.damping[0, i]),
        }
        for i in range(source.images.shape[1])
    ]
    images.sort(key=lambda p: (p["order"], *p["image"]))
    assert len({tuple(p["image"]) for p in images}) == len(images)
    return images, str(source.images.dtype), str(source.damping.dtype)


def main():
    actual_version = version("pyroomacoustics")
    if actual_version != REFERENCE_VERSION:
        raise SystemExit(f"Expected pyroomacoustics {REFERENCE_VERSION}, found {actual_version}")
    baseline = {
        "room": [5.0, 4.0, 3.0],
        "source": [1.0, 1.0, 1.0],
        "receivers": [[3.0, 2.0, 1.5], [3.5, 2.5, 1.0]],
        "absorption": [0.19, 0.36, 0.51, 0.64, 0.75, 0.84],
        "sample_rate": 16000,
        "max_order": 0,
        "duration_ms": 1000,
        "speed": 343.0,
        "half_width": 16,
    }
    inputs = [(f"half_integer_order_{order}", {**baseline, "max_order": order}) for order in range(6)]
    inputs += [
        ("perfectly_reflecting_order_2", {**baseline, "absorption": [0.0] * 6, "max_order": 2}),
        ("perfectly_absorbing_order_2", {**baseline, "absorption": [1.0] * 6, "max_order": 2}),
    ]
    rng = random.Random(SEED)
    for i in range(24):
        dimensions = [round(rng.uniform(3.0, 12.0), 3) for _ in range(3)]
        def interior_point():
            return [round(rng.uniform(0.25, length - 0.25), 3) for length in dimensions]
        source = interior_point()
        receivers = []
        while len(receivers) < 2:
            point = interior_point()
            if sum((a - b) ** 2 for a, b in zip(source, point)) >= 0.1 ** 2:
                receivers.append(point)
        inputs.append((f"seeded_{i:02d}", {
            "room": dimensions,
            "source": source,
            "receivers": receivers,
            "absorption": [v / 100.0 for v in rng.sample(range(1, 95), 6)],
            "sample_rate": (8000, 16000, 48000)[i % 3],
            "max_order": i % 6,
            "duration_ms": 1000,
            "speed": (330.0, 343.0, 350.0)[i % 3],
            "half_width": 16,
        }))

    cases = []
    image_dtype = damping_dtype = None
    for name, scene in inputs:
        expected, image_dtype, damping_dtype = reference(scene)
        cases.append({"name": name, "scene": scene, "expected_images": expected})
    payload = {
        "schema_version": 1,
        "reference": {
            "package": "pyroomacoustics",
            "version": actual_version,
            "numpy_version": version("numpy"),
            "license": "MIT",
            "source": "https://github.com/LCAV/pyroomacoustics",
            "api": "ShoeBox + make_materials + add_source + add_microphone_array + image_source_model",
            "seed": SEED,
            "image_dtype": image_dtype,
            "damping_dtype": damping_dtype,
            "wall_order": list(WALLS),
        },
        "comparison": {
            "sort_key": ["order", "image[0]", "image[1]", "image[2]"],
            "image_abs_tolerance": 0.00002,
            "image_rel_tolerance": 0.0000002,
            "reflection_abs_tolerance": 0.0000001,
            "reflection_rel_tolerance": 0.000002,
            "order_tolerance": 0,
            "notes": "Compare complete geometric image sets, including zero-pressure reflections. The upstream image and damping arrays are float32; tolerances permit their rounding. No waveform/sample-kernel equality is claimed.",
        },
        "case_count": len(cases),
        "image_count": sum(len(case["expected_images"]) for case in cases),
        "cases": cases,
    }
    destination = ROOT / "pyroomacoustics-0.10.1.json"
    destination.write_text(json.dumps(payload, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(f"Generated {len(cases)} cases / {payload['image_count']} images using pyroomacoustics {actual_version}; {image_dtype}/{damping_dtype}")


if __name__ == "__main__":
    main()
