"""One local entry; reuse a successful run, otherwise create one isolated run."""
from pathlib import Path
import json
import subprocess
import sys

source=Path(__file__).resolve().parent
artifact=source.parents[2]/"artifacts"/"racing-models"
runs=[]
if artifact.exists():
    for result in artifact.glob("*/evidence/godot_result.json"):
        if json.loads(result.read_text(encoding="utf-8"))["status"]=="PASS":
            runs.append(result.parent.parent)
if runs:
    name=max(runs,key=lambda p:p.stat().st_mtime).name
else:
    name="preview-01"
    subprocess.run([sys.executable,"-B",str(source/"run_preview.py"),"--run-name",name],check=True)
subprocess.run([sys.executable,"-B",str(source/"run_preview.py"),"--run-name",name,"--interactive"],check=True)
