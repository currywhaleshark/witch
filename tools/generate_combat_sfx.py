"""Generate combat sound effect candidates with ElevenLabs text-to-sound-effects.

The effect list lives in tools/combat_sfx.json. Run from the repository root:

    python tools/generate_combat_sfx.py --dry-run          # show the plan, no API call
    python tools/generate_combat_sfx.py --only shotgun_fire
    python tools/generate_combat_sfx.py                    # every missing effect

The API key is read from ELEVENLABS_API_KEY, loaded from .env.local; it is never
printed or written anywhere else. Existing files are kept unless --force is given.
Generated files are candidates: nothing here wires them into the game.
"""
import argparse
import hashlib
import io
import json
import sys
import wave
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / "tools/combat_sfx.json").read_text(encoding="utf-8"))
parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
parser.add_argument("--only", nargs="+", metavar="ID", help="generate only these effect ids")
parser.add_argument("--force", action="store_true", help="regenerate effects that already exist")
parser.add_argument("--dry-run", action="store_true", help="print the plan without calling the API")
args = parser.parse_args()

effects = manifest["effects"]
known = {effect["id"] for effect in effects}
if args.only:
    unknown = sorted(set(args.only) - known)
    if unknown:
        sys.exit(f"Unknown effect id(s): {', '.join(unknown)}")
    effects = [effect for effect in effects if effect["id"] in args.only]

output_dir = root / manifest["output_dir"]
report_path = root / manifest["report"]
# Effects replaced by user-supplied files are never generated, even with --force.
supplied = [effect for effect in effects if effect.get("supplied")]
effects = [effect for effect in effects if not effect.get("supplied")]
for effect in supplied:
    print(f"  {effect['id']}: user-supplied ({', '.join(effect['supplied'])}), skipped")
todo = [effect for effect in effects if args.force or not (output_dir / f"{effect['id']}.wav").exists()]
print(f"{len(todo)} to generate, {len(effects) - len(todo)} already present, "
      f"{sum(effect['seconds'] for effect in todo):.1f}s requested in total")
if args.dry_run:
    for effect in todo:
        print(f"  {effect['id']:<18} {effect['seconds']:>4}s{' loop' if effect.get('loop') else ''}  {effect['text']}")
    sys.exit(0)
if not todo:
    sys.exit(0)

load_dotenv(root / ".env.local")
from elevenlabs import ElevenLabs  # noqa: E402  (imported after the key is in the environment)

client = ElevenLabs()
report = json.loads(report_path.read_text(encoding="utf-8")) if report_path.exists() else {"effects": {}}
report.update({"generator": "ElevenLabs text-to-sound-effects", "model_id": manifest["model_id"],
               "output_format": manifest["output_format"], "status": manifest["status"]})
output_dir.mkdir(parents=True, exist_ok=True)
report_path.parent.mkdir(parents=True, exist_ok=True)
failed = []
for effect in todo:
    influence = effect.get("prompt_influence", manifest["defaults"]["prompt_influence"])
    try:
        audio = b"".join(client.text_to_sound_effects.convert(
            text=effect["text"], model_id=manifest["model_id"], output_format=manifest["output_format"],
            duration_seconds=effect["seconds"], prompt_influence=influence, loop=bool(effect.get("loop", False))))
    except Exception as error:  # Keep going; report every failure at the end.
        print(f"  FAILED {effect['id']}: {error}")
        failed.append(effect["id"])
        continue
    path = output_dir / f"{effect['id']}.wav"
    path.write_bytes(audio)
    with wave.open(io.BytesIO(audio), "rb") as clip:
        seconds = clip.getnframes() / clip.getframerate()
        rate, channels = clip.getframerate(), clip.getnchannels()
    report["effects"][effect["id"]] = {
        "file": path.relative_to(root).as_posix(), "text": effect["text"], "cue": effect["cue"],
        "requested_seconds": effect["seconds"], "prompt_influence": influence, "loop": bool(effect.get("loop", False)),
        "seconds": round(seconds, 3), "sample_rate": rate, "channels": channels,
        "sha256": hashlib.sha256(audio).hexdigest(),
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "listened": False, "wired_into_game": False}
    print(f"  wrote {path.relative_to(root).as_posix()} ({seconds:.2f}s)")
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
if failed:
    sys.exit(f"Failed: {', '.join(failed)}")
