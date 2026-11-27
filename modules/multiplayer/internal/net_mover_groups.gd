class_name NetMoverGroups
extends RefCounted
## Many host-driven bodies streamed compactly (the demolition's debris): each group is a set
## of nodes by small integer index, the same on every peer. The host sends only the nodes
## that moved since it last sent them, packed 12 bytes each (index, position in cm from the
## group's origin, rotation as smallest-three), RATE times a second. Peers play them back
## DELAY s behind, interpolated, like NetMovers.
##
## Wire format, per batch: [u16 count] then count x [u16 index, i16 x, i16 y, i16 z, u32 rot].

const RATE := 12.0
const DELAY := 0.12
const BUFFER := 6
## Moved further than this (m) or turned more than ROT_EPS (rad) since last sent: send again.
const POS_EPS := 0.01
const ROT_EPS := 0.01
const CM := 100.0
const MAX_PER_PACKET := 400

## group id -> {"origin": Vector3, "nodes": {index: Node3D}, "sent": {index: Transform3D},
##   "samples": {index: [[t, Transform3D], ...]}}
var _groups: Dictionary = {}


func register(group: String, origin: Vector3) -> void:
	_groups[group] = {"origin": origin, "nodes": {}, "sent": {}, "samples": {}}


func unregister(group: String) -> void:
	_groups.erase(group)


func has(group: String) -> bool:
	return _groups.has(group)


func set_node(group: String, index: int, node: Node3D) -> void:
	if _groups.has(group):
		_groups[group].nodes[index] = node
		_groups[group].samples.erase(index)
		_groups[group].sent.erase(index)


func erase_node(group: String, index: int) -> void:
	if _groups.has(group):
		_groups[group].nodes.erase(index)
		_groups[group].samples.erase(index)
		_groups[group].sent.erase(index)


func node_count() -> int:
	var n := 0
	for g: String in _groups:
		n += (_groups[g].nodes as Dictionary).size()
	return n


## Host: packed batches of what moved, per group: {group: [PackedByteArray, ...]}.
func outgoing() -> Dictionary:
	var out := {}
	for g: String in _groups:
		var grp: Dictionary = _groups[g]
		var origin: Vector3 = grp.origin
		var moved: Array = []
		for i: int in grp.nodes:
			var node: Variant = grp.nodes[i]
			if not is_instance_valid(node) or not (node as Node3D).is_inside_tree():
				continue
			var at: Transform3D = (node as Node3D).global_transform
			var last: Variant = grp.sent.get(i)
			if last != null and _close(last, at):
				continue
			grp.sent[i] = at
			moved.append([i, at])
		if moved.is_empty():
			continue
		var packets: Array[PackedByteArray] = []
		var k := 0
		while k < moved.size():
			var n := mini(MAX_PER_PACKET, moved.size() - k)
			var buf := StreamPeerBuffer.new()
			buf.put_u16(n)
			for j in n:
				var e: Array = moved[k + j]
				_put(buf, int(e[0]), e[1] as Transform3D, origin)
			packets.append(buf.data_array)
			k += n
		out[g] = packets
	return out


## Peer: takes a host batch for `group` at host time t.
func receive(group: String, t: float, data: PackedByteArray) -> void:
	if not _groups.has(group):
		return
	var grp: Dictionary = _groups[group]
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	if data.size() < 2:
		return
	var n := buf.get_u16()
	for j in n:
		if buf.get_available_bytes() < 12:
			return
		var i := buf.get_u16()
		var x := buf.get_16() / CM
		var y := buf.get_16() / CM
		var z := buf.get_16() / CM
		var q := _unpack_quat(buf.get_u32())
		var at := Transform3D(Basis(q), grp.origin + Vector3(x, y, z))
		var list: Array = grp.samples.get(i, [])
		if not list.is_empty() and t <= float(list.back()[0]):
			continue
		list.append([t, at])
		if list.size() > BUFFER:
			list.pop_front()
		grp.samples[i] = list


## Peer: moves every node to where it was at render_t.
func play_back(render_t: float) -> void:
	for g: String in _groups:
		var grp: Dictionary = _groups[g]
		for i: int in grp.samples:
			var node: Variant = grp.nodes.get(i)
			if not is_instance_valid(node) or not (node as Node3D).is_inside_tree():
				continue
			var at := NetMovers.sample_at(grp.samples[i], render_t)
			if not (node as Node3D).global_transform.is_equal_approx(at):
				(node as Node3D).global_transform = at


static func _close(a: Transform3D, b: Transform3D) -> bool:
	if a.origin.distance_squared_to(b.origin) > POS_EPS * POS_EPS:
		return false
	return a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()) <= ROT_EPS


static func _put(buf: StreamPeerBuffer, i: int, at: Transform3D, origin: Vector3) -> void:
	var p := (at.origin - origin) * CM
	buf.put_u16(i)
	buf.put_16(clampi(roundi(p.x), -32767, 32767))
	buf.put_16(clampi(roundi(p.y), -32767, 32767))
	buf.put_16(clampi(roundi(p.z), -32767, 32767))
	buf.put_u32(_pack_quat(at.basis.orthonormalized().get_rotation_quaternion()))


## Smallest three: 2 bits for the largest component, 10 bits each for the other three.
static func _pack_quat(q: Quaternion) -> int:
	var c := [q.x, q.y, q.z, q.w]
	var big := 0
	for k in 4:
		if absf(c[k]) > absf(c[big]):
			big = k
	if c[big] < 0.0:
		for k in 4:
			c[k] = -c[k]
	var out := big
	var shift := 2
	for k in 4:
		if k == big:
			continue
		var v := clampi(roundi((float(c[k]) / sqrt(2.0) + 0.5) * 1023.0), 0, 1023)
		out |= v << shift
		shift += 10
	return out


static func _unpack_quat(bits: int) -> Quaternion:
	var big := bits & 3
	var c := [0.0, 0.0, 0.0, 0.0]
	var shift := 2
	var sum := 0.0
	for k in 4:
		if k == big:
			continue
		var v := float((bits >> shift) & 1023) / 1023.0
		c[k] = (v - 0.5) * sqrt(2.0)
		sum += c[k] * c[k]
		shift += 10
	c[big] = sqrt(maxf(0.0, 1.0 - sum))
	return Quaternion(c[0], c[1], c[2], c[3]).normalized()
