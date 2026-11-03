import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/video_source_repository.dart';
import 'package:purevideo/presentation/global/widgets/error_view.dart';
import 'package:purevideo/presentation/player/bloc/player_bloc.dart';
import 'package:purevideo/presentation/player/bloc/player_event.dart';
import 'package:purevideo/presentation/player/bloc/player_state.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_cast_framework/widgets.dart';

const Color _kNetflixRed = Color(0xFFE50914);

class PlayerScreen extends StatefulWidget {
  final MovieDetailsModel movie;
  final int? seasonIndex;
  final int? episodeIndex;
  final int? initialSourceIndex;

  const PlayerScreen({
    super.key,
    required this.movie,
    this.seasonIndex,
    this.episodeIndex,
    this.initialSourceIndex,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late PlayerBloc _playerBloc;

  @override
  void initState() {
    super.initState();
    _playerBloc = PlayerBloc()
      ..add(InitializePlayer(
        movie: widget.movie,
        seasonIndex: widget.seasonIndex,
        episodeIndex: widget.episodeIndex,
        initialSourceIndex: widget.initialSourceIndex,
      ));
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void deactivate() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.deactivate();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _playerBloc.add(const DisposePlayer());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _playerBloc,
      child: const PlayerView(),
    );
  }
}

class PlayerView extends StatefulWidget {
  const PlayerView({super.key});

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  double? _draggingProgress;
  double _brightness = 0.5;
  Timer? _seekReleaseTimer;

  @override
  void initState() {
    super.initState();
    _initBrightness();
  }

