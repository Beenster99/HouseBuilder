"""The library's PBR materials: name -> (base colour, roughness, metallic, alpha, density kg/m3).

A kit piece names one of these as its material slot. Blender builds a Principled BSDF from
the row and the glTF export carries it to the game for the realistic look; the sketch look
ignores it. Density gives each break piece its mass.
"""
import bpy

MATERIALS = {
	# metals
	"steel_painted": ((0.42, 0.45, 0.50), 0.45, 0.8, 1.0, 7850),
	"steel_galvanised": ((0.66, 0.68, 0.70), 0.35, 0.9, 1.0, 7850),
	"steel_stainless": ((0.78, 0.78, 0.78), 0.2, 1.0, 1.0, 7900),
	"aluminium": ((0.80, 0.81, 0.82), 0.3, 1.0, 1.0, 2700),
	"cast_iron": ((0.16, 0.16, 0.17), 0.6, 0.8, 1.0, 7200),
	"brass": ((0.78, 0.62, 0.30), 0.3, 1.0, 1.0, 8500),
	"plant_yellow": ((0.95, 0.68, 0.05), 0.5, 0.3, 1.0, 7850),
	"hazard_red": ((0.75, 0.10, 0.08), 0.5, 0.3, 1.0, 7850),
	# timber and boards
	"softwood": ((0.72, 0.56, 0.36), 0.75, 0.0, 1.0, 420),
	"glulam": ((0.80, 0.64, 0.42), 0.6, 0.0, 1.0, 460),
	"hardwood": ((0.42, 0.26, 0.15), 0.55, 0.0, 1.0, 700),
	"plywood": ((0.76, 0.63, 0.44), 0.7, 0.0, 1.0, 600),
	"laminate_white": ((0.92, 0.92, 0.90), 0.4, 0.0, 1.0, 700),
	"laminate_grey": ((0.45, 0.47, 0.50), 0.4, 0.0, 1.0, 700),
	"paint_white": ((0.94, 0.94, 0.92), 0.5, 0.0, 1.0, 600),
	# mineral
	"concrete": ((0.60, 0.59, 0.56), 0.9, 0.0, 1.0, 2500),
	"brick": ((0.56, 0.30, 0.22), 0.9, 0.0, 1.0, 1900),
	"ceramic": ((0.96, 0.96, 0.95), 0.1, 0.0, 1.0, 2300),
	"enamel": ((0.95, 0.95, 0.95), 0.15, 0.0, 1.0, 2000),
	"worktop": ((0.20, 0.20, 0.21), 0.3, 0.0, 1.0, 2600),
	# glass and plastics
	"glass": ((0.75, 0.88, 0.92), 0.05, 0.0, 0.25, 2500),
	"plastic_white": ((0.93, 0.93, 0.93), 0.4, 0.0, 1.0, 1200),
	"plastic_black": ((0.05, 0.05, 0.05), 0.5, 0.0, 1.0, 1200),
	"plastic_grey": ((0.35, 0.36, 0.38), 0.5, 0.0, 1.0, 1200),
	"rubber": ((0.04, 0.04, 0.04), 0.9, 0.0, 1.0, 1100),
	"hivis_orange": ((1.0, 0.35, 0.02), 0.6, 0.0, 1.0, 1000),
	# soft
	"fabric_grey": ((0.45, 0.46, 0.48), 0.95, 0.0, 1.0, 120),
	"fabric_blue": ((0.20, 0.32, 0.50), 0.95, 0.0, 1.0, 120),
	"fabric_white": ((0.93, 0.92, 0.89), 0.95, 0.0, 1.0, 120),
	"leather_black": ((0.06, 0.06, 0.06), 0.5, 0.0, 1.0, 400),
}


def get(name: str) -> bpy.types.Material:
	if name not in MATERIALS:
		raise KeyError("unknown material slot '%s'" % name)
	mat = bpy.data.materials.get(name)
	if mat:
		return mat
	colour, rough, metal, alpha, _density = MATERIALS[name]
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
	bsdf.inputs["Roughness"].default_value = rough
	bsdf.inputs["Metallic"].default_value = metal
	bsdf.inputs["Alpha"].default_value = alpha
	mat.diffuse_color = (*colour, alpha)
	if alpha < 1.0:
		mat.surface_render_method = "BLENDED"
	return mat


def density(name: str) -> float:
	return float(MATERIALS[name][4])
