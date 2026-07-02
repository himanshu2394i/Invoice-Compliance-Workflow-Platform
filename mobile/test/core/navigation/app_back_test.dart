import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invoice_capture/core/navigation/app_back.dart';

GoRouter _router({String initialLocation = '/child'}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const Text('Home')),
        GoRoute(
          path: '/child',
          builder: (_, __) => AppBackScope(
            fallbackLocation: '/home',
            child: Scaffold(
              appBar: AppBar(title: const Text('Child')),
              body: const Text('Child body'),
            ),
          ),
        ),
      ],
    );

void main() {
  testWidgets('AppBackScope sends hardware back to fallback route',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('goBack sends a direct route to its fallback', (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    AppBackScope.goBack(
      tester.element(find.text('Child body')),
      fallbackLocation: '/home',
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });
}
