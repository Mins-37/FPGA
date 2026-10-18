import struct
def expected(d):
 lbas=[int(v,16) for v in (d/'lbas.hex').read_text().split()];raw=bytes(int(v,16) for v in (d/'bytes.hex').read_text().split());media={n:raw[i*512:(i+1)*512] for i,n in enumerate(lbas)}
 u16=lambda b,o:struct.unpack_from('<H',b,o)[0];u32=lambda b,o:struct.unpack_from('<I',b,o)[0]
 part=0 if u16(media[0],11)==512 else u32(media[0],454);boot=media[part];spc=boot[13];fatbase=part+u16(boot,14);fatsz=u32(boot,36);flags=u16(boot,40)
 data=fatbase+boot[16]*fatsz;fatbase+=(flags&15)*fatsz if flags&128 else 0;c=u32(boot,44);found=[];end=False
 while c<0xffffff8 and not end:
  for sec in range(spc):
   b=media.get(data+(c-2)*spc+sec,bytes(512))
   for offset in range(0,512,32):
    e=b[offset:offset+32]
    if e[0]==0:end=True;break
    cluster=u16(e,26)|(u16(e,20)<<16)
    if len(found)<32 and e[0]!=229 and not(e[11]&24) and e[8:11] in [b'BMP',b'ANM',b'WAV',b'AVM'] and cluster>=2 and 54<=u32(e,28)<=16777216:found.append(e[:11])
   if end:break
  if not end:c=u32(media[fatbase+c//128],(c%128)*4)&0xfffffff
 found.sort();gold=bytearray(b' '*512)
 for i,n in enumerate(found):gold[i*16:i*16+11]=n;gold[i*16+11]=(len(n[:8].rstrip(b' '))<<2)|{b'BMP':0,b'ANM':1,b'WAV':2,b'AVM':3}[n[8:11]]
 return gold,len(found)