  Future<void> _initBrightness() async {
    try {
      final b = await ScreenBrightness.instance.application;
      if (mounted) {
        setState(() {
          _brightness = b.clamp(0.0, 1.0);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _seekReleaseTimer?.cancel();
    super.dispose();
  }

  Widget _buildBadge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  void _showSourcesBottomSheet(
      BuildContext context, PlayerState state, PlayerBloc bloc) {
    final sources = state.videoSources ?? const <VideoSource>[];
    if (sources.isEmpty) return;

    bloc.add(const ShowControls());

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.82,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 12, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.dns_rounded,
                          color: _kNetflixRed, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Wybierz źródło wideo (${sources.length})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(14),
                    itemCount: sources.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, idx) {
                      final source = sources[idx];
                      final isSelected = source == state.selectedSource ||
                          source.url == state.selectedSource?.url;
                      final isWeb = source.host.contains('(Web)');
                      final cleanHost =
                          source.host.replaceAll('(Web)', '').trim();
                      final lang = source.lang.trim().isEmpty
                          ? 'PL'
                          : source.lang.trim();
                      final qual = source.quality.trim().isEmpty
                          ? 'HD'
                          : source.quality.trim();

                      return Material(
                        color: isSelected
                            ? const Color(0xFF281214)
                            : const Color(0xFF1F1F1F),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            bloc.add(ChangeVideoSource(source: source));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    isSelected ? _kNetflixRed : Colors.white12,
                                width: isSelected ? 1.6 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: isWeb
                                        ? const Color(0xFF1E3A5F)
                                        : _kNetflixRed.withAlpha(45),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    isWeb
                                        ? Icons.language_rounded
                                        : Icons.bolt_rounded,
                                    color: isWeb
                                        ? const Color(0xFF64B5F6)
                                        : _kNetflixRed,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              'Link #${idx + 1} • $cleanHost',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          if (isSelected) ...[
                                            const SizedBox(width: 8),
                                            _buildBadge(
                                              'Aktywne',
                                              _kNetflixRed,
                                              Colors.white,
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          _buildBadge(
                                            lang,
                                            Colors.white12,
                                            Colors.white,
                                          ),
                                          _buildBadge(
                                            qual,
                                            const Color(0xFF263238),
                                            const Color(0xFF81C784),
                                          ),
                                          _buildBadge(
                                            isWeb
                                                ? 'Odtwarzacz Web'
                                                : 'Odtwarzacz natywny',
                                            isWeb
                                                ? const Color(0xFF1A2736)
                                                : const Color(0xFF1B3320),
                                            isWeb
                                                ? const Color(0xFF90CAF9)
                                                : const Color(0xFF69F0AE),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.play_circle_fill_rounded,
                                  color: isSelected
                                      ? _kNetflixRed
                                      : Colors.white70,
                                  size: 28,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlayerBloc, PlayerState>(
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.errorMessage!)),
          );
        }
      },
      builder: (context, state) {
        if (state.isLoading) {
          return _buildLoadingView(context, state);
        }

        if (state.errorMessage != null) {
          return _buildErrorView(context, state);
        }

        return _buildPlayerView(context, state);
      },
    );
  }

  Widget _buildLoadingView(BuildContext context, PlayerState state) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: _kNetflixRed),
            const SizedBox(height: 16),
            Text(
              state.displayState,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              label: const Text('Anuluj'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, PlayerState state) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ErrorView(
        message: state.errorMessage!,
        onRetry: () {
          context.read<PlayerBloc>().add(const LoadVideoSources());
        },
      ),
    );
  }

  Widget _buildPlayerView(BuildContext context, PlayerState state) {
    final bloc = context.read<PlayerBloc>();
    final selectedUrl = state.selectedSource?.url ?? '';
    final isWeb = (state.selectedSource?.host ?? '').contains('(Web)');
    if (selectedUrl.isNotEmpty && isWeb) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            InAppWebView(
              key: ValueKey(selectedUrl),
              initialUrlRequest: URLRequest(
                url: WebUri(selectedUrl),
                headers: const {'Referer': 'https://filman.cc/'},
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                iframeAllowFullscreen: true,
                supportMultipleWindows: true,
                javaScriptCanOpenWindowsAutomatically: false,
                useShouldOverrideUrlLoading: true,
                userAgent:
                    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
              ),
              onCreateWindow: (controller, action) async => false,
              onLoadResource: (controller, resource) {
                final rUrl = resource.url.toString();
                final lower = rUrl.toLowerCase();
                if ((lower.contains('.m3u8') || lower.contains('.mp4')) &&
                    !lower.contains('vast') &&
                    !lower.contains('preroll') &&
                    rUrl.startsWith('http')) {
                  if (context.mounted) {
                    final curOrigin =
                        Uri.tryParse(selectedUrl)?.origin ?? 'https://filman.cc';
                    context.read<PlayerBloc>().add(
                          ChangeVideoSource(
                            source: VideoSource(
                              url: rUrl,
                              lang: state.selectedSource?.lang ?? 'PL',
                              quality: state.selectedSource?.quality ?? 'HD',
                              host: (state.selectedSource?.host ?? 'Wideo')
                                  .replaceAll('(Web)', '')
                                  .trim(),
                              headers: {
                                'User-Agent':
                                    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
                                'Referer': '/',
                                'Origin': curOrigin,
                              },
                            ),
                          ),
                        );
                  }
                }
              },
              onLoadStop: (controller, loadedUrl) async {
                await controller.evaluateJavascript(source: """
                  (function() {
                    window.open = function() { return null; };
                    function cleanOverlays() {
                      document.querySelectorAll('a[target="_blank"]').forEach(function(el) {
                        el.style.pointerEvents = 'none';
                        el.style.display = 'none';
                      });
                    }
                    cleanOverlays();
                    setInterval(cleanOverlays, 1000);
                  })();
                """);
              },
              shouldOverrideUrlLoading: (controller, nav) async {
                final u = nav.request.url?.toString() ?? '';
                if (!u.startsWith('http')) return NavigationActionPolicy.CANCEL;
                if (nav.isForMainFrame) {
                  final initHost = Uri.tryParse(selectedUrl)
                          ?.host
                          .replaceFirst('www.', '') ??
                      '';
                  final targetHost =
                      Uri.tryParse(u)?.host.replaceFirst('www.', '') ?? '';
                  if (initHost.isNotEmpty &&
                      targetHost.isNotEmpty &&
                      targetHost != initHost) {
                    final p = Uri.tryParse(u)?.path ?? '';
                    final isEmbedPath = p.startsWith('/e/') ||
                        p.startsWith('/d/') ||
                        p.startsWith('/embed');
                    if (!isEmbedPath) return NavigationActionPolicy.CANCEL;
                  }
                }
                return NavigationActionPolicy.ALLOW;
              },
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  color: Colors.black54,
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          '${state.selectedSource?.host ?? "Odtwarzacz"} • ${state.selectedSource?.quality ?? ""} ${state.selectedSource?.lang ?? ""}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (state.videoSources != null &&
                          state.videoSources!.length > 1)
                        TextButton.icon(
                          onPressed: () =>
                              _showSourcesBottomSheet(context, state, bloc),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: _kNetflixRed,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.dns_rounded,
                              color: Colors.white, size: 17),
                          label: Text(
                            'Źródła (${state.videoSources!.length})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Video(
            controller: bloc.controller,
            controls: NoVideoControls,
            fit: state.isImersive ? BoxFit.cover : BoxFit.contain,
          ),
          SafeArea(child: _buildOverlay(context, state)),
        ],
      ),
    );
  }

  Widget _buildOverlay(BuildContext context, PlayerState state) {
    final bloc = context.read<PlayerBloc>();

    return MouseRegion(
      onHover: (_) {
        if (!state.isOverlayVisible) {
          bloc.add(const ShowControls());
        }
      },
      child: GestureDetector(
        onTap: () {
          bloc.add(const ToggleControlsVisibility());
        },
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            _buildSeekingIndicator(state),
            _buildLoadingIndicator(state),
            _buildDoubleTapControls(bloc),
            IgnorePointer(
              ignoring: !state.isOverlayVisible,
              child: AnimatedOpacity(
                opacity: state.isOverlayVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.0, 0.25, 0.72, 1.0],
                      colors: [
                        Color(0xB3000000),
                        Color(0x33000000),
                        Color(0x33000000),
                        Color(0xCC000000),
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      _buildTopBar(context),
                      _buildCenterControls(state, bloc),
                      _buildBrightnessControl(context, bloc),
                      _buildIconsList(context, state, bloc),
                      _buildBottomBar(context, state, bloc),
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSeekingIndicator(PlayerState state) {
    return Center(
      child: Transform(
        transform: Matrix4.translationValues(
            state.seekDirection == SeekDirection.forward ? 120 : -120, 0, 0),
        child: AnimatedOpacity(
          opacity: state.isSeeking ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: Icon(
              state.seekDirection == SeekDirection.forward
                  ? Icons.forward_10
                  : Icons.replay_10,
              size: 48,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator(PlayerState state) {
    if (!state.isBuffering) return const SizedBox.shrink();

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _kNetflixRed, strokeWidth: 3.5),
          if (state.displayState.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              state.displayState,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildDoubleTapControls(PlayerBloc bloc) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: double.infinity,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTap: () =>
                  bloc.add(const SeekWithDirection(isForward: false)),
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: double.infinity,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTap: () =>
                  bloc.add(const SeekWithDirection(isForward: true)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNextEpisodeButton(BuildContext context) {
    final playerScreen = context.findAncestorWidgetOfExactType<PlayerScreen>();
    final movie = playerScreen!.movie;
    final seasonIndex = playerScreen.seasonIndex;
    final episodeIndex = playerScreen.episodeIndex;

    late Map<String, dynamic> queryParameters;

    if (seasonIndex == null || episodeIndex == null) {
      return const SizedBox.shrink();
    }
    final nextEpisodeIndex = episodeIndex + 1;
    if (nextEpisodeIndex < movie.seasons![seasonIndex].episodes.length) {
      queryParameters = {
        'season': seasonIndex.toString(),
        'episode': nextEpisodeIndex.toString(),
      };
    } else if (seasonIndex + 1 < movie.seasons!.length) {
      queryParameters = {
        'season': (seasonIndex + 1).toString(),
        'episode': '0',
      };
    } else {
      return const SizedBox.shrink();
    }

    return TextButton.icon(
      onPressed: () async {
        context.pushReplacementNamed(
          'player',
          extra: movie,
          queryParameters: queryParameters,
        );
      },
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white12,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      icon: const Icon(Icons.skip_next, color: Colors.white, size: 20),
      label: const Text(
        'Następny odcinek',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildBrightnessControl(BuildContext context, PlayerBloc bloc) {
    return Positioned(
      left: 16,
      top: 56,
      bottom: 64,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _getBrightnessIcon(_brightness),
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 150,
            child: RotatedBox(
              quarterTurns: -1,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4.0,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white30,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7.0),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14.0),
                ),
                child: Slider(
                  value: _brightness.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  onChangeStart: (_) {
                    bloc.add(const ShowControls());
                  },
                  onChanged: (value) {
                    setState(() {
                      _brightness = value;
                    });
                    bloc.add(const ShowControls());
                    ScreenBrightness.instance
                        .setApplicationScreenBrightness(value);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getBrightnessIcon(final double brightness) {
    if (brightness >= 0.75) return Icons.brightness_high;
    if (brightness >= 0.35) return Icons.brightness_medium;
    return Icons.brightness_low;
  }

  Widget _buildTopBar(BuildContext context) {
    final playerScreen = context.findAncestorWidgetOfExactType<PlayerScreen>();
    final movie = playerScreen!.movie;

    String title = movie.title;
    if (movie.isSeries == true &&
        playerScreen.seasonIndex != null &&
        playerScreen.episodeIndex != null) {
      final seasonIndex = playerScreen.seasonIndex!;
      final episodeIndex = playerScreen.episodeIndex!;
      final episode = movie.seasons![seasonIndex].episodes[episodeIndex];
      title =
          '${movie.title}  •  S${seasonIndex + 1}:E${episode.number} ${episode.title}';
    }

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        width: double.infinity,
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 140),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (movie.isSeries)
              Align(
                alignment: Alignment.centerRight,
                child: _buildNextEpisodeButton(context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls(PlayerState state, PlayerBloc bloc) {
    if (state.isBuffering) return const SizedBox.shrink();

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.replay_10),
            iconSize: 48,
            color: Colors.white,
            onPressed: () {
              bloc.add(const ShowControls());
              bloc.add(const SeekWithDirection(isForward: false));
            },
          ),
          const SizedBox(width: 42),
          IconButton(
            icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
            iconSize: 72,
            color: Colors.white,
            onPressed: () => bloc.add(const PlayPause()),
          ),
          const SizedBox(width: 42),
          IconButton(
            icon: const Icon(Icons.forward_10),
            iconSize: 48,
            color: Colors.white,
            onPressed: () {
              bloc.add(const ShowControls());
              bloc.add(const SeekWithDirection(isForward: true));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIconsList(
      BuildContext context, PlayerState state, PlayerBloc bloc) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (state.videoSources != null && state.videoSources!.length > 1)
              IconButton(
                icon: const Icon(Icons.dns_rounded, color: Colors.white),
                tooltip: 'Wybierz źródło wideo',
                onPressed: () =>
                    _showSourcesBottomSheet(context, state, bloc),
              ),
            IconButton(
              icon: Icon(
                state.isImersive ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white,
              ),
              onPressed: () {
                bloc.add(const ToggleImmersiveMode());
              },
            ),
            CastButton(
              castFramework: state.castFramework,
              activeColor: _kNetflixRed,
              color: Colors.white,
              disabledColor: Colors.white54,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(
      BuildContext context, PlayerState state, PlayerBloc bloc) {
    final totalMs = state.duration.inMilliseconds;
    final double liveProgress = totalMs > 0
        ? (state.position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;
    final double effectiveProgress =
        (_draggingProgress ?? liveProgress).clamp(0.0, 1.0);
    final Duration displayPosition = _draggingProgress != null && totalMs > 0
        ? Duration(milliseconds: (_draggingProgress! * totalMs).round())
        : state.position;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        width: double.infinity,
        height: 52,
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                _formatDuration(displayPosition),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: _draggingProgress != null ? 6.0 : 4.0,
                  activeTrackColor: _kNetflixRed,
                  inactiveTrackColor: Colors.white30,
                  thumbColor: _kNetflixRed,
                  overlayColor: _kNetflixRed.withAlpha(65),
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: _draggingProgress != null ? 9.5 : 7.0,
                  ),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 18.0),
                ),
                child: Slider(
                  value: effectiveProgress,
                  min: 0.0,
                  max: 1.0,
                  onChangeStart: (value) {
                    _seekReleaseTimer?.cancel();
                    setState(() {
                      _draggingProgress = value;
                    });
                    bloc.add(const ShowControls());
                  },
                  onChanged: (value) {
                    setState(() {
                      _draggingProgress = value;
                    });
                    bloc.add(const ShowControls());
                  },
                  onChangeEnd: (value) {
                    bloc.add(SeekTo(position: value));
                    _seekReleaseTimer?.cancel();
                    _seekReleaseTimer =
                        Timer(const Duration(milliseconds: 350), () {
                      if (mounted) {
                        setState(() {
                          _draggingProgress = null;
                        });
                      }
                    });
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: AnimatedOpacity(
                opacity: state.duration == Duration.zero ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                child: Text(
                  _formatDuration(state.duration),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (state.videoSources != null && state.videoSources!.length > 1) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _showSourcesBottomSheet(context, state, bloc),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white12,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon:
                    const Icon(Icons.dns_rounded, color: _kNetflixRed, size: 17),
                label: Text(
                  'Źródła (${state.videoSources!.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
    } else {
      return '$twoDigitMinutes:$twoDigitSeconds';
    }
  }
}
