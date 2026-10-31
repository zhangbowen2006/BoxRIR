"""Independent shortest-reflection-word oracle, using only Python stdlib.

Images are obtained by reflecting coordinates in each of the six fixed wall
planes and breadth-first deduplicating positions. No image-index formula or
abs(n-p) wall-count formula is used. Integer half-metre coordinates avoid float
hashing. Shortest equal-depth words must have the same per-wall counts.
"""
from collections import deque
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent
ROOM = (10, 8, 6)  # 0.5 m units
SOURCE = (2, 3, 2)
KNOWN_COUNTS = (1, 7, 25, 63, 129)


def reflected_images(max_order):
    seen = {SOURCE: (0, (0,) * 6)}
    queue = deque([SOURCE])
    while queue:
        position = queue.popleft()
        order, bounces = seen[position]
        if order == max_order:
            continue
        for wall in range(6):
            axis = wall // 2
            candidate = list(position)
            candidate[axis] = -candidate[axis] if wall % 2 == 0 else 2 * ROOM[axis] - candidate[axis]
            candidate = tuple(candidate)
            counts = list(bounces)
            counts[wall] += 1
            counts = tuple(counts)
            if candidate not in seen:
                seen[candidate] = (order + 1, counts)
                queue.append(candidate)
            elif seen[candidate][0] == order + 1:
                assert seen[candidate][1] == counts, (candidate, seen[candidate], counts)
    expected = [
        {"image": [c / 2.0 for c in image], "order": order, "bounces": list(bounces)}
        for image, (order, bounces) in seen.items()
    ]
    expected.sort(key=lambda p: (p["order"], *p["image"]))
    return expected


def main():
    cases = []
    for order, count in enumerate(KNOWN_COUNTS):
        images = reflected_images(order)
        assert len(images) == count
        assert all(sum(p["bounces"]) == p["order"] for p in images)
        scene = {
            "room": [v / 2.0 for v in ROOM],
            "source": [v / 2.0 for v in SOURCE],
            "receivers": [[3.0, 2.0, 1.5]],
            "absorption": [0.19, 0.36, 0.51, 0.64, 0.75, 0.84],
            "sample_rate": 16000,
            "max_order": order,
            "duration_ms": 1000,
            "speed": 343.0,
            "half_width": 16,
        }
        cases.append({"name": f"bfs_order_{order}", "scene": scene, "expected_images": images})
    payload = {
        "schema_version": 1,
        "oracle": "Independent breadth-first reflection in six fixed wall planes, integer half-metre coordinates",
        "wall_order": ["xlow", "xhigh", "ylow", "yhigh", "zlow", "zhigh"],
        "case_count": len(cases),
        "image_count": sum(len(c["expected_images"]) for c in cases),
        "cases": cases,
    }
    (ROOT / "bfs-images.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {len(cases)} independent BFS cases / {payload['image_count']} images: {list(KNOWN_COUNTS)}")


if __name__ == "__main__":
    main()
