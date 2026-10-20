# RetinaLink

**Give your iMac a second life as a display.**

Use an older Retina iMac as a second display for your Apple silicon Mac. Put your editor, documents or reference windows on its 5K screen, and keep working from your main Mac.

Install **Host** on your main Mac and **Viewer** on the iMac. Approve the connection once, then manage everyday use from Host. Viewer opens fullscreen and reconnects automatically.

**[Download Host for your main Mac](https://github.com/apkdmg/RetinaLink/releases/download/v0.8.4/RetinaLink-Host-0.8.4.pkg)** · **[Download Viewer for your iMac](https://github.com/apkdmg/RetinaLink/releases/download/v0.8.4/RetinaLink-Viewer-0.8.4.dmg)**

Current release: **0.8.4** · [Release notes](https://github.com/apkdmg/RetinaLink/releases/tag/v0.8.4) · [User guide](USER_GUIDE.md) · [Compare alternatives](COMPARISON.md)

## Why RetinaLink?

- **Reuse the screen you already own.** Extend your workspace onto a Retina iMac at native 5120 × 2880 resolution.
- **Set up once.** Saved pairing, startup after sign-in and automatic reconnection mean no daily code or Connect button on the iMac.
- **One saved iMac.** A different macOS sign-in can reconnect with a simple approval. Previously approved sign-ins reconnect automatically.
- **Update an offline iMac.** From 0.8.3, only Host needs internet for updates. Viewer receives and verifies updates through the existing display connection.
- **Control it from your main Mac.** Arrange displays, pause the connection and manage updates from Host. Close Host’s window to keep it in the menu bar while Viewer stays fullscreen or shows a quiet standby screen.
- **Choose your connection.** Use Ethernet, or direct USB on supported setups, without a proprietary display dongle. RetinaLink discovers available connections automatically.
- **Keep control of your Macs.** Standard setup leaves FileVault and network settings unchanged. Connections are encrypted; normal installation and pairing do not require Remote Login.
- **Free and open source.** Use the signed, Apple-notarized apps, or inspect and modify the source under GNU GPLv3.

**What to expect:** Native 5K is supported, but stable 60 fps across workloads and the latency of a directly connected monitor are not established. Performance depends on the connection, Macs and screen content. See [current limitations](#current-limitations).

## What you need

| | Main Mac — Host | Display Mac — Viewer |
| --- | --- | --- |
| Processor | Apple silicon, such as an M-series Mac Studio | Intel or Apple silicon |
| macOS | macOS 13 Ventura or later | Intel: macOS 10.15 Catalina or later; Apple silicon: macOS 11 Big Sur or later |
| Connection | A local connection between the Macs | Ethernet or supported direct USB; Wi-Fi preview is also available |

The hardware test setup is a **2023 Mac Studio and Late-2014 27-inch Retina 5K iMac running Big Sur**, with AMD Radeon R9 M290X graphics. Not every Mac and macOS combination has been tested. One display Mac is supported at a time.

## Get started

You need access to both Macs for the first installation and approval. After that, everyday controls live on Host.

1. **Connect the Macs.** For the first setup, connect both to the same local network, preferably by Ethernet. You can change to a supported cable connection later without pairing again.
2. **Install Host on your main Mac.** Open the Host `.pkg`, follow the installer, then open **Applications → RetinaLink Host**. Allow **Screen Recording** and **Local Network** access when macOS asks.
3. **Install Viewer on the iMac.** Open the Viewer `.dmg`, drag **RetinaLink Viewer** into **Applications**, and open it. Viewer does not need Screen Recording permission.
4. **Pair once.** On Host, choose **Add Display** and select your iMac. Compare the eight-digit number on both screens. If they match, choose **Numbers Match — Pair** on Host and **Allow This Mac** on Viewer.
5. **Make it yours.** Choose startup after sign-in, then use **Arrange Displays** on Host to position the iMac beside your main screen. Move a window onto it to begin.

Viewer starts fullscreen after sign-in and reconnects to your trusted Mac. If the connection disappears, it shows a standby screen and keeps trying. You can close Host's window and continue using it from the menu bar.

**After an iMac restart:** FileVault may require someone to unlock it before Viewer can start. RetinaLink explains this during setup and leaves encryption unchanged. Optional dedicated-display setup is available for suitable retired iMacs; [read the automatic-login tradeoffs first](USER_GUIDE.md#using-a-retired-imac-as-a-dedicated-display).

**Already using 0.8.2 or earlier?** Install Viewer 0.8.4 once to enable updates through Host without internet on the iMac. Host 0.8.1 or later can update itself with **Update Now…**; Host 0.8.0 or earlier also needs one replacement. Keep each app in its existing location and retain its saved pairing. The Host PKG installs to `/Applications`; it does not replace a copy in your home Applications folder. See [updating an existing installation](USER_GUIDE.md#updating-retinalink).

## Choose a connection

| Connection | How it fits your desk | What to know |
| --- | --- | --- |
| **Ethernet through your network** | Both Macs connect to your existing LAN. | The simplest place to start. Bandwidth depends on the entire network path. |
| **Direct Ethernet** | A cable joins the Macs; a USB Ethernet adapter can provide a spare port. | Automatic discovery is implemented. The intended adapter-and-cable setup still needs its physical hardware test. |
| **Direct USB-C to USB-A** | A rear Studio USB-C port connects directly to USB-A on a supported Intel iMac. | The tested cable ran at USB 2 speed. USB 3 operation and stable 5K60 over USB remain unverified. |

RetinaLink uses existing automatic addresses; normal cable setup needs no typed IP address or network-setting changes. Cable compatibility and company policies still matter. See the [connection guide](USER_GUIDE.md#choosing-a-connection).

## How does it compare?

RetinaLink focuses on reusing an older iMac with controls on the main Mac, saved pairing and an open codebase. Other products may suit different hardware, support needs or workflows.

| Option | Main distinction |
| --- | --- |
| **RetinaLink** | Free, GPLv3, encrypted pairing and controls on the main Mac. Native 5K tested; stable 5K60 remains a goal. |
| **[RetinaRelay](https://www.retinarelay.com/compatibility)** | Commercial iMac-focused software with audio. Vendor reports 5K60 on a Late-2015 iMac over USB SuperSpeed. |
| **[Luna Display](https://support.astropad.com/en/articles/11835385-does-luna-display-support-4k-and-5k-retina-resolutions)** | Requires Luna hardware. Its Mac-specific 5K modes are listed at 45 or 30 Hz. |
| **[Duet](https://www.duetdisplay.com/use-imac-as-a-monitor)** | A broader Mac, PC and mobile-device ecosystem. Check legacy-macOS connection options for a Big Sur iMac. |
| **[Apple's built-in options](COMPARISON.md)** | Target Display Mode and AirPlay to Mac do not provide a supported route for the Late-2014 Big Sur iMac + 2023 Studio setup. |

Read the [full comparison and sources](COMPARISON.md), checked **19 October 2026**, before choosing. Vendor specifications are not head-to-head benchmarks; we have not established RetinaLink as faster than these alternatives.

## Current limitations

- **60 fps is a target.** Native 5K dimensions do not guarantee sustained 60-fps presentation or external-monitor latency.
- **Image compression is lossy.** This is not a reference-colour workflow.
- **Audio, clipboard sharing and remote input are not implemented.** Use your main Mac's keyboard and pointing device for its extended desktop.
- **Both Macs must be running and signed in.** Standard startup cannot bypass FileVault or the login screen.
- **macOS compatibility can change.** The virtual-display implementation uses an undocumented Apple API.

[Validation and measured performance](VALIDATION.md) records what has actually been tested, including startup, reconnection and updates.

## Help and more detail

| Looking for… | Start here |
| --- | --- |
| Installation, updates, permissions or a missing iMac | [User guide and troubleshooting](USER_GUIDE.md) |
| An alternative that fits your setup | [Compare display apps](COMPARISON.md) |
| Cable requirements and automatic connection behavior | [USB and Ethernet details](DIRECT_ETHERNET.md) |
| Pairing and connection security | [Connection design](NATIVE_CONNECTION.md) |
| Test results and known gaps | [Validation](VALIDATION.md) |
| A place to report a problem | [GitHub Issues](https://github.com/apkdmg/RetinaLink/issues) |

For contributors: [build from source](SOURCE_BUILD.md), [developer test tools](Tools/README.md), [release packaging](RELEASING.md) and [signed-update publishing](AUTOMATIC_UPDATES.md).

## License

RetinaLink is licensed under the **[GNU General Public License, version 3 only](LICENSE)** and is provided without warranty. [Third-party components](THIRD_PARTY_NOTICES.md) retain their own licenses. Matching source archives are included with public releases.
