import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:purevideo/core/services/media_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/movie_repository.dart';
import 'package:purevideo/data/repositories/video_source_repository.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/player/bloc/player_event.dart';
import 'package:purevideo/presentation/player/bloc/player_state.dart';
import 'package:flutter_cast_framework/cast.dart' hide PlayerState;
import 'package:pip/pip.dart';

class PlayerBloc extends Bloc<PlayerEvent, PlayerState> {
  final WatchedService watchedService = getIt();

  late final Player _player;
  late final VideoController _controller;
  late StreamSubscription<Duration> _positionSubscription;
  late StreamSubscription<Duration?> _durationSubscription;
  late StreamSubscription<bool> _playingSubscription;
  late StreamSubscription<bool> _bufferingSubscription;

  Timer? _hideControlsTimer;
  Timer? _seekingTimer;
  Timer? _debounceHideControlsTimer;
  Timer? _bufferingDebounceTimer;
  VoidCallback? _castStateListener;

  final VideoSourceRepository _videoSourceRepository =
      getIt<VideoSourceRepository>();
  final Map<SupportedService, MovieRepository> _movieRepositories =
      getIt<Map<SupportedService, MovieRepository>>();
  final MediaService _mediaService = getIt<MediaService>();

  AudioSession? _audioSession;

  MovieDetailsModel? _movie;
  int? _seasonIndex;
  int? _episodeIndex;
  int? _initialSourceIndex;
  int _lastSavedSecond = -1;
  int _lastEmittedSecond = -1;
  Duration _latestPosition = Duration.zero;

  PlayerBloc()
      : super(PlayerState(
            castFramework: getIt<FlutterCastFramework>(),
            pipFramework: Pip())) {
    on<InitializePlayer>(_onInitializePlayer);
    on<LoadVideoSources>(_onLoadVideoSources);
    on<InitializeVideoPlayer>(_onInitializeVideoPlayer);
    on<PlayPause>(_onPlayPause);
    on<SeekTo>(_onSeekTo);
    on<SeekWithDirection>(_onSeekWithDirection);
    on<ChangeVideoSource>(_onChangeVideoSource);
    on<ToggleControlsVisibility>(_onToggleControlsVisibility);
    on<ShowControls>(_onShowControls);
    on<HideControls>(_onHideControls);
    on<HideSeekingIndicator>(_onHideSeekingIndicator);
    on<UpdatePosition>(_onUpdatePosition);
    on<UpdateDuration>(_onUpdateDuration);
    on<UpdatePlayingState>(_onUpdatePlayingState);
    on<UpdateBufferingState>(_onUpdateBufferingState);
    on<PlayerError>(_onPlayerError);
    on<DisposePlayer>(_onDisposePlayer);
    on<ToggleImmersiveMode>(_onToggleImmersiveMode);
    on<CastVideo>(_onCastVideo);
  }

  bool _mediaItemAdded = false;

  void _saveWatchedProgress([int? overrideSeconds, bool notify = false]) {
    if (_movie == null) return;
    try {
      final sec = overrideSeconds ?? _latestPosition.inSeconds;
      if (_movie!.isSeries &&
          _seasonIndex != null &&
          _episodeIndex != null &&
          _movie!.seasons != null &&
          _seasonIndex! < _movie!.seasons!.length &&
          _episodeIndex! < _movie!.seasons![_seasonIndex!].episodes.length) {
        watchedService.watchEpisode(
          _movie!,
          _movie!.seasons![_seasonIndex!],
          _movie!.seasons![_seasonIndex!].episodes[_episodeIndex!],
          sec,
          notify: notify,
        );
      } else {
        watchedService.watchMovie(_movie!, sec, notify: notify);
      }
    } catch (e) {
      debugPrint('Error saving watched progress: $e');
    }
  }

