/// Validates a backend-generated wallet receipt object key/path.
/// Rejects external URLs and path traversal so an admin never opens user-supplied destinations.
/// Also tolerates legacy Supabase public receipt URLs during migration.
String? walletReceiptPath(String value, [String? supabaseUrl]) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null) return null;
  String path;
  if (uri.hasScheme || uri.hasAuthority) {
    if (supabaseUrl == null || supabaseUrl.isEmpty) return null;
    final backend = Uri.tryParse(supabaseUrl);
    if (backend == null || uri.scheme != 'https' || uri.host != backend.host) return null;
    const prefix = '/storage/v1/object/public/wallet_receipts/';
    if (!uri.path.startsWith(prefix)) return null;
    path = Uri.decodeComponent(uri.path.substring(prefix.length));
  } else {
    path = value.trim();
  }
  final parts = path.split('/');
  if (parts.length < 3 || parts[1] != 'receipts' ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
      path.contains('\\')) {
    return null;
  }
  return path;
}
