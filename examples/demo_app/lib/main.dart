import 'package:flutter/material.dart';
import 'package:rhttp/rhttp.dart';
import 'package:sqlite3/sqlite3.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Rhttp.init();

  final db = sqlite3.openInMemory();
  final sqliteVersion =
      db.select('SELECT sqlite_version() AS v').first['v'] as String;
  db.dispose();

  runApp(MyApp(sqliteVersion: sqliteVersion));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.sqliteVersion = '—'});

  final String sqliteVersion;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flatpak Demo',
      home: Scaffold(
        appBar: AppBar(title: const Text('Flatpak Demo')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('SQLite: $sqliteVersion'),
              const SizedBox(height: 8),
              const Text('rhttp: ready'),
            ],
          ),
        ),
      ),
    );
  }
}
