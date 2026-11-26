import 'package:dio/dio.dart';
import 'package:flutter_cast_framework/cast.dart';
import 'package:get_it/get_it.dart';
import 'package:purevideo/core/services/media_service.dart';
import 'package:purevideo/core/services/cast_proxy_service.dart';
import 'package:purevideo/core/services/merg_service.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/core/services/captcha_service.dart';
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/core/services/resolve_url_service.dart';
import 'package:purevideo/core/utils/global_context.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/repositories/ekino/ekino_auth_repository.dart';
import 'package:purevideo/data/repositories/ekino/ekino_movie_repository.dart';
import 'package:purevideo/data/repositories/ekino/ekino_search_repository.dart';
import 'package:purevideo/data/repositories/filman/filman_search_repository.dart';
import 'package:purevideo/data/repositories/filmweb/filmweb_info_repository.dart';
import 'package:purevideo/data/repositories/obejrzyjto/obejrzyjto_auth_repository.dart';
import 'package:purevideo/data/repositories/obejrzyjto/obejrzyjto_movie_repository.dart';
import 'package:purevideo/data/repositories/obejrzyjto/obejrzyjto_search_repository.dart';
import 'package:purevideo/data/repositories/search_repository.dart';
import 'package:purevideo/data/repositories/video_source_repository.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/filman/filman_auth_repository.dart';
import 'package:purevideo/data/repositories/filman/filman_movie_repository.dart';
import 'package:purevideo/data/repositories/movie_repository.dart';
import 'package:purevideo/data/repositories/docchi/docchi_auth_repository.dart';
import 'package:purevideo/data/repositories/docchi/docchi_movie_repository.dart';
import 'package:purevideo/data/repositories/docchi/docchi_search_repository.dart';
import 'package:purevideo/data/repositories/bajeczki/bajeczki_auth_repository.dart';
import 'package:purevideo/data/repositories/bajeczki/bajeczki_movie_repository.dart';
import 'package:purevideo/core/services/extra_sources_service.dart';
import 'package:purevideo/core/services/app_update_service.dart';
import 'package:purevideo/core/services/tv_preview_service.dart';
import 'package:purevideo/data/repositories/bajeczki/bajeczki_search_repository.dart';
import 'package:purevideo/data/repositories/custom/custom_auth_repository.dart';
import 'package:purevideo/data/repositories/custom/custom_movie_repository.dart';
import 'package:purevideo/data/repositories/custom/custom_search_repository.dart';

final getIt = GetIt.instance;

void setupInjection() {
  // Shared Dio instance for HTTP
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));
  getIt.registerSingleton<Dio>(dio);

  getIt.registerSingleton<FlutterCastFramework>(
    FlutterCastFramework.create(const <String>[]),
  );

  getIt.registerFactory<CaptchaService>(() => CaptchaService());
  getIt.registerFactory<WebViewService>(() => WebViewService());

  getIt.registerSingleton<ResolveUrlService>(ResolveUrlService(dio));
  getIt.registerSingleton<VideoSourceRepository>(VideoSourceRepository());
  getIt.registerSingleton<CastProxyService>(CastProxyService());
  getIt.registerSingleton<MergeService>(MergeService());
  getIt.registerSingleton<MediaService>(MediaService());
  getIt.registerSingleton<SettingsService>(SettingsService());
  getIt.registerSingleton<ExtraSourcesService>(ExtraSourcesService());
  getIt.registerSingleton<AppUpdateService>(AppUpdateService());
  getIt.registerSingleton<WatchedService>(WatchedService());

  getIt.registerSingleton<FilmwebInfoRepository>(FilmwebInfoRepository());
  getIt.registerSingleton<TvPreviewService>(TvPreviewService(getIt<FilmwebInfoRepository>()));

  getIt.registerSingleton<Map<SupportedService, AuthRepository>>({
    SupportedService.filman: FilmanAuthRepository(),
    SupportedService.obejrzyjto: ObejrzyjtoAuthRepository(),
    SupportedService.ekino: EkinoAuthRepository(),
    SupportedService.docchi: DocchiAuthRepository(),
    SupportedService.bajeczki: BajeczkiAuthRepository(),
    SupportedService.custom: CustomAuthRepository(),
  });
  getIt.registerSingleton<Map<SupportedService, MovieRepository>>({
    SupportedService.filman: FilmanMovieRepository(),
    SupportedService.obejrzyjto: ObejrzyjtoMovieRepository(),
    SupportedService.ekino: EkinoMovieRepository(),
    SupportedService.docchi: DocchiMovieRepository(),
    SupportedService.bajeczki: BajeczkiMovieRepository(),
    SupportedService.custom: CustomMovieRepository(),
  });
  getIt.registerSingleton<Map<SupportedService, SearchRepository>>({
    SupportedService.filman: FilmanSearchRepository(),
    SupportedService.obejrzyjto: ObejrzyjtoSearchRepository(),
    SupportedService.ekino: EkinoSearchRepository(),
    SupportedService.docchi: DocchiSearchRepository(),
    SupportedService.bajeczki: BajeczkiSearchRepository(),
    SupportedService.custom: CustomSearchRepository(),
  });
  getIt.registerSingleton<GlobalContext>(GlobalContext());
}
