import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({required bool localized}) {
  return MaterialApp(
    localizationsDelegates: localized
        ? const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ]
        : null,
    supportedLocales: const [Locale('es', 'ES'), Locale('es'), Locale('en')],
    locale: localized ? const Locale('es', 'ES') : null,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showDatePicker(
              context: context,
              initialDate: DateTime(2026, 10, 12),
              firstDate: DateTime(2020),
              lastDate: DateTime(2035, 12, 31),
              locale: const Locale('es', 'ES'),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('showDatePicker abre en español con las localizaciones',
      (tester) async {
    await tester.pumpWidget(_app(localized: true));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
}
