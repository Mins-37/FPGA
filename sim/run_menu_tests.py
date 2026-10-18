"""Media browser RTL checks. --full includes the long physical-key/FAT32/AVM integration."""
from pathlib import Path
import argparse,subprocess,tempfile,json,shutil,sys
from menu_fixture_tools import expected
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tools-dir',type=Path);p.add_argument('--full',action='store_true');a=p.parse_args()
project=Path(__file__).resolve().parents[1];sim=project/'sim';hdl=project/'user_source/hdl_source'
iv=a.tools_dir/'bin/iverilog.exe' if a.tools_dir else shutil.which('iverilog');vv=a.tools_dir/'bin/vvp.exe' if a.tools_dir else shutil.which('vvp');lib=a.tools_dir/'lib/ivl' if a.tools_dir else None
if not iv or not vv:p.error('Install Icarus or pass --tools-dir')
tests=[]
with tempfile.TemporaryDirectory(prefix='media_menu_') as folder:
 cwd=Path(folder);(cwd/'work').mkdir()
 def run(command):
  r=subprocess.run([str(v) for v in command],cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1200)
  if r.returncode:raise RuntimeError(r.stdout+r.stderr)
  return r.stdout+r.stderr
 def compile(top,files):run([iv]+(['-B',lib] if lib else [])+['-g2012','-s',top,'-o',top+'.vvp']+files)
 def simulate(top,args=None):return run([vv,'-i']+(['-M','-','-M',lib] if lib else [])+[top+'.vvp']+(args or []))
 for top,modules in [('tb_menu_control',['audio_controls.v','media_menu_control.v']),('tb_menu_osd',['media_menu_osd.v','media_menu_control.v']),('tb_audio_controls',['audio_controls.v','SD/sd_card_bmp.v']),('tb_clean_controls',['audio_controls.v']),('tb_clean_video',['audio_waveform.v','video_osd.v'])]:
  compile(top,[sim/(top+'.sv')]+[hdl/n for n in modules]);output=simulate(top);print(output.strip(),flush=True);tests.append(dict(name=top,passed=True,output=output))
 (sim/'menu_unit_results.json').write_text(json.dumps(tests,ensure_ascii=False,indent=2),encoding='utf-8')
 output=run([sys.executable,sim/'fat32/run_tests.py']+(['--tools-dir',a.tools_dir] if a.tools_dir else [])+['--unit-only']);print(output.strip(),flush=True)
 tests.extend(json.loads((sim/'fat32/latest_results.json').read_text(encoding='utf-8')))
 for script in ['fat32/fat_fixture.py','make_audio_fixture.py','make_animation_fixture.py','make_plus_switch_fixture.py']:run([sys.executable,sim/script])
 compile('tb_menu_fat',[sim/'tb_menu_fat.sv',hdl/'SD/fat32_store.v']);name_tests=[]
 for d in [cwd/'work/fat_tests'/n for n in ['empty','one','five','thirtytwo','cap']]+[cwd/'work'/n for n in ['audio_fixture','animation_fixture','plus_switch_fixture']]:
  meta=json.loads((d/'meta.json').read_text());gold,count=expected(d)
  (cwd/'work/names.hex').write_text('\n'.join(f'{v:02x}' for v in gold));nr=0
  if meta.get('requests',0):
   words=(d/'requests.hex').read_text().split();(cwd/'work/requests.hex').write_text('\n'.join(words[:2]+words[-2:]));nr=2
  rel=d.relative_to(cwd).as_posix()
  args=[f'+LBAS={rel}/lbas.hex',f'+BYTES={rel}/bytes.hex','+REQ=work/requests.hex',f'+N={meta["n"]}',f'+COUNT={count}',f'+NREQ={nr}','+MERR=0','+RERR=0','+NAMES=work/names.hex']
  output=simulate('tb_menu_fat',args);print(d.name,output.strip(),flush=True);name_tests.append(dict(name=d.name,passed=True,output=output))
 (sim/'menu_fat_results.json').write_text(json.dumps(name_tests,ensure_ascii=False,indent=2),encoding='utf-8');tests.extend(name_tests)
 if a.full:
  mods=['SD/sd_card_bmp.v','SD/fat32_store.v','SD/bmp_read.v','SD/anm_read.v','wav_read.v','cdc_status_bus.v','audio_test_pcm.v','audio_controls.v','media_menu_control.v','media_menu_osd.v']
  compile('tb_menu_player',[sim/'tb_menu_player.sv']+[hdl/n for n in mods]);d=cwd/'work/plus_switch_fixture';n=json.loads((d/'meta.json').read_text())['n']
  output=simulate('tb_menu_player',['+LBAS=work/plus_switch_fixture/lbas.hex','+BYTES=work/plus_switch_fixture/bytes.hex',f'+N={n}']);print(output,flush=True)
  result=dict(name='physical_menu_real_fat_avm',passed=True,output=output);(sim/'menu_player_result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8');tests.append(result)
(sim/'menu_latest_results.json').write_text(json.dumps(tests,ensure_ascii=False,indent=2),encoding='utf-8');print(f'PASS {len(tests)} menu checks')
