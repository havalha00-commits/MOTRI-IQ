import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final int width = 320;
  final int height = 120;

  final png = img.Image(width: width, height: height);

  // Semi-transparent black background (60% opacity)
  img.fill(png, color: img.ColorUint8.rgba(0, 0, 0, 160));

  // White rounded border
  img.drawRect(
    png,
    x1: 4,
    y1: 4,
    x2: width - 5,
    y2: height - 5,
    color: img.ColorUint8.rgba(255, 255, 255, 255),
    thickness: 2,
    radius: 12,
  );

  // Draw "MOTRI IQ" text in white
  img.drawString(
    png,
    'MOTRI IQ',
    x: (width - 160) ~/ 2,
    y: (height - 48) ~/ 2,
    font: img.arial48,
    color: img.ColorUint8.rgba(255, 255, 255, 255),
  );

  final bytes = img.encodePng(png);
  final file = File(
    r'C:\Users\hp\Desktop\MOTRI-IQ-clean-project\assets\logo\motri_iq_logo.png',
  );
  file.writeAsBytesSync(bytes);
  stdout.writeln('Logo created: ${file.path} (${bytes.length} bytes)');
}
