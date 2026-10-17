#!/usr/bin/env python3
"""Install a supplied Viewer and reopen with saved pairing; no security settings change."""
import argparse
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys

p=argparse.ArgumentParser();p.add_argument('app',type=Path);p.add_argument('--label',required=True);p.add_argument('--workspace',type=Path);
argv=sys.argv[1:];split=argv.index('--') if '--' in argv else len(argv)
a=p.parse_args(argv[:split]);a.args=argv[split+1:]
if not re.fullmatch(r'[A-Za-z0-9.-]+',a.label):raise RuntimeError('Invalid install label')
root=a.workspace or next((x for x in Path(__file__).resolve().parents if (x/'work/host-live.json').exists()),None)
if root is None:raise RuntimeError('Pass --workspace')
root=root.resolve();app=(root/a.app).resolve();archive=root/f'work/RetinaLink-Viewer-{a.label}.zip'
subprocess.run(['/usr/bin/codesign','--verify','--strict',str(app)],check=True)
subprocess.run(['/usr/bin/ditto','-c','-k','--sequesterRsrc','--keepParent',str(app),str(archive)],check=True)
ssh=['/usr/bin/ssh','-S',str(root/'work/imac-ssh-session/control'),'-o','BatchMode=yes','-o','ConnectTimeout=5','-l','opsounimas','10.28.114.22']
doc=json.loads(subprocess.check_output(ssh+['cat "$HOME/Library/Logs/RetinaLink/Viewer.json"'],text=True));pid=int(doc['pid'])
subprocess.run(['/usr/bin/scp','-o','ControlPath='+str(root/'work/imac-ssh-session/control'),'-o','BatchMode=yes',str(archive),'opsounimas@10.28.114.22:Applications/'+archive.name],check=True)
args=a.args[1:] if a.args and a.args[0]=='--' else a.args
arguments=' '.join(shlex.quote(x) for x in args)
script=f'''set -e
command=$(/bin/ps -p {pid} -o command=)
case "$command" in
  "$HOME/Applications/RetinaLink"*"/RetinaLink Viewer.app/Contents/MacOS/RetinaLink"*) /bin/kill -TERM {pid} ;;
  *) printf 'Unexpected Viewer process; installation stopped\\n' >&2; exit 1 ;;
esac
/bin/sleep 1
/bin/mkdir -p "$HOME/Applications/RetinaLink-{a.label}"
/usr/bin/ditto -x -k "$HOME/Applications/{archive.name}" "$HOME/Applications/RetinaLink-{a.label}"
/usr/bin/codesign --verify --strict "$HOME/Applications/RetinaLink-{a.label}/RetinaLink Viewer.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/RetinaLink-{a.label}/RetinaLink Viewer.app"
"$HOME/Applications/RetinaLink-{a.label}/RetinaLink Viewer.app/Contents/MacOS/RetinaLink" --self-test > "$HOME/Library/Logs/RetinaLink/self-test-{a.label}.txt" 2>&1
/usr/bin/open -n "$HOME/Applications/RetinaLink-{a.label}/RetinaLink Viewer.app" --args --autoconnect --fullscreen {arguments}
'''
subprocess.run(ssh+[script],check=True)
(root/f'work/viewer-self-test-{a.label}.txt').write_bytes(subprocess.check_output(ssh+[f'cat "$HOME/Library/Logs/RetinaLink/self-test-{a.label}.txt"']))
print('Installed',a.label,'with native self-tests passed',flush=True)
