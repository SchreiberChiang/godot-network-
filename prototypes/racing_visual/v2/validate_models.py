"""Independent validation of the bytes written to GLB, not generator objects."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import struct

HERE=Path(__file__).resolve().parent


def require(condition,message):
    if not condition:
        raise ValueError(message)


def inspect(path):
    raw=path.read_bytes()
    magic,version,size=struct.unpack_from("<III",raw)
    require(magic==0x46546c67 and version==2 and size==len(raw),"Invalid GLB header")
    chunks=[]; cursor=12
    while cursor<len(raw):
        length,kind=struct.unpack_from("<II",raw,cursor);cursor+=8
        require(length%4==0 and cursor+length<=len(raw),"Invalid chunk bounds")
        chunks.append((kind,raw[cursor:cursor+length]));cursor+=length
    require([t for t,_ in chunks]==[0x4e4f534a,0x004e4942],"Expected JSON/BIN")
    doc=json.loads(chunks[0][1]);data=chunks[1][1]
    require(len(doc["buffers"])==1 and "uri" not in doc["buffers"][0],"External buffer")
    require(0<=len(data)-doc["buffers"][0]["byteLength"]<=3,"BIN length mismatch")
    require(not doc.get("images") and not doc.get("textures") and not doc.get("extensionsRequired"),"External/texture/extension dependency")
    require(1<=len(doc["materials"])<=6,"Material budget")
    require(all(not m.get("doubleSided",False) for m in doc["materials"]),"Two-sided material masks winding")
    def accessor(index):
        require(isinstance(index,int) and 0<=index<len(doc["accessors"]),"Accessor index")
        a=doc["accessors"][index];v=doc["bufferViews"][a["bufferView"]]
        require(0<=a["bufferView"]<len(doc["bufferViews"]),"View index")
        require(v["buffer"]==0 and not a.get("sparse"),"Unsupported buffer/accessor")
        count={"VEC3":3,"SCALAR":1}[a["type"]]
        fmt,width={5126:("f",4),5123:("H",2),5125:("I",4)}[a["componentType"]]
        step=v.get("byteStride",count*width);offset=a.get("byteOffset",0)
        require(a["count"]>0 and step>=count*width and offset>=0,"Invalid count/stride/offset")
        require(offset+(a["count"]-1)*step+count*width<=v["byteLength"],"Accessor beyond view")
        start=v.get("byteOffset",0)
        require(start>=0 and v["byteLength"]>0 and start+v["byteLength"]<=doc["buffers"][0]["byteLength"],"View beyond buffer")
        out=[struct.unpack_from("<"+fmt*count,data,start+offset+i*step) for i in range(a["count"])]
        require(all(math.isfinite(x) for row in out for x in row),"Nonfinite accessor")
        if "min" in a:
            require(all(abs(min(p[i] for p in out)-a["min"][i])<1e-6 for i in range(count)),"Accessor min mismatch")
            require(all(abs(max(p[i] for p in out)-a["max"][i])<1e-6 for i in range(count)),"Accessor max mismatch")
        return out
    meshes=[]
    for mesh in doc["meshes"]:
        all_positions=[];triangles=0;bad=0;min_cross_sq=float("inf")
        for p in mesh["primitives"]:
            require(p.get("mode",4)==4,"Not triangles")
            require(0<=p["material"]<len(doc["materials"]),"Material index")
            positions=accessor(p["attributes"]["POSITION"])
            normals=accessor(p["attributes"]["NORMAL"])
            indices=[v[0] for v in accessor(p["indices"])]
            for key in ["POSITION","NORMAL"]:
                a=doc["accessors"][p["attributes"][key]]
                require(a["componentType"]==5126 and a["type"]=="VEC3","Attribute type")
            ia=doc["accessors"][p["indices"]]
            require(ia["componentType"] in [5123,5125] and ia["type"]=="SCALAR","Index type")
            require(len(normals)==len(positions) and len(indices)%3==0,"Array lengths")
            require(all(0<=i<len(positions) for i in indices),"Invalid vertex index")
            require(all(abs(sum(x*x for x in n)-1)<1e-5 for n in normals),"Nonunit normal")
            for i in range(0,len(indices),3):
                ids=indices[i:i+3];a,b,c=[positions[j] for j in ids]
                u=[b[k]-a[k] for k in range(3)];v=[c[k]-a[k] for k in range(3)]
                cross=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
                square=sum(x*x for x in cross);min_cross_sq=min(min_cross_sq,square)
                bad+=square<1e-16
                require(all(sum(cross[k]*normals[j][k] for k in range(3))>0 for j in ids),"Normal/winding mismatch")
            triangles+=len(indices)//3;all_positions.extend(positions)
        require(bad==0,"Degenerate triangles")
        meshes.append({"name":mesh["name"],"triangles":triangles,"degenerate_triangles":bad,
                       "min_cross_squared":min_cross_sq,"positions":all_positions})
    nodes=doc["nodes"];visited=set();world_points=[];wheel_nodes=[];instance_triangles=0
    def walk(index,parent=(0,0,0)):
        nonlocal instance_triangles
        require(0<=index<len(nodes) and index not in visited,"Cycle/shared node/index")
        visited.add(index);n=nodes[index]
        require("matrix" not in n and n.get("rotation",[0,0,0,1])==[0,0,0,1] and n.get("scale",[1,1,1])==[1,1,1],"Expected baked identity rotation/scale")
        t=n.get("translation",[0,0,0]);require(len(t)==3 and all(math.isfinite(x) for x in t),"Invalid translation")
        world=tuple(parent[k]+t[k] for k in range(3))
        if "mesh" in n:
            require(0<=n["mesh"]<len(meshes),"Mesh index")
            mesh=meshes[n["mesh"]];instance_triangles+=mesh["triangles"]
            pts=mesh["positions"]
            world_points.extend([tuple(p[k]+world[k] for k in range(3)) for p in pts])
            if n["name"].startswith("Wheel_"):
                low=[min(p[k] for p in pts) for k in range(3)];high=[max(p[k] for p in pts) for k in range(3)]
                require(all(abs(low[k]+high[k])<1e-6 for k in range(3)),"Wheel mesh not centered on pivot")
                require(abs(high[1]-.34)<1e-6 and abs(high[2]-.34)<1e-6 and high[0]<.16,"Wrong rolling axis/radius")
                require(t==[0,0,0],"Wheel local offset")
                wheel_nodes.append({"name":n["name"],"mesh_index":n["mesh"],"center":world,"local_bounds":[low,high]})
        for child in n.get("children",[]):walk(child,world)
    for root in doc["scenes"][doc.get("scene",0)]["nodes"]:walk(root)
    require(len(visited)==len(nodes),"Unreachable nodes")
    lo=[min(p[k] for p in world_points) for k in range(3)];hi=[max(p[k] for p in world_points) for k in range(3)]
    dim=[hi[k]-lo[k] for k in range(3)]
    require(-1e-5<=lo[1]<=.025,"Asset root not on ground")
    clearance=None
    if path.name=="street_car_v2.glb":
        require(3.8<=dim[2]<=4.3 and dim[2]>dim[0] and 1.2<=dim[1]<=1.5,"Car dimensions/orientation")
        require(instance_triangles<=5000,"Car triangle budget")
        require(len(wheel_nodes)==4 and len({w["mesh_index"] for w in wheel_nodes})==4,"Four independent wheels")
        by_name={n["name"]:n for n in nodes}
        spine=meshes[by_name["Chassis_Visual"]["mesh"]]["positions"]
        spine_half_width=max(abs(p[0]) for p in spine)
        # Conservative swept cylinder: valid for every roll angle, not just samples.
        max_steer=.44
        tire_axial=max(abs(x) for w in wheel_nodes for x in [w["local_bounds"][0][0],w["local_bounds"][1][0]])
        tire_radius=max(math.hypot(p[1],p[2]) for w in wheel_nodes for p in meshes[w["mesh_index"]]["positions"])
        swept_half_width=tire_axial*math.cos(max_steer)+tire_radius*math.sin(max_steer)
        min_clearance=min(abs(w["center"][0]) for w in wheel_nodes)-swept_half_width-spine_half_width
        require(min_clearance>.04,"Internal chassis intrudes into wheel steering envelope")
        clearance={"method":"conservative_cylinder_swept_about_Y_any_roll","max_steer_radians":max_steer,
                   "chassis_half_width":spine_half_width,"wheel_max_radial_distance_m":tire_radius,"minimum_lateral_gap_m":min_clearance,
                   "scope":"internal_Chassis_Visual_only_not_full_body_or_physics"}
        for w in wheel_nodes:
            x,y,z=w["center"]
            require((x<0)==("Left" in w["name"]) and (z<0)==("Front" in w["name"]),"Wheel naming/position")
            require(abs(y-.34)<1e-6,"Wheel height")
            parent=by_name[w["name"].replace("Wheel_","Steer_")]
            require(parent["children"]==[next(i for i,n in enumerate(nodes) if n["name"]==w["name"])],"Steer/roll hierarchy")
    else:
        require(instance_triangles<=2500 and max(dim)<2.5,"Prop complexity/size")
    for mesh in meshes:mesh.pop("positions")
    return {"file":path.name,"bytes":len(raw),"sha256":hashlib.sha256(raw).hexdigest(),"status":"PASS",
            "materials":[m["name"] for m in doc["materials"]],"triangles":instance_triangles,
            "dimensions_xyz":dim,"world_bounds":[lo,hi],"meshes":meshes,"wheels":wheel_nodes,
            "external_resources":False,"degenerate_triangles":sum(m["degenerate_triangles"] for m in meshes),
            "wheel_chassis_clearance":clearance}


def main():
    parser=argparse.ArgumentParser();parser.add_argument("--output",type=Path,default=HERE/"validation.json")
    args=parser.parse_args()
    assets=[inspect(HERE/"models"/name) for name in ["street_car_v2.glb","traffic_cone_v2.glb","tire_barrier_v2.glb","road_barrier_v2.glb"]]
    require(len({m for a in assets for m in a["materials"]})<=6,"Kit material budget")
    report={"status":"PASS","checks":"GLB bytes/accessors/indices/finite positions/unit normals/winding/bounds/budgets/degenerates/wheel pivots/self-contained",
            "not_checked":["Full Khronos validator","Blender","Godot import/render (separate evidence)","Physics/driving"],"assets":assets}
    args.output.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"status":"PASS","assets":[{"file":a["file"],"triangles":a["triangles"],"dimensions_xyz":a["dimensions_xyz"],"degenerate_triangles":a["degenerate_triangles"]} for a in assets]}))


if __name__=="__main__":main()
