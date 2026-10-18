"""AVM RTL checks: metadata/OSD and handoff; --full also checks real-rate sync/loop."""
from pathlib import Path
import argparse,subprocess,tempfile,json,shutil,sys
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tools-dir',type=Path);p.add_argument('--full',action='store_true');a=p.parse_args()
project=Path(__file__).resolve().parents[1];sim=project/'sim';hdl=project/'user_source/hdl_source'
iv=a.tools_dir/'bin/iverilog.exe' if a.tools_dir else shutil.which('iverilog');vv=a.tools_dir/'bin/vvp.exe' if a.tools_dir else shutil.which('vvp');lib=a.tools_dir/'lib/ivl' if a.tools_dir else None
if not iv or not vv:p.error('Install Icarus or pass --tools-dir')
results=[]
with tempfile.TemporaryDirectory(prefix='avm_rtl_') as tmp:
 cwd=Path(tmp);(cwd/'work').mkdir()
 def run(cmd):
  r=subprocess.run([str(x) for x in cmd],cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1800)
  if r.returncode:raise RuntimeError(r.stdout+r.stderr)
  return r.stdout+r.stderr
 def case(name,top,files,params=None,args=None):
  print('Running',name,flush=True)
  run([iv]+(['-B',lib] if lib else [])+['-g2012','-s',top]+[f'-P{top}.{k}={v}' for k,v in (params or {}).items()]+['-o',name+'.vvp']+files)
  output=run([vv,'-i']+(['-M','-','-M',lib] if lib else [])+[name+'.vvp']+(args or []));print(output.strip(),flush=True);results.append(dict(name=name,passed=True,output=output))
 for bad in [0,5,6,7,8,9]:case('metadata'+str(bad),'tb_av_header',[sim/'tb_av_header.sv',hdl/'SD/anm_read.v'],dict(BAD=bad))
 case('av_osd','tb_av_osd',[sim/'tb_av_osd.sv',hdl/'video_osd.v'])
 shared=[hdl/'SD/sd_card_bmp.v',hdl/'SD/fat32_store.v',hdl/'SD/bmp_read.v',hdl/'SD/anm_read.v',hdl/'wav_read.v',hdl/'cdc_status_bus.v',hdl/'audio_test_pcm.v']
 run([sys.executable,sim/'make_av_switch_fixture.py'])
 case('av_to_av_switch','tb_av_switch',[sim/'tb_av_switch.sv']+shared,args=['+LBAS=work/av_switch_fixture/lbas.hex','+BYTES=work/av_switch_fixture/bytes.hex','+N=483'])
 if a.full:
  run([sys.executable,sim/'make_av_fixture.py'])
  case('av_integration','tb_av_player',[sim/'tb_av_player.sv']+shared,args=['+LBAS=work/av_fixture/lbas.hex','+BYTES=work/av_fixture/bytes.hex','+N=246'])
(project/'sim/av_latest_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8');print(f'PASS {len(results)} AVM RTL checks')
