"""Run read-only FAT32/player RTL simulations; never accesses an actual SD card."""
from pathlib import Path
import argparse,subprocess,sys,tempfile,json,shutil
p=argparse.ArgumentParser();p.add_argument('--tools-dir',type=Path,help='Portable Icarus root containing bin/ and lib/ivl/')
p.add_argument('--unit-only',action='store_true');a=p.parse_args()
here=Path(__file__).resolve().parent;project=here.parents[1];hdl=project/'user_source/hdl_source'
if a.tools_dir:
 compiler=a.tools_dir/'bin/iverilog.exe';runtime=a.tools_dir/'bin/vvp.exe';lib=a.tools_dir/'lib/ivl'
else:
 compiler=shutil.which('iverilog');runtime=shutil.which('vvp');lib=None
if not compiler or not runtime:raise SystemExit('Install Icarus or pass --tools-dir PATH.')
results=[]
with tempfile.TemporaryDirectory(prefix='fat32_rtl_') as tmp:
 cwd=Path(tmp)
 def run(args):
  r=subprocess.run([str(v) for v in args],cwd=cwd,text=True,capture_output=True,timeout=300)
  if r.returncode:raise RuntimeError(r.stdout+r.stderr)
  return r.stdout+r.stderr
 def compile(top,files):
  args=[compiler]+(['-B',lib] if lib else [])+['-g2012','-s',top,'-o',top+'.vvp']+files
  run(args)
 def simulate(top,args):
  command=[runtime]+(['-M','-','-M',lib] if lib else [])+[top+'.vvp']+args
  return run(command)
 for script in ['fat_fixture.py','make_integration.py','fat_extra_cases.py']:run([sys.executable,here/script])
 compile('tb_fat32',[here/'tb_fat32.sv',hdl/'SD/fat32_store.v'])
 for d in sorted((cwd/'work/fat_tests').iterdir()):
  m=json.loads((d/'meta.json').read_text());rel=d.relative_to(cwd).as_posix()
  output=simulate('tb_fat32',[f'+LBAS={rel}/lbas.hex',f'+BYTES={rel}/bytes.hex',f'+REQ={rel}/requests.hex',f'+N={m["n"]}',f'+COUNT={m["count"]}',f'+NREQ={m["requests"]}',f'+MERR={int(m["mount_error"])}',f'+RERR={int(m["read_error"])}'])
  results.append(dict(name=d.name,passed=True,output=output));print(output.strip(),flush=True)
 if not a.unit_only:
  compile('tb_fat_player',[here/'tb_fat_player.sv',hdl/'SD/fat32_store.v',hdl/'SD/sd_card_bmp.v',hdl/'SD/bmp_read.v',hdl/'SD/anm_read.v',hdl/'wav_read.v',hdl/'cdc_status_bus.v'])
  output=simulate('tb_fat_player',['+LBAS=work/fat_tests/integration/lbas.hex','+BYTES=work/fat_tests/integration/bytes.hex','+N=203'])
  results.append(dict(name='player_6_frames',passed=True,output=output));print(output.strip(),flush=True)
 compile('tb_fat_osd',[here/'tb_fat_osd.sv',hdl/'video_osd.v'])
 output=simulate('tb_fat_osd',[]);results.append(dict(name='osd_32',passed=True,output=output));print(output.strip())
 print(f'PASS: {len(results)} simulations')
 target=project/'sim/fat32/latest_results.json';target.write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
