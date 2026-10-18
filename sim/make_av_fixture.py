from pathlib import Path
import struct,json
d=Path('work/av_fixture');d.mkdir(exist_ok=True);media={};part=2048;spc=2;fatbase=2080;data=4128
boot=bytearray(512);boot[:3]=b'\xeb\x58\x90';struct.pack_into('<HBHBHH',boot,11,512,spc,32,2,0,0);struct.pack_into('<II',boot,32,70000*spc+2080,1024);struct.pack_into('<I',boot,44,2);boot[510:]=b'\x55\xaa';media[part]=boot
m=bytearray(512);m[450]=12;struct.pack_into('<II',m,454,part,70000*spc+2080);m[510:]=b'\x55\xaa';media[0]=m
def fat(c,v):
 b=media.setdefault(fatbase+c//128,bytearray(512));struct.pack_into('<I',b,(c%128)*4,v|0xa0000000)
fat(2,0xfffffff)
w,h=17,11;stride=(w*3+3)&~3;size=54+stride*h;bmp=bytearray(size);struct.pack_into('<2sIHHI',bmp,0,b'BM',size,0,0,54);struct.pack_into('<IiiHHIIiiII',bmp,14,40,w,-h,1,24,0,stride*h,0,0,0,0)
for y in range(h):
 for x in range(w):bmp[54+y*stride+x*3:54+y*stride+x*3+3]=bytes([x^y,y,x])
anm=bytearray(512+2*38400);struct.pack_into('<4sHHHHIIHH',anm,0,b'HXA1',160,120,10,2,38400,len(anm),1,1)
for f in range(2):
 for y in range(120):
  for x in range(160):struct.pack_into('<H',anm,512+f*38400+(y*160+x)*2,(((x+f*3)&31)<<11)|(((y+f*5)&63)<<5)|((x^y^f)&31))
struct.pack_into('<4sIHH',anm,24,b'AVM1',48000,2,16)
wave=bytearray(44+2*4800*4);struct.pack_into('<4sI4s4sIHHIIHH4sI',wave,0,b'RIFF',len(wave)-8,b'WAVE',b'fmt ',16,1,2,48000,192000,4,16,b'data',len(wave)-44)
for i in range(9600):struct.pack_into('<HH',wave,44+4*i,(i*17)&65535,(~(i*17))&65535)
anm+=wave
directory=bytearray(512)
for entry,(name,content,base) in enumerate([(b'002     AVM',anm,1000),(b'001     BMP',bmp,100)]):
 sectors=(len(content)+511)//512;nc=(sectors+spc-1)//spc;chain=[base+j*13 for j in range(nc)]
 b=bytearray(32);b[:11]=name;b[11]=32;struct.pack_into('<H',b,26,chain[0]);struct.pack_into('<I',b,28,len(content));directory[entry*32:entry*32+32]=b
 for j,c in enumerate(chain):fat(c,chain[j+1] if j+1<nc else 0xfffffff)
 for fs in range(sectors):media[data+(chain[fs//spc]-2)*spc+fs%spc]=bytearray(content[fs*512:(fs+1)*512]).ljust(512,b'\0')
media[data]=directory;keys=sorted(media);(d/'lbas.hex').write_text('\n'.join(f'{s:08x}' for s in keys));(d/'bytes.hex').write_text('\n'.join(f'{v:02x}' for s in keys for v in media[s]));(d/'meta.json').write_text(json.dumps(dict(n=len(keys))))
print('Mixed BMP/AVM FAT32 fixture:',len(keys),'sectors')
