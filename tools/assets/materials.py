"""The library's PBR materials: name -> (base colour as seen on screen, roughness, metallic,
alpha, density kg/m3).

A kit piece names one of these as its material slot. Blender builds a Principled BSDF from
the row and the glTF export carries it to the game for the realistic look; the sketch look
ignores it. Density gives each break piece its mass.
"""
import bpy

MATERIALS = {
	# metals
	"steel_dark": ((0.16, 0.17, 0.18), 0.5, 0.7, 1.0, 7850),
	"container_blue": ((0.07, 0.33, 0.45), 0.45, 0.3, 1.0, 7850),
	"ply_brown": ((0.42, 0.26, 0.10), 0.55, 0.0, 1.0, 650),
	"sand": ((0.80, 0.68, 0.45), 0.95, 0.0, 1.0, 1600),
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
	# services, finishes and outdoors (second batch)
	"copper": ((0.72, 0.45, 0.20), 0.35, 1.0, 1.0, 8900),
	"insulation": ((0.75, 0.76, 0.78), 0.6, 0.6, 1.0, 60),
	"plastic_red": ((0.75, 0.08, 0.06), 0.4, 0.0, 1.0, 1200),
	"plastic_blue": ((0.10, 0.25, 0.60), 0.4, 0.0, 1.0, 1200),
	"plastic_green": ((0.10, 0.45, 0.20), 0.4, 0.0, 1.0, 1200),
	"plastic_yellow": ((0.95, 0.80, 0.10), 0.4, 0.0, 1.0, 1200),
	"light_emitter": ((1.0, 0.98, 0.92), 0.3, 0.0, 1.0, 1200),
	"screen": ((0.02, 0.03, 0.05), 0.15, 0.0, 1.0, 2000),
	"mirror": ((0.9, 0.92, 0.93), 0.02, 1.0, 1.0, 2500),
	"blockwork": ((0.62, 0.62, 0.60), 0.95, 0.0, 1.0, 1400),
	"plasterboard": ((0.90, 0.89, 0.86), 0.9, 0.0, 1.0, 700),
	"mineral_wool": ((0.85, 0.75, 0.30), 1.0, 0.0, 1.0, 30),
	"render": ((0.88, 0.85, 0.78), 0.95, 0.0, 1.0, 1800),
	"clay_tile": ((0.55, 0.25, 0.16), 0.85, 0.0, 1.0, 1900),
	"slate": ((0.20, 0.22, 0.25), 0.7, 0.0, 1.0, 2700),
	"roof_felt": ((0.12, 0.12, 0.13), 0.95, 0.0, 1.0, 1100),
	"lead": ((0.40, 0.42, 0.45), 0.5, 0.9, 1.0, 11300),
	"asphalt": ((0.10, 0.10, 0.11), 0.95, 0.0, 1.0, 2300),
	"paving": ((0.66, 0.64, 0.60), 0.9, 0.0, 1.0, 2300),
	"soil": ((0.28, 0.20, 0.13), 1.0, 0.0, 1.0, 1600),
	"bark": ((0.28, 0.20, 0.14), 0.95, 0.0, 1.0, 600),
	"foliage": ((0.20, 0.42, 0.16), 0.9, 0.0, 1.0, 40),
	"foliage_dark": ((0.10, 0.28, 0.14), 0.9, 0.0, 1.0, 40),
	"car_red": ((0.60, 0.05, 0.05), 0.25, 0.5, 1.0, 600),
	"car_blue": ((0.08, 0.18, 0.45), 0.25, 0.5, 1.0, 600),
	"car_silver": ((0.70, 0.71, 0.73), 0.25, 0.8, 1.0, 600),
	"car_white": ((0.92, 0.92, 0.92), 0.3, 0.2, 1.0, 600),
	"hivis_yellow": ((0.80, 0.95, 0.05), 0.6, 0.0, 1.0, 1000),
	"skin": ((0.80, 0.62, 0.50), 0.7, 0.0, 1.0, 1000),
	"denim": ((0.15, 0.22, 0.38), 0.9, 0.0, 1.0, 1000),
	"fabric_red": ((0.60, 0.12, 0.10), 0.95, 0.0, 1.0, 120),
	"fabric_green": ((0.20, 0.40, 0.25), 0.95, 0.0, 1.0, 120),
	"vinyl_floor": ((0.60, 0.68, 0.70), 0.5, 0.0, 1.0, 1300),
	"carpet": ((0.35, 0.36, 0.42), 1.0, 0.0, 1.0, 300),
	"water": ((0.25, 0.45, 0.60), 0.05, 0.0, 0.5, 1000),
	# showpiece rooms
	"glow": ((1.0, 0.93, 0.78), 0.3, 0.0, 1.0, 1200),
	"marble": ((0.90, 0.89, 0.86), 0.15, 0.0, 1.0, 2700),
	"velvet_teal": ((0.05, 0.22, 0.24), 1.0, 0.0, 1.0, 150),
	"glass_dark": ((0.03, 0.045, 0.06), 0.06, 0.0, 1.0, 2500),
}


def _linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


# The table above is written as the colours should look on screen (sRGB); Blender and glTF
# want linear values. (Slots added later by recipes/torque.py are linear already.)
MATERIALS = {name: (tuple(round(_linear(c), 4) for c in row[0]),) + row[1:] for name, row in MATERIALS.items()}


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
