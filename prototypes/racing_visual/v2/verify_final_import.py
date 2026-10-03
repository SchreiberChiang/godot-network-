"""Additional headless import only; preserves the two original rendered runs."""
import json
import os
import shutil
from run_preview import ARTIFACT, SOURCE, KNOWN_ENGINE, safe_directory, command, sha

run=ARTIFACT/"review-02"/"final-import"
if run.exists():raise RuntimeError("Final-import evidence already exists; refusing overwrite")
safe_directory(run/"project")
safe_directory(run/"evidence")
shutil.copytree(SOURCE/"models",run/"project"/"models")
shutil.copyfile(SOURCE/"verify_final.gd",run/"project"/"verify_final.gd")
(run/"project"/"project.godot").write_text('config_version=5\n[application]\nconfig/name="Racing V2 Final Headless Gate"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding="utf-8")
env=os.environ.copy()
prior=json.loads((ARTIFACT/"review-02"/"evidence"/"provenance.json").read_text(encoding="utf-8"))
env.update(prior["environment_overrides"])
engine=ARTIFACT/"runtime"/KNOWN_ENGINE.name
if sha(engine)!=sha(KNOWN_ENGINE):raise RuntimeError("Engine hash changed")
sources={p.name:{"bytes":p.stat().st_size,"sha256":sha(p)} for p in sorted((run/"project"/"models").glob("*.glb"))}
for name,record in sources.items():
    if record["sha256"]!=sha(SOURCE/"models"/name):raise RuntimeError("Model staging mismatch")
(run/"evidence"/"provenance.json").write_text(json.dumps({"models":sources,"engine_sha256":sha(engine),"cold_import":True,"rendered":False},indent=2)+"\n",encoding="utf-8")
base=[engine,"--headless","--path",run/"project"]
command(base+["--editor","--import"],run,"cold-import",env)
command(base+["--script","res://verify_final.gd"],run,"final-mesh-check",env)
print("FINAL_HEADLESS_IMPORT_PASS")
