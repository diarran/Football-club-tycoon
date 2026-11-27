# Bus du club « FC » : modèle détaillé généré par script (Blender headless).
# Un objet par matériau pour que l'Importateur 3D de Roblox crée des MeshParts simples.
import bpy, math, sys, os
out = sys.argv[sys.argv.index("--")+1] if "--" in sys.argv else "/tmp/bus"
os.makedirs(out, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene

def mat(name, rgb, metal=0.0, rough=0.5, alpha=1.0, emit=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Metallic"].default_value = metal; b.inputs["Roughness"].default_value = rough
    if alpha < 1: b.inputs["Alpha"].default_value = alpha; m.blend_method = 'BLEND' if hasattr(m,'blend_method') else None
    if emit: b.inputs["Emission Color"].default_value = (*rgb, 1); b.inputs["Emission Strength"].default_value = emit
    return m
M = {
 "Carrosserie": mat("Carrosserie", (0.02,0.02,0.025), 0.6, 0.25),
 "Livree": mat("Livree", (0.75,0.55,0.12), 0.9, 0.25),
 "Vitres": mat("Vitres", (0.03,0.05,0.07), 0.2, 0.05),
 "Pneus": mat("Pneus", (0.015,0.015,0.015), 0.0, 0.8),
 "Jantes": mat("Jantes", (0.8,0.8,0.82), 1.0, 0.2),
 "Feux": mat("Feux", (1.0,0.9,0.7), 0.0, 0.3, emit=4),
 "FeuxArriere": mat("FeuxArriere", (0.9,0.05,0.05), 0.0, 0.3, emit=3),
}
parts = {k: [] for k in M}

def box(name, size, loc, m, bevel=0.0, segs=3):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object; o.name = name; o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        mod = o.modifiers.new("b", "BEVEL"); mod.width = bevel; mod.segments = segs; mod.limit_method = 'ANGLE'
        bpy.ops.object.modifier_apply(modifier="b")
    o.data.materials.append(M[m]); parts[m].append(o); return o

def cyl(name, r, depth, loc, m, rot=(0, math.pi/2, 0), verts=32, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=verts)
    o = bpy.context.object; o.name = name
    if bevel:
        mod = o.modifiers.new("b", "BEVEL"); mod.width = bevel; mod.segments = 3
        bpy.ops.object.modifier_apply(modifier="b")
    o.data.materials.append(M[m]); parts[m].append(o); return o

# Dimensions en mètres ~ autocar 12 m (Roblox : 1 stud ≈ 0,28 m ; on exporte à l'échelle 1 = 1 stud plus loin)
L, W, H = 12.0, 2.55, 3.5
box("Caisse", (L, W, H-0.55), (0, 0, 0.55 + (H-0.55)/2), "Carrosserie", bevel=0.18)
box("Toit", (L-0.6, W-0.3, 0.12), (0, 0, H+0.02), "Carrosserie", bevel=0.05)
# bandeau vitré latéral + pare-brise + lunette
for s in (-1, 1):
    box("VitresCote", (L-2.2, 0.04, 1.25), (0.3, s*(W/2+0.005), 2.45), "Vitres", bevel=0.02)
    # montants entre vitres
    for i in range(7):
        x = -L/2 + 1.6 + i*1.42
        box("Montant", (0.09, 0.05, 1.25), (x, s*(W/2+0.02), 2.45), "Carrosserie")
    # livrée : bande dorée et filet
    box("Bande", (L-0.4, 0.03, 0.22), (0, s*(W/2+0.01), 1.55), "Livree", bevel=0.01)
    box("Filet", (L-3.0, 0.03, 0.06), (0.6, s*(W/2+0.01), 1.3), "Livree")
    # rétroviseurs
    box("Retro", (0.08, 0.25, 0.42), (L/2+0.25, s*(W/2+0.2), 2.6), "Carrosserie", bevel=0.03)
    box("RetroBras", (0.35, 0.05, 0.05), (L/2+0.1, s*(W/2+0.1), 2.85), "Carrosserie")
box("PareBrise", (0.04, W-0.25, 1.6), (L/2+0.005, 0, 2.3), "Vitres", bevel=0.02)
box("Lunette", (0.04, W-0.4, 0.9), (-L/2-0.005, 0, 2.6), "Vitres", bevel=0.02)
box("Porte", (1.0, 0.04, 2.3), (L/2-1.3, -(W/2+0.01), 1.6), "Vitres")
# calandre, feux
box("Calandre", (0.05, 1.6, 0.35), (L/2+0.02, 0, 0.95), "Jantes")
for s in (-1, 1):
    box("Phare", (0.06, 0.45, 0.2), (L/2+0.02, s*0.95, 0.95), "Feux", bevel=0.03)
    box("FeuArriere", (0.06, 0.18, 0.7), (-L/2-0.02, s*1.05, 1.3), "FeuxArriere", bevel=0.02)
box("PareChocsAv", (0.25, W, 0.3), (L/2+0.05, 0, 0.6), "Carrosserie", bevel=0.06)
box("PareChocsAr", (0.25, W, 0.3), (-L/2-0.05, 0, 0.6), "Carrosserie", bevel=0.06)
box("Logo", (0.03, 0.9, 0.9), (-L/2-0.03, 0, 1.9), "Livree", bevel=0.2)
# roues (3 essieux : 1 avant, 2 arrière)
for x in (L/2-2.4, -L/2+2.6, -L/2+3.9):
    for s in (-1, 1):
        y = s*(W/2-0.18)
        cyl("Pneu", 0.52, 0.32, (x, y, 0.52), "Pneus", rot=(math.pi/2,0,0), bevel=0.06)
        cyl("Jante", 0.3, 0.38, (x, y, 0.52), "Jantes", rot=(math.pi/2,0,0), verts=10)
        cyl("Moyeu", 0.09, 0.42, (x, y, 0.52), "Carrosserie", rot=(math.pi/2,0,0), verts=12)

# Un objet par matériau (jointure), origine au centre au sol
names = []
for m, objs in parts.items():
    if not objs: continue
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object; o.name = "Bus_" + m; names.append(o.name)
tris = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == 'MESH')
print("faces:", tris)

# Export : échelle 1 m -> 1 stud * 3.57 (un bus de 12 m ≈ 43 studs serait trop grand : on vise ~26 studs)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.fbx(filepath=os.path.join(out, "bus_du_club.fbx"), use_selection=True, global_scale=1.0,
    apply_unit_scale=True, axis_forward='-Z', axis_up='Y', object_types={'MESH'}, mesh_smooth_type='FACE')
