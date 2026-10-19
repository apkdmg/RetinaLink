#!/usr/bin/env python3
"""Test synthetic download quarantine on disposable copies of a completed PKG.

Developer integration check, not an end-user installation step. Never installs
an app. Optional native Installer inspection uses accessibility text only and
refuses to run when another Installer session is open. No screen capture helper.
Actual delivery through WhatsApp and the recipient's OS need separate validation.
"""
import argparse
import json
import pathlib
import shutil
import subprocess
import tempfile
import time

import package_pkg
from release import digest


def result(argv, timeout=30):
    process = subprocess.run([str(item) for item in argv], capture_output=True,
                             text=True, timeout=timeout)
    return {'exit': process.returncode, 'stdout': process.stdout, 'stderr': process.stderr}


def helper_off():
    processes = result(['/bin/ps', '-axo', 'comm='])
    if processes['exit'] or any(pathlib.Path(line.strip()).name == 'SkyComputerUseService'
                                for line in processes['stdout'].splitlines()):
        raise RuntimeError('Cannot confirm the UI capture helper is off; stopping.')


def inspect_installer(package):
    existing = result(['/usr/bin/pgrep', '-x', 'Installer'])
    if existing['exit'] != 1:
        raise RuntimeError('Close the existing Installer session before the optional UI check.')
    opened = result(['/usr/bin/open', '-a', '/System/Library/CoreServices/Installer.app', package])
    if opened['exit']:
        raise RuntimeError('Native Installer did not open: ' + opened['stderr'])
    launched = result(['/usr/bin/pgrep', '-x', 'Installer'])
    try:
        # Only this app's text/buttons are read. No image, desktop capture,
        # installation click or administrator authentication is performed.
        inspected = result(['/usr/bin/osascript', '-e', '''
tell application "System Events"
  repeat 20 times
    if exists process "Installer" then
      tell process "Installer"
        if (count of windows) > 0 then
          set installerWindow to window 1
          set labels to value of every static text of installerWindow
          set buttonsPresent to name of every button of installerWindow
          set ready to false
          if exists button "Continue" of installerWindow then
            set ready to enabled of button "Continue" of installerWindow
          end if
          if ready and (name of installerWindow is "Install RetinaLink Host") then
            return {name of installerWindow, labels, buttonsPresent, "continueEnabled=true"}
          end if
        end if
      end tell
    end if
    delay 0.5
  end repeat
  error "Installer did not reach an enabled Continue button."
end tell'''])
        if inspected['exit'] or 'continueEnabled=true' not in inspected['stdout']:
            raise RuntimeError('Native Installer did not reach its normal welcome screen: ' +
                               inspected['stderr'])
        return {'open': opened, 'welcome': inspected, 'installClicked': False,
                'accessibilityTextOnly': True}
    finally:
        # Installer was absent at the start. Refuse cleanup if the process or
        # exclusive single-window session changed while this test ran.
        current = result(['/usr/bin/pgrep', '-x', 'Installer'])
        exclusive = result(['/usr/bin/osascript', '-e', '''
tell application "System Events" to tell process "Installer"
  if (count of windows) is 1 then
    if name of window 1 is "Install RetinaLink Host" then return "exclusive=true"
  end if
  return "exclusive=false"
end tell'''])
        if (launched['exit'] or current != launched or exclusive['exit'] or
                'exclusive=true' not in exclusive['stdout']):
            raise RuntimeError('Installer session changed; leaving its windows open for manual closure.')
        closed = result(['/usr/bin/osascript', '-e', 'tell application "Installer" to quit'])
        if closed['exit']:
            raise RuntimeError('Close the disposable Installer window manually; quit failed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=pathlib.Path, required=True,
                        help='Completed package_pkg.py directory, not an arbitrary PKG.')
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--open-installer', action='store_true')
    args = parser.parse_args()
    directory = args.directory.resolve()
    output = args.output.resolve()
    if output.exists():
        raise ValueError('Use a new evidence file; existing results are not overwritten.')
    helper_off()
    package_pkg.verify(argparse.Namespace(directory=directory, output=None))
    state = json.loads((directory / 'pkg-state.json').read_text())
    source = directory / state['file']
    report = {'platform': result(['/usr/bin/sw_vers']), 'sourceSHA256': digest(source),
              'notarization': state['notarization'], 'syntheticQuarantine': True,
              'actualWhatsAppDeliveryTested': False, 'systemInstallationTested': False,
              'appInstalledOrLaunched': False, 'uiCaptureHelperUsed': False, 'checks': []}
    try:
        with tempfile.TemporaryDirectory(prefix='pkg-delivery-', dir=directory) as temporary:
            for flags in ('0083', '0087', '0187'):
                copied = pathlib.Path(temporary) / ('RetinaLink-' + flags + '.pkg')
                shutil.copy2(source, copied)
                quarantine = flags + ';' + format(int(time.time()), 'x') + ';RetinaLink Delivery Test;'
                subprocess.run(['/usr/bin/xattr', '-w', 'com.apple.quarantine', quarantine,
                                str(copied)], check=True)
                check = {'flags': flags, 'quarantine': quarantine, 'sha256': digest(copied),
                         'policy': result(['/usr/sbin/spctl', '--assess', '--type', 'install',
                                           '--verbose=2', copied])}
                report['checks'].append(check)
                if check['sha256'] != state['sha256'] or check['policy']['exit']:
                    raise RuntimeError('Quarantined PKG failed integrity or install policy: ' + repr(check))
                if flags == '0087' and args.open_installer:
                    check['nativeInstaller'] = inspect_installer(copied)
        helper_off()
        report['passed'] = True
    except Exception as error:
        report.update(passed=False, error=str(error), errorType=type(error).__name__)
        raise
    finally:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2) + '\n')
    print('PASS: synthetic quarantine accepted; no app installed. Evidence: ' + str(output))


if __name__ == '__main__':
    main()
