///|
fn prism_for_test(
  vertices : Array[Point2],
  order : Int32,
) -> Result[Scene, String] {
  prism_scene(
    vertices,
    3.0,
    { x: 1.37, y: 1.21, z: 1.13, },
    [{ x: 3.82, y: 2.31, z: 1.74, }],
    Array::make(vertices.length() + 2, 0.2),
    16000,
    order,
    150,
  )
}

///|
fn rectangle_for_test() -> Array[Point2] {
  [
    { x: 0.0, y: 0.0, },
    { x: 6.0, y: 0.0, },
    { x: 6.0, y: 4.0, },
    { x: 0.0, y: 4.0, },
  ]
}

///|
test "convex geometry rejects concavity, clockwise, repeated vertices and outside points" {
  let clockwise = [
    { x: 0.0, y: 0.0, },
    { x: 0.0, y: 4.0, },
    { x: 6.0, y: 4.0, },
    { x: 6.0, y: 0.0, },
  ]
  assert_true(prism_for_test(clockwise, 2) is Err(_))
  let concave = [
    { x: 0.0, y: 0.0, },
    { x: 6.0, y: 0.0, },
    { x: 3.0, y: 2.0, },
    { x: 6.0, y: 4.0, },
    { x: 0.0, y: 4.0, },
  ]
  assert_true(prism_for_test(concave, 2) is Err(_))
  let repeated = rectangle_for_test()
  repeated.push(repeated[0])
  assert_true(prism_for_test(repeated, 2) is Err(_))
  assert_true(prism_for_test(rectangle_for_test(), 5) is Err(_))
  let triangle = [{ x: 0.0, y: 0.0, }, { x: 6.0, y: 0.0, }, { x: 0.0, y: 4.0, }]
  // The microphone lies in the bounding box but outside this triangle.
  assert_true(prism_for_test(triangle, 2) is Err(_))
}

///|
test "rectangle prism validates exactly the same physical paths as the closed form" {
  let vertices = rectangle_for_test()
  for order in 0..<4 {
    let prism = prism_for_test(vertices, order).unwrap()
    let box = scene(
      prism.room,
      prism.source,
      prism.receivers,
      prism.absorption,
      16000,
      order,
      150,
    ).unwrap()
    let a = trace(prism)
    let b = trace(box)
    assert_eq(a.length(), b.length())
    for path in a {
      let matching = b.filter(fn(q) {
        q.order == path.order && distance(q.image, path.image) < 1.0e-8
      })
      assert_eq(matching.length(), 1)
      assert_true((matching[0].gain - path.gain).abs() < 1.0e-10)
    }
    let ar = render(prism).channel(0).unwrap()
    let br = render(box).channel(0).unwrap()
    for i in 0..<ar.length() {
      assert_true((ar[i] - br[i]).abs() < 1.0e-10)
    }
  }
}

///|
test "trapezoid hits obey finite faces, reflection law and unfolded path length" {
  let vertices = [
    { x: 0.0, y: 0.0, },
    { x: 6.0, y: 0.0, },
    { x: 5.0, y: 4.0, },
    { x: 0.0, y: 4.0, },
  ]
  let s = prism_for_test(vertices, 3).unwrap()
  let paths = trace_prism(s)
  assert_true(paths.length() > 20)
  assert_true(paths.length() < images(s).length())
  let planes = prism_planes(vertices, 3.0)
  for p in paths {
    assert_eq(p.hits.length(), p.path.order)
    let mut previous = s.source
    let mut physical_length = 0.0
    for i in 0..<p.hits.length() {
      let hit = p.hits[i]
      let next = if i + 1 < p.hits.length() {
        p.hits[i + 1]
      } else {
        s.receivers[0]
      }
      let plane = planes[p.walls[i]]
      assert_true((dot(plane.normal, hit) - plane.offset).abs() < 1.0e-8)
      let incoming = subtract(hit, previous)
      let outgoing = subtract(next, hit)
      let a = dot(plane.normal, incoming) / distance(previous, hit)
      let b = dot(plane.normal, outgoing) / distance(next, hit)
      assert_true((a + b).abs() < 1.0e-8)
      physical_length = physical_length + distance(previous, hit)
      previous = hit
    }
    physical_length = physical_length + distance(previous, s.receivers[0])
    assert_true((physical_length - p.path.distance).abs() < 1.0e-8)
  }
}

///|
test "prism materials use edge order and caller arrays are isolated" {
  let vertices = rectangle_for_test()
  let absorption = [0.19, 0.36, 0.51, 0.64, 0.75, 0.84]
  let s = prism_scene(
    vertices,
    3.0,
    { x: 1.37, y: 1.21, z: 1.13, },
    [{ x: 3.82, y: 2.31, z: 1.74, }],
    absorption,
    16000,
    1,
    150,
  ).unwrap()
  vertices.clear()
  absorption[0] = 1.0
  let paths = trace_prism(s)
  assert_eq(paths.length(), 7)
  for p in paths {
    if !p.walls.is_empty() {
      let expected = (1.0 - s.absorption[p.walls[0]]).sqrt()
      assert_true((p.path.reflection - expected).abs() < 1.0e-12)
    }
  }
  let copied = s.floor_plan().unwrap()
  copied.clear()
  assert_eq(s.floor_plan().unwrap().length(), 4)
}

///|
test "edge and corner reflection degeneracy is explicitly excluded" {
  let s = prism_scene(
    [
      { x: 0.0, y: 0.0, },
      { x: 4.0, y: 0.0, },
      { x: 4.0, y: 4.0, },
      { x: 0.0, y: 4.0, },
    ],
    3.0,
    { x: 1.0, y: 1.0, z: 1.0, },
    [{ x: 3.0, y: 3.0, z: 1.0, }],
    Array::make(6, 0.2),
    16000,
    2,
    150,
  ).unwrap()
  let corner = { x: 7.0, y: 7.0, z: 1.0, }
  assert_true(images(s).any(fn(p) { distance(p.image, corner) < 1.0e-8 }))
  assert_true(trace(s).all(fn(p) { distance(p.image, corner) > 1.0e-8 }))
}

///|
test "maximum convex geometry has a bounded reflection-word search" {
  let vertices = Array::makei(8, fn(i) {
    let angle = i.to_double() * PI / 4.0
    { x: 5.0 + 4.0 * @math.cos(angle), y: 5.0 + 4.0 * @math.sin(angle), }
  })
  let s = prism_scene(
    vertices,
    3.0,
    { x: 4.1, y: 4.7, z: 1.3, },
    [{ x: 6.2, y: 5.4, z: 1.9, }],
    Array::make(10, 0.2),
    16000,
    4,
    150,
  ).unwrap()
  assert_eq(images(s).length(), 8201)
  let paths = trace_prism(s)
  assert_true(paths.length() > 100 && paths.length() < 8201)
  assert_true(paths.all(fn(p) { p.path.order <= 4 && p.path.distance > 0.0 }))
}
