import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/plating_provider.dart';
import 'screens/simulator_screen.dart';

void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    final exception = details.exceptionAsString();
    debugPrint('FlutterError: $exception');
  };
  runApp(const PlatingSimulatorApp());
}

class PlatingSimulatorApp extends StatelessWidget {
  const PlatingSimulatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PlatingProvider(),
      child: MaterialApp(
        title: '전기도금 시뮬레이터',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0A0F1E),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00E5FF),
            secondary: Color(0xFF00BFA5),
            surface: Color(0xFF0D1526),
          ),
          fontFamily: 'sans-serif',
          cardTheme: CardThemeData(
            color: const Color(0xFF0D1526),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 4,
          ),
          sliderTheme: const SliderThemeData(
            activeTrackColor: Color(0xFF00E5FF),
            thumbColor: Color(0xFF00E5FF),
            inactiveTrackColor: Colors.white12,
          ),
          textTheme: const TextTheme(
            bodyMedium: TextStyle(color: Colors.white70),
            bodySmall: TextStyle(color: Colors.white54),
          ),
        ),
        home: const PlatingSimulatorScreen(),
      ),
    );
  }
}
