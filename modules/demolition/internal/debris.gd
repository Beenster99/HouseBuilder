extends Node3D
## Fine debris for the demolition: the fragments a charge or a hard hit throws off, drawn as
## one MultiMesh per burst and moved by a light ballistic step (gravity, a bouncing, sliding
## ground) rather than Jolt, so hundreds cost next to nothing and the collapse keeps 60 fps.
## They are a local effect on every peer (seeded by the part, so peers see much the same),
## never streamed.
##
## Fragments are graded by distance from the burst's centre: fine and many close to it,
## coarser further out. Each material breaks its own way:
##   masonry, concrete (and the rest): brittle shatter, chunky lumps and grit
##   timber: long splinters
##   steel: thin torn shards and bent lengths
##   glass: small bright slivers
##
##   debris.burst(part_box, charge_point, "concrete", material, 1.0)

const GRAVITY := 9.8
const MAX_LIVE := 3500
const MAX_PER_BURST := 260
## Coarse and fine fragment sizes, m, far from and close to the centre.
const COARSE := 0.55
const FINE := 0.07
const SETTLE := 0.35
const LIFE := 14.0

var ground_y := 0.0
var _bursts: Array[Dictionary] = []   # {mmi, pos, vel, axis, spin, angle, scale, done, age}
var _live := 0
static var _meshes: Dictionary = {}


## Throws off fragments from `box` (world AABB), finest round `centre`, as `material` breaks
## (see the class notes). `power` 1 is a charge going off on the part; less for a hard hit
## or spalling off a part near a charge. Returns how many fragments it made.
func burst(box: AABB, centre: Vector3, material: String, look: Material, power := 1.0, seed_key := "") -> int:
	var style := style_of(material)
	var volume := maxf(box.get_volume(), 0.01)
	var n := clampi(int(volume * 14.0 * power), 12, MAX_PER_BURST)
	if style == "steel":
		n = maxi(n >> 1, 8)
	n = mini(n, MAX_LIVE - _live)
	if n <= 0:
		_retire_oldest()
		n = mini(clampi(int(volume * 14.0 * power), 12, MAX_PER_BURST), MAX_LIVE - _live)
		if n <= 0:
			return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key + str(box.position)) if seed_key != "" else hash(str(box))
	var reach := maxf(box.size.length() * 0.5, 0.5)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh(style)
	mm.instance_count = n
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var axis := PackedVector3Array()
	var spin := PackedFloat32Array()
	var scale := PackedVector3Array()
	for i in n:
		# Most fragments come from near the centre; some from anywhere in the part.
		var p := Vector3(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y),
				rng.randf_range(box.position.z, box.end.z))
		if rng.randf() < 0.6:
			p = centre.lerp(p, rng.randf() * rng.randf())
		var d := clampf(p.distance_to(centre) / reach, 0.0, 1.0)
		var size := lerpf(FINE, COARSE, d) * rng.randf_range(0.6, 1.3)
		var out := p - centre
		if out.length() < 0.01:
			out = Vector3(rng.randf_range(-1, 1), rng.randf_range(0, 1), rng.randf_range(-1, 1))
		var speed := lerpf(14.0, 2.0, d) * power * rng.randf_range(0.5, 1.2)
		pos.append(p)
		vel.append(out.normalized() * speed + Vector3(0, rng.randf_range(0.5, 3.0) * power, 0))
		axis.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized())
		spin.append(rng.randf_range(2.0, 14.0) * (1.0 - d * 0.5))
		scale.append(_shape(style, size, rng))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = look
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if n > 120 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	var angle := PackedFloat32Array()
	angle.resize(n)
	var done := PackedByteArray()
	done.resize(n)
	var b := {"mmi": mmi, "pos": pos, "vel": vel, "axis": axis, "spin": spin, "angle": angle,
			"scale": scale, "done": done, "age": 0.0, "moving": n}
	_bursts.append(b)
	_live += n
	_write(b)
	return n


## How a material breaks: "brittle", "timber", "steel" or "glass".
static func style_of(material: String) -> String:
	match material:
		"timber":
			return "timber"
		"steel":
			return "steel"
		"glass":
			return "glass"
	return "brittle"


## Fragments alive now, and how many are still moving.
func live() -> int:
	return _live


func moving() -> int:
	var n := 0
	for b in _bursts:
		n += int(b.moving)
	return n


## The bursts so far, for tests ({mmi, pos, vel, scale, ...} each).
func bursts() -> Array[Dictionary]:
	return _bursts


func clear() -> void:
	for b in _bursts:
		(b.mmi as Node).queue_free()
	_bursts.clear()
	_live = 0


func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	for b in _bursts:
		b.age = float(b.age) + delta
		if int(b.moving) == 0:
			continue
		_step(b, dt)
		_write(b)


