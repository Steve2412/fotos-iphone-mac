# Genera App/AppIcon.icns (requiere Pillow: pip3 install pillow). Uso: python3 App/generar-icono.py
import os; os.chdir(os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw, ImageFilter
S=1024; K=4  # supersampling
W=S*K
img=Image.new("RGBA",(W,W),(0,0,0,0))
# Cuerpo del icono (rejilla de macOS: 824 px con 100 de margen)
m=100*K; r=185*K
grad=Image.new("RGBA",(W,W))
gd=ImageDraw.Draw(grad)
top=(37,99,235); bot=(13,148,136)
for y in range(W):
    t=y/W
    c=tuple(int(top[i]*(1-t)+bot[i]*t) for i in range(3))
    gd.line([(0,y),(W,y)],fill=c+(255,))
mask=Image.new("L",(W,W),0)
ImageDraw.Draw(mask).rounded_rectangle([m,m,W-m,W-m],radius=r,fill=255)
# sombra
sombra=Image.new("RGBA",(W,W),(0,0,0,0))
ImageDraw.Draw(sombra).rounded_rectangle([m,m+14*K,W-m,W-m+14*K],radius=r,fill=(0,0,0,90))
sombra=sombra.filter(ImageFilter.GaussianBlur(18*K))
img.alpha_composite(sombra)
img.paste(grad,(0,0),mask)
d=ImageDraw.Draw(img)
# Teléfono
px0,py0,px1,py1=330*K,215*K,640*K,790*K
d.rounded_rectangle([px0,py0,px1,py1],radius=62*K,fill=(255,255,255,255))
pantalla=[px0+26*K,py0+26*K,px1-26*K,py1-26*K]
d.rounded_rectangle(pantalla,radius=40*K,fill=(224,242,254,255))
# isla
d.rounded_rectangle([(px0+px1)//2-48*K,py0+44*K,(px0+px1)//2+48*K,py0+70*K],radius=13*K,fill=(30,41,59,255))
# Foto: sol y montañas
d.ellipse([560*K-38*K,330*K,560*K+38*K,406*K],fill=(251,191,36,255))
d.polygon([(pantalla[0],640*K),(445*K,450*K),(540*K,640*K)],fill=(16,185,129,255))
d.polygon([(470*K,640*K),(555*K,500*K),(pantalla[2],640*K)],fill=(5,150,105,255))
d.rectangle([pantalla[0],640*K,pantalla[2],pantalla[3]-40*K],fill=(5,150,105,255))
d.rounded_rectangle([pantalla[0],pantalla[3]-80*K,pantalla[2],pantalla[3]],radius=40*K,fill=(5,150,105,255))
# Insignia con flecha hacia abajo
cx,cy,R=690*K,720*K,128*K
d.ellipse([cx-R-10*K,cy-R-10*K,cx+R+10*K,cy+R+10*K],fill=(255,255,255,255))
d.ellipse([cx-R,cy-R,cx+R,cy+R],fill=(249,115,22,255))
w=34*K
d.rounded_rectangle([cx-w//2,cy-78*K,cx+w//2,cy+30*K],radius=w//2,fill=(255,255,255,255))
d.polygon([(cx-70*K,cy+5*K),(cx+70*K,cy+5*K),(cx,cy+80*K)],fill=(255,255,255,255))
icono=img.resize((S,S),Image.LANCZOS)
# Solo se guarda el .icns (los .png están en .gitignore).
icono.save("AppIcon.icns", sizes=[(16,16),(32,32),(64,64),(128,128),(256,256),(512,512),(1024,1024)])
print("ok")
