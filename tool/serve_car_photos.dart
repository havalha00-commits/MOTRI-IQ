// Temporary: serves ./car_photos over localhost so the browser-side uploader can
// read the dealership image files from disk. Deleted after use.
import 'dart:io';

Future<void> main(List<String> args) async {
  final dir = Directory(args.isEmpty ? 'car_photos' : args.first);
  if (!dir.existsSync()) {
    stderr.writeln('NO_DIR ${dir.path}');
    exitCode = 1;
    return;
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8899);
  stdout.writeln('SERVING ${dir.absolute.path} on http://127.0.0.1:8899/');
  await for (final req in server) {
    final name = Uri.decodeComponent(req.uri.path.replaceAll('/', ''));
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    if (name.isEmpty || !file.existsSync()) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      continue;
    }
    req.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Content-Type', 'image/jpeg');
    await req.response.addStream(file.openRead());
    await req.response.close();
  }
}