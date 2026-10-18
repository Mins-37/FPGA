from pathlib import Path
import argparse,importlib.util,struct,tempfile,subprocess,hashlib
from PIL import Image
parser=argparse.ArgumentParser();parser.add_argument('--ffmpeg');a=parser.parse_args()
project=Path(__file__).resolve().parents[1];spec=importlib.util.spec_from_file_location('converter',project/'tools/convert_animation.py');c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
with tempfile.TemporaryDirectory(prefix='anm_converter_') as tmp:
 d=Path(tmp);gif=d/'input.gif';images=[Image.new('RGB',(160,120),color) for color in ('red','lime','blue')]
 images[0].save(gif,save_all=True,append_images=images[1:],duration=[100,200,100],loop=0)
 output=d/'out.ANM';meta=c.convert(gif,output,10,1);data=output.read_bytes()
 assert meta['frames']==4 and struct.unpack_from('<4sHHHHIIHH',data)==(b'HXA1',160,120,10,4,38400,len(data),1,1)
 assert [struct.unpack_from('<H',data,512+i*38400)[0] for i in range(4)]==[0xf800,0x07e0,0x07e0,0x001f]
 meta=c.convert(gif,d/'five.ANM',5,1);assert meta['frames']==2 and meta['fps']==5
 old=hashlib.sha256(data).hexdigest()
 try:c.convert(gif,output)
 except FileExistsError:pass
 else:raise AssertionError('Overwrite allowed')
 assert hashlib.sha256(output.read_bytes()).hexdigest()==old
 for fps,seconds in [(7,1),(10,41),(10,0)]:
  try:c.convert(gif,d/'bad.ANM',fps,seconds)
  except ValueError:pass
  else:raise AssertionError('Invalid settings accepted')
 bad=d/'bad.gif';bad.write_bytes(b'not a GIF')
 try:c.convert(bad,d/'bad.ANM')
 except Exception:pass
 else:raise AssertionError('Bad GIF accepted')
 assert not (d/'bad.ANM').exists() and not list(d.glob('*.tmp'))
 if a.ffmpeg:
  video=d/'input.mp4';subprocess.run([a.ffmpeg,'-nostdin','-v','error','-y','-f','lavfi','-i','testsrc=size=160x120:rate=10','-t','1','-c:v','libx264','-pix_fmt','yuv420p',str(video)],check=True)
  meta=c.convert(video,d/'video.ANM',10,1,a.ffmpeg);assert meta['frames']==10 and meta['bytes']==384512
  print('PASS: actual MP4 conversion')
 print('PASS: GIF timing, 5/10fps, header, RGB565 order, overwrite protection, input validation and atomic cleanup')
