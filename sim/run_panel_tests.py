"""Regression checks for the unified right-side audio panel."""
from pathlib import Path
import argparse,subprocess,tempfile,json,shutil
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tools-dir',type=Path);a=p.parse_args()
root=Path(__file__).resolve().parents[1];sim=root/'sim';hdl=root/'user_source/hdl_source'
iv=a.tools_dir/'bin/iverilog.exe' if a.tools_dir else shutil.which('iverilog');vv=a.tools_dir/'bin/vvp.exe' if a.tools_dir else shutil.which('vvp');lib=a.tools_dir/'lib/ivl' if a.tools_dir else None
if not iv or not vv:p.error('Install Icarus or pass --tools-dir')
tests=[]
with tempfile.TemporaryDirectory(prefix='audio_panel_') as cwd:
 for name,modules in [('tb_audiofx_overlay',['audio_waveform','video_osd']),('tb_audio_waveform',['audio_waveform','audio_test_pcm']),('tb_waveform_pipeline',['audio_waveform']),('tb_progress_osd',['video_osd']),('tb_av_osd',['video_osd']),('tb_wav_osd',['video_osd']),('tb_animation_overlay',['video_osd','video_fade'])]:
  def run(args):
   r=subprocess.run([str(x) for x in args],cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=300)
   if r.returncode:raise RuntimeError(r.stdout+r.stderr)
   return r.stdout+r.stderr
  run([iv]+(['-B',lib] if lib else [])+['-g2012','-s',name,'-o',name+'.vvp',sim/(name+'.sv')]+[hdl/(n+'.v') for n in modules])
  output=run([vv,'-i']+(['-M','-','-M',lib] if lib else [])+[name+'.vvp']);print(output.strip(),flush=True);tests.append(dict(name=name,passed=True,output=output))
(sim/'panel_results.json').write_text(json.dumps(tests,ensure_ascii=False,indent=2),encoding='utf-8');print(f'PASS {len(tests)} panel checks')
