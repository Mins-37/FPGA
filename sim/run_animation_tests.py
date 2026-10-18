"""Run animation RTL checks. --full also runs the two long player regressions."""
from pathlib import Path
import argparse,subprocess,sys,tempfile,json,shutil
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--tools-dir',type=Path);parser.add_argument('--full',action='store_true');args=parser.parse_args()
project=Path(__file__).resolve().parents[1];sim=project/'sim';hdl=project/'user_source/hdl_source'
iv=args.tools_dir/'bin/iverilog.exe' if args.tools_dir else shutil.which('iverilog')
vv=args.tools_dir/'bin/vvp.exe' if args.tools_dir else shutil.which('vvp');lib=args.tools_dir/'lib/ivl' if args.tools_dir else None
if not iv or not vv:raise SystemExit('Install Icarus or pass --tools-dir PATH.')
results=[]
with tempfile.TemporaryDirectory(prefix='anm_rtl_') as tmp:
 cwd=Path(tmp);(cwd/'work').mkdir()
 def run(command):
  r=subprocess.run([str(x) for x in command],cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=900)
  if r.returncode:raise RuntimeError(r.stdout+r.stderr)
  return r.stdout+r.stderr
 def case(name,top,files,parameters=None,extra=None):
  print('Running',name,flush=True)
  run([iv]+(['-B',lib] if lib else [])+['-g2012','-s',top]+[f'-P{top}.{k}={v}' for k,v in (parameters or {}).items()]+['-o',name+'.vvp']+files)
  output=run([vv,'-i']+(['-M','-','-M',lib] if lib else [])+[name+'.vvp']+(extra or []))
  results.append(dict(name=name,passed=True,output=output));print(output.strip(),flush=True)
 sourcefiles=[sim/'tb_anm_read.sv',hdl/'SD/anm_read.v']
 for name,p in [('frame2',{}),('first',dict(FRAME=0,STALL=0)),('last',dict(FRAME=399,FRAMES=400,FPS=5)),('magic',dict(BAD=1)),('format',dict(BAD=2)),('length',dict(BAD=3)),('rate',dict(BAD=4)),('range',dict(FRAME=3)),('abort',dict(ABORT=1)),('spi_25mhz',dict(BYTE_GAP=31))]:case(name,'tb_anm_read',sourcefiles,p)
 case('overlay','tb_animation_overlay',[sim/'tb_animation_overlay.sv',hdl/'video_osd.v',hdl/'video_fade.v'])
 case('handoff','tb_reader_handoff',[sim/'tb_reader_handoff.sv',hdl/'SD/frame_fifo_read.v'])
 output=run([sys.executable,sim/'fat32/run_tests.py']+(['--tools-dir',args.tools_dir] if args.tools_dir else [])+['--unit-only']);print(output.strip(),flush=True)
 results.extend(json.loads((sim/'fat32/latest_results.json').read_text(encoding='utf-8')))
 if args.full:
  for name in ['fat_fixture.py','make_integration.py']:run([sys.executable,sim/'fat32'/name])
  shared=[hdl/'SD/sd_card_bmp.v',hdl/'wav_read.v',hdl/'cdc_status_bus.v',hdl/'SD/anm_read.v',hdl/'SD/bmp_read.v',hdl/'SD/fat32_store.v']
  case('pictures','tb_fat_player',[sim/'fat32/tb_fat_player.sv']+shared,extra=['+LBAS=work/fat_tests/integration/lbas.hex','+BYTES=work/fat_tests/integration/bytes.hex','+N=203'])
  run([sys.executable,sim/'make_animation_fixture.py'])
  case('mixed','tb_animation_player',[sim/'tb_animation_player.sv',sim/'fat32/tb_fat_player.sv']+shared,extra=['+LBAS=work/animation_fixture/lbas.hex','+BYTES=work/animation_fixture/bytes.hex','+N=159'])
(sim/'animation_latest_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8');print(f'PASS: {len(results)} RTL tests')
