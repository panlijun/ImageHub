import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'features/gallery/presentation/gallery_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) =>
          const NoTransitionPage(child: GalleryScreen()),
    ),
  ],
);

class ImageHostApp extends StatelessWidget {
  const ImageHostApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'ImageHost',
    debugShowCheckedModeBanner: false,
    routerConfig: _router,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff315de6)),
      scaffoldBackgroundColor: const Color(0xfff8f9fb),
      fontFamily: 'Microsoft YaHei',
      cardTheme: const CardThemeData(elevation: 0),
    ),
  );
}

void launchImageHost() => runApp(const ProviderScope(child: ImageHostApp()));
