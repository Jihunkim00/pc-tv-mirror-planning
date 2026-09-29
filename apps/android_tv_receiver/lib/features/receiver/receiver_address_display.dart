List<String> usableReceiverIpv4Addresses(Iterable<String> addresses) {
  final usable = <String>{};
  for (final address in addresses) {
    final octets = address.split('.');
    if (octets.length != 4) {
      continue;
    }

    final values = <int>[];
    var valid = true;
    for (final octet in octets) {
      if (octet.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(octet)) {
        valid = false;
        break;
      }
      final value = int.tryParse(octet);
      if (value == null || value > 255) {
        valid = false;
        break;
      }
      values.add(value);
    }
    if (!valid) {
      continue;
    }

    final firstOctet = values.first;
    if (firstOctet == 0 || firstOctet == 127 || firstOctet >= 224) {
      continue;
    }

    usable.add(values.join('.'));
  }

  final sorted = usable.toList()..sort();
  return sorted;
}
