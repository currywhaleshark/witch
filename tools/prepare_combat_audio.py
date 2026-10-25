"""Trim the generated impact; never synthesize replacement audio.

Source is an Agent Audio 3-second output, retained locally but ignored in Git.
Run from the repository root after generating that source.
"""
import array
import hashlib
import json
import math
import wave
from pathlib import Path

source = Path("game/audio/mechanical_impact_source.wav")
output = source.with_name("mechanical_impact.wav")
with wave.open(str(source), "rb") as wav:
    channels, width, rate, frames, _, _ = wav.getparams()
    assert width == 2, "Expected PCM16"
    samples = array.array("h", wav.readframes(frames))
# Keep the first isolated impact and its decay, discard generated trailing silence.
frame_peaks = [max(abs(samples[i * channels + c]) for c in range(channels)) for i in range(frames)]
onset = next(i for i, peak in enumerate(frame_peaks) if peak > 600)
start = max(0, onset - int(rate * 0.005))
end = min(frames, onset + int(rate * 0.45))
trimmed = samples[start * channels:end * channels]
peak = max(map(abs, trimmed))
gain = min(1.0, 0.8 * 32767 / peak)
fade = int(rate * 0.005)
length = len(trimmed) // channels
for i in range(length):
    envelope = min(1.0, i / fade, (length - 1 - i) / fade)
    for c in range(channels):
        index = i * channels + c
        trimmed[index] = round(trimmed[index] * gain * envelope)
with wave.open(str(output), "wb") as wav:
    wav.setparams((channels, width, rate, length, "NONE", "not compressed"))
    wav.writeframes(trimmed.tobytes())
report = {
    "source": str(source), "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
    "generator": "Agent Audio / Stable Audio 3 Medium / local tflite CPU",
    "source_seconds": frames / rate, "output": str(output),
    "seconds": length / rate, "sample_rate": rate, "channels": channels,
    "peak_dbfs": 20 * math.log10(max(map(abs, trimmed)) / 32768),
    "rms_dbfs": 20 * math.log10(math.sqrt(sum(v * v for v in trimmed) / len(trimmed)) / 32768),
    "clipped_samples": sum(abs(v) >= 32767 for v in trimmed),
    "listened_by_agent": False,
    "processing": "First impact, 5ms edge fades, peak capped at -1.94dBFS; runtime -15dB gain and event pitch variation.",
}
Path("reports/combat_audio_report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, indent=2))