  @override
  Future<void> close() {
    try {
      _audioSession?.setActive(false);
    } catch (_) {}
    try {
      _mediaService.audioHandler.playbackState.add(PlaybackState(
        playing: false,
      ));
    } catch (_) {}
    try {
      state.castFramework.castContext.sessionManager.remoteMediaClient.stop();
    } catch (_) {}
    _saveWatchedProgress(null, true);
    try {
      state.pipFramework.dispose();
    } catch (_) {}
    _disposeMediaKit();
    _hideControlsTimer?.cancel();
    _seekingTimer?.cancel();
    _debounceHideControlsTimer?.cancel();
    _bufferingDebounceTimer?.cancel();
    if (_castStateListener != null) {
      try {
        state.castFramework.castContext.state
            .removeListener(_castStateListener!);
      } catch (e) {
        debugPrint('Error removing cast state listener: $e');
      }
    }
    return super.close();
  }

  Future<void> _initMediaKit() async {
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
      ),
    );

    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    try {
      final dynamic nativePlayer = _player.platform;
      await nativePlayer.setProperty('audio-channels', 'stereo');
      await nativePlayer.setProperty('cache', 'yes');
      await nativePlayer.setProperty('cache-secs', '60');
      await nativePlayer.setProperty('demuxer-readahead-secs', '30');
      await nativePlayer.setProperty('demuxer-max-bytes', '33554432');
      await nativePlayer.setProperty('demuxer-max-back-bytes', '16777216');
      await nativePlayer.setProperty('cache-pause', 'yes');
      await nativePlayer.setProperty('cache-pause-initial', 'no');
      await nativePlayer.setProperty('cache-pause-wait', '1');
      await nativePlayer.setProperty(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_delay_max=2',
      );
      await nativePlayer.setProperty('framedrop', 'vo');
    } catch (_) {}

    _positionSubscription = _player.stream.position.listen((position) {
      _latestPosition = position;
      final sec = position.inSeconds;
      if (sec != _lastEmittedSecond) {
        _lastEmittedSecond = sec;
        add(UpdatePosition(position: position));
      }
    });

    _durationSubscription = _player.stream.duration.listen((duration) {
      if (duration.inSeconds > 0 &&
          duration.inSeconds != state.duration.inSeconds) {
        add(UpdateDuration(duration: duration));
      }
    });

    _playingSubscription = _player.stream.playing.listen((playing) {
      if (playing != state.isPlaying) {
        add(UpdatePlayingState(isPlaying: playing));
      }
    });

    _bufferingSubscription = _player.stream.buffering.listen((buffering) {
      _bufferingDebounceTimer?.cancel();
      if (buffering) {
        _bufferingDebounceTimer = Timer(const Duration(milliseconds: 900), () {
          if (!isClosed && !state.isBuffering) {
            add(const UpdateBufferingState(isBuffering: true));
          }
        });
      } else {
        if (state.isBuffering) {
          add(const UpdateBufferingState(isBuffering: false));
        }
      }
    });
  }

  void _disposeMediaKit() {
    try {
      _positionSubscription.cancel();
    } catch (_) {}
    try {
      _durationSubscription.cancel();
    } catch (_) {}
    try {
      _playingSubscription.cancel();
    } catch (_) {}
    try {
      _bufferingSubscription.cancel();
    } catch (_) {}
    try {
      _player.dispose();
    } catch (_) {}
  }

  Future<void> _onInitializePlayer(
    InitializePlayer event,
    Emitter<PlayerState> emit,
  ) async {
    _movie = event.movie;
    _seasonIndex = event.seasonIndex;
    _episodeIndex = event.episodeIndex;
    _initialSourceIndex = event.initialSourceIndex;

    await _initMediaKit();

    const options = PipOptions(
      autoEnterEnabled: true,
      aspectRatioX: 16,
      aspectRatioY: 9,
      sourceRectHintLeft: 0,
      sourceRectHintTop: 0,
      sourceRectHintRight: 1080,
      sourceRectHintBottom: 720,
      sourceContentView: 0,
      contentView: 0,
      preferredContentWidth: 480,
      preferredContentHeight: 270,
      controlStyle: 2,
    );

    try {
      await state.pipFramework.setup(options);
      await state.pipFramework
          .registerStateChangedObserver(PipStateChangedObserver(
        onPipStateChanged: (pipState, error) {
          switch (pipState) {
            case PipState.pipStateStarted:
              emit(state.copyWith(isOverlayVisible: false));
              _hideControlsTimer?.cancel();
              break;
            default:
              break;
          }
        },
      ));
    } catch (_) {}

    emit(state.copyWith(
      isLoading: true,
      errorMessage: null,
    ));

    add(const LoadVideoSources());
  }

  Future<void> _onLoadVideoSources(
    LoadVideoSources event,
    Emitter<PlayerState> emit,
  ) async {
    if (_movie == null) return;

    emit(state.copyWith(
      isLoading: true,
      errorMessage: null,
    ));

    try {
      MovieDetailsModel movieDetails;

      if (_seasonIndex != null && _episodeIndex != null) {
        final episodes = <EpisodeModel>[];
        final combinedSeasons = _movie!.seasons;
        final targetSeason = (combinedSeasons != null &&
                _seasonIndex! < combinedSeasons.length)
            ? combinedSeasons[_seasonIndex!]
            : null;
        final targetEpisode = (targetSeason != null &&
                _episodeIndex! < targetSeason.episodes.length)
            ? targetSeason.episodes[_episodeIndex!]
            : null;

        for (final service in _movie!.services) {
          final movieRepository = _movieRepositories[service.service];
          if (movieRepository == null) continue;
          final svcSeasons = service.seasons;
          if (svcSeasons == null || svcSeasons.isEmpty) continue;

          SeasonModel? season;
          if (targetSeason != null) {
            for (final s in svcSeasons) {
              if (s.number == targetSeason.number) {
                season = s;
                break;
              }
            }
          }
          season ??= (_seasonIndex! < svcSeasons.length)
              ? svcSeasons[_seasonIndex!]
              : null;
          if (season == null || season.episodes.isEmpty) continue;

          EpisodeModel? episode;
          if (targetEpisode != null) {
            for (final e in season.episodes) {
              if (e.number == targetEpisode.number) {
                episode = e;
                break;
              }
            }
          }
          episode ??= (_episodeIndex! < season.episodes.length)
              ? season.episodes[_episodeIndex!]
              : null;
          if (episode == null) continue;

          if (episode.videoUrls != null && episode.videoUrls!.isNotEmpty) {
            episodes.add(episode);
          } else {
            try {
              final episodeWithHosts =
                  await movieRepository.getEpisodeHosts(episode);
              episodes.add(episodeWithHosts);
            } catch (e) {
              debugPrint('Error loading episode hosts (${service.service}): $e');
            }
          }
        }

        final tempModel = MovieDetailsModel(
          services: [
            ServiceMovieDetailsModel(
                service: SupportedService.values.first,
                url: '',
                title: '',
                description: '',
                imageUrl: '',
                isSeries: true,
                videoUrls:
                    episodes.expand((e) => e.videoUrls!).toList()),
          ],
          filmwebInfo: _movie!.filmwebInfo,
        );

        movieDetails = await _videoSourceRepository.scrapeVideoUrls(tempModel);
      } else {
        movieDetails = _movie!;
        if (movieDetails.directUrls == null ||
            movieDetails.directUrls!.isEmpty) {
          movieDetails = await _videoSourceRepository.scrapeVideoUrls(_movie!);
        }
      }

      if (movieDetails.directUrls != null &&
          movieDetails.directUrls!.isNotEmpty) {
        final sources = movieDetails.directUrls!;
        final idx = (_initialSourceIndex != null &&
                _initialSourceIndex! >= 0 &&
                _initialSourceIndex! < sources.length)
            ? _initialSourceIndex!
            : 0;
        final selectedSource = sources[idx];

        emit(state.copyWith(
          videoSources: sources,
          selectedSource: selectedSource,
          isLoading: false,
        ));

        add(InitializeVideoPlayer(source: selectedSource));
      } else {
        emit(state.copyWith(
          isLoading: false,
          errorMessage: 'Nie znaleziono źródeł odtwarzania',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Wystąpił błąd: $e',
      ));
    }
  }

  Future<void> _onInitializeVideoPlayer(
    InitializeVideoPlayer event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(
      displayState: 'Przygotowywanie odtwarzacza...',
      isBuffering: true,
    ));

    if (state.castFramework.castContext.state.value == CastState.connected) {
      add(const CastVideo());
      final sessionManager = state.castFramework.castContext.sessionManager;
      sessionManager.remoteMediaClient.onProgressUpdated =
          (final progressMs, final durationMs) {
        final pos = Duration(milliseconds: progressMs);
        _latestPosition = pos;
        if (pos.inSeconds != _lastEmittedSecond) {
          _lastEmittedSecond = pos.inSeconds;
          add(UpdatePosition(position: pos));
        }
      };
    }

    try {
      if (_castStateListener == null) {
        _castStateListener = () async {
          switch (state.castFramework.castContext.state.value) {
            case CastState.connected:
              add(const CastVideo());
              break;
            default:
              break;
          }
        };
        state.castFramework.castContext.state.addListener(_castStateListener!);
      }
    } catch (e) {
      debugPrint('Error initializing google cast: $e');
    }

    try {
      if (_audioSession == null) {
        _audioSession = await AudioSession.instance;
        await _audioSession!.configure(const AudioSessionConfiguration.music());
      }
    } catch (e) {
      debugPrint('Error initializing audio session: $e');
    }

    try {
      final Map<String, String> headers = event.source.headers ?? {};

      int? watchedPosition;
      if (_seasonIndex != null && _episodeIndex != null) {
        final episode =
            _movie!.seasons![_seasonIndex!].episodes[_episodeIndex!];
        final watchedEpisode = watchedService.getByEpisode(_movie!, episode);
        watchedPosition = watchedEpisode?.watchedTime;
      } else {
        final watchedMovie = watchedService.getByMovie(_movie!);
        watchedPosition = watchedMovie?.watchedTime;
      }

      _saveWatchedProgress(watchedPosition ?? 0);

      debugPrint('[PlayerBloc] Opening media: ${event.source.url}');

      Future.delayed(const Duration(seconds: 6), () {
        if (!isClosed && state.isBuffering) {
          add(const UpdateBufferingState(isBuffering: false));
        }
      });

      if (event.source.host.contains('(Web)')) {
        await _player.stop();
        emit(state.copyWith(
          isBuffering: false,
          isPlaying: true,
          selectedSource: event.source,
          displayState: '',
        ));
        return;
      }

      await _player.open(
        Media(
          event.source.url,
          httpHeaders: headers,
          start: Duration(seconds: watchedPosition ?? 0),
        ),
        play: true,
      );

      emit(state.copyWith(
        isBuffering: false,
        isPlaying: true,
        selectedSource: event.source,
        displayState: '',
      ));
    } catch (e) {
      emit(state.copyWith(
        isBuffering: false,
        errorMessage: 'Błąd inicjalizacji odtwarzacza: $e',
      ));
    }
  }

  Future<void> _onPlayPause(
    PlayPause event,
    Emitter<PlayerState> emit,
  ) async {
    _audioSession?.setActive(!state.isPlaying);
    _player.playOrPause();
    _saveWatchedProgress();
    if (state.isOverlayVisible) {
      _resetHideControlsTimer();
    }
  }

  Future<void> _onSeekTo(
    SeekTo event,
    Emitter<PlayerState> emit,
  ) async {
    final position = Duration(
      milliseconds: (event.position * state.duration.inMilliseconds).round(),
    );
    _latestPosition = position;
    _lastEmittedSecond = position.inSeconds;
    _player.seek(position);
    emit(state.copyWith(position: position));
    _saveWatchedProgress(position.inSeconds);
    _updateNotification();
  }

  Future<void> _onSeekWithDirection(
    SeekWithDirection event,
    Emitter<PlayerState> emit,
  ) async {
    final direction =
        event.isForward ? SeekDirection.forward : SeekDirection.backward;

    int newPositionSeconds = _latestPosition.inSeconds;
    if (direction == SeekDirection.backward) {
      newPositionSeconds = max(0, newPositionSeconds - 10);
    } else {
      newPositionSeconds =
          min(newPositionSeconds + 10, state.duration.inSeconds);
    }

    final newPos = Duration(seconds: newPositionSeconds);
    _latestPosition = newPos;
    _lastEmittedSecond = newPositionSeconds;

    emit(state.copyWith(
      seekDirection: direction,
      isSeeking: true,
      isOverlayVisible: false,
      position: newPos,
    ));

    _seekingTimer?.cancel();
    _seekingTimer = Timer(const Duration(milliseconds: 400), () {
      add(const HideSeekingIndicator());
    });

    _player.seek(newPos);
    _saveWatchedProgress(newPositionSeconds);
    _updateNotification();
  }

  Future<void> _onChangeVideoSource(
    ChangeVideoSource event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(selectedSource: event.source));
    add(InitializeVideoPlayer(source: event.source));
  }

  Future<void> _onToggleControlsVisibility(
    ToggleControlsVisibility event,
    Emitter<PlayerState> emit,
  ) async {
    if (state.isOverlayVisible) {
      emit(state.copyWith(isOverlayVisible: false));
      _hideControlsTimer?.cancel();
    } else {
      emit(state.copyWith(
        isOverlayVisible: true,
        position: _latestPosition,
      ));
      _resetHideControlsTimer();
    }
  }

  Future<void> _onShowControls(
    ShowControls event,
    Emitter<PlayerState> emit,
  ) async {
    if (!state.isOverlayVisible) {
      emit(state.copyWith(
        isOverlayVisible: true,
        position: _latestPosition,
      ));
    }
    _resetHideControlsTimer();
  }

  Future<void> _onHideControls(
    HideControls event,
    Emitter<PlayerState> emit,
  ) async {
    if (state.isOverlayVisible) {
      emit(state.copyWith(isOverlayVisible: false));
    }
  }

  Future<void> _onHideSeekingIndicator(
    HideSeekingIndicator event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(isSeeking: false));
  }

  Future<void> _onUpdatePosition(
    UpdatePosition event,
    Emitter<PlayerState> emit,
  ) async {
    _latestPosition = event.position;
    final curSec = event.position.inSeconds;
    if (curSec > 0 && (curSec - _lastSavedSecond).abs() >= 180) {
      _lastSavedSecond = curSec;
      _saveWatchedProgress(curSec);
    }
    // Only rebuild UI when overlay controls are actually visible!
    if (state.isOverlayVisible) {
      emit(state.copyWith(position: event.position));
    }
  }

  Future<void> _onUpdateDuration(
    UpdateDuration event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(duration: event.duration));
    if (event.duration.inSeconds == 0) {
      return;
    }

    if (!_mediaItemAdded) {
      _mediaItemAdded = true;
      _mediaService.audioHandler.add(MediaItem(
        id: _movie!.title,
        title: _movie!.title,
        artUri: Uri.parse(_movie!.imageUrl),
        duration: state.duration,
      ));
      _updateNotification();
    }
  }

  Future<void> _onUpdatePlayingState(
    UpdatePlayingState event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(isPlaying: event.isPlaying));
    _updateNotification();
  }

  Future<void> _onUpdateBufferingState(
    UpdateBufferingState event,
    Emitter<PlayerState> emit,
  ) async {
    if (event.isBuffering) {
      emit(state.copyWith(isBuffering: true));
    } else {
      emit(state.copyWith(
        isBuffering: false,
        displayState: '',
      ));
    }
  }

  Future<void> _onPlayerError(
    PlayerError event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(
      isBuffering: false,
      errorMessage: event.message,
    ));
  }

  Future<void> _onDisposePlayer(
    DisposePlayer event,
    Emitter<PlayerState> emit,
  ) async {
    if (isClosed) return;
    try {
      _audioSession?.setActive(false);
    } catch (_) {}

    try {
      _mediaService.audioHandler.playbackState.add(PlaybackState(
        playing: false,
      ));
    } catch (_) {}

    try {
      state.castFramework.castContext.sessionManager.remoteMediaClient.stop();
    } catch (_) {}

    _saveWatchedProgress(null, true);

    try {
      state.pipFramework.dispose();
    } catch (_) {}

    _disposeMediaKit();

    _hideControlsTimer?.cancel();
    _seekingTimer?.cancel();
    _debounceHideControlsTimer?.cancel();
    _bufferingDebounceTimer?.cancel();
  }

  void _resetHideControlsTimer() {
    _debounceHideControlsTimer?.cancel();
    _bufferingDebounceTimer?.cancel();
    _debounceHideControlsTimer = Timer(const Duration(milliseconds: 500), () {
      _hideControlsTimer?.cancel();
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (!isClosed && state.isPlaying) {
          add(const HideControls());
        }
      });
    });
  }

  Future<void> _onToggleImmersiveMode(
    ToggleImmersiveMode event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(isImersive: !state.isImersive));
  }

  VideoController get controller => _controller;

  void setVolume(double normalizedVolume) {
    try {
      final vol = (normalizedVolume.clamp(0.0, 1.0)) * 100.0;
      _player.setVolume(vol);
    } catch (_) {}
  }

  Future<void> _onCastVideo(CastVideo event, Emitter<PlayerState> emit) async {
    if (state.castFramework.castContext.state.value == CastState.connected) {
      if (state.selectedSource == null) {
        emit(state.copyWith(
          errorMessage: 'Nie wybrano źródła wideo do przesłania.',
        ));
        return;
      }

      _player.pause();
      state.castFramework.castContext.sessionManager.remoteMediaClient.load(
          MediaLoadRequestData(
              currentTime: _latestPosition.inMilliseconds,
              shouldAutoplay: true,
              mediaInfo: MediaInfo(
                  streamDuration: state.duration.inMilliseconds,
                  streamType: StreamType.buffered,
                  contentType: state.selectedSource!.url.contains('.m3u8')
                      ? 'application/x-mpegurl'
                      : 'video/mp4',
                  contentId: state.selectedSource!.url,
                  customDataAsJson:
                      jsonEncode({'headers': state.selectedSource!.headers}),
                  mediaMetadata: MediaMetadata(
                      mediaType: MediaType.movie,
                      strings: _movie!.isSeries
                          ? {
                              MediaMetadataKey.title.name: _movie!
                                  .seasons![_seasonIndex!]
                                  .episodes[_episodeIndex!]
                                  .title,
                              MediaMetadataKey.subtitle.name: _movie!.title,
                            }
                          : {MediaMetadataKey.title.name: _movie!.title},
                      webImages: [
                        WebImage(url: _movie!.imageUrl),
                        WebImage(url: _movie!.imageUrl)
                      ]))));
    }
  }

  void _updateNotification() {
    try {
      _mediaService.audioHandler.playbackState.add(PlaybackState(
        playing: state.isPlaying,
        updatePosition: _latestPosition,
        processingState: state.isBuffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        bufferedPosition: state.duration,
      ));
    } catch (_) {}
  }
}
