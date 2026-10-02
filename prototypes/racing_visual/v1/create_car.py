import bpy, math, json
from mathutils import Vector
from mathutils.geometry import tessellate_polygon
from pathlib import Path
P=Path(__file__).parent
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.materials): bpy.data.materials.remove(m)
def mat(name,c,metal,rough):
 m=bpy.data.materials.new(name); m.diffuse_color=(*c,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 return m
paint=mat('01_Petrol_Teal',(.018,.36,.34),.55,.29)
glass=mat('02_Smoked_Glass',(.022,.042,.063),.25,.19)
rubber=mat('03_Graphite',(.018,.022,.028),0,.72)
alloy=mat('04_Satin_Alloy',(.7,.76,.8),.65,.25)
body=[]
def mesh(name,verts,faces,material,collect=True):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);o.data.materials.append(material)
 if collect:body.append(o)
 return o
def box(name,loc,scale,material,bevel=0):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(material)
 if bevel:
  mod=o.modifiers.new('Small hard edge bevel','BEVEL');mod.width=bevel;mod.segments=1;bpy.ops.object.modifier_apply(modifier=mod.name)
 body.append(o);return o
# Single extruded side outline, with genuine open wheel arches.
outline=[(-2,.36),(-2,.66),(-1.8,.8),(-1.28,.85),(.9,.8),(1.83,.71),(2,.58),(2,.36)]
for cx in [1.2,-1.2]:
 outline.append((cx+.4,.36))
 for i in range(1,13):
  a=i*math.pi/12;outline.append((cx+.4*math.cos(a),.36+.4*math.sin(a)))
outline.append((-2,.36));outline=outline[:-1]
n=len(outline);v=[(x,y,z) for y in [-.76,.76] for x,z in outline]
faces=[]
for off in [0,n]:
 poly=[Vector(v[i+off]) for i in range(n)]
 for tri in tessellate_polygon([poly]):
  ix=[(t if isinstance(t,int) else poly.index(t))+off for t in tri];faces.append(tuple(ix if off else ix[::-1]))
for i in range(n):j=(i+1)%n;faces.append((i,j,n+j,n+i))
mesh('Sculpted body with wheel arches',v,faces,paint)
# Glass cabin volume; painted roof and slim structural pillars overlay it.
v=[(-1.27,-.70,.845),(.94,-.70,.8),(.39,-.57,1.32),(-.78,-.57,1.32),(-1.27,.70,.845),(.94,.70,.8),(.39,.57,1.32),(-.78,.57,1.32)]
mesh('Cabin glass',v,[(0,1,2,3),(4,7,6,5),(1,5,6,2),(0,3,7,4),(3,2,6,7)],glass)
box('Roof',(-.195,0,1.335),(1.22,1.18,.055),paint,.025)
def beam(name,a,b,width,material):
 a,b=Vector(a),Vector(b);o=box(name,(a+b)/2,(width,width,(b-a).length),material);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
for s in [-1,1]:
 beam('A pillar',(.94,s*.704,.8),(.39,s*.59,1.34),.055,paint)
 beam('C pillar',(-1.27,s*.704,.845),(-.78,s*.59,1.34),.085,paint)
 beam('B pillar',(-.38,s*.71,.835),(-.38,s*.586,1.32),.045,rubber)
 box('Door handle',(-.48,s*.777,.8),(.15,.026,.028),alloy,.008)
 box('Mirror',(.58,s*.84,.91),(.18,.14,.09),paint,.02)
 box('Lower sill',(0,s*.765,.39),(1.52,.045,.1),rubber,.014)
 # Front / rear lamp inserts all original geometric details, no logos.
 box('Headlight',(1.94,s*.51,.62),(.085,.34,.12),alloy,.02)
 box('Rear lamp',(-1.976,s*.51,.63),(.05,.31,.075),alloy,.008)