bpy.ops.wm.obj_export(filepath=os.path.join(out, "bus_du_club.obj"), export_materials=True, forward_axis='NEGATIVE_Z', up_axis='Y')

# Rendu d'aperçu
bpy.ops.mesh.primitive_plane_add(size=60, location=(0,0,0))
g = bpy.context.object; g.data.materials.append(mat("Sol", (0.18,0.18,0.19), 0, 0.9))
world = bpy.data.worlds.new("W"); scn.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.55,0.65,0.8,1); world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
bpy.ops.object.light_add(type='SUN', rotation=(math.radians(50), math.radians(10), math.radians(140))); bpy.context.object.data.energy = 4
bpy.ops.object.camera_add(location=(14, -11, 5.5)); cam = bpy.context.object; scn.camera = cam
d = cam.constraints.new('TRACK_TO'); 
bpy.ops.object.empty_add(location=(0,0,1.6)); d.target = bpy.context.object; d.track_axis='TRACK_NEGATIVE_Z'; d.up_axis='UP_Y'
cam.data.lens = 40
scn.render.engine = 'CYCLES'; scn.cycles.samples = 48; scn.cycles.device = 'CPU'
scn.render.resolution_x, scn.render.resolution_y = 1400, 800
scn.view_settings.view_transform = 'AgX' if 'AgX' in [v for v in ('AgX','Filmic')] else 'Filmic'
scn.render.filepath = os.path.join(out, "bus_du_club.png")
bpy.ops.render.render(write_still=True)
print("ok", names)
