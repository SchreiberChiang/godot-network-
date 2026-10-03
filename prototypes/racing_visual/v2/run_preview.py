"""Prepare a fresh isolated import and real Godot rendering. No dependencies.

Copy the exact known engine, with a local self-contained marker, to this
worktree's ignored artifacts. Never run the RoomKit main project or shared
editor cache. Existing runs are preserved; a third capture requires manual
review of retention instead of deleting evidence automatically.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

SOURCE=Path(__file__).resolve().parent
ROOT=SOURCE.parents[2]
ARTIFACT=ROOT/"artifacts"/"racing-models"
KNOWN_ENGINE=Path(r"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe")


def sha(path):
    return hashlib.file_digest(path.open("rb"),"sha256").hexdigest()


def safe_directory(path):
    require=path.resolve().is_relative_to(ROOT.resolve()/"artifacts")
    if not require: raise RuntimeError(f"Output escapes local artifacts: {path}")
    for p in [path,*path.parents]:
        if p==ROOT:break
        if p.exists() and (p.is_symlink() or p.is_junction()):raise RuntimeError(f"Linked output path: {p}")
    path.mkdir(parents=True,exist_ok=True)


def command(args,run,name,environment,timeout=60):
    startup=subprocess.STARTUPINFO()
    startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow=0
    stdout=run/"evidence"/(name+".stdout.log")
    stderr=run/"evidence"/(name+".stderr.log")
    with stdout.open("wb") as out,stderr.open("wb") as err:
        proc=subprocess.Popen([str(x) for x in args],cwd=run,env=environment,stdout=out,stderr=err,
                              startupinfo=startup,creationflags=subprocess.CREATE_NO_WINDOW)
        try: code=proc.wait(timeout)
        except subprocess.TimeoutExpired:
            proc.kill();proc.wait();code=124
    record={"command":[str(x) for x in args],"exit_code":code,"stdout":stdout.name,"stderr":stderr.name}
    (run/"evidence"/(name+".command.json")).write_text(json.dumps(record,indent=2)+"\n",encoding="utf-8")
    print(f"{name}: exit {code}")
    combined=stdout.read_text(encoding="utf-8",errors="replace")+stderr.read_text(encoding="utf-8",errors="replace")
    if code!=0 or any(t in combined for t in ["SCRIPT ERROR:","Parse Error:","ERROR:"]):
        raise RuntimeError(f"{name} failed; original logs retained in {run/'evidence'}\n{combined[-5000:]}")
    return combined


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--run-name",default="review-01")
    parser.add_argument("--interactive",action="store_true")
    args=parser.parse_args()
    if not re.fullmatch(r"[a-z0-9-]{1,40}",args.run_name):raise ValueError("Invalid run name")
    safe_directory(ARTIFACT)
    runtime=ARTIFACT/"runtime";safe_directory(runtime)
    engine=runtime/KNOWN_ENGINE.name
    for original in [KNOWN_ENGINE,KNOWN_ENGINE.with_name("steam_api64.dll")]:
        target=runtime/original.name
        if not target.exists():shutil.copyfile(original,target)
        if sha(target)!=sha(original):raise RuntimeError("Isolated engine copy differs from known engine")
    (runtime/"._sc_").touch()
    run=ARTIFACT/args.run_name
    if not args.interactive:
        if run.exists():raise RuntimeError("Fresh import requires a new run; previous evidence preserved")
        prior=[p for p in ARTIFACT.iterdir() if p.is_dir() and p.name!="runtime"]
        if len(prior)>=2:raise RuntimeError("Two runs already retained; inspect evidence before any cleanup")
        safe_directory(run)
        safe_directory(run/"project");safe_directory(run/"evidence")
        shutil.copytree(SOURCE/"models",run/"project"/"models")
        shutil.copyfile(SOURCE/"preview.gd",run/"project"/"preview.gd")
        (run/"project"/"project.godot").write_text('''config_version=5
[application]
config/name="Racing Models V2 Isolated Preview"
run/main_scene="res://main.tscn"
[display]
window/size/viewport_width=1280
window/size/viewport_height=960
window/size/window_width_override=1280
window/size/window_height_override=960
window/stretch/mode="canvas_items"
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/default_filters/use_nearest_mipmap_filter=false
anti_aliasing/quality/msaa_3d=2
''',encoding="utf-8")
        (run/"project"/"main.tscn").write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://preview.gd" id="1"]
[node name="Preview" type="Node3D"]
script = ExtResource("1")
''',encoding="utf-8")
    elif not (run/"evidence"/"godot_result.json").exists() or json.loads((run/"evidence"/"godot_result.json").read_text(encoding="utf-8"))["status"]!="PASS":
        raise RuntimeError("Interactive preview requires a previously successful capture run")
    env=os.environ.copy()
    for key,sub in [("APPDATA","profile/roaming"),("LOCALAPPDATA","profile/local"),("USERPROFILE","profile"),
                    ("HOME","profile"),("TEMP","temp"),("TMP","temp"),("XDG_DATA_HOME","profile/data"),
                    ("XDG_CONFIG_HOME","profile/config"),("XDG_CACHE_HOME","profile/cache")]:
        location=run/sub;safe_directory(location);env[key]=str(location)
    base=[engine,"--path",run/"project"]
    if args.interactive:
        final=run/"final-import"
        if (final/"evidence"/"final_import_result.json").exists():
            checked=json.loads((final/"evidence"/"final_import_result.json").read_text(encoding="utf-8"))
            if checked["status"]!="PASS":raise RuntimeError("Final model gate did not pass")
            for p in (SOURCE/"models").glob("*.glb"):
                if sha(p)!=sha(final/"project"/"models"/p.name):raise RuntimeError("Final preview model has changed")
            # Prepare the user's final-model preview without replacing old captures.
            shutil.copyfile(SOURCE/"preview.gd",final/"project"/"preview.gd")
            for name in ["project.godot","main.tscn"]:
                shutil.copyfile(run/"project"/name,final/"project"/name)
            base=[engine,"--path",final/"project"]
        subprocess.Popen([str(x) for x in base]+["--","--interactive"],cwd=run,env=env)
        print(f"Preview launched from {run}; ESC exits.")
        return
    version=command([engine,"--version"],run,"version",env)
    if version.strip()!="4.7.2.stable.steam.ed1daf0bf":raise RuntimeError("Unexpected engine version")
    if (run/"project"/".godot").exists():raise RuntimeError("Cold-import cache unexpectedly present")
    sources={p.name:{"bytes":p.stat().st_size,"sha256":sha(p)} for p in sorted((run/"project"/"models").glob("*.glb"))}
    for name,record in sources.items():
        if record["sha256"]!=sha(SOURCE/"models"/name):raise RuntimeError("Model copy differs from source")
    if sha(run/"project"/"preview.gd")!=sha(SOURCE/"preview.gd"):raise RuntimeError("Preview copy differs from source")
    (run/"evidence"/"provenance.json").write_text(json.dumps({"engine_source":str(KNOWN_ENGINE),"engine_sha256":sha(engine),
        "isolated_engine":str(engine),"cold_import":True,"models":sources,"preview_sha256":sha(run/"project"/"preview.gd"),
        "environment_overrides":{k:env[k] for k in ["APPDATA","LOCALAPPDATA","USERPROFILE","HOME","TEMP","TMP","XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME"]}},indent=2)+"\n",encoding="utf-8")
    command(base+["--headless","--editor","--import","--log-file",run/"evidence"/"import.engine.log"],run,"cold-import",env)
    command(base+["--rendering-method","gl_compatibility","--rendering-driver","opengl3","--max-fps","60",
                  "--log-file",run/"evidence"/"render.engine.log"],run,"render",env)
    result=json.loads((run/"evidence"/"godot_result.json").read_text(encoding="utf-8"))
    if result["status"]!="PASS":raise RuntimeError("Runtime checks failed")
    expected={"three_quarter.png","top.png","kit.png","wheel_check.png"}
    if {p.name for p in (run/"evidence").glob("*.png")}!=expected:raise RuntimeError("Missing screenshots")
    print("V2_PREVIEW_PASS " + str(run/"evidence"))


if __name__=="__main__":
    try:main()
    except Exception as exc:
        print(str(exc),file=sys.stderr)
        sys.exit(1)
