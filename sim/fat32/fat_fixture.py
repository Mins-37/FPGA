from pathlib import Path
import struct, json
out=Path('work/fat_tests');out.mkdir(parents=True,exist_ok=True)
def make(name,files=5,spc=1,part=2048,nfats=2,active=0,fault=None):
 d=out/name;d.mkdir(exist_ok=True);media={}
 reserved=32; fatsz=1024; fatbase=part+reserved+active*fatsz;data=part+reserved+nfats*fatsz
 b=bytearray(512);b[0:3]=b'\xeb\x58\x90';struct.pack_into('<HBHBHH',b,11,512,spc,reserved,nfats,0,0)
 struct.pack_into('<I',b,32,70000*spc+reserved+nfats*fatsz)
 struct.pack_into('<I',b,36,fatsz);struct.pack_into('<H',b,40,0x80|active if active else 0)
 struct.pack_into('<I',b,44,2);b[510:512]=b'\x55\xaa';media[part]=b
 if part:
  m=bytearray(512);m[450]=0x0c;struct.pack_into('<I',m,454,part);struct.pack_into('<I',m,458,70000*spc+2080);m[510:512]=b'\x55\xaa';media[0]=m
 def fat(c,n):
  sec=fatbase+c//128;v=media.setdefault(sec,bytearray(512));struct.pack_into('<I',v,(c%128)*4,n|0xa0000000)
 fat(0,0xffffff8);fat(1,0xfffffff)
 entries=[];maps={};names=[]
 # Deliberately reverse directory order to test sorting.
 for k in reversed(range(files)):
  sfn=f'{k+1:03d}'.ljust(8).encode()+b'BMP';names.append(sfn)
  length=39*512-57;nc=(39+spc-1)//spc
  chain=[100+k*100+((j*13)%97) for j in range(nc)]
  e=bytearray(32);e[:11]=sfn;e[11]=0x20;struct.pack_into('<H',e,20,chain[0]>>16);struct.pack_into('<H',e,26,chain[0]&65535);struct.pack_into('<I',e,28,length);entries.append(e)
  for j,c in enumerate(chain):fat(c,chain[j+1] if j+1<nc else 0xfffffff)
  for fsec in range(39):
   physical=data+(chain[fsec//spc]-2)*spc+fsec%spc
   media[physical]=bytearray(((k*17+fsec*11+x*3)^(x>>3))&255 for x in range(512));maps[(k,fsec)]=physical
  if fault=='chain' and k==0:fat(chain[0],0xfffffff)
  if fault=='self' and k==0:fat(chain[0],chain[0])
 # Deleted, volume, subdirectory, LFN and TXT must not enter the catalogue.
 for first,attr,ext in [(0xe5,0x20,b'BMP'),(ord('V'),8,b'BMP'),(ord('D'),0x10,b'BMP'),(ord('L'),0x0f,b'BMP'),(ord('T'),0x20,b'TXT')]:
  e=bytearray(32);e[:11]=b'IGNORED '+ext;e[0]=first;e[11]=attr;struct.pack_into('<H',e,26,150);struct.pack_into('<I',e,28,1000);entries.insert(0,e)
 entries.append(bytearray(32))
 rootclusters=[2,5000,6000,7000]
 sectors=(len(entries)+15)//16;rootcount=(sectors+spc-1)//spc
 for j in range(rootcount):fat(rootclusters[j],rootclusters[j+1] if j+1<rootcount else 0xfffffff)
 for n,e in enumerate(entries):
  fs=n//16;phy=data+(rootclusters[fs//spc]-2)*spc+fs%spc
  buf=media.setdefault(phy,bytearray(512));buf[(n%16)*32:(n%16+1)*32]=e
 if fault=='boot':media[part][11:13]=b'\x00\x04'
 keys=sorted(media);(d/'lbas.hex').write_text('\n'.join(f'{s:08x}' for s in keys))
 (d/'bytes.hex').write_text('\n'.join(f'{v:02x}' for s in keys for v in media[s]))
 # Keep first 32 directory BMPs, then sort. More than 32 retains the first 32
 # encountered, i.e. largest numbered files in this reverse-order fixture.
 chosen=sorted(range(max(0,files-32),files));requests=[]
 if files:
  for idx,k in enumerate(chosen):
   for fs in [0,38,16,15,17,1]:requests.append((idx*32768+fs,maps[(k,fs)]))
  for idx in [len(chosen)-1,0,len(chosen)//2]:requests.append((idx*32768+38,maps[(chosen[idx],38)]))
 if fault in ('chain','self'):requests=[(0,0)]
 (d/'requests.hex').write_text('\n'.join(f'{v:08x}\n{p:08x}' for v,p in requests) or '00000000\n00000000')
 meta=dict(n=len(keys),count=len(chosen),requests=len(requests),mount_error=fault=='boot',read_error=fault in ('chain','self'))
 (d/'meta.json').write_text(json.dumps(meta));return meta
if __name__=='__main__':
 for args in [('empty',0,1,0,1,0,None),('one',1,1,0,1,0,None),('five',5,1,2048,2,0,None),('thirtytwo',32,1,2048,2,0,None),('cap',40,1,2048,2,0,None),('activefat',5,8,2048,2,1,None),('cluster64',5,64,2048,2,0,None),('badboot',1,1,2048,2,0,'boot'),('shortchain',1,1,2048,2,0,'chain'),('selfchain',1,1,2048,2,0,'self')]:
  print(args[0],make(*args))
