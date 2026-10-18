"""Extra player checks. --full includes high-resolution sync and KEY3 media switching."""
from pathlib import Path
import argparse,subprocess,tempfile,json,shutil,sys
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tools-dir',type=Path);p.add_argument('--full',action='store_true');a=p.parse_args()
project=Path(__file__).resolve().parents[1];sim=project/'sim';hdl=project/'user_source/hdl_source'
iv=a.tools_dir/'bin/iverilog.exe' if a.tools_dir else shutil.which('iverilog');vv=a.tools_dir/'bin/vvp.exe' if a.tools_dir else shutil.which('vvp');lib=a.tools_dir/'lib/ivl' if a.tools_dir else None
if not iv or not vv:p.error('Install Icarus or pass --tools-dir')
results=[]
with tempfile.TemporaryDirectory(prefix='player_plus_') as tmp:
 cwd=Path(tmp);(cwd/'work').mkdir()
 def run(cmd):
  r=subprocess.run([str(x) for x in cmd],cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1800)
  if r.returncode:raise RuntimeError(r.stdout+r.stderr)
  return r.stdout+r.stderr
 def case(name,top,files,params=None,args=None):
  print('Running',name,flush=True)
  run([iv]+(['-B',lib] if lib else [])+['-g2012','-s',top]+[f'-P{top}.{k}={v}' for k,v in (params or {}).items()]+['-o',name+'.vvp']+files)
  output=run([vv,'-i']+(['-M','-','-M',lib] if lib else [])+[name+'.vvp']+(args or []));print(output.strip(),flush=True);results.append(dict(name=name,passed=True,output=output))
 for name,params in [('highres_spi',{}),('highres_first',dict(FRAME=0,BYTE_GAP=0,STALL=0)),('highres_last',dict(FRAME=139,FRAMES=140,BYTE_GAP=0)),('highres_dimensions',dict(BAD=10)),('highres_limit',dict(FRAMES=141,BAD=11)),('highres_abort',dict(ABORT=1))]:case(name,'tb_highres',[sim/'tb_highres.sv',hdl/'SD/anm_read.v'],params)
 case('progress_math','tb_media_progress',[sim/'tb_media_progress.sv',hdl/'media_progress.v'])
 case('progress_osd','tb_progress_osd',[sim/'tb_progress_osd.sv',hdl/'video_osd.v'])
 case('wav_timeline','tb_wav_progress',[sim/'tb_wav_progress.sv',hdl/'wav_read.v',hdl/'cdc_status_bus.v'])
 for bad in [0,5,6,7,8,9]:case('legacy_av_metadata'+str(bad),'tb_av_header',[sim/'tb_av_header.sv',hdl/'SD/anm_read.v'],dict(BAD=bad))
 case('legacy_av_osd','tb_av_osd',[sim/'tb_av_osd.sv',hdl/'video_osd.v'])
 if a.full:
  shared=[hdl/'SD/sd_card_bmp.v',hdl/'SD/fat32_store.v',hdl/'SD/bmp_read.v',hdl/'SD/anm_read.v',hdl/'wav_read.v',hdl/'cdc_status_bus.v',hdl/'audio_test_pcm.v']
  for name,script,top,folder in [('hd','make_highres_fixture.py','tb_highres_av','highres_fixture'),('prev','make_plus_switch_fixture.py','tb_plus_switch','plus_switch_fixture')]:
   run([sys.executable,sim/script]);fixture=cwd/'work'/folder;n=json.loads((fixture/'meta.json').read_text())['n']
   case(name,top,[sim/(top+'.sv')]+shared,args=[f'+LBAS=work/{folder}/lbas.hex',f'+BYTES=work/{folder}/bytes.hex',f'+N={n}'])
(project/'sim/plus_latest_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8');print(f'PASS {len(results)} extra player checks')
