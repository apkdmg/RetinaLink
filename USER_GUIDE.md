# RetinaLink user guide

RetinaLink lets your main Mac use an iMac as a second display. Install **Host** on your main Mac and **Viewer** on the iMac, then approve the connection once on both screens. After setup, everyday controls live on Host.

## Before you begin

| Device | Requirements |
| --- | --- |
| Main Mac running Host | Apple silicon, macOS 13 or later |
| iMac running Viewer | Intel with macOS Catalina 10.15 or later; Apple silicon Viewer requires macOS 11 or later |
| Connection | A working local network, compatible direct USB data cable, or Ethernet connection |

RetinaLink currently supports one Viewer at a time. Native 5K means **5120 × 2880**. The target is 60 updates per second, but stable 5K60 and the latency of a directly connected monitor are not guaranteed. Actual performance depends on both Macs, the connection and the content being displayed. Audio, clipboard sharing and remote keyboard/mouse input are not included.

You need access to the iMac for the one-time Viewer installation and approval. Normal setup does **not** require Remote Login, an iMac account password, disk changes or another macOS installation.

## Install and pair for the first time

1. Open the [latest release](https://github.com/apkdmg/RetinaLink/releases/latest). Download the **Host `.pkg`** for your main Mac and the **Viewer `.dmg`** for your iMac.
2. On the main Mac, open the Host package. Follow **Continue → Install**, approving Apple's administrator prompt if requested. Open **RetinaLink Host** from Applications.
3. On the iMac, open the Viewer DMG, drag **RetinaLink Viewer** into Applications, and open that installed copy. You can also choose **Save Viewer Installer…** in Host and transfer its Viewer ZIP to the iMac.
4. In Host, choose **Add Display** and select your iMac. Both apps should be open and able to communicate over the same local network or supported cable connection.
5. Compare the **eight-digit number on both screens**. If the numbers match and you initiated setup, choose **Numbers Match — Pair** on Host and **Allow This Mac** on Viewer. Both approvals are required.
6. During setup, read the restart notice and choose **Open Viewer automatically after iMac sign-in** if you want Viewer to start whenever that account signs in. **Start Host automatically when this Mac signs in** enables startup on the main Mac too. These choices do not enable automatic login or change FileVault.
7. Allow Host's Screen Recording permission and either app's Local Network permission if macOS requests them. Viewer does not need Screen Recording permission. Use **Arrange Displays** on Host to position the iMac beside your main display. Eject the installer volumes afterward.

An unpaired Viewer is discoverable for ten minutes. If setup times out, use the iMac's **Display → Make Discoverable for Setup** menu and try **Add Display** again. A paired Viewer stops accepting new pairing requests. To reconnect an existing pair, open the original Host and use **Connect**; another pairing is unnecessary.

If discovery is blocked, Host also accepts a local hostname or IP address. On a managed network, ask your administrator whether local device discovery and traffic are permitted. RetinaLink leaves company restrictions and network settings unchanged. See [connection and pairing details](NATIVE_CONNECTION.md).

## Everyday use

Keep Host running on your main Mac. In Host 0.8.2 and later, clicking the red close button hides its window and running Dock icon while the display stays connected. The first close shows a brief hint pointing to RetinaLink in the menu bar. Choose **Open RetinaLink** there to restore the window and Dock icon. Clicking the yellow minimize button keeps the Dock icon, as usual. A Dock shortcut you have manually pinned remains under macOS's control.

Automatic Host startup after sign-in runs quietly in the menu bar, without opening its window or taking focus. Opening the installed Host again brings its controls forward. Choose **Quit RetinaLink** explicitly to exit; closing the window is not a disconnect or quit action. Viewer opens fullscreen after iMac sign-in when startup is enabled.

Host provides these controls:

- **Arrange Displays** opens macOS display arrangement.
- **Identify** helps you recognize the connected display.
- **Disconnect** pauses the connection without removing pairing; **Connect** resumes it.
- **Connection Details** shows connection status, display profiles and **Copy Diagnostics**.
- **Forget Display…** deliberately removes pairing and Viewer automatic startup. The iMac must be reachable to finish. Use it when removing a display, rather than for an ordinary update or temporary connection problem.

If the main Mac or connection becomes unavailable, Viewer keeps the iMac covered with a quiet fullscreen standby screen. It waits for the trusted Mac or network and retries automatically; it is not waiting for a Connect click. When the connection returns, the extended desktop replaces standby.

A sleeping, signed-out or FileVault-locked iMac cannot act as a display until it is available again. RetinaLink does not provide a new remote power-on or wake feature. Explicitly quitting Viewer is respected; it starts again at the next sign-in if startup is enabled.

## Choosing a connection

### Existing Ethernet or Wi-Fi

You can use the Macs' existing local network. Ethernet usually provides more consistent bandwidth than Wi-Fi, but the entire route matters: an older switch can limit the connection even if both Macs report a gigabit link.

### Direct Ethernet through an adapter

Connect a supported USB Ethernet adapter or hub to the Studio, then run an Ethernet cable from that adapter to the iMac's Ethernet port. Keep the Studio's company connection in place. With macOS's usual automatic addressing, RetinaLink discovers the cable route without manual IP addresses or a router.

The iMac's Ethernet port is now occupied by the display cable. If it previously provided company access, the iMac needs another existing connection, such as Wi-Fi or a second Ethernet adapter, to keep that access. RetinaLink does not configure or share Internet access for you.

The specific UGREEN CM888 direct-Ethernet hardware setup and its unplug/replug behavior have not yet been tested. See [cable requirements and test limits](DIRECT_ETHERNET.md).

### Direct USB-C-to-USB-A

Connect a data-capable cable directly from a **rear USB-C port on the Apple silicon Mac Studio** to a USB-A port on the Intel iMac. Leave existing company-network cables connected. This method does not use a USB hub, charging-only cable or USB-A-to-USB-A cable.

When macOS exposes the supported connection, RetinaLink detects it automatically and reuses the saved pairing. No IP address, new code or Remote Login setting is needed. If USB is disconnected, Viewer tries available network alternatives. When USB returns, it can switch back automatically. A switch between routes can briefly interrupt the picture.

The working cable in testing negotiated **USB 2 at 480 Mbps** and produced approximately **29–39 rendered updates per second at native 5K** in the measured moving-window test. USB 3 operation and stable 5K60 over USB remain unverified. A cable's printed speed rating does not establish its actual negotiated speed. See [USB and Ethernet details](DIRECT_ETHERNET.md).

## Updating RetinaLink

On Host, leave **Automatically keep both Macs up to date** enabled, or choose **Update Now…**. Both Macs need Internet access to GitHub's download services. An installed update restarts the affected app and reconnects using the existing pairing. An unavailable or rejected update leaves the current installation in place; Host reports the Viewer's update status.

**Version 0.8.0 and earlier need one manual signed replacement on both Macs before public automatic updates work.** These versions do not contain the public update addresses. Installing the latest release adds them; publishing an update alone cannot activate them in an older app.

For that first replacement:

1. Quit the app you are replacing and note its current permanent location.
2. Replace Host and Viewer **in their original locations**, then reopen them. Use the Viewer DMG on the iMac. For an existing Host outside `/Applications`, the role-specific **Host ZIP** in the release contains the signed Host app for replacement at that original location.
3. Keep the existing pairing. Do not choose **Forget Display** or enroll again just to update.

The Host PKG always installs into `/Applications`. It does not replace an older Host in your home Applications folder. Creating a second copy can leave you opening the old version. Likewise, installing Viewer in a different iMac account does not update the Viewer running in the dedicated display account. That protected account's first replacement requires administrator maintenance of its existing installation.

Compatible releases preserve saved pairing. macOS can still request first-run or periodic privacy approval. More information is in [Automatic updates](AUTOMATIC_UPDATES.md).

## Receiving Host through WhatsApp

Send the **Host `.pkg` as a document**. The recipient saves it, opens it in Apple's Installer, follows **Continue → Install**, then opens Host in Applications. They can use the received package; standard installation does not require Terminal commands or downloading it again through a browser.

Some download apps mark a DMG or app in a way that blocks launching even when it has been notarized. An already blocked DMG cannot repair itself. Send the new Host PKG to that recipient instead. Quit a running Host before installing, and observe the original-location advice above when upgrading.

The package approach was tested against a reproduction of the reported download-marking problem. Actual package delivery through WhatsApp and installation on the reported Tahoe Mac remain unverified. See the [installer validation record](VALIDATION.md) for the exact limits.

## Restarts, FileVault and unattended use

RetinaLink checks FileVault during setup and **leaves encryption unchanged**. On an older Intel iMac with FileVault enabled, someone must unlock the startup disk after shutdown or restart before Viewer can run. A startup app or an SSH connection cannot bypass that step. With ordinary setup, Viewer also waits for the chosen account to sign in.

### Using a retired iMac as a dedicated display

For a retired iMac, Host offers an optional **Dedicated Display Guide…** and advanced setup. On a supported Catalina or Big Sur iMac with FileVault already off, this can create a separate non-administrator **RetinaLink Display** account, enable automatic login, and start Viewer fullscreen. It disables that account's idle password lock and screensaver, and Viewer prevents idle system sleep while it runs. Other accounts' lock settings and global power settings stay unchanged.

This is a deliberate tradeoff: anyone with physical access can use the display account, and macOS stores a recoverable automatic-login credential. Keep personal files out of that account. Company policies may prohibit automatic login; RetinaLink does not override them. If FileVault is on or its status is unknown, setup explains the restart limitation instead of disabling encryption.

Dedicated account creation and restoration are advanced administrator operations that use authenticated **Remote Login/SSH** and an iMac administrator password entered securely in Host. They are separate from normal installation, pairing, streaming and reconnection, which do not require Remote Login. No extra disk, partition or macOS installation is part of this setup.

**Turn Off Dedicated Mode…** disables its automatic login and Viewer startup and re-enables its idle lock, while preserving the account and files. Administrator authorization is required. Turn this mode off before using **Forget Display**. Manually locking or signing out of the dedicated account still requires intervention. Successful reboot and wake testing on one iMac does not guarantee every managed setup; see [Validation](VALIDATION.md).

## If something does not work

**Host keeps asking for Screen Recording:** Check **System Settings → Privacy & Security → Screen & System Audio Recording** (the name varies by macOS version). Enable the permanently installed Host copy. Accept **Quit & Reopen** if offered, reopen Host, and use **Retry capture** if shown. If an enabled entry still refers to an older development copy, remove that RetinaLink Host entry with **−**, add the current installed app with **+**, and enable it. Keep only the intended installed copy running.

**The Macs cannot find each other:** Confirm both apps are open, the iMac is signed in and awake, and the connection is active. On macOS versions that request **Local Network** access, allow the relevant RetinaLink app. For first setup, renew Viewer's ten-minute discoverability window if needed. Company multicast, VPN or device-isolation policies can prevent discovery; contact your administrator rather than changing the company connection.

**Viewer stays on standby:** Check Host's status and Screen Recording permission, then try **Connect** on Host. After an iMac restart, check whether it needs FileVault unlock or sign-in. Changing cables should not require another pairing.

**The picture is laggy:** Check **Connection Details** on Host and confirm the intended USB or Ethernet route is being used. A USB 2 cable, a slow network switch or Wi-Fi congestion can limit performance. Native 5K resolution and a target of 60 updates/s do not prove 60 fresh frames reach the panel each second.

For further investigation, use **Copy Diagnostics** on Host and report the app versions and connection type. The [validation record](VALIDATION.md) distinguishes tested behavior from remaining performance and hardware limits.
