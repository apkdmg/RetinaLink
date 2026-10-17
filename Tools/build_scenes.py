#!/usr/bin/env python3
"""Build bounded native macOS benchmark scenes into a test workspace."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess

p=argparse.ArgumentParser();p.add_argument('--workspace',required=True,type=Path);a=p.parse_args()
root=a.workspace.resolve()
developer=Path(subprocess.check_output(['/usr/bin/xcode-select','-p'],text=True).strip())
default_sdk=developer/'Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
sdk=os.environ.get('RETINALINK_SDK') or (str(default_sdk) if default_sdk.is_dir() else subprocess.check_output(['/usr/bin/xcrun','--show-sdk-path'],text=True).strip())
sdk=str(Path(sdk).resolve())
scenes=Path(__file__).resolve().parent/'Scenes'
for source,name,exe in [('LayerScene','Layer','LayerScene'),('NativeWindowScene','Native','LayerScene'),('GPUScene','GPU','GPUScene'),('GPUScene','Source Probe','GPUScene')]:
    app=root/'work'/('RetinaLink Source Probe.app' if name=='Source Probe' else 'RetinaLink '+name+' Test.app');contents=app/'Contents'
    (contents/'MacOS').mkdir(parents=True,exist_ok=True)
    subprocess.run(['/usr/bin/xcrun','swiftc','-O','-sdk',sdk,'-target','arm64-apple-macos14.0','-module-cache-path',str(root/'work/scene-cache'),'-framework','AppKit','-framework','QuartzCore','-framework','MetalKit',str(scenes/(source+'.swift')),'-o',str(contents/'MacOS'/exe)],check=True)
    (contents/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':exe,'CFBundleIdentifier':'local.retinalink.Benchmark'+name.replace(' ',''),'CFBundleName':'RetinaLink '+name+' Test','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True}))
    subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(app)],check=True)
    print(app)
