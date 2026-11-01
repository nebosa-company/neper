import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final tk = GlobalKey(debugLabel: 't');
const ratios = [1.0, 1.5, 2.0];
String ratioName(double r) => r == 1.0 ? '1x' : (r == 1.5 ? '1.5x' : '2x');
const std = ['rest', 'hover', 'focus', 'pressed', 'disabled'];
const sel = ['rest', 'hover', 'focus', 'pressed', 'disabled', 'selected'];

typedef Act = Future<void> Function(WidgetTester t, String st);

class Spec {
  final String name, neper, widget;
  final List<String> states;
  final Widget Function(String st) build;
  final Size size;
  final bool raw; // build returns the whole page (no Center wrapper)
  final Act? act; // for non-standard states (open, expanded ...)
  final Offset off;
  Spec(this.name, this.neper, this.widget, this.states, this.build,
      {this.size = const Size(280, 96), this.raw = false, this.act, this.off = Offset.zero});
}

String get outDir => Platform.environment['OUT'] ?? 'out';

Future<void> loadFonts() async {
  const mf = 'D:/flutter/bin/cache/artifacts/material_fonts';
  Future<ByteData> bd(String p) async => ByteData.sublistView(await File(p).readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final w in ['thin', 'light', 'regular', 'medium', 'bold', 'black', 'italic', 'bolditalic']) {
    roboto.addFont(bd('$mf/roboto-$w.ttf'));
  }
  await roboto.load();
  // Cupertino stand-in: the SF families resolve to Roboto.
  for (final n in ['.SF Pro Text', '.SF Pro Display', '.SF UI Text', '.SF UI Display', '.AppleSystemUIFont', 'CupertinoSystemText', 'CupertinoSystemDisplay']) {
    final l = FontLoader(n);
    for (final w in ['light', 'regular', 'medium', 'bold']) {
      l.addFont(bd('$mf/roboto-$w.ttf'));
    }
    await l.load();
  }
  final mi = FontLoader('MaterialIcons')..addFont(bd('$mf/materialicons-regular.otf'));
  await mi.load();
  final ci = FontLoader('packages/cupertino_icons/CupertinoIcons')
    ..addFont(bd(Platform.environment['CUPERTINO_ICONS_TTF'] ?? 'C:/Users/gaddl/AppData/Local/Pub/Cache/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf'));
  await ci.load();
}

ThemeData mtheme(String fam, bool dark) => ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: ColorScheme.fromSeed(
          seedColor: Color(fam == 'neper' ? 0xFF1B3A6B : 0xFF6750A4),
          brightness: dark ? Brightness.dark : Brightness.light),
    );

Widget wrap(String fam, bool dark, Spec s, String st, GlobalKey rb) {
  final w = s.build(st);
  Widget app;
  if (fam == 'cupertino') {
    app = CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: CupertinoThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: s.raw ? w : CupertinoPageScaffold(child: Center(child: w)),
    );
  } else {
    app = MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: mtheme(fam, dark),
      home: s.raw ? w : Scaffold(body: Center(child: w)),
    );
  }
  return RepaintBoundary(key: rb, child: SizedBox(width: s.size.width, height: s.size.height, child: app));
}

void runFamily(String fam, List<Spec> specs) {
  setUpAll(loadFonts);
  final file = File('$outDir/manifest.csv');
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    group('$fam $mode', () {
      for (final s in specs) {
        testWidgets(s.name, (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = s.size;
          addTearDown(t.view.reset);
          t.binding.focusManager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
          for (final st in s.states) {
            final rb = GlobalKey();
            await t.pumpWidget(wrap(fam, dark, s, st, rb));
            await t.pump(const Duration(milliseconds: 100));
            TestGesture? g;
            final hasT = find.byKey(tk).evaluate().isNotEmpty;
            final target = (hasT ? t.getCenter(find.byKey(tk)) : s.size.center(Offset.zero)) + s.off;
            if (st == 'hover') {
              g = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
              await g.addPointer(location: const Offset(1, 1));
              await g.moveTo(target);
              await t.pump(); await t.pump(const Duration(milliseconds: 500));
            } else if (st == 'pressed') {
              g = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
              await g.addPointer(location: const Offset(1, 1));
              await g.moveTo(target);
              await g.down(target);
              await t.pump(); await t.pump(const Duration(milliseconds: 500));
            } else if (st == 'focus') {
              await t.sendKeyEvent(LogicalKeyboardKey.tab);
              await t.pump(); await t.pump(const Duration(milliseconds: 500));
            } else if (s.act != null && !std.contains(st) && st != 'selected') {
              await s.act!(t, st);
            } else {
              await t.pump(); await t.pump(const Duration(milliseconds: 500));
            }
            await t.runAsync(() async {
              final b = rb.currentContext!.findRenderObject() as RenderRepaintBoundary;
              final d = Directory('$outDir/$fam/$mode')..createSync(recursive: true);
              for (final r in ratios) {
                final im = await b.toImage(pixelRatio: r);
                final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
                await File('${d.path}/${s.name}-$st@${ratioName(r)}.png').writeAsBytes(bytes!.buffer.asUint8List());
                im.dispose();
                file.writeAsStringSync(
                    'flutter/$fam/$mode/${s.name}-$st@${ratioName(r)}.png,$fam,$mode,${s.name},$st,${ratioName(r)},${s.neper},${s.widget}\n',
                    mode: FileMode.append);
              }
            });
            if (g != null) {
              if (st == 'pressed') await g.up();
              await g.removePointer();
            }
          }
        });
      }
    });
  }
}
