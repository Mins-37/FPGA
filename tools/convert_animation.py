"""Convert an image/GIF or FFmpeg-readable video to the board's HXA1 stream.
No audio is included. Output is fixed 160x120 RGB565, 5 or 10 frames/second.
"""
from pathlib import Path
import argparse,os,shutil,struct,subprocess,sys,tempfile
sys.path.insert(0,str(Path(__file__).resolve().parent/'runtime_lib'))
from PIL import Image,ImageOps,ImageSequence
W,H=160,120
def fit(image):
 rgba=image.convert('RGBA');background=Image.new('RGBA',rgba.size,(0,0,0,255));background.alpha_composite(rgba)
 rgb=background.convert('RGB');rgb=ImageOps.contain(rgb,(W,H),Image.Resampling.BILINEAR)
 canvas=Image.new('RGB',(W,H));canvas.paste(rgb,((W-rgb.width)//2,(H-rgb.height)//2));return canvas
def rgb565(rgb_bytes):
 if len(rgb_bytes)!=W*H*3:raise ValueError('Wrong raw RGB frame size')
 result=bytearray(W*H*2)
 for j,i in enumerate(range(0,len(rgb_bytes),3)):
  v=((rgb_bytes[i]&248)<<8)|((rgb_bytes[i+1]&252)<<3)|(rgb_bytes[i+2]>>3)
  result[j*2]=v&255;result[j*2+1]=v>>8
 return result
def gif_frames(path,fps,seconds):
 elapsed=0.0;target=0;maximum=min(400,int(seconds*fps+1e-6))
 with Image.open(path) as image:
  for frame in ImageSequence.Iterator(image):
   duration=max(10,float(frame.info.get('duration',100) or 100));end=elapsed+duration
   packed=None
   while target<maximum and target*1000/fps<end-1e-7:
    if packed is None:packed=rgb565(fit(frame).tobytes())
    yield packed;target+=1
   elapsed=end
   if target>=maximum:break
def find_ffmpeg(explicit=None):
 if explicit:
  f=Path(explicit)
  if not f.is_file():raise FileNotFoundError(f)
  return str(f)
 found=shutil.which('ffmpeg')
 if found:return found
 try:
  import imageio_ffmpeg
  return imageio_ffmpeg.get_ffmpeg_exe()
 except ImportError:raise RuntimeError('Video conversion needs FFmpeg. Run Setup-Converter.cmd, install imageio-ffmpeg, or pass --ffmpeg PATH.')
def video_frames(path,fps,seconds,ffmpeg=None):
 exe=find_ffmpeg(ffmpeg)
 filt=f'fps={fps},scale={W}:{H}:force_original_aspect_ratio=decrease:flags=bilinear,pad={W}:{H}:(ow-iw)/2:(oh-ih)/2:black,setsar=1,format=rgb24'
 cmd=[exe,'-nostdin','-v','error','-i',str(path),'-an','-t',str(seconds),'-frames:v',str(min(400,int(seconds*fps+1e-6))),'-vf',filt,'-f','rawvideo','-pix_fmt','rgb24','pipe:1']
 proc=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 try:
  while True:
   data=proc.stdout.read(W*H*3)
   if not data:break
   if len(data)!=W*H*3:raise RuntimeError('FFmpeg returned a partial frame')
   yield rgb565(data)
  errors=proc.stderr.read().decode('utf-8',errors='replace');code=proc.wait()
  if code:raise RuntimeError(errors or f'FFmpeg exit code {code}')
 finally:
  if proc.poll() is None:proc.kill();proc.wait()
  proc.stdout.close();proc.stderr.close()
def convert(source,output,fps=10,seconds=10,ffmpeg=None,overwrite=False):
 source=Path(source);output=Path(output)
 if fps not in (5,10):raise ValueError('Frame rate must be 5 or 10')
 if not 1/fps<=seconds<=40:raise ValueError('Duration must be between one frame and 40 seconds')
 if not source.is_file():raise FileNotFoundError(source)
 if source.resolve()==output.resolve():raise ValueError('Input and output must differ')
 if output.suffix.upper()!='.ANM':raise ValueError('Output extension must be .ANM')
 if output.exists() and not overwrite:raise FileExistsError(f'{output} already exists; choose another output or use --overwrite')
 if not output.parent.is_dir():raise FileNotFoundError(output.parent)
 iterator=(gif_frames(source,fps,seconds) if source.suffix.lower() in ('.gif','.png','.jpg','.jpeg','.bmp','.webp') else video_frames(source,fps,seconds,ffmpeg))
 fd,tempname=tempfile.mkstemp(prefix=output.stem+'_',suffix='.tmp',dir=output.parent);temp=Path(tempname)
 try:
  with os.fdopen(fd,'w+b') as stream:
   stream.write(bytes(512));count=0
   for frame in iterator:
    if len(frame)!=38400 or count>=400:raise ValueError('Animation exceeds format limits')
    stream.write(frame);count+=1
   if not count:raise ValueError('No decodable frames')
   header=bytearray(512);struct.pack_into('<4sHHHHIIHH',header,0,b'HXA1',W,H,fps,count,38400,512+count*38400,1,1)
   stream.seek(0);stream.write(header);stream.flush();os.fsync(stream.fileno())
  temp.replace(output)
  return dict(frames=count,fps=fps,width=W,height=H,bytes=output.stat().st_size,seconds=count/fps)
 finally:
  if hasattr(iterator,'close'):iterator.close()
  temp.unlink(missing_ok=True)
def main():
 if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf-8')
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('input',type=Path);parser.add_argument('-o','--output',type=Path);parser.add_argument('--fps',type=int,choices=(5,10),default=10);parser.add_argument('--seconds',type=float,default=10);parser.add_argument('--ffmpeg');parser.add_argument('--overwrite',action='store_true');a=parser.parse_args()
 try:
  output=a.output or a.input.with_suffix('.ANM');result=convert(a.input,output,a.fps,a.seconds,a.ffmpeg,a.overwrite)
  print(f'Created {output}: {result["frames"]} frames, {result["fps"]} fps, {result["seconds"]:.1f}s, {result["bytes"]} bytes. No source audio included.')
 except Exception as e:print(f'Conversion failed: {e}',file=sys.stderr);raise SystemExit(1)
if __name__=='__main__':main()
