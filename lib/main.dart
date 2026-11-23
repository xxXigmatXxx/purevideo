import 'dart:io';
import 'dart:ui';

import 'package:fast_cached_network_image/fast_cached_network_image.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:purevideo/core/services/media_service.dart';
import 'package:purevideo/core/services/extra_sources_service.dart';
import 'package:purevideo/core/services/app_update_service.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/core/utils/device_utils.dart';
import 'package:purevideo/di/adapters_container.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/global/widgets/app.dart';
import 'package:serious_python/serious_python.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseAnalytics.instance;
    FlutterError.onError = (errorDetails) {
      try {
        FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
      } catch (_) {}
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      try {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      } catch (_) {}
      return true;
    };
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
  }

  try {
    await FastCachedImageConfig.init(
      clearCacheAfter: const Duration(days: 7),
    );
  } catch (e) {
    debugPrint('FastCachedImageConfig init error: $e');
  }

  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('MediaKit init skipped: $e');
  }
  Hive.init((await getApplicationDocumentsDirectory()).path);

  setupHiveAdapters();
  setupInjection();
  await getIt<SettingsService>().init();
  if (getIt<SettingsService>().extraSourcesEnabled) {
    getIt<ExtraSourcesService>().syncRemoteSources();
  }
  getIt<AppUpdateService>().checkForUpdates();
  await getIt<WatchedService>().init();
  try {
    await getIt<MediaService>().init();
  } catch (e) {
    debugPrint('MediaService init skipped: $e');
  }

  await DeviceUtils.init();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  try {
    if (DeviceUtils.isTv) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  } catch (e) {
    debugPrint('SystemChrome init skipped: $e');
  }

  try {
    final sd = await getApplicationSupportDirectory();
    final fd = Directory('${sd.path}/flet/app');
    if (await fd.exists() &&
        !await File('${fd.path}/.purevideo_v43').exists()) {
      debugPrint('Upgrading app.zip to v41');
      await fd.delete(recursive: true);
    }
  } catch (_) {}

  SeriousPython.run('app/app.zip').then((log) {
    debugPrint('Python log: $log');
  }).catchError((error) {
    debugPrint('Error executing Python code: $error');
  });

  runApp(PureVideoApp());
}
