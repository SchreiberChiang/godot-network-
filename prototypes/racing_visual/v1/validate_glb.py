import bpy,json,math,struct
from pathlib import Path
from mathutils import Vector
P=Path(__file__).parent
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(P/'street_car_v1.glb'))
obs=[o for o in bpy.context.scene.objects if o.type=='MESH']; wheels=[o for o in obs if o.name.startswith('Wheel_')]
pts=[o.matrix_world@Vector(v) for o in obs for v in o.bound_box]
bounds=[[min(v[i] for v in pts),max(v[i] for v in pts)] for i in range(3)]
dim=[b-a for a,b in bounds];tri=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in obs)
materials=sorted(set(m.name for o in obs for m in o.data.materials))
centers={o.name:list(o.matrix_world.translation) for o in wheels}
checks={'exactly_one_body_and_four_wheels':len(obs)==5 and len(wheels)==4 and sum(o.name=='Body' for o in obs)==1,'distinct_wheel_meshes':len(set(o.data.as_pointer() for o in wheels))==4,'finite_nonzero_bounds':all(math.isfinite(x) and x>0 for x in dim),'approximately_four_meters':3.9<dim[0]<4.2,'ground_contact':abs(bounds[2][0])<1e-5,'triangle_budget':tri<=4000,'material_budget':len(materials)<=4,'nonzero_glb':(P/'street_car_v1.glb').stat().st_size>0,'wheel_pivots':all(abs(abs(c[0])-1.2)<1e-5 and abs(abs(c[1])-.8)<1e-5 and abs(c[2]-.32)<1e-5 for c in centers.values())}
data=(P/'street_car_v1.glb').read_bytes();length,typ=struct.unpack_from('<II',data,12);gltf=json.loads(data[20:20+length]);checks['no_external_assets']=not gltf.get('images') and all('uri' not in b for b in gltf.get('buffers',[]))
r={'status':'PASS' if all(checks.values()) else 'FAIL','checks':checks,'reimport_meshes':[o.name for o in obs],'bounds_xyz_m':bounds,'dimensions_xyz_m':dim,'triangles':tri,'materials':materials,'wheel_centers_blender_xyz':centers,'glb_bytes':len(data),'blender_version':bpy.app.version_string}
json.dump(r,open(P/'validation.json','w'),indent=2);print(json.dumps(r,indent=2));assert all(checks.values())