box('Front grille',(2.007,0,.455),(.025,.88,.12),rubber,.018)
box('Front splitter',(1.89,0,.335),(.28,1.58,.055),rubber,.012)
box('Rear bumper',(-1.96,0,.36),(.12,1.56,.075),rubber,.012)
# Hood sculpting / central dark accent.
mesh('Hood inset',[(1.03,-.30,.797),(1.77,-.24,.727),(1.77,.24,.727),(1.03,.30,.797)],[(0,1,2,3)],rubber)
def join(obs,name,origin):
 bpy.ops.object.select_all(action='DESELECT')
 for o in obs:o.select_set(True)
 bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();o=bpy.context.object;o.name=name;bpy.context.scene.cursor.location=origin;bpy.ops.object.origin_set(type='ORIGIN_CURSOR');return o
carbody=join(body,'Body',(0,0,0));wheels=[]
for x,label in [(1.2,'Front'),(-1.2,'Rear')]:
 for y,side in [(-.8,'Right'),(.8,'Left')]:
  obs=[]
  for radius,depth,yy,material in [(.32,.23,y,rubber),(.205,.237,y,alloy),(.138,.241,y,rubber),(.075,.249,y,alloy)]:
   bpy.ops.mesh.primitive_cylinder_add(vertices=16,radius=radius,depth=depth,end_fill_type='NGON',location=(x,yy,.32),rotation=(math.pi/2,0,0));o=bpy.context.object;o.data.materials.append(material);obs.append(o)
  wheel=join(obs,'Wheel_'+label+'_'+side,(x,y,.32));wheels.append(wheel)
assets=[carbody]+wheels
# Consistent outward normals and applied transforms, no hidden modifiers.
for o in assets:
 bpy.context.view_layer.objects.active=o;o.select_set(True)
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT');o.select_set(False)
root=bpy.data.objects.new('Street_Car_V1',None);bpy.context.collection.objects.link(root)
for o in assets:o.parent=root
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
# Export only car, not rendering rig.
bpy.ops.object.select_all(action='DESELECT');root.select_set(True)
for o in assets:o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(P/'street_car_v1.glb'),export_format='GLB',use_selection=True,export_yup=True,export_cameras=False,export_lights=False)
tri=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in assets)
pts=[o.matrix_world@Vector(p) for o in assets for p in o.bound_box]
bounds=[[min(p[i] for p in pts),max(p[i] for p in pts)] for i in range(3)]
json.dump({'blender':bpy.app.version_string,'triangles':tri,'mesh_objects':len(assets),'materials':len(bpy.data.materials),'bounds_xyz':bounds,'dimensions_xyz':[b-a for a,b in bounds]},open(P/'source_stats.json','w'),indent=2)
# Render rig, separate collection. Ground uses existing material, excluded from GLB.
rig=bpy.data.collections.new('Preview_Rig_NOT_EXPORTED');scene.collection.children.link(rig)
def rigmove(o):
 for c in list(o.users_collection):c.objects.unlink(o)
 rig.objects.link(o)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.015));ground=bpy.context.object;ground.name='Preview floor';ground.data.materials.append(rubber);rigmove(ground)
world=bpy.data.worlds.new('Studio') if not bpy.data.worlds else bpy.data.worlds[0];scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.15,.19,.25,1);world.node_tree.nodes['Background'].inputs[1].default_value=.45
for name,loc,power,size in [('Key',(1,-3,6),1100,5),('Fill',(-3,-1,4),700,4),('Rim',(0,4,5),1400,3)]:
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler();rigmove(o)
bpy.ops.object.camera_add(location=(5.5,-6,4.6));camera=bpy.context.object;rigmove(camera);scene.camera=camera;camera.data.type='ORTHO';camera.data.ortho_scale=5.9
scene.render.engine='CYCLES';scene.cycles.samples=64;scene.cycles.use_denoising=False
scene.render.resolution_x=1200;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
def render(loc,target,out,scale):
 camera.location=loc;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=scale;scene.render.filepath=str(P/out);bpy.ops.render.render(write_still=True)
render((5.5,-6,4.6),(0,0,.55),'three_quarter.png',5.65)
render((0,0,7),(0,0,0),'top.png',5.0)
camera.location=(5.5,-6,4.6);camera.rotation_euler=(Vector((0,0,.55))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=5.65
bpy.ops.object.select_all(action='DESELECT');carbody.select_set(True);bpy.context.view_layer.objects.active=carbody
bpy.ops.wm.save_as_mainfile(filepath=str(P/'street_car_v1.blend'),compress=True)
print('FINISHED',tri,bounds)
