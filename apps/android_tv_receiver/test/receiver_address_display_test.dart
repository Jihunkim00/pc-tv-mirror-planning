import 'package:android_tv_receiver/features/receiver/receiver_address_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps valid LAN, link-local, and public IPv4 addresses', () {
    expect(
      usableReceiverIpv4Addresses([
        '192.168.1.40',
        '10.2.3.4',
        '169.254.8.9',
        '203.0.113.24',
      ]),
      ['10.2.3.4', '169.254.8.9', '192.168.1.40', '203.0.113.24'],
    );
  });

  test('filters unspecified, loopback, multicast, and malformed addresses', () {
    expect(
      usableReceiverIpv4Addresses([
        '0.0.0.0',
        '0.15.0.1',
        '127.0.0.1',
        '127.10.1.2',
        '224.0.0.1',
        '255.255.255.255',
        '256.1.1.1',
        '192.168.1',
        'host.local',
        '',
      ]),
      isEmpty,
    );
  });

  test('canonicalizes octets and removes duplicate addresses', () {
    expect(usableReceiverIpv4Addresses(['192.168.001.040', '192.168.1.40']), [
      '192.168.1.40',
    ]);
  });
}
