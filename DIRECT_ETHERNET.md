# Automatic Ethernet connections

RetinaLink 0.7.0 discovers the paired Mac on each available network interface and can use an Ethernet cable without entering IP addresses. It uses macOS's existing automatic addressing. RetinaLink does not assign static addresses or change DHCP, IPv6, DNS, gateways, routes, network service order, Internet Sharing or company network policies.

## Connecting a display

1. Install the compatible signed Host and Viewer apps. An existing pairing remains valid.
2. Connect the USB Ethernet hub to the Studio, then connect an ordinary Ethernet cable between that hub and the iMac's Ethernet port. Keep the Studio's existing company network connection plugged in.
3. Keep Viewer open on the iMac and Host open on the Studio. Allow macOS's normal Local Network permission if requested. RetinaLink discovers the connection and authenticates it using the saved pairing.

With the usual automatic macOS network settings, no router, DHCP server or manual address entry is needed for that cable. IPv6 link-local addressing works without a DHCP server; macOS can also assign an IPv4 link-local address when DHCP is unavailable. RetinaLink observes these addresses rather than configuring them.

The iMac's Ethernet port is occupied by the display cable in this arrangement. If that port previously provided its company connection, maintaining separate company access requires another existing connection, such as Wi-Fi, or another Ethernet adapter. RetinaLink does not change those connections.

New users still approve Host once on both screens. Changing the network cable does not require pairing again, Remote Login, an administrator password or changes to FileVault and login settings. A cable does not remove the requirement to unlock FileVault after a restart.

## What the connection status means

RetinaLink prefers Ethernet with automatic addresses over configured Ethernet, then Wi-Fi. It reports the actual selected interface after authentication. **Ethernet · automatic addressing** means the local interface has link-local addresses and no configured network address. **Ethernet** can also be a normal company LAN connection.

Neither label proves that the cable connects the Macs directly. A switch can carry the same link-local traffic. RetinaLink does not inspect the rack, scan other computers or claim a physical topology it cannot verify.

When a better Ethernet route appears during a working session, Viewer first authenticates a separate connection using the existing TLS credential. Only a successful authentication and interface check permit the working stream to reconnect on the preferred route. Discovery announcements or failed authentication alone cannot interrupt the current stream. The handover uses normal reconnection and resets frame state; a brief interruption is possible. If the verified Ethernet route briefly disappears from discovery during that switch, Viewer retains its choice for up to 15 seconds while waiting for it to return. After that window, normal fallback selection resumes instead of waiting indefinitely.

If the cable becomes unavailable, Viewer keeps the pairing and tries other discovered routes. Failed routes have a cooldown, and retries rotate fairly so several unreachable preferred routes cannot permanently starve a usable fallback. If no route is available, the fullscreen standby screen remains while Viewer retries.

## Managed or unusual network settings

Automatic connection depends on the adapter being supported by macOS and local traffic being permitted. Existing manual settings, disabled IPv6, blocked multicast discovery, VPN rules or company device policies can prevent discovery or communication. RetinaLink leaves those policies unchanged. It does not silently enable protocols, add network aliases or bypass Local Network permission.

## Implementation and validation boundaries

- Bonjour results retain their concrete `NWInterface`. Connections use a typed service endpoint scoped to that interface plus `NWParameters.requiredInterface`; flattening discovery into an unscoped hostname would lose this guarantee.
- Advertised names, UUIDs and address classifications are hints. Only the saved TLS credential authenticates a paired peer. Interface indexes and IPv6 scopes are rediscovered rather than stored as permanent identities.
- Host allows at most four provisional connections. A TLS probe sends no Viewer greeting or screen data and cannot claim or stop the active stream. Invalid provisional greetings and timeouts close their own connection.
- Automatic handover probes have a global interval and per-route cooldown. Retry and attempt histories are bounded. Tests cover fallback starvation, equal-time retries, scoped IPv6 endpoints, strict legacy address validation and retaining TLS when constraining a connection to Ethernet.
- SSH is used for independent deployment and diagnostics during testing; it is not RetinaLink's display transport. The UI capture helper remains off. Read-only checks compare network configuration, pairing and FileVault before and after testing.

Testing scoped, authenticated link-local traffic between the two Macs on the existing Ethernet network does **not** prove that traffic bypasses the company switch. The physical UGREEN CM888 connection, a cable with no DHCP server, and actual cable unplug/replug recovery remain pending until that hardware is connected. Native 5K dimensions and software counters also do not establish stable physical 60 fps.
