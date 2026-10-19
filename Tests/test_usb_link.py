import argparse
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('retinalink_usb_link_test', ROOT / 'Tools/test_usb_link.py')
usb = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(usb)


def diagnostic(*interfaces):
    return {'schema': 1, 'version': '0.7.0', 'build': '60', 'interfaces': list(interfaces),
            'networkSettingsChanged': False, 'pairingAccessed': False,
            'peerAuthenticated': False, 'readOnly': True}


def interface(name='en9', source='deviceNCM', active=True):
    return {'interface': name, 'usbEvidence': source, 'interfaceUp': True,
            'hasLinkLocalAddress': True, 'automaticAddressing': True, 'linkActive': active}


def machine(*, role='Viewer', usb_records=()):
    binding = {'available': True, 'uid': 502, 'sha256': 'a' * 64}
    return {'services': {'company': {'deviceName': 'en0', 'configurationSHA256': 'company-settings'}},
            'sets': {'office': {'serviceOrder': ['company'], 'otherGlobalSHA256': 'global-settings'}},
            'currentSet': '/Sets/office', 'defaultRouteIPv4': {'gateway': 'hashed-gateway', 'interface': 'en0'},
            'defaultRouteIPv6': {}, 'primaryService': 'company', 'primaryServiceDNSSHA256': 'dns-hash',
            'globalDNSSHA256': 'global-dns-hash', 'fileVaultStatus': 'FileVault is Off.',
            'uiCaptureHelperOff': True, 'appDisplaySSHAbsent': True,
            'requestedBinding': copy.deepcopy(binding), 'activeBinding': copy.deepcopy(binding),
            'usbStatus': diagnostic(*usb_records),
            'appState': {'available': True, 'time': 1000, 'streaming': role == 'Host', 'phase': 'streaming',
                         'fullscreen': True, 'transport': 'direct-tls', 'requiresRemoteLogin': False,
                         'connectionPath': {'interface': 'en9', 'transportKind': 'usb', 'usbEvidence': 'deviceNCM',
                                            'authenticated': True, 'requiredInterfaceVerified': True,
                                            'networkSettingsChanged': False}}}


