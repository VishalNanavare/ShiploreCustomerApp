import 'dart:io';

/// Debug-only global HTTP override so EVERY network client (including
/// CachedNetworkImage, which has its own HTTP stack) reaches the dev server.
///
/// Always bypasses SSL cert verification in debug so self-signed / locally-issued
/// server certs (shiplorelocal.in etc.) work on simulators and physical devices
/// whose trust store doesn't include the dev CA.
///
/// When DEV_HOST_IP is also set, we additionally redirect the TCP connection for
/// the API host to that IP while keeping the real hostname for TLS so nginx routes
/// the right vhost. Never installed in release builds.
class DevHttpOverrides extends HttpOverrides {
  DevHttpOverrides(this.apiHost, this.devIp);
  final String apiHost;
  final String devIp;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // Accept any certificate in debug — covers self-signed and locally-issued certs.
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    if (devIp.isEmpty) return client;
    // Optional IP redirect: keep hostname for TLS/vhost but connect to devIp.
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      final redirect = uri.host == apiHost;
      final target = redirect ? devIp : uri.host;
      if (uri.scheme == 'https') {
        return SecureSocket.startConnect(
          target,
          uri.port,
          onBadCertificate: (X509Certificate _) => true,
        );
      }
      return Socket.startConnect(target, uri.port);
    };
    return client;
  }
}
