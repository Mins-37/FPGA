"""Convert local audio to canonical 48 kHz stereo PCM16 WAV for this board."""
from pathlib import Path
import argparse,subprocess,wave,shutil,sys,os,tempfile
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('input',type=Path);p.add_argument('-o','--output',type=Path,default=Path('007.WAV'));p.add_argument('--seconds',type=float,default=30);p.add_argument('--ffmpeg');p.add_argument('--overwrite',action='store_true');a=p.parse_args()
if not a.input.is_file():p.error('Input file does not exist')
if not .1<=a.seconds<=80:p.error('Duration must be 0.1 to 80 seconds')
if a.output.resolve()==a.input.resolve():p.error('Output must differ from input')
if a.output.suffix.lower()!='.wav':p.error('Output suffix must be .WAV')
if a.output.exists() and not a.overwrite:p.error('Output exists; use --overwrite intentionally')
local=Path(__file__).resolve().parent/'runtime_lib'
if local.is_dir():sys.path.insert(0,str(local))
ff=a.ffmpeg or shutil.which('ffmpeg')
if not ff:
 try:
  import imageio_ffmpeg
  ff=imageio_ffmpeg.get_ffmpeg_exe()
 except ImportError:p.error('Pass --ffmpeg PATH or use the animation converter runtime')
r=subprocess.run([ff,'-v','error','-i',str(a.input),'-t',str(a.seconds),'-vn','-f','s16le','-acodec','pcm_s16le','-ar','48000','-ac','2','-'],capture_output=True)
if r.returncode:raise SystemExit(r.stderr.decode('utf-8',errors='replace'))
if len(r.stdout)<2048 or len(r.stdout)%4:raise SystemExit('Audio must contain at least 512 complete stereo samples')
a.output.parent.mkdir(parents=True,exist_ok=True)
fd,tmp=tempfile.mkstemp(prefix='wav_',suffix='.tmp',dir=a.output.parent);os.close(fd)
try:
 with wave.open(tmp,'wb') as w:w.setnchannels(2);w.setsampwidth(2);w.setframerate(48000);w.writeframes(r.stdout)
 os.replace(tmp,a.output)
finally:
 if os.path.exists(tmp):os.unlink(tmp)
print(f'Created {a.output}: {len(r.stdout)/192000:.3f}s, 48000Hz stereo PCM16, canonical 44-byte header')
