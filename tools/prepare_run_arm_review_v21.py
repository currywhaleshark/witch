"""Use the existing isolated game preparation with the new complete family."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
source=(ROOT/'tools/prepare_right_hand_review_v20.py').read_text(encoding='utf-8')
source=source.replace('heavy_swing_v20','run_arm_v21').replace('_v20.glb','_v21.glb').replace('RIGHT_HAND_V20','RUN_ARM_V21')
exec(compile(source,str(ROOT/'tools/prepare_right_hand_review_v20.py'),'exec'),globals())
