import 'package:flutter/material.dart';

import 'screens/connect_screen.dart';
import 'screens/home_shell.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(HarnessApp(state: AppState()..load()));
}

class HarnessApp extends StatelessWidget {
  final AppState state;
  const HarnessApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Donna',
        debugShowCheckedModeBanner: false,
        theme: DonnaTheme.light(),
        darkTheme: DonnaTheme.dark(),
        home: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            if (!state.loaded) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return state.connected ? const HomeShell() : const ConnectScreen();
          },
        ),
      ),
    );
  }
}

/// Minimal inherited access to [AppState] — one dependency fewer than a
/// state-management package, and all this app needs.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
