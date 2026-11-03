from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
R=Path('reports/drive_tree_v1')
tiles=[('demo_hydraulic_press_base',35),('demo_compound_executor_base',55),('demo_broad_cutter_base',32),('demo_restraint_winch_pull',28),('exoskeleton_transformed_run',6),('exoskeleton_transformed_attack_thrust',6)]
canvas=Image.new('RGB',(1500,880),'#111e28');d=ImageDraw.Draw(canvas);font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',17)
for i,(name,frame) in enumerate(tiles):
 im=Image.open(R/'review'/name/f'{frame:03d}.jpg');im.thumbnail((500,400))
 x=i%3*500;y=i//3*440;canvas.paste(im,(x+(500-im.width)//2,y+32));d.text((x+10,y+8),f'{name} / {frame}',fill='white',font=font)
canvas.save(R/'motion_inspection.jpg')
