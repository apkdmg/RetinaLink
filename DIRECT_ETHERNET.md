# Automatic USB and Ethernet connections

RetinaLink discovers the paired Mac over direct USB as well as Ethernet, without entering IP addresses. It uses macOS's existing automatic addressing. RetinaLink does not assign static addresses or change DHCP, IPv6, DNS, gateways, routes, network service order, Internet Sharing or company network policies.

## Direct USB-C-to-USB-A

1. Install matching current Host and Viewer apps. Keep the existing pairing; no setup code is needed again.
2. Connect a data-capable cable directly from a **rear USB-C port on the Apple silicon Mac Studio** to a USB-A port on the Intel iMac. The Intel Viewer supports macOS Catalina 10.15 or later. Do not use a hub or a USB-A-to-USB-A cable.
3. Leave both existing company-network connections in place and keep Host and Viewer open. Once macOS exposes and addresses the USB NCM interface, RetinaLink discovers it, verifies the saved TLS credential and selects **USB**. Normal Local Network permission still applies.

No user-entered address, Remote Login, Internet Sharing, added network service or administrator network configuration is part of this flow. An absent or unconfigured USB interface cannot be repaired by RetinaLink's discovery code; it waits for macOS and retains available network alternatives. Connecting USB does not alter FileVault or remove its restart/unlock requirement.

The first working cable on this Studio/iMac pair negotiated **USB 2.0 High Speed (480 Mbps)**. The replacement cable tested on 21 October negotiated **USB 3 SuperSpeed (5 Gbps)**, with about **2.87 Gbps** of application throughput. The 0.8.8 compression changes reduced bytes per full-screen 5K frame by approximately 27.7% and improved delivered updates from 25.5 to 35.3/s. Moving-window and text-scroll scenes stayed near 59–60/s. These counters measure Viewer GPU-completion acknowledgements; stable physical 5K60 remains unvalidated. See [VALIDATION.md](VALIDATION.md) for the same-build comparison. A nominal 100 Mbps value reported by Apple's virtual NCM network interface is not the USB bus rate and must not be used to label the cable's speed.

Detection reads the interface's IOKit ancestry. A public Apple device-side NCM interface or a supported Apple Mac NCM peer can identify a USB route; ordinary USB Ethernet adapters, iPhone tethering, Thunderbolt interfaces and private/restricted Apple management channels are not labelled direct USB. Positive hardware evidence is still only a transport hint. The saved TLS credential authenticates the peer.

## Connecting with Ethernet

1. Install the compatible signed Host and Viewer apps. An existing pairing remains valid.
2. Connect the USB Ethernet hub to the Studio, then connect an ordinary Ethernet cable between that hub and the iMac's Ethernet port. Keep the Studio's existing company network connection plugged in.
3. Keep Viewer open on the iMac and Host open on the Studio. Allow macOS's normal Local Network permission if requested. RetinaLink discovers the connection and authenticates it using the saved pairing.

With the usual automatic macOS network settings, no router, DHCP server or manual address entry is needed for that cable. IPv6 link-local addressing works without a DHCP server; macOS can also assign an IPv4 link-local address when DHCP is unavailable. RetinaLink observes these addresses rather than configuring them.

The iMac's Ethernet port is occupied by the display cable in this arrangement. If that port previously provided its company connection, maintaining separate company access requires another existing connection, such as Wi-Fi, or another Ethernet adapter. RetinaLink does not change those connections.

New users still approve Host once on both screens. Changing the network cable does not require pairing again, Remote Login, an administrator password or changes to FileVault and login settings. A cable does not remove the requirement to unlock FileVault after a restart.

## What the connection status means

RetinaLink prefers a positively identified USB route, then Ethernet with automatic addresses, configured Ethernet and Wi-Fi. It reports the actual selected interface after authentication. **USB** describes an identified USB NCM route. **Ethernet · automatic addressing** means the local interface has link-local addresses and no configured network address. **Ethernet** can also be a normal company LAN connection.

The Ethernet labels do not prove that the cable connects the Macs directly. A switch can carry the same link-local traffic. RetinaLink does not inspect the rack, scan other computers or claim a physical topology it cannot verify. The presence of an instantiated USB interface does not prove that a cable is connected or that a trusted peer is available; inactive USB links are excluded from selection.

When a better USB or Ethernet route appears during a working session, Viewer first authenticates a separate connection using the existing TLS credential. Only a successful authentication and interface check permit the working stream to reconnect on the preferred route. Discovery announcements or failed authentication alone cannot interrupt the current stream. The handover uses normal reconnection and resets frame state; a brief interruption is possible. If the verified cable route briefly disappears from discovery during that switch, Viewer retains its choice for up to 15 seconds while waiting for it to return. After that window, normal fallback selection resumes instead of waiting indefinitely.

If the cable becomes unavailable, Viewer keeps the pairing and tries other discovered routes. Failed routes have a cooldown, and retries rotate fairly so several unreachable preferred routes cannot permanently starve a usable fallback. If no route is available, the fullscreen standby screen remains while Viewer retries.

## Managed or unusual network settings

Automatic connection depends on macOS exposing a usable USB or Ethernet interface and local traffic being permitted. Existing manual settings, disabled IPv6, blocked multicast discovery, VPN rules or company device policies can prevent discovery or communication. RetinaLink leaves those policies unchanged. It does not silently enable protocols, add network aliases or bypass Local Network permission.

## Implementation and validation boundaries

- Bonjour results retain their concrete `NWInterface`. Connections use a typed service endpoint scoped to that interface plus `NWParameters.requiredInterface`; flattening discovery into an unscoped hostname would lose this guarantee.
- Advertised names, UUIDs and address classifications are hints. Only the saved TLS credential authenticates a paired peer. Interface indexes and IPv6 scopes are rediscovered rather than stored as permanent identities.
- USB observations use bounded, read-only IOKit queries. Private/restricted Apple interfaces and inactive USB links are excluded. Neither USB detection nor the `--usb-link-status` diagnostic opens the pairing Keychain or authenticates a peer.
- Host allows at most four provisional connections. A TLS probe sends no Viewer greeting or screen data and cannot claim or stop the active stream. Invalid provisional greetings and timeouts close their own connection.
- Automatic handover probes have a global interval and per-route cooldown. Retry and attempt histories are bounded. Tests cover fallback starvation, equal-time retries, scoped IPv6 endpoints, strict legacy address validation and retaining TLS when constraining a connection to Ethernet.
- SSH is used for independent deployment and diagnostics during testing; it is not RetinaLink's display transport. The UI capture helper remains off. Read-only checks compare network configuration, pairing and FileVault before and after testing.

Testing scoped, authenticated link-local traffic between the two Macs on the existing Ethernet network does **not** prove that traffic bypasses the company switch. The physical UGREEN CM888 Ethernet connection, operation on that Ethernet cable without DHCP, and its actual unplug/replug recovery remain pending until that hardware is connected. The separate USB link described above does not validate those Ethernet results. Native 5K dimensions and software counters also do not establish stable physical 60 fps; SuperSpeed USB is now verified, while stable physical 5K60 over USB remains unvalidated.

Signed build 59 passed existing-LAN scoped Ethernet selection, trusted/wrong-key probes without stream interruption, simulated Wi-Fi fallback, automatic Ethernet return and immediate healthy-backup reuse. Recovery took 6–9 seconds; automatic preferred-route return took about 56 seconds including retry cooldowns. Final read-only checks preserved company configuration, routes, DNS, pairing and FileVault. See [VALIDATION.md](VALIDATION.md) for exact evidence and account/testing limits.
