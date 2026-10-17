# Reproducing the local two-Mac tests

These scripts automate the existing, user-authorized Studio/iMac test setup. They do not establish SSH credentials, change sharing/security settings, or create a new tunnel. The iMac must already be unlocked, and the saved encrypted RetinaLink pairing must work.

The workspace contains `work/imac-ssh-session/control`, an authenticated SSH control socket for `opsounimas@10.28.114.22`, and an existing reverse forward from the iMac's `127.0.0.1:58473` to the Studio's port 58473. Change these explicit test-machine defaults when adapting the tools. Do not commit SSH sockets, private keys, saved pairing codes or screen recordings.

Build apps with `bash build.sh` and scenes with:

```
python3 Tools/build_scenes.py --workspace /absolute/test-workspace
```

Install a supplied Viewer, run its self-tests directly on the iMac GPU, and reopen it with saved pairing:

```
python3 Tools/install_viewer.py --workspace /absolute/test-workspace \
  --label candidate /absolute/RetinaLink\ Viewer.app \
  -- --trace-path /Users/opsounimas/Library/Logs/RetinaLink/Viewer-trace.jsonl
```

Run a bounded scene and collect both endpoints automatically:

```
python3 Tools/run_stall_test.py --workspace /absolute/test-workspace \
  --seconds 90 --source layer --scene scroll \
  --host-app /absolute/test-workspace/work/build/apps/RetinaLink\ Host.app \
  unique-test-name --
python3 Tools/analyze_stalls.py /absolute/test-workspace/work/perf/unique-test-name
```

`--no-trace` leaves Host frame tracing disabled and skips trace collection; also launch Viewer without `--trace-path` for a production comparison. Automatic bounded one-second diagnostics still run. For these trials, run `summarize_perf.py` from the workspace with test names.

`--host-app` stops only a verified RetinaLink Host executable inside the workspace, then launches that app and waits for automatic reconnection. Omit it to retain the current connection. The default run makes no SSH calls during motion and fetches logs afterward. `--poll` reproduces two-second polling, using `poll_scene_test.py`. Use fresh names; completed results are not overwritten. Keep quiet trials at 90 seconds or less when one-second samples matter, because automatic snapshots retain 120 records. The metadata frame trace has a separate 250,000-event bound and can cover a longer trial; restart the traced apps before reaching that bound.

Source choices are `layer` (Core Animation bitmap text), `native` (a real AppKit window) and `gpu` (a Metal-generated motion scene with draw/GPU-completion timing; positive presentation timestamps are unavailable on the virtual display in these trials). `--prefer-60` explicitly requests a 60 Hz Core Animation animation; `--measure-display-link` adds a source callback counter. Neither a requested rate nor callbacks prove displayed frames. The GPU scene is captured through ScreenCaptureKit; it does not bypass capture.

Host arguments follow `--`. Version 0.2.8 defaults to negotiated parallel lossless packing for large frames. `--serial-packing` supplies a control; old Viewers always receive the original serial format. `--baseline-dirty-atomic` restores the old GPU flag operation. `--capture-only` releases capture buffers immediately without encoding or transmission. `--encode-only` captures, encodes and packs but discards frames instead of transmitting. These last two probes deliver zero displayed frames and must never be reported as display-FPS tests.

`--trace-path` enables timing and frame-identity metadata only, written off the hot queues in one-second batches. It contains no images, pairing codes, packet payloads, addresses or window titles. It is disabled by default. Allow two seconds after motion for trace batches to settle.

The analyzer matches sequence numbers and subtracts elapsed intervals measured on each machine; it does not depend on synchronized system clocks. `transport_residual_ms` includes transfer, TLS/SSH and unclassified endpoint overhead, including Host ACK queue time; it is not a pure network RTT. `gpu_queue_ms` measures pre-commit to reported GPU start; build 20 additionally measures presentation-registration and commit-call durations. Actual positive Metal presentation callbacks are counted separately from rendered frames and ACKs. None of these measurements establishes camera-measured input-to-photon latency.


## Version 0.2.9 isolation tools

`--tile-blits --cached-upload` on Viewer restores the old per-tile, cached-memory upload path. Use each flag separately to isolate grouping or memory policy. The default is coalesced horizontal runs and write-combined, CPU-write-only staging. Packet contents and BC7 bytes are unchanged.

Build the standalone universal Viewer probe with `bash Tools/build_viewer_probe.sh 31`. Install its generated app through `install_viewer.py`, with arguments such as `--plan full,sparse,full --period 15 --trace-path /Users/opsounimas/Library/Logs/RetinaLink/Probe.jsonl`. It generates bounded 5K test packets in RAM, omitting capture/network/LZ4 work, and exits after its plan. `collect_viewer_probe.py TEST --trace Probe.jsonl` waits for completion and normal app exit, then retrieves the same process's logs and trace. `analyze_viewer_probe.py work/perf/TEST` reports stages and marks zero-presentation or visibility/sleep samples. All rendering still uses production `DisplayView`; it is not an end-to-end display benchmark. Build 29 used `--write-combined` as an opt-in control; build 30 instead defaults to it and uses `--cached-upload` for the control.

