"""Offline Blender 5.2.1 wall vent; rotor pivot exports at model origin, axis +Z."""
import hashlib
import json
import math
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets-production/environment/colony-vent'
RUNTIME = ROOT / 'apps/world/assets/environment/colony-vent'

def main():
    if not bpy.app.background or bpy.app.version[:3] != (5, 2, 1):
        raise RuntimeError('Separate background Blender 5.2.1 required')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    mats = {}
    for name, color, metal in [('Ivory', (.64,.61,.52), .25), ('Graphite', (.04,.06,.065), .45), ('Copper', (.38,.17,.06), .65)]:
        m = bpy.data.materials.new(name); m.diffuse_color = (*color,1); m.use_nodes=True
        p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1); p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=.42
        mats[name]=m
    rotor_parts=[]
    def finish(obj,name,material):
        obj.name=name; obj.data.materials.append(mats[material]); return obj
    # Blender XY face becomes Godot XY face after rotation of entire geometry.
    def box(name, p, size, material):
        bpy.ops.mesh.primitive_cube_add(size=1, location=p); o=bpy.context.object; o.dimensions=size
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        b=o.modifiers.new('Soft manufactured edges','BEVEL'); b.width=.018; b.segments=2
        bpy.ops.object.modifier_apply(modifier=b.name); return finish(o,name,material)
    for x,y,sx,sy in [(-.55,0,.14,1.24),(.55,0,.14,1.24),(0,.55,.98,.14),(0,-.55,.98,.14)]:
        box('Housing',(x,y,0),(sx,sy,.22),'Ivory')
    box('Recess',(0,0,-.10),(1.03,1.03,.03),'Graphite')
    bpy.ops.mesh.primitive_torus_add(major_radius=.47,minor_radius=.028,major_segments=48,minor_segments=8,location=(0,0,.07)); finish(bpy.context.object,'CopperRim','Copper')
    for i in range(5):
        a=i*math.tau/5
        o=box('Blade',(math.cos(a)*.265,math.sin(a)*.265,.02),(.38,.13,.045),'Graphite'); o.rotation_euler.z=a+.35; rotor_parts.append(o)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=.11,location=(0,0,.07)); o=bpy.context.object; o.scale.z=.45; finish(o,'Hub','Copper'); rotor_parts.append(o)
    bpy.ops.object.select_all(action='DESELECT')
    for o in rotor_parts: o.select_set(True)
    bpy.context.view_layer.objects.active=rotor_parts[0]; bpy.ops.object.join(); rotor=bpy.context.object; rotor.name='Rotor'
    bpy.context.scene.cursor.location=(0,0,0); bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    # Narrow protective bars keep the rotor readable without an opaque grille.
    for x in [-.30,0,.30]: box('Guard',(x,0,.14),(.022,.90,.025),'Ivory')
    for x in [-.55,.55]:
        for y in [-.50,.50]:
            bpy.ops.mesh.primitive_uv_sphere_add(segments=8,ring_count=4,radius=.025,location=(x,y,.13)); finish(bpy.context.object,'Fastener','Copper')
    # Convert intended Godot coordinates (x,y,z) to Blender (x,-z,y).
    from mathutils import Matrix
    rotation=Matrix.Rotation(math.pi/2,4,'X')
    for o in list(bpy.context.scene.objects):
        o.matrix_world=rotation@o.matrix_world
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    SOURCE.joinpath('blender').mkdir(parents=True,exist_ok=True); RUNTIME.mkdir(parents=True,exist_ok=True)
    blend=SOURCE/'blender/colony-vent.blend'; glb=RUNTIME/'colony-vent.glb'
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',export_animations=False)
    files={str(p.relative_to(ROOT)):{'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size} for p in [blend,glb,Path(__file__)]}
    (SOURCE/'provenance.json').write_text(json.dumps({'asset_id':'colony-vent','blender_version':bpy.app.version_string,'source_kind':'Authored offline; zero paid generation','dimensions_m':[1.24,1.24,.265],'rotor_axis':'Godot local Z','files':files},indent=2)+'\n')
if __name__=='__main__': main()
