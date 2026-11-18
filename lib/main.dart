import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';

import 'package:lumina/config/dependencies.dart';
import 'package:lumina/data/services/ble/reactive_ble_service.dart';
import 'package:lumina/data/services/home_store.dart';
import 'package:lumina/ui/core/theme.dart';
import 'package:lumina/ui/features/home/views/home_screen.dart';
import 'package:lumina/widget_entry.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts are bundled in google_fonts/; never fetch at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    for (final f in ['Figtree', 'BricolageGrotesque']) {
      yield LicenseEntryWithLineBreaks([f], await rootBundle.loadString('google_fonts/OFL-$f.txt'));
    }
  });
  unawaited(HomeWidget.registerInteractivityCallback(widgetTapped));
  final deps = Dependencies(ble: ReactiveBleService(), store: SecureHomeStore());
  runApp(MultiProvider(providers: deps.providers, child: const LuminaApp()));
}

class LuminaApp extends StatelessWidget {
  const LuminaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumina',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: HomeScreen(viewModel: context.read()),
    );
  }
}
