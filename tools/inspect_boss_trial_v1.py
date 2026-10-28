"""Inspect this task's raw sources using the established Blender cardinal-view inspector."""
from pathlib import Path
source = (Path(__file__).parent / 'inspect_actor_source_v1.py').read_text(encoding='utf-8')
source = source.replace('assets/actors/combat_set_v1', 'assets/actors/boss_trial_v1').replace('reports/combat_actors_v1', 'reports/boss_trial_v1')
exec(compile(source, __file__, 'exec'))
