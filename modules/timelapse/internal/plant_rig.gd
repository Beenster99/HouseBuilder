extends RefCounted
## Moves a library machine's parts about their pivots. Library models are split into stage
## meshes named "<stage>__<slot>" with pivot sockets (AssetLibrary.info(id).sockets); a rig
## remembers each mesh's rest pose in the machine's own space and puts it at
## joint * rest, where joint is the stage's transform in that space.
##
##   var rig := PlantRig.new(node)
##   var swing := PlantRig.turn(rig.socket("slew"), Vector3.UP, 0.8)
##   rig.pose({"upper": swing, "boom": swing * PlantRig.turn(rig.socket("boom_pivot"), Vector3.RIGHT, -0.3)})

var root: Node3D
var id := ""
var _parts: Array[Dictionary] = []   # {mesh, stage, rest, parent_inv}
var _sockets: Dictionary = {}


func _init(machine: Node3D) -> void:
	root = machine
	id = str(machine.get_meta("asset_id", ""))
	_sockets = AssetLibrary.info(id).get("sockets", {})
	for mi in machine.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var stage := str(m.name).get_slice("__", 0)
		var rest := _in_root(m)
		var parent_rest := _in_root(m.get_parent() as Node3D) if m.get_parent() != machine else Transform3D.IDENTITY
		_parts.append({"mesh": m, "stage": stage, "rest": rest, "parent_inv": parent_rest.affine_inverse()})


## Whether the model has these stages (a fallback box has none).
func has_stages(names: PackedStringArray) -> bool:
	for n in names:
		var found := false
		for p: Dictionary in _parts:
			if p.stage == n:
				found = true
				break
		if not found:
			return false
	return true


## A socket in the machine's own space (no scale applied: the rig works in model space).
func socket(socket_name: String) -> Vector3:
	var s: Variant = _sockets.get(socket_name)
	return Vector3(float(s[0]), float(s[1]), float(s[2])) if s is Array else Vector3.ZERO


## Puts every mesh of each named stage at joint * rest; stages not named go back to rest.
func pose(joints: Dictionary) -> void:
	for p: Dictionary in _parts:
		var j: Variant = joints.get(p.stage)
		var t: Transform3D = (j as Transform3D) * (p.rest as Transform3D) if j != null else p.rest
		(p.mesh as MeshInstance3D).transform = (p.parent_inv as Transform3D) * t


## A turn of `angle` about the line through `pivot` along `axis`.
static func turn(pivot: Vector3, axis: Vector3, angle: float) -> Transform3D:
	var r := Transform3D(Basis(axis.normalized(), angle), Vector3.ZERO)
	return Transform3D(Basis(), pivot) * r * Transform3D(Basis(), -pivot)


static func shift(by: Vector3) -> Transform3D:
	return Transform3D(Basis(), by)


## A stretch of `factor` along y about height `y0` (the scissor lift's scissors).
static func stretch_y(y0: float, factor: float) -> Transform3D:
	var t := Transform3D(Basis.from_scale(Vector3(1, factor, 1)), Vector3.ZERO)
	return Transform3D(Basis(), Vector3(0, y0, 0)) * t * Transform3D(Basis(), Vector3(0, -y0, 0))


func _in_root(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