class USBStatusTests(unittest.TestCase):
    def test_empty_hardware_is_valid_diagnostic_but_not_a_usb_link(self):
        value = machine()
        self.assertEqual(usb.parse_usb_status(value['usbStatus'])['interfaces'], [])
        self.assertFalse(usb.usb_stream_check(value, role='Viewer', now=1001))

    def test_ordinary_usb_nic_claim_is_rejected(self):
        for source in ('AX88179B', 'USB Ethernet', 'ethernet', None, []):
            with self.subTest(source=source), self.assertRaises(ValueError):
                usb.parse_usb_status(diagnostic(interface(source=source)))

    def test_readonly_diagnostic_is_strict_and_drops_unrelated_fields(self):
        value = diagnostic(interface())
        value['serial'] = 'not-exported'
        value['interfaces'][0]['address'] = 'not-exported'
        cleaned = usb.parse_usb_status(value)
        self.assertNotIn('not-exported', json.dumps(cleaned))
        for key in ('readOnly', 'networkSettingsChanged', 'pairingAccessed', 'peerAuthenticated'):
            invalid = copy.deepcopy(value)
            invalid[key] = not invalid[key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                usb.parse_usb_status(invalid)

    def test_unknown_or_repeated_interface_rejected(self):
        for records in ((interface('utun9'),), (interface(), interface()), (interface('en9%10.1.1.1'),)):
            with self.subTest(records=records), self.assertRaises(ValueError):
                usb.parse_usb_status(diagnostic(*records))

    def test_unsigned_missing_old_cli_does_not_launch_app(self):
        with tempfile.TemporaryDirectory() as root:
            binary = Path(root) / 'old-viewer'
            binary.write_bytes(b'--old-option\0')
            with mock.patch.object(usb.subprocess, 'run') as run, self.assertRaises(ValueError):
                usb.require_usb_cli(binary)
            run.assert_not_called()
            binary.write_bytes(b'new executable\0--usb-link-status\0')
            usb.require_usb_cli(binary)


class CompanyNetworkPolicyTests(unittest.TestCase):
    def test_no_change_passes(self):
        before = machine()
        self.assertEqual(usb.result_status(usb.compare_machine(before, copy.deepcopy(before))), 'passed')

    def test_identified_usb_service_and_order_addition_allowed(self):
        before = machine()
        after = copy.deepcopy(before)
        after['usbStatus'] = diagnostic(interface())
        after['services']['usb'] = {'deviceName': 'en9', 'configurationSHA256': 'new-os-created-usb-service'}
        after['sets']['office']['serviceOrder'] = ['usb', 'company']
        self.assertEqual(usb.result_status(usb.compare_machine(before, after)), 'passed')

    def test_new_company_or_usb_ethernet_nic_service_is_not_allowed(self):
        before = machine()
        after = copy.deepcopy(before)
        after['services']['adapter'] = {'deviceName': 'en8', 'configurationSHA256': 'new-adapter-service'}
        after['sets']['office']['serviceOrder'].append('adapter')
        checks = usb.compare_machine(before, after)
        self.assertFalse(checks['addedServicesAreIdentifiedUSB'])
        self.assertEqual(usb.result_status(checks), 'failed')

    def test_existing_company_settings_cannot_hide_behind_usb_addition(self):
        before = machine()
        after = copy.deepcopy(before)
        after['usbStatus'] = diagnostic(interface())
        after['services']['usb'] = {'deviceName': 'en9', 'configurationSHA256': 'usb-settings'}
        after['sets']['office']['serviceOrder'].append('usb')
        after['services']['company']['configurationSHA256'] = 'changed-company-dhcp-or-dns'
        self.assertFalse(usb.compare_machine(before, after)['existingServicesUnchanged'])

    def test_company_order_global_config_route_dns_and_filevault_are_frozen(self):
        before = machine()
        mutations = (
            lambda x: x['sets']['office'].update(otherGlobalSHA256='changed'),
            lambda x: x['sets']['office'].update(serviceOrder=[]),
            lambda x: x.update(defaultRouteIPv4={'interface': 'en9'}),
            lambda x: x.update(globalDNSSHA256='changed'),
            lambda x: x.update(fileVaultStatus='FileVault is On.'),
            lambda x: x.update(uiCaptureHelperOff=False),
        )
        for mutate in mutations:
            after = copy.deepcopy(before)
            mutate(after)
            self.assertEqual(usb.result_status(usb.compare_machine(before, after)), 'failed')

    def test_protected_active_binding_is_not_forged_as_unchanged(self):
        before, after = machine(), machine()
        for value in (before, after):
            value['activeBinding'] = {'available': False, 'uid': 502, 'reason': 'protectedAccount'}
        checks = usb.compare_machine(before, after)
        self.assertIsNone(checks['activeAccountPairingUnchanged'])
        self.assertTrue(checks['requestedAccountPairingUnchanged'])
        self.assertEqual(usb.result_status(checks), 'notVerified')

    def test_account_switch_or_pairing_hash_change_fails(self):
        before, after = machine(), machine()
        after['activeBinding']['uid'] = 501
        self.assertFalse(usb.compare_machine(before, after)['activeAccountPairingUnchanged'])
        after = machine()
        after['requestedBinding']['sha256'] = 'b' * 64
        self.assertFalse(usb.compare_machine(before, after)['requestedAccountPairingUnchanged'])

    def test_missing_pairing_digest_cannot_pass(self):
        before, after = machine(), machine()
        before['activeBinding'].pop('sha256')
        after['activeBinding'].pop('sha256')
        self.assertIsNone(usb.compare_machine(before, after)['activeAccountPairingUnchanged'])


class ActualUSBStreamTests(unittest.TestCase):
    def test_active_hardware_alone_is_not_authenticated_stream(self):
        value = machine(usb_records=(interface(),))
        value['appState']['connectionPath']['authenticated'] = False
        self.assertFalse(usb.usb_stream_check(value, role='Viewer', now=1001))

    def test_active_fresh_scoped_authenticated_usb_stream_passes(self):
        value = machine(usb_records=(interface(),))
        self.assertTrue(usb.usb_stream_check(value, role='Viewer', now=1001))
        self.assertTrue(usb.usb_stream_check(machine(role='Host', usb_records=(interface(),)), role='Host', now=1001))

    def test_inactive_unknown_or_stale_link_cannot_pass(self):
        value = machine(usb_records=(interface(active=False),))
        self.assertFalse(usb.usb_stream_check(value, role='Viewer', now=1001))
        value['usbStatus']['interfaces'][0].pop('linkActive')
        self.assertFalse(usb.usb_stream_check(value, role='Viewer', now=1001))
        value['usbStatus'] = diagnostic(interface())
        self.assertFalse(usb.usb_stream_check(value, role='Viewer', now=1016))

    def test_protected_viewer_ui_is_not_verified(self):
        value = machine(usb_records=(interface(),))
        value['appState'] = {'available': False, 'reason': 'protectedAccount'}
        self.assertIsNone(usb.usb_stream_check(value, role='Viewer', now=1001))

    def test_company_route_or_unverified_scope_is_not_usb(self):
        value = machine(usb_records=(interface(),))
        for key, changed in (('transportKind', 'ethernet'), ('interface', 'en0'), ('requiredInterfaceVerified', False)):
            candidate = copy.deepcopy(value)
            candidate['appState']['connectionPath'][key] = changed
            self.assertFalse(usb.usb_stream_check(candidate, role='Viewer', now=1001))


class ParserTests(unittest.TestCase):
    def test_explicit_snapshot_and_comparison_modes(self):
        common = ['--socket', '/tmp/socket', '--address', 'imac.local', '--user', 'viewer',
                  '--host-binary', '/tmp/host', '--viewer-binary', '/tmp/viewer', '--output', '/tmp/report']
        args = usb.parser().parse_args(['--snapshot', '--hardware-connected'] + common)
        self.assertTrue(args.snapshot)
        self.assertTrue(args.hardware_connected)
        self.assertFalse(args.require_usb)
        args = usb.parser().parse_args(['--compare', '/tmp/baseline', '--require-usb', '--viewer-user', 'display'] + common)
        self.assertEqual(args.compare, Path('/tmp/baseline'))
        self.assertEqual(args.viewer_user, 'display')
        self.assertTrue(args.require_usb)


if __name__ == '__main__':
    unittest.main()
