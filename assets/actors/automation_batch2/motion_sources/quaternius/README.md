# Quaternius canine animation source

Official **Ultimate Animated Animal Pack** (July 2021), downloaded 2026-11-05.

- [Official pack page](https://quaternius.com/packs/ultimateanimatedanimals.html)
- [Official distribution folder](https://drive.google.com/drive/folders/1uJ3N5HfB7jKTseJUNQr3N4YaN0UuEtHk)
- [Wolf.blend](https://drive.google.com/file/d/1daskW0IjLfPK8tLe7qTRTrjNwzyrQnjl/view)
- [Distributed License.txt](https://drive.google.com/file/d/1F2uy8T2fRpdc6gZ4mnS02_C2E63WvKtn/view), preserved beside this file: **CC0 1.0 Universal**.

`Wolf.blend` is an unchanged 2,571,200-byte download, SHA-256 `fe31c3829dd2a8b9dfedb2e5cb656939a1d525ebd535a62434d2d25a4399cb9e`.

Used action: **Gallop**, source frames 0–17 at 30fps. `tools/sample_quaternius_gallop.py` evaluates the original IK constraints and saves 241 normalized-phase samples into `wolf_gallop_samples.json.gz`. The hound retarget uses evaluated paw paths, body/head/tail motion and digitigrade hock articulation. It is an authored source animation, not claimed to be motion capture. Only the animation is used on the existing mechanical hound; the wolf model remains a source reference.

The hound v3 has two fitted gallops per 0.5-second clip, retaining the existing 3.25m/0.5s/6.5m/s art contract. Planted intervals are adapted to that speed; airborne reach is bounded for the shorter mechanical limb proportions. No additional purchase or Tripo generation was needed.

AI4Animation's canine mocap was also found, but its official repository limits the dataset to noncommercial research/education. It was not downloaded or used in this deliverable.
