"""Export the v29 hand-rebuild body GLB with the same exporter and clip list as v28.

Usage: blender -b -P tools/export_hands_v29.py
Only the body part is exported; eyes and the civilian outfit stay the v28 runtime files.
The shared exporter only knows filename versions up to v28, so the file is written as
body_standard_v28.glb into the v29 export folder and renamed to body_standard_v29.glb.
"""
import json, struct, sys
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/characters/player/3d/source/middle_school_v1/hand_rebuild_v29/hand_rebuild_v29.blend"
EXPORTS = ROOT / "assets/characters/player/3d/exports/hand_rebuild_v29"
REPORT = ROOT / "reports/hand_rebuild_v29"
bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False, use_scripts=False)
assert bpy.data.objects["Body_Hands_v7"].get("v29_rebuilt_hands"), "Run build_hands_v29.py --save first"
EXPORTS.mkdir(parents=True, exist_ok=True); REPORT.mkdir(parents=True, exist_ok=True)
data = (ROOT / "game/assets/characters/player/run_arm_v21/body_standard_v21.glb").read_bytes()
length = struct.unpack_from("<I", data, 12)[0]
clips = [a["name"] for a in json.loads(data[20:20 + length])["animations"]]
sys.path.insert(0, str(ROOT / "tools"))
import export_source_outfit_v11 as exporter
sys.argv = ["export", "--", str(EXPORTS), str(REPORT / "export_reference.json"), "--filename-version", "v28",
            "--parts", "body", "--sample-step", "12"]
for clip in clips:
    sys.argv += ["--clip", clip]
exporter.main()
written = EXPORTS / "body_standard_v28.glb"
final = EXPORTS / "body_standard_v29.glb"
written.replace(final)
print("V29_EXPORTED", final, clips, flush=True)