Host `--probe-plan capture,hold,source,snapshot,source,pack,capture --probe-period 30 --probe-hold 0.006` holds one continuous capture stream while changing only the measured processing phase. It transmits no frames. `source` GPU-encodes the captured surface; `snapshot` GPU-encodes an independent deep copy; both force full frames. `pack` packs cached output on the CPU. `analyze_capture_probe.py` compares these phases with source draw counters. Do not equate a source draw callback, GPU completion or changed application property with actual source presentation.

Host `--capture-cycle-period 20` stops and restarts ScreenCaptureKit at that interval while retaining the same virtual display and source. The Viewer intentionally freezes during capture-off phases. It is an explicit diagnostic control, not a reconnect policy or production optimization. Cancel it by restarting Host without the flag.

The GPU scene's `--frame-trace` records per-frame drawable acquisition, GPU execution, active/visible state and draw gaps, capped at 15,000 records. Source `--presentation-plan native,no-counter,unsynced,native --presentation-period 20` changes only that test app's presentation controls. Physical Viewer vsync remains enabled. Unsynced source results are diagnostic evidence, not normal-workload performance claims. `build_scenes.py` also builds the source-control test app from `Tools/Scenes/GPUScene.swift`; set `--source probe` in the harness for `work/RetinaLink Source Probe.app`. Frame times are metadata only.

Viewer `--trace-actual-present` replaces Metal's convenience presentation registration with an explicit scheduled-handler call to `drawable.present()`. This measures that alternative handoff but changed observed scheduling, so it must not be treated as a transparent measurement of the original helper. It remains opt-in and is excluded from release tests.

The transparent compositor pulse experiment did not show a reversed on/off effect and is not part of production. `run_pulse_test.py` and `Scenes/PulseScene.swift` retain the bounded reproduction, not a recommended setting.


Keep UI automation inactive during performance measurements. Resetting the REPL alone did not stop SkyComputerUseService in this session; its continuing capture materially lowered source FPS. Only the agent-owned helper was terminated for the successful SSH-only control. Do not terminate unrelated capture/remote-access services without authorization. The test runner writes `collectionFinished` after fetching evidence; a scene's earlier `finished` timestamp is not a safe signal to replace Host or Viewer. Prefer waiting for the runner process to exit.


Build 31+ traces `surface_update`, `redraw` and `redraw_presented`, including the original content sequence. This accounts for the static-image resize path separately from received frames. `--skip-redundant-redraws` is a diagnostic control, not enabled by default; the steady trace found no extra redraw presentations.

Build 32 Viewer `--presentation-plan 0,24,0 --presentation-period 25` runs immediate/timed/immediate phases. Leads must be finite, 0…40 ms, plans bounded to six phases, first and last lead zero, and periods 10…60 seconds. Targets and phase changes are traced. The final zero phase persists, returning to normal rendering. Discard transition windows; scheduling changes can perturb queued frames. This experiment did not establish a production gain and is disabled by default. Timed presentation can add latency; do not report its FPS without that tradeoff.

## Host-led setup and appliance recovery (0.3.0)

`test_display_setup.py` uses an existing authenticated SSH ControlMaster and the actual Host setup UI controller. Pass a permanently installed Host app whose bundled Viewer archive matches it:

```sh
python3 Tools/test_display_setup.py \
  --host-app '/Users/YOUR_USER/Applications/RetinaLink Host.app' \
  --address IMAC_ADDRESS --user IMAC_USER \
  --socket /absolute/path/to/existing/control \
  --workspace /absolute/path/to/retinaku
```

The harness is intended for this development setup, not an end-user installer. It replaces the verified running RetinaLink Host, drives enrollment, and installs/loads the selected user login agents. It uses `work/setup-030/control` as an explicitly enabled local test-command directory; that seam is absent from normal app launches. Output is saved in `work/setup-030`. The private directory contains only test state, metadata reports and app-rendered interface images; enrollment secrets are not written there.

The default tests standard display setup. Add `--dedicated-display` to exercise that opt-in selection; it still never enables automatic login. Host launches through native Launch Services, then through its GUI login agent during recovery, so Screen Recording must be granted to the installed Host itself. A terminal or Codex capture grant is not substituted for that permission.

It tests fullscreen streaming/standby, Host pause/resume, window-close behavior, a verified Viewer process crash, pairing removal and re-enrollment, Host startup through its GUI login agent and recreation of the app-owned display tunnel. It does not reboot, log out, lock a display, stop Screen Sharing, run a UI capture bridge, disable FileVault, change automatic login or modify screen-lock policy. Login-agent loading in the existing GUI session is not evidence of bypassing FileVault or an actual cold-boot test.

For app-only visual review, `--export-ui /absolute/file.png` renders that app’s own content view; it does not capture the desktop or other applications. Viewer `--standby-only --windowed-viewer` is a bounded preview option when paired with separate `--diagnostics-path` and `--ui-state-path` destinations. Do not leave preview/test options on a production login agent.
