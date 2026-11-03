from PIL import Image,ImageDraw,ImageFont
from pathlib import Path
p=Path('reports/drive_tree_v1/review/models')
names=['guillotine','guillotine_saw','guillotine_lock','restraint_winch','hydraulic_press','compound_executor','shock_frame_transformed_rear','exoskeleton_transformed','broad_cutter']
sheet=Image.new('RGB',(1440,1140),'#14232d')
d=ImageDraw.Draw(sheet); f=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',19)
for i,n in enumerate(names):
 im=Image.open(p/(n+'.jpg'));im.thumbnail((480,340));x=(i%3)*480;y=(i//3)*380
 sheet.paste(im,(x+(480-im.width)//2,y+35));d.text((x+15,y+8),n,font=f,fill='white')
sheet.save('reports/drive_tree_v1/inspection.jpg')
