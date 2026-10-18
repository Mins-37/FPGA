from fat_fixture import make,out
import struct,json
make('integration',5,2,2048,2,0,None)
d=out/'integration';keys=[int(s,16) for s in (d/'lbas.hex').read_text().split()]
vals=bytearray(int(s,16) for s in (d/'bytes.hex').read_text().split());lookup={k:i for i,k in enumerate(keys)}
for k,(w,h) in enumerate([(32,24),(96,54),(48,80),(64,48),(17,11)]):
 stride=(w*3+3)&~3;size=54+stride*h;b=bytearray(39*512)
 struct.pack_into('<2sIHHI',b,0,b'BM',size,0,0,54)
 struct.pack_into('<IiiHHIIiiII',b,14,40,w,-h if k==4 else h,1,24,0,stride*h,0,0,0,0)
 for py in range(h):
  y=py if k==4 else h-1-py
  for x in range(w):b[54+py*stride+x*3:54+py*stride+x*3+3]=bytes([(x^y^k)&255,(y+23*k)&255,(x+17*k)&255])
 for fs in range(39):
  c=100+k*100+(((fs//2)*13)%97);phy=2048+32+2048+(c-2)*2+fs%2;i=lookup[phy]
  vals[i*512:(i+1)*512]=b[fs*512:(fs+1)*512]
(d/'bytes.hex').write_text('\n'.join(f'{v:02x}' for v in vals))
print('Integration fixture sectors:',len(keys))
