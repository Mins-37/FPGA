from pathlib import Path
from fat_fixture import make,out
import json,struct,shutil
make('maxfile',1,1,2048,2,0,None)
d=out/'maxfile';keys=[int(x,16) for x in (d/'lbas.hex').read_text().split()];values=bytes(int(x,16) for x in (d/'bytes.hex').read_text().split());media={k:bytearray(values[i*512:(i+1)*512]) for i,k in enumerate(keys)}
fatbase=2080;data=4128
for c in range(100,100+32768):
 sec=fatbase+c//128;buf=media.setdefault(sec,bytearray(512));struct.pack_into('<I',buf,(c%128)*4,(c+1 if c<100+32767 else 0xfffffff)|0xa0000000)
struct.pack_into('<I',media[data],5*32+28,16777216)
requests=[]
for fs in [0,32767,32752,16384,17,0]:
 phy=data+100+fs-2;media[phy]=bytearray(((fs*11+x*3)^(x>>3))&255 for x in range(512));requests.append((fs,phy))
keys=sorted(media);(d/'lbas.hex').write_text('\n'.join(f'{s:08x}' for s in keys));(d/'bytes.hex').write_text('\n'.join(f'{v:02x}' for s in keys for v in media[s]));(d/'requests.hex').write_text('\n'.join(f'{v:08x}\n{p:08x}' for v,p in requests));(d/'meta.json').write_text(json.dumps(dict(n=len(keys),count=1,requests=len(requests),mount_error=False,read_error=False)))
for name,addr in [('past_eof',39),('bad_index',1<<20)]:
 dest=out/name;shutil.copytree(out/'one',dest,dirs_exist_ok=True)
 (dest/'requests.hex').write_text(f'{addr:08x}\n00000000')
 m=json.loads((dest/'meta.json').read_text());m['requests']=1;m['read_error']=True;(dest/'meta.json').write_text(json.dumps(m))
print('Added maximum-file checkpoint boundary, EOF and invalid-index cases.')
