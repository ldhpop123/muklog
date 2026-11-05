import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/map/widgets/muk_map.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initMukMap();
  runApp(const ProviderScope(child: MuklogApp()));
}
