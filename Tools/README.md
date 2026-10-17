# Reproducing the local two-Mac tests

These scripts automate the existing, user-authorized Studio/iMac test setup. They do not establish SSH credentials, change sharing/security settings, or create a new tunnel. The iMac must already be unlocked, and the saved encrypted RetinaLink pairing must work.

The workspace contains `work/imac-ssh-session/control`, an authenticated SSH control socket for `opsounimas@10.28.114.22`, and an existing reverse forward from the iMac's `127.0.0.1:58473` to the Studio's port 58473. Change these explicit test-machine defaults when adapting the tools. Do not commit SSH sockets, private keys, saved pairing codes or screen recordings.

Build apps with `../build.sh` and scenes with:

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

Source choices are `layer` (Core Animation bitmap text), `native` (a real AppKit window) and `gpu` (a Metal-generated motion scene with actual source presentation counters). `--prefer-60` explicitly requests a 60 Hz Core Animation animation; `--measure-display-link` adds a source callback counter. Neither a requested rate nor callbacks prove displayed frames. The GPU scene is captured through ScreenCaptureKit; it does not bypass capture.

Host arguments follow `--`. Version 0.2.8 defaults to negotiated parallel lossless packing for large frames. `--serial-packing` supplies a control; old Viewers always receive the original serial format. `--baseline-dirty-atomic` restores the old GPU flag operation. `--capture-only` releases capture buffers immediately without encoding or transmission. `--encode-only` captures, encodes and packs but discards frames instead of transmitting. These last two probes deliver zero displayed frames and must never be reported as display-FPS tests.

`--trace-path` enables timing and frame-identity metadata only, written off the hot queues in one-second batches. It contains no images, pairing codes, packet payloads, addresses or window titles. It is disabled by default. Allow two seconds after motion for trace batches to settle.

The analyzer matches sequence numbers and subtracts elapsed intervals measured on each machine; it does not depend on synchronized system clocks. `transport_residual_ms` includes transfer, TLS/SSH and unclassified endpoint overhead, including Host ACK queue time; it is not a pure network RTT. `gpu_queue_ms` measures pre-commit to reported GPU start; build 20 additionally measures presentation-call and commit-call durations. Actual positive Metal presentation callbacks are counted separately from rendered frames and ACKs. None of these measurements establishes camera-measured input-to-photon latency.
