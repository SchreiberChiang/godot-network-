"""Original geometric street-car kit. Python 3 standard library only.

Units: metres; +Y up, -Z forward, -X driver left. No external inputs/textures.
All normals are authored outwards; no double-sided workaround or zero-area faces.
"""
from pathlib import Path
import hashlib
import json
import math
import struct

HERE = Path(__file__).resolve().parent
MATERIALS = [
    ("Lagoon_Paint", (0.035, 0.51, 0.43), 0.12, 0.43),
    ("Ink_Glass", (0.035, 0.080, 0.105), 0.12, 0.24),
    ("Graphite_Rubber", (0.038, 0.047, 0.055), 0.0, 0.85),
    ("Warm_Porcelain", (0.88, 0.88, 0.78), 0.03, 0.45),
    ("Signal_Orange", (1.0, 0.24, 0.045), 0.0, 0.52),
    ("Satin_Aluminium", (0.40, 0.48, 0.51), 0.25, 0.48),
]
TEAL, GLASS, RUBBER, WHITE, ORANGE, ALLOY = range(6)


def sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


class Mesh:
    def __init__(self, name):
        self.name = name
        self.parts = {}

    def face(self, pts, material, outward):
        """Convex planar polygons only, fan triangles with explicit outward hint."""
        pts = list(pts)
        n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
        if dot(n, outward) < 0:
            pts.reverse()
        p, normals, indices = self.parts.setdefault(material, ([], [], []))
        for i in range(1, len(pts)-1):
            tri = [pts[0], pts[i], pts[i+1]]
            n = cross(sub(tri[1], tri[0]), sub(tri[2], tri[0]))
            length = math.sqrt(dot(n, n))
            if length < 1e-9:
                raise ValueError(f"Degenerate source face in {self.name}: {tri}")
            normal = [x/length for x in n]
            start = len(p)
            p.extend(tri)
            normals.extend([normal]*3)
            indices.extend([start, start+1, start+2])

    def box(self, center, size, material):
        x, y, z = center
        a, b, c = [s/2 for s in size]
        v = [(x+dx*a, y+dy*b, z+dz*c) for dx, dy, dz in
             [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),
              (-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        for ids, normal in [([0,3,2,1],(0,0,-1)),([4,5,6,7],(0,0,1)),
                            ([0,4,7,3],(-1,0,0)),([1,2,6,5],(1,0,0)),
                            ([3,7,6,2],(0,1,0)),([0,1,5,4],(0,-1,0))]:
            self.face([v[i] for i in ids], material, normal)

    def beam(self, a, b, width, material):
        direction = sub(b, a)
        length = math.sqrt(dot(direction, direction))
        axis = tuple(x/length for x in direction)
        ref = (1,0,0) if abs(axis[0]) < .9 else (0,1,0)
        u = cross(axis, ref)
        scale = width/(2*math.sqrt(dot(u,u)))
        u = tuple(x*scale for x in u)
        v = cross(axis,u)
        rings = [[tuple(p[k]+i*u[k]+j*v[k] for k in range(3))
                  for i,j in [(-1,-1),(1,-1),(1,1),(-1,1)]] for p in [a,b]]
        self.face(rings[0],material,tuple(-x for x in axis))
        self.face(rings[1],material,axis)
        for i in range(4):
            j=(i+1)%4
            out=tuple(rings[0][i][k]+rings[0][j][k]-2*a[k] for k in range(3))
            self.face([rings[0][i],rings[0][j],rings[1][j],rings[1][i]],material,out)

    def lathe(self, profile, material, segments=16, axis="x", center=(0,0,0), caps=False):
        """Profile is (axis_position,radius), from one end to the other.
        Closed annular profiles are oriented by their signed 2D polygon area.
        """
        def point(a,r,t):
            local = (a,r*math.cos(t),r*math.sin(t)) if axis=="x" else (r*math.cos(t),a,r*math.sin(t))
            return tuple(local[k]+center[k] for k in range(3))
        closed = profile[0] == profile[-1]
        if not closed and profile[-1][0] < profile[0][0]:
            profile = list(reversed(profile))
        signed = sum(a*d-c*b for (a,b),(c,d) in zip(profile,profile[1:])) if closed else 1
        for (a,r),(b,s) in zip(profile,profile[1:]):
            for i in range(segments):
                t, u = i*math.tau/segments, (i+1)*math.tau/segments
                # For open tires: outward radial; closed rings: right/left profile normal.
                axial, radial = (r-s, b-a)
                if closed and signed > 0:
                    axial, radial = -axial,-radial
                mid=(t+u)/2
                n=(axial,radial*math.cos(mid),radial*math.sin(mid)) if axis=="x" else (radial*math.cos(mid),axial,radial*math.sin(mid))
                self.face([point(a,r,t),point(b,s,t),point(b,s,u),point(a,r,u)],material,n)
        if caps:
            for (a,r), sign in [(profile[0],-1),(profile[-1],1)]:
                self.face([point(a,r,i*math.tau/segments) for i in range(segments)],material,
                          (sign,0,0) if axis=="x" else (0,sign,0))


class Asset:
    def __init__(self, name):
        self.name=name
        self.meshes=[]
        self.nodes=[{"name":name,"children":[],"extras":{"units":"metres","forward":"-Z","up":"+Y"}}]

    def node(self,name,parent=0,translation=None,mesh=None,extras=None):
        n={"name":name}
        if translation is not None:
            n["translation"]=translation
        if mesh is not None:
            n["mesh"]=len(self.meshes)
            self.meshes.append(mesh)
        if extras:
            n["extras"]=extras
        index=len(self.nodes)
        self.nodes.append(n)
        self.nodes[parent].setdefault("children",[]).append(index)
        return index

    def save(self,path):
        data=bytearray()
        doc={"asset":{"version":"2.0","generator":"RoomKit original V2 standard-library generator"},
             "scene":0,"scenes":[{"nodes":[0]}],"nodes":self.nodes,
             "meshes":[],"materials":[],"accessors":[],"bufferViews":[]}
        used=sorted({m for mesh in self.meshes for m in mesh.parts})
        for index in used:
            name,color,metal,rough=MATERIALS[index]
            doc["materials"].append({"name":name,"doubleSided":False,"pbrMetallicRoughness":{
                "baseColorFactor":[*color,1],"metallicFactor":metal,"roughnessFactor":rough}})
        def accessor(values,kind,component,target):
            while len(data)%4: data.append(0)
            start=len(data)
            for value in values:
                value=value if isinstance(value,(list,tuple)) else [value]
                data.extend(struct.pack("<"+("f" if component==5126 else "H")*len(value),*value))
            view=len(doc["bufferViews"])
            doc["bufferViews"].append({"buffer":0,"byteOffset":start,"byteLength":len(data)-start,"target":target})
            acc={"bufferView":view,"componentType":component,"count":len(values),"type":kind}
            if kind=="VEC3":
                acc.update(min=[min(v[i] for v in values) for i in range(3)],max=[max(v[i] for v in values) for i in range(3)])
            doc["accessors"].append(acc)
            return len(doc["accessors"])-1
        for mesh in self.meshes:
            primitives=[]
            for mat,(positions,normals,indices) in sorted(mesh.parts.items()):
                primitives.append({"attributes":{"POSITION":accessor(positions,"VEC3",5126,34962),
                                                   "NORMAL":accessor(normals,"VEC3",5126,34962)},
                                   "indices":accessor(indices,"SCALAR",5123,34963),"material":used.index(mat),"mode":4})
            doc["meshes"].append({"name":mesh.name,"primitives":primitives})
        doc["buffers"]=[{"byteLength":len(data)}]
        raw=json.dumps(doc,separators=(",",":"),allow_nan=False).encode()
        raw+=b" "*((-len(raw))%4)
        data+=b"\0"*((-len(data))%4)
        glb=struct.pack("<III",0x46546c67,2,12+8+len(raw)+8+len(data))
        glb+=struct.pack("<II",len(raw),0x4e4f534a)+raw+struct.pack("<II",len(data),0x004e4942)+data
        path.write_bytes(glb)
        return {"file":path.name,"bytes":len(glb),"sha256":hashlib.sha256(glb).hexdigest(),
                "triangles":sum(len(part[2])//3 for mesh in self.meshes for part in mesh.parts.values()),
                "materials":len(used),"nodes":len(self.nodes)}


def street_car():
    asset=Asset("Street_Car_V2")
    body=Mesh("Body")
    # Longitudinal shoulder contour, front at -Z. Open wheel arches in outer skin.
    contour=[(-2.0,.70,.65),(-1.78,.80,.78),(-1.0,.83,.87),(.9,.83,.87),(1.67,.80,.79),(2.0,.73,.69)]
    def shoulder(z):
        for (a,x,y),(b,u,v) in zip(contour,contour[1:]):
            if a<=z<=b:
                t=(z-a)/(b-a)
                return x+(u-x)*t,y+(v-y)*t
        raise ValueError(z)
    cuts=sorted(set([p[0] for p in contour]+[-2.,2.]+[
        round(c+.435*math.cos(i*math.pi/12),9) for c in [-1.23,1.22] for i in range(13)]))
    def lower(z):
        for c in [-1.23,1.22]:
            if abs(z-c)<=.435+1e-8:
                return .34+math.sqrt(max(0,.435**2-(z-c)**2))
        return .29
    # Independent strips guarantee every triangle has nonzero width.
    for side in [-1,1]:
        for a,b in zip(cuts,cuts[1:]):
            ax,ay=shoulder(a); bx,by=shoulder(b)
            body.face([(side*ax,ay,a),(side*bx,by,b),(side*bx,lower(b),b),(side*ax,lower(a),a)],TEAL,(side,0,0))
        for c in [-1.23,1.22]:
            for i in range(12):
                a=i*math.pi/12;b=(i+1)*math.pi/12
                pts=[(side*.845,.34+r*math.sin(t),c+r*math.cos(t)) for r,t in
                     [(.438,a),(.438,b),(.478,b),(.478,a)]]
                body.face(pts,TEAL,(side,0,0))
        body.box((side*.80,.33,0),(.06,.09,1.45),RUBBER)
        body.box((side*.839,.73,.46),(.02,.027,.20),ALLOY)
        body.box((side*.90,.96,-.73),(.20,.105,.20),TEAL)
        body.box((side*1.005,.965,-.73),(.015,.068,.13),GLASS)
        # Fine door seam, kept below the bright shoulder line.
        body.beam((side*.838,.45,.82),(side*.838,.82,.82),.013,RUBBER)
    # Narrow internal spine leaves clearance for the front tires at +/-25 degrees.
    # Separate mesh also allows exact imported-AABB clearance verification.
    chassis=Mesh("Chassis_Visual")
    chassis.box((0,.48,0),(.98,.36,3.76),RUBBER)
    asset.node("Chassis_Visual",mesh=chassis)
    for (a,x,y),(b,u,v) in zip(contour,contour[1:]):
        body.face([(-x,y,a),(x,y,a),(u,v,b),(-u,v,b)],TEAL,(0,1,0))
    for z,x,y in [contour[0],contour[-1]]:
        body.face([(-x,.29,z),(x,.29,z),(x,y,z),(-x,y,z)],TEAL,(0,0,z))
    body.box((0,.315,-1.95),(1.53,.09,.16),RUBBER)
    body.box((0,.33,1.96),(1.52,.11,.12),RUBBER)
    body.box((0,.47,-2.012),(.84,.17,.028),RUBBER)
    body.box((0,.51,2.012),(.58,.16,.025),RUBBER)
    for s in [-1,1]:
        body.box((s*.49,.62,-2.014),(.29,.095,.035),WHITE)
        body.box((s*.58,.63,2.014),(.27,.085,.035),ORANGE)
    body.box((.42,.37,-2.045),(.115,.10,.05),ORANGE)
    # Fastback cabin: six separate planar surfaces, contrasting floating roof.
    fl=(-.70,.882,-.99); fr=(.70,.882,-.99)
    rl=(-.70,.882,1.29); rr=(.70,.882,1.29)
    tfl=(-.56,1.315,-.43); tfr=(.56,1.315,-.43)
    trl=(-.56,1.315,.63); trr=(.56,1.315,.63)
    body.face([fl,fr,tfr,tfl],GLASS,(0,1,-1))
    body.face([rl,trl,trr,rr],GLASS,(0,1,1))
    body.face([fl,tfl,trl,rl],GLASS,(-1,0,0))
    body.face([fr,rr,trr,tfr],GLASS,(1,0,0))
    for a,b in [(fl,tfl),(fr,tfr),(rl,trl),(rr,trr)]: body.beam(a,b,.065,TEAL)
    for s in [-1,1]:
        body.beam((s*.705,.89,.30),(s*.563,1.315,.30),.046,TEAL)
        body.beam((s*.71,.897,-.96),(s*.71,.897,1.24),.034,TEAL)
    body.box((0,1.338,.10),(1.18,.055,1.17),WHITE)
    body.box((0,.928,1.38),(1.41,.062,.16),TEAL)
    # Restrained orange identification tab, asymmetric to help read heading.
    body.face([(.34,.873,-1.04),(.50,.873,-1.04),(.49,.807,-1.55),(.33,.807,-1.55)],ORANGE,(0,1,0))
    body.face([(-.43,.837,-1.23),(.15,.837,-1.23),(.15,.814,-1.44),(-.43,.814,-1.44)],TEAL,(0,1,0))
    asset.node("Body",mesh=body)
    for z,label in [(-1.23,"Front"),(1.22,"Rear")]:
        for x,side in [(-.82,"Left"),(.82,"Right")]:
            carrier=asset.node(f"Steer_{label}_{side}",translation=[x,.34,z],extras={"steering_axis":"+Y","steerable":label=="Front"})
            wheel=Mesh(f"Wheel_{label}_{side}")
            wheel.lathe([(-.13,.28),(-.108,.325),(-.082,.34),(.082,.34),(.108,.325),(.13,.28)],RUBBER,16,caps=True)
            # Wheel faces are annular; visible spoke offsets make rolling readable.
            for sign in [-1,1]:
                wheel.lathe([(sign*.132,.245),(sign*.132,.185),(sign*.14,.185),(sign*.14,.245),(sign*.132,.245)],ALLOY,16)
                wheel.lathe([(sign*.135,.082),(sign*.154,.082)],ALLOY,12,caps=True)
                for i in range(6):
                    a=i*math.tau/6+.1
                    b=a+.21
                    wheel.face([(sign*.147,r*math.cos(t),r*math.sin(t)) for r,t in
                                [(.074,a),(.22,a),(.22,b),(.074,b)]],ALLOY,(sign,0,0))
                wheel.face([(sign*.151,r*math.cos(t),r*math.sin(t)) for r,t in
                            [(.247,0),(.285,0),(.285,.13),(.247,.13)]],ORANGE,(sign,0,0))
            asset.node(f"Wheel_{label}_{side}",parent=carrier,mesh=wheel,
                       extras={"rolling_axis":"+X","radius_m":.34,"forward_roll_sign":-1})
    asset.node("CenterOfMass_Suggested",translation=[0,.52,.04],extras={"advisory_only":True})
    return asset


def cone():
    asset=Asset("Traffic_Cone_V2")
    m=Mesh("Cone")
    m.box((0,.035,0),(.47,.07,.47),RUBBER)
    levels=[(.07,.19),(.26,.138),(.37,.108),(.52,.067),(.63,.037),(.68,.023)]
    for i,(a,b) in enumerate(zip(levels,levels[1:])):
        m.lathe([a,b],WHITE if i in [1,3] else ORANGE,12,axis="y")
    m.lathe([(.68,.023),(.689,.021)],ORANGE,12,axis="y",caps=True)
    asset.node("Cone",mesh=m)
    return asset


def tires():
    asset=Asset("Tire_Barrier_V2")
    m=Mesh("Tire_Barrier")
    for x in [-.72,0,.72]:
        for y in [.12,.38]:
            m.lathe([(-.12,.18),(-.12,.29),(-.085,.34),(.085,.34),(.12,.29),(.12,.18),(-.12,.18)],
                    RUBBER,16,axis="y",center=(x,y,0))
            # One sidewall highlight band; still a physical open tire.
            m.lathe([(.121,.205),(.122,.255),(.126,.255),(.126,.205),(.121,.205)],
                    ALLOY,16,axis="y",center=(x,y,0))
        m.box((x,.265,-.344),(.075,.53,.012),ORANGE)
    asset.node("Tire_Barrier",mesh=m)
    return asset


def roadblock():
    asset=Asset("Road_Barrier_V2")
    m=Mesh("Road_Barrier")
    for x in [-.75,.75]:
        for z in [-.29,.29]:
            m.box((x,.035,z),(.36,.07,.21),RUBBER)
            m.beam((x,.075,z),(x,.84,0),.075,ALLOY)
    m.box((0,.80,0),(2.1,.40,.13),WHITE)
    for side in [-1,1]:
        for i in range(5):
            x=-.93+i*.40
            m.face([(x,.603,side*.066),(x+.17,.603,side*.066),(x+.35,.997,side*.066),(x+.18,.997,side*.066)],
                   ORANGE,(0,0,side))
    m.box((0,1.01,0),(2.13,.035,.16),ALLOY)
    asset.node("Road_Barrier",mesh=m)
    return asset


def main():
    output=HERE/"models"
    output.mkdir(exist_ok=True)
    manifest=[]
    for name,build in [("street_car_v2",street_car),("traffic_cone_v2",cone),("tire_barrier_v2",tires),("road_barrier_v2",roadblock)]:
        result=build().save(output/(name+".glb"))
        manifest.append(result)
        print(json.dumps(result))
    (HERE/"source_manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")


if __name__=="__main__": main()
