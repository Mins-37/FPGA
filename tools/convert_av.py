"""Convert video+audio to AVM1; 256x192/10fps by default, 160x120 compatible mode."""
from pathlib import Path
import argparse,os,struct,subprocess,tempfile,wave,json
from convert_animation import find_ffmpeg

def convert_av(source,output,seconds=14,ffmpeg=None,overwrite=False,size='256x192'):
 source=Path(source);output=Path(output)
 if size not in ('160x120','256x192'):raise ValueError('Unsupported video size')
 w,h=(int(x) for x in size.split('x'));maximum=14 if w==256 else 20
 if not .1<=seconds<=maximum:raise ValueError(f'Duration must be 0.1 to {maximum} seconds at {size}')
 if output.suffix.upper()!='.AVM':raise ValueError('Output suffix must be .AVM')
 if output.resolve()==source.resolve():raise ValueError('Input and output must differ')
 if output.exists() and not overwrite:raise FileExistsError(output)
 exe=find_ffmpeg(ffmpeg)
 with tempfile.TemporaryDirectory(prefix='avm_convert_',dir=output.parent) as tmp:
  tmp=Path(tmp);filt=f'fps=fps=10:start_time=0,scale={w}:{h}:force_original_aspect_ratio=decrease:flags=bilinear,pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:black,setsar=1,format=rgb24'
  vr=subprocess.run([exe,'-nostdin','-v','error','-i',str(source),'-map','0:v:0','-an','-t',str(seconds),'-frames:v',str(int(seconds*10+1e-6)),'-vf',filt,'-f','rawvideo','-pix_fmt','rgb24','pipe:1'],capture_output=True)
  if vr.returncode:raise RuntimeError(vr.stderr.decode('utf-8',errors='replace'))
  rgb=vr.stdout;raw_frame=w*h*3
  if not rgb or len(rgb)%raw_frame:raise ValueError('No complete RGB frames')
  n=len(rgb)//raw_frame;wanted=n*19200
  packed=bytearray(len(rgb)//3*2)
  for j,i in enumerate(range(0,len(rgb),3)):
   pixel=((rgb[i]&248)<<8)|((rgb[i+1]&252)<<3)|(rgb[i+2]>>3);packed[j*2]=pixel&255;packed[j*2+1]=pixel>>8
  r=subprocess.run([exe,'-nostdin','-v','error','-i',str(source),'-map','0:a:0','-vn','-t',str(n/10),'-af','aresample=48000:async=1:first_pts=0','-f','s16le','-acodec','pcm_s16le','-ar','48000','-ac','2','pipe:1'],capture_output=True)
  if r.returncode:raise RuntimeError(r.stderr.decode('utf-8',errors='replace'))
  if not r.stdout:raise ValueError('No audio samples decoded')
  raw=r.stdout[:wanted].ljust(wanted,b'\0');wav=tmp/'audio.WAV'
  with wave.open(str(wav),'wb') as f:f.setnchannels(2);f.setsampwidth(2);f.setframerate(48000);f.writeframes(raw)
  header=bytearray(512);struct.pack_into('<4sHHHHIIHH',header,0,b'HXA1',w,h,10,n,w*h*2,512+len(packed),1,1);struct.pack_into('<4sIHH',header,24,b'AVM1',48000,2,16)
  result=tmp/'complete.AVM'
  with result.open('wb') as f:f.write(header);f.write(packed);f.write(wav.read_bytes());f.flush();os.fsync(f.fileno())
  if result.stat().st_size>16777216:raise ValueError('Container exceeds 16MiB/file limit')
  os.replace(result,output)
  return dict(frames=n,fps=10,seconds=n/10,width=w,height=h,audio_rate=48000,audio_channels=2,audio_bits=16,audio_frames=n*4800,audio_sector=1+n*w*h*2//512,bytes=output.stat().st_size,padded_audio_bytes=max(0,wanted-len(r.stdout)))

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('input',type=Path);p.add_argument('-o','--output',type=Path,required=True);p.add_argument('--size',choices=['256x192','160x120'],default='256x192');p.add_argument('--seconds',type=float,default=14);p.add_argument('--ffmpeg');p.add_argument('--overwrite',action='store_true');a=p.parse_args()
 try:print(json.dumps(convert_av(a.input,a.output,a.seconds,a.ffmpeg,a.overwrite,a.size),ensure_ascii=False,indent=2))
 except Exception as e:p.exit(1,f'Conversion failed: {e}\n')