func _step(b: Dictionary, dt: float) -> void:
	var pos: PackedVector3Array = b.pos
	var vel: PackedVector3Array = b.vel
	var angle: PackedFloat32Array = b.angle
	var spin: PackedFloat32Array = b.spin
	var done: PackedByteArray = b.done
	var scale: PackedVector3Array = b.scale
	var moving := 0
	for i in pos.size():
		if done[i] == 1:
			continue
		var v := vel[i]
		v.y -= GRAVITY * dt
		var p := pos[i] + v * dt
		var rest := ground_y + scale[i].y * 0.5
		if p.y < rest:
			p.y = rest
			if absf(v.y) < 1.5:
				v.y = 0.0
				v.x *= 0.85
				v.z *= 0.85
				spin[i] *= 0.8
			else:
				v.y = -v.y * 0.3
				v.x *= 0.6
				v.z *= 0.6
				spin[i] *= 0.6
			if v.length() < SETTLE or float(b.age) > LIFE:
				done[i] = 1
				v = Vector3.ZERO
		pos[i] = p
		vel[i] = v
		angle[i] += spin[i] * dt
		if done[i] == 0:
			moving += 1
	b.pos = pos
	b.vel = vel
	b.angle = angle
	b.spin = spin
	b.done = done
	b.moving = moving


func _write(b: Dictionary) -> void:
	var mm: MultiMesh = (b.mmi as MultiMeshInstance3D).multimesh
	var pos: PackedVector3Array = b.pos
	var axis: PackedVector3Array = b.axis
	var angle: PackedFloat32Array = b.angle
	var scale: PackedVector3Array = b.scale
	for i in pos.size():
		mm.set_instance_transform(i, Transform3D(Basis(axis[i], angle[i]).scaled_local(scale[i]), pos[i]))


func _retire_oldest() -> void:
	if _bursts.is_empty():
		return
	var b: Dictionary = _bursts.pop_front()
	_live -= (b.pos as PackedVector3Array).size()
	(b.mmi as Node).queue_free()


## A fragment's size along its own axes for a style.
static func _shape(style: String, size: float, rng: RandomNumberGenerator) -> Vector3:
	match style:
		"timber":
			# Splinters: long and thin.
			return Vector3(size * rng.randf_range(0.12, 0.25), size * rng.randf_range(0.12, 0.25), size * rng.randf_range(2.0, 4.5))
		"steel":
			# Torn plate and bent lengths: thin, long-ish.
			return Vector3(size * rng.randf_range(0.8, 2.0), size * rng.randf_range(0.05, 0.12), size * rng.randf_range(1.0, 3.0))
		"glass":
			return Vector3(size * rng.randf_range(0.3, 0.8), size * 0.04, size * rng.randf_range(0.4, 1.0)) * 0.6
	# Brittle lumps and grit.
	return Vector3(size * rng.randf_range(0.7, 1.2), size * rng.randf_range(0.5, 1.0), size * rng.randf_range(0.7, 1.2))


## A unit fragment mesh per style, built once: an irregular lump, a splinter pointed at both
## ends, a bent steel length, a flat shard.
static func _mesh(style: String) -> Mesh:
	if _meshes.has(style):
		return _meshes[style]
	var m: Mesh
	match style:
		"timber":
			m = _hull([Vector3(0, 0, -0.5), Vector3(0, 0, 0.5), Vector3(-0.5, -0.3, -0.1), Vector3(0.5, -0.4, 0.15),
					Vector3(0.4, 0.5, -0.05), Vector3(-0.45, 0.4, 0.1)])
		"steel":
			m = _bent()
		"glass":
			m = _hull([Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.3), Vector3(0.1, 0, 0.5), Vector3(0, 0.5, 0), Vector3(0.05, -0.5, 0.05)])
		_:
			m = _hull([Vector3(-0.5, -0.4, -0.45), Vector3(0.45, -0.5, -0.4), Vector3(0.5, -0.35, 0.5), Vector3(-0.4, -0.5, 0.45),
					Vector3(-0.45, 0.5, -0.35), Vector3(0.4, 0.45, -0.5), Vector3(0.5, 0.5, 0.4), Vector3(-0.5, 0.4, 0.5),
					Vector3(0.1, 0.62, 0.0), Vector3(-0.62, 0.0, 0.1)])
	_meshes[style] = m
	return m


static func _hull(points: Array) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := PackedVector3Array(points)
	var centre := Vector3.ZERO
	for p in pts:
		centre += p
	centre /= pts.size()
	# Every triple whose plane has all points on one side is a hull face.
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			for k in range(j + 1, pts.size()):
				var n := (pts[j] - pts[i]).cross(pts[k] - pts[i])
				if n.length() < 1e-5:
					continue
				var side := 0
				var ok := true
				for q in pts.size():
					if q == i or q == j or q == k:
						continue
					var s := n.dot(pts[q] - pts[i])
					if absf(s) < 1e-5:
						continue
					var sg := 1 if s > 0.0 else -1
					if side == 0:
						side = sg
					elif sg != side:
						ok = false
						break
				if not ok:
					continue
				var a := pts[i]
				var b := pts[j]
				var c := pts[k]
				# Front faces wind clockwise seen from outside: (c - a) x (b - a) points out.
				if (c - a).cross(b - a).dot(a - centre) < 0.0:
					var t := b
					b = c
					c = t
				st.add_vertex(a)
				st.add_vertex(b)
				st.add_vertex(c)
	st.generate_normals()
	return st.commit()


## A bent steel length: two flat bars meeting at an angle (unit size along z).
static func _bent() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 0.55)
	st.append_from(box, 0, Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.08, -0.24)))
	st.append_from(box, 0, Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 0.08, 0.24)))
	st.generate_normals()
	return st.commit()
