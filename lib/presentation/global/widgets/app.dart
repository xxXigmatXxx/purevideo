import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/accounts/bloc/accounts_bloc.dart';
import 'package:purevideo/presentation/accounts/bloc/accounts_event.dart';
import 'package:purevideo/presentation/global/routes/router.dart';
import 'package:purevideo/presentation/settings/widgets/settings_listenable.dart';

class PureVideoApp extends StatelessWidget {
  final SettingsService _settingsService = getIt();

  PureVideoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsListenable(builder: (context, box, child) {
      const netflixRed = Color(0xFFE50914);
      final isNetflix = _settingsService.isNetflixStyle;
      final seedColor = isNetflix ? netflixRed : Colors.deepPurple;

      final darkColorScheme = isNetflix
          ? ColorScheme.fromSeed(
              seedColor: netflixRed,
              brightness: Brightness.dark,
              primary: netflixRed,
              onPrimary: Colors.white,
              surface: const Color(0xFF0A0A0A),
              surfaceContainerHighest: const Color(0xFF1F1F1F),
            )
          : ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark,
            );

      return MaterialApp.router(
        title: 'PureVideo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: seedColor,
            primary: isNetflix ? netflixRed : null,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: darkColorScheme,
          scaffoldBackgroundColor: isNetflix ? Colors.black : null,
          canvasColor: isNetflix ? const Color(0xFF121212) : null,
          appBarTheme: isNetflix
              ? const AppBarTheme(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                )
              : null,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        debugShowCheckedModeBanner: false,
        themeMode: _settingsService.theme,
        routerConfig: router,
        builder: (context, child) {
          return MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) =>
                    AccountsBloc()..add(const LoadAccountsRequested()),
              ),
            ],
            child: child!,
          );
        },
      );
    });
  }
}
