"""Run WAV reader and FAT32/BMP/WAV integration simulations."""
from pathlib import Path
import argparse,subprocess,tempfile,json,shutil,sys
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tools-dir',type=Path);a=p.parse_args()
project=Path(__file__).resolve().parents[1];sim=project/'sim';hdl=project/'user_source/hdl_source'
iv=a.tools_dir/'bin/iverilog.exe' if a.tools_dir else shutil.which('iverilog');vv=a.tools_dir/'bin/vvp.exe' if a.tools_dir else shutil.which('vvp');lib=a.tools_dir/'lib/ivl' if a.tools_dir else None
if not iv or not vv:p.error('Install Icarus or pass --tools-dir')
results=[]
with tempfile.TemporaryDirectory(prefix='wav_rtl_') as tmp:
 cwd=Path(tmp);(cwd/'work').mkdir()
 def run(cmd):
  r=subprocess.run([str(x) for x in cmd],cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=900)
  if r.returncode:raise RuntimeError(r.stdout+r.stderr)
  return r.stdout+r.stderr
 def case(name,top,files,params=None,args=None):
  run([iv]+(['-B',lib] if lib else [])+['-g2012','-s',top]+[f'-P{top}.{k}={v}' for k,v in (params or {}).items()]+['-o',name+'.vvp']+files)
  output=run([vv,'-i']+(['-M','-','-M',lib] if lib else [])+[name+'.vvp']+(args or []));print(output.strip(),flush=True);results.append(dict(name=name,passed=True,output=output))
 for bad,gap in [(0,31),(0,0),(1,31),(2,31)]:case(f'wav_bad{bad}_gap{gap}','tb_wav',[sim/'tb_wav.sv',hdl/'wav_read.v',hdl/'cdc_status_bus.v'],dict(BAD=bad,GAP=gap))
 run([sys.executable,sim/'make_audio_fixture.py'])
 case('mixed_wav','tb_audio_player',[sim/'tb_audio_player.sv',sim/'fat32/tb_fat_player.sv',hdl/'SD/sd_card_bmp.v',hdl/'SD/fat32_store.v',hdl/'SD/bmp_read.v',hdl/'SD/anm_read.v',hdl/'wav_read.v',hdl/'cdc_status_bus.v'],args=['+LBAS=work/audio_fixture/lbas.hex','+BYTES=work/audio_fixture/bytes.hex','+N=17'])
 case('wav_osd','tb_wav_osd',[sim/'tb_wav_osd.sv',hdl/'video_osd.v'])
 run([sys.executable,sim/'make_audio_only_fixture.py'])
 case('audio_only','tb_audio_only',[sim/'tb_audio_only.sv',sim/'fat32/tb_fat_player.sv',hdl/'SD/sd_card_bmp.v',hdl/'SD/fat32_store.v',hdl/'SD/bmp_read.v',hdl/'SD/anm_read.v',hdl/'wav_read.v',hdl/'cdc_status_bus.v'],args=['+LBAS=work/audio_only_fixture/lbas.hex','+BYTES=work/audio_only_fixture/bytes.hex','+N=15'])
(project/'sim/audio_latest_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8');print(f'PASS {len(results)} audio simulations')
