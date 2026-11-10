import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/contact/wallet_receipt.dart';

void main() {
  const backend = 'https://example.supabase.co';
  test('accepts object paths and legacy receipt URLs', () {
    expect(walletReceiptPath('owner/receipts/photo.jpg', backend),
        'owner/receipts/photo.jpg');
    expect(walletReceiptPath('$backend/storage/v1/object/public/wallet_receipts/owner/receipts/photo.jpg', backend),
        'owner/receipts/photo.jpg');
  });
  test('rejects external links, other buckets and traversal', () {
    for (final input in [
      'https://evil.example/owner/receipts/photo.jpg',
      '$backend/storage/v1/object/public/cars/owner/receipts/photo.jpg',
      '../receipts/photo.jpg', 'owner/receipts/../photo.jpg',
      '//evil.example/owner/receipts/photo.jpg', '',
    ]) {
      expect(walletReceiptPath(input, backend), isNull, reason: input);
    }
  });
}
