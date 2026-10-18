"""Audio control/gain/spectrum verification. Pass --tools-dir with a portable Icarus installation."""
from pathlib import Path
import argparse,subprocess,tempfile,json,shutil,math,random,sys
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tools-dir',type=Path);p.add_argument('--full',action='store_true',help='Also run real FAT32/media clean-key integration');a=p.parse_args()
project=Path(__file__).resolve().parents[1];sim=project/'sim';hdl=project/'user_source/hdl_source'
iv=a.tools_dir/'bin/iverilog.exe' if a.tools_dir else shutil.which('iverilog');vv=a.tools_dir/'bin/vvp.exe' if a.tools_dir else shutil.which('vvp');lib=a.tools_dir/'lib/ivl' if a.tools_dir else None
if not iv or not vv:p.error('Install Icarus or pass --tools-dir')
results=[]
with tempfile.TemporaryDirectory(prefix='audiofx_') as tmp:
 cwd=Path(tmp)
 def run(cmd):
  r=subprocess.run([str(x) for x in cmd],cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
  if r.returncode:raise RuntimeError(r.stdout+r.stderr)
  return r.stdout+r.stderr
 def case(name,files,args=None):
  print('Running',name,flush=True)
  run([iv]+(['-B',lib] if lib else [])+['-g2012','-s',name,'-o',name+'.vvp']+[sim/(name+'.sv')]+files)
  output=run([vv,'-i']+(['-M','-','-M',lib] if lib else [])+[name+'.vvp']+(args or []));print(output.strip(),flush=True);results.append(dict(name=name,passed=True,output=output))
 case('tb_audio_controls',[hdl/'audio_controls.v',hdl/'SD/sd_card_bmp.v'])
 case('tb_audio_gain',[hdl/'audio_gain.v'])
 bins=[1,2,4,8,16,32,64,96];blocks=[]
 for k in bins:blocks.append([round(6000000*math.sin(2*math.pi*k*n/256)) for n in range(256)])
 blocks.extend([[round(6000000*scale*math.sin(2*math.pi*8*n/256)) for n in range(256)] for scale in [.5,.25,.125]])
 blocks += [[round(4000000*math.sin(2*math.pi*1000*n/48000)) for n in range(256)], [round(2200000*(math.sin(2*math.pi*4*n/256)+math.sin(2*math.pi*32*n/256))) for n in range(256)]]
 rng=random.Random(192);blocks+=[[rng.randrange(-6000000,6000000) for _ in range(256)], [0]*256, [8388607]*256, [-8388608]*256, [0]*256]
 blocks += [[8388607 if math.sin(2*math.pi*n/256)>=0 else -8388608 for n in range(256)],[-8388608 if n%2 else 8388607 for n in range(256)],[0]*256]
 def level_model(block,k):
  # Independent scalar fixed-point recurrence and terminal complex projection.
  coef=round(32768*math.cos(2*math.pi*k/256));si=round(16384*math.sin(2*math.pi*k/256));s1=s2=0
  for pcm in block:
   x=pcm//65536;new=x+(s1*coef//16384)-s2;s2=s1;s1=new
   assert -(1<<21)<=s1<(1<<21)
  real=s1-s2*(coef//2)//16384;imag=s2*si//16384;mag=abs(real)+abs(imag)
  return 0 if mag<8 else min(56,(mag.bit_length()-3)*4+((mag>>(mag.bit_length()-3))&3))
 levels=[[level_model(b,k) for k in bins] for b in blocks]
 for i in range(8):assert levels[i].index(max(levels[i]))==i,(i,levels[i])
 assert levels[3][3]>levels[8][3]>levels[9][3]>levels[10][3]
 assert levels[14]==[0]*8 and levels[-1]==[0]*8
 (cwd/'pcm.hex').write_text('\n'.join(f'{v&0xffffff:06x}' for b in blocks for v in b))
 (cwd/'levels.hex').write_text('\n'.join(f'{sum(v<<(8*i) for i,v in enumerate(b)):016x}' for b in levels))
 case('tb_audio_spectrum',[hdl/'audio_spectrum.v'],[f'+PCM={cwd / "pcm.hex"}',f'+LEVELS={cwd / "levels.hex"}',f'+BLOCKS={len(blocks)}'])
 case('tb_audiofx_overlay',[hdl/'audio_waveform.v',hdl/'video_osd.v'])
 case('tb_audiofx_chain',[hdl/'audio_test_pcm.v',hdl/'audio_gain.v',hdl/'audio_spectrum.v'])
 case('tb_audio_waveform',[hdl/'audio_waveform.v',hdl/'audio_test_pcm.v'])
 case('tb_waveform_pipeline',[hdl/'audio_waveform.v'])
 for name in ['tb_progress_osd','tb_av_osd','tb_wav_osd','tb_animation_overlay']:
  case(name,[hdl/'video_osd.v']+([hdl/'video_fade.v'] if name=='tb_animation_overlay' else []))
 if a.full:
  (cwd/'work').mkdir();run([sys.executable,sim/'make_plus_switch_fixture.py']);fixture=cwd/'work/plus_switch_fixture';n=json.loads((fixture/'meta.json').read_text())['n']
  case('tb_audiofx_player',[hdl/'SD/sd_card_bmp.v',hdl/'SD/fat32_store.v',hdl/'SD/bmp_read.v',hdl/'SD/anm_read.v',hdl/'wav_read.v',hdl/'cdc_status_bus.v',hdl/'audio_test_pcm.v'],[f'+LBAS=work/plus_switch_fixture/lbas.hex',f'+BYTES=work/plus_switch_fixture/bytes.hex',f'+N={n}'])
  (sim/'audiofx_player_result.json').write_text(json.dumps(results.pop(),ensure_ascii=False,indent=2),encoding='utf-8')
(sim/'audiofx_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8');print(f'PASS {len(results)+int(a.full)} audio effect checks')
