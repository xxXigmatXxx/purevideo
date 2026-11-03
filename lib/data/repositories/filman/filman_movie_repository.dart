import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/services/webview_service.dart';
import 'package:flutter/material.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/link_model.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/filman/filman_dio_factory.dart';
import 'package:purevideo/data/repositories/movie_repository.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:purevideo/di/injection_container.dart';

class FilmanMovieRepository implements MovieRepository {
  final AuthRepository _authRepository =
      getIt<Map<SupportedService, AuthRepository>>()[SupportedService.filman]!;
  final SettingsService _settingsService = getIt<SettingsService>();
  Dio? _dio;

  FilmanMovieRepository() {
    _authRepository.authStream.listen(_onAuthChanged);
  }

  void _onAuthChanged(AuthModel auth) {
    if (auth.service == SupportedService.filman) {
      _dio = FilmanDioFactory.getDio(auth.account);
    }
  }

  Future<void> _prepareDio() async {
    await WebViewService.ensureCleanUserAgent();
    if (_dio == null) {
      final account = _authRepository.getAccount();
      _dio = FilmanDioFactory.getDio(account);
    }
  }

  Future<String> _resolveTempUrl(String tempUrl) async => tempUrl;

  Future<List<HostLink>> _extractHostLinksFromDocument(
      dom.Document document) async {
    final videoUrls = <HostLink>[];

    for (final row in document.querySelectorAll('tbody tr')) {
      String? link;

      try {
        final rawAttr =
            row.querySelector('a[data-iframe]')?.attributes['data-iframe'] ??
                '';
        if (rawAttr.isEmpty) continue;
        final decoded = base64Decode(rawAttr);
        final d = utf8.decode(decoded).trim();
        if (d.startsWith('{')) {
          try {
            final dynamic m = jsonDecode(d);
            link = (m is Map ? (m['src'] ?? m['url'] ?? d) : d)
                .toString()
                .trim();
          } catch (_) {
            link = d;
          }
        } else {
          link = d;
        }
        if (link.startsWith('//')) link = 'https:$link';
      } catch (e) {
        debugPrint(
            'Failed to decode link: ${row.querySelector('a[data-iframe]')?.attributes['data-iframe']} - ${e.toString()}');
        link = null;
      }

      if (link == null || link.isEmpty == true) continue;

      if (link.contains('tmp-url.pro')) {
        link = await _resolveTempUrl(link);
      }

      final tableData = row.querySelectorAll('td');
      if (tableData.isEmpty) continue;
      final language = tableData.length > 1 ? tableData[1].text.trim() : 'PL';
      final qualityVersion =
          tableData.length > 2 ? tableData[2].text.trim() : 'HD';

      videoUrls.add(HostLink(
        url: link,
        lang: language.isEmpty ? 'PL' : language,
        quality: qualityVersion.isEmpty ? 'HD' : qualityVersion,
      ));
    }

    return videoUrls;
  }

  Future<bool> _verifyMovieHasLinks(String url) async {
    if (_settingsService.isUrlLinkless(url)) return false;
    if (_settingsService.isUrlVerified(url)) return true;
    try {
      final resp = await _dio!
          .get(url)
          .timeout(const Duration(seconds: 6));
      final body = resp.data?.toString() ?? '';
      if (body.isEmpty) return true;
      final hasLinks =
          body.contains('data-iframe') || body.contains('episode-list');
      if (hasLinks) {
        _settingsService.markUrlVerified(url);
        return true;
      } else {
        _settingsService.markUrlLinkless(url);
        return false;
      }
    } catch (_) {
      return true;
    }
  }

  @override
  Future<List<ServiceMovieModel>> getMovies() async {
    await _prepareDio();

    final response = await _dio!.get('/');
    final document = html.parse(response.data);

    final candidates = <ServiceMovieModel>[];

    for (final list in document.querySelectorAll('div[id=item-list]')) {
      for (final item in list.children) {
        final poster = item.querySelector('.poster');
        if (poster == null) continue;

        final aTag = poster.querySelector('a');
        final rawTitle = (aTag?.attributes['title'] ??
                item.querySelector('.film_title')?.text ??
                '')
            .trim()
            .split('/')
            .first
            .trim();
        final imgEl = poster.querySelector('img');
        final imageUrl =
            (imgEl?.attributes['data-src'] ?? imgEl?.attributes['src'] ?? '')
                .trim();
        final link = (aTag?.attributes['href'] ?? '').trim();
        final category =
            list.parent?.querySelector('h3')?.text.trim() ?? 'Polecane';

        if (rawTitle.isEmpty ||
            rawTitle == 'Brak danych' ||
            imageUrl.isEmpty ||
            link.isEmpty ||
            link == 'Brak danych' ||
            !link.startsWith('http') ||
            _settingsService.isUrlLinkless(link)) {
          continue;
        }

        candidates.add(ServiceMovieModel(
          service: SupportedService.filman,
          title: rawTitle,
          imageUrl: imageUrl,
          url: link,
          category: category,
        ));
      }
    }

    // Verify in parallel batches of 10 so movies without links never appear on the Home Screen
    final verified = <ServiceMovieModel>[];
    const batchSize = 10;
    for (var i = 0; i < candidates.length; i += batchSize) {
      final end = (i + batchSize < candidates.length)
          ? i + batchSize
          : candidates.length;
      final batch = candidates.sublist(i, end);
      final checks = await Future.wait(
        batch.map((m) async {
          final ok = await _verifyMovieHasLinks(m.url);
          return ok ? m : null;
        }),
      );
      verified.addAll(checks.whereType<ServiceMovieModel>());
    }

    return verified;
  }

  Future<List<HostLink>> _scrapeEpisodeVideoUrls(String episodeUrl) async {
    await _prepareDio();

    final response = await _dio!.get(episodeUrl);
    final document = html.parse(response.data);

    final hostLinks = await _extractHostLinksFromDocument(document);

    return hostLinks;
  }

  String _prepareTitle(String title) {
    return title.contains('/') ? title.split('/').first.trim() : title.trim();
  }

  @override
  Future<ServiceMovieDetailsModel> getMovieDetails(String url) async {
    await _prepareDio();

    final response = await _dio!.get(url);
    final document = html.parse(response.data);

    final title = _prepareTitle(document
            .querySelector('[itemprop="name"]')
            ?.text
            .replaceAll(
                document.querySelector('[itemprop="name"] *')?.text ?? '',
                '') ??
        'Brak tytułu');
    final description =
        document.querySelector('.description')?.text.trim() ?? '';
    final posterImg = document.querySelector('#single-poster img');
    final imageUrl =
        (posterImg?.attributes['src'] ?? posterImg?.attributes['data-src'] ?? '')
            .trim();

    final episodeList = document.querySelector('#episode-list');
    final isSeries = episodeList != null;

    if (isSeries) {
      final seasons = <SeasonModel>[];
      for (int i = 0; i < episodeList.children.length; i++) {
        final seasonElement = episodeList.children[i];
        final episodes = <EpisodeModel>[];

        for (int j = 0; j < seasonElement.children.last.children.length; j++) {
          final episodeElement = seasonElement.children.last.children[j];
          final episodeTitle =
              episodeElement.text.trim().split(' ').skip(1).join(' ');
          final episodeUrl =
              episodeElement.querySelector('a')?.attributes['href'];

          if (episodeUrl == null || episodeUrl.trim().isEmpty) {
            continue;
          }

          episodes.add(
            EpisodeModel(
                title: episodeTitle.isEmpty
                    ? 'Odcinek ${seasonElement.children.last.children.length - j}'
                    : episodeTitle,
                number: seasonElement.children.last.children.length - j,
                url: episodeUrl.trim(),
                videoUrls: []),
          );
        }

        if (episodes.isNotEmpty) {
          seasons.add(SeasonModel(
              number: episodeList.children.length - i,
              episodes: episodes.toList().reversed.toList()));
        }
      }

      if (seasons.isEmpty) {
        _settingsService.markUrlLinkless(url);
        throw Exception('Ten serial nie posiada jeszcze dostępnych odcinków.');
      }

      _settingsService.markUrlVerified(url);
      return ServiceMovieDetailsModel(
        service: SupportedService.filman,
        url: url,
        title: title,
        description: description,
        imageUrl: imageUrl,
        isSeries: isSeries,
        seasons: seasons.toList().reversed.toList(),
      );
    }

    final videoUrls = await _extractHostLinksFromDocument(document);
    if (videoUrls.isEmpty) {
      _settingsService.markUrlLinkless(url);
      throw Exception('Ten film nie posiada jeszcze aktywnych linków wideo.');
    }

    _settingsService.markUrlVerified(url);
    final movieModel = ServiceMovieDetailsModel(
      service: SupportedService.filman,
      url: url,
      title: title,
      description: description,
      imageUrl: imageUrl,
      isSeries: isSeries,
      videoUrls: videoUrls,
    );

    return movieModel;
  }

  @override
  Future<EpisodeModel> getEpisodeHosts(EpisodeModel episode) async {
    final videoUrls = await _scrapeEpisodeVideoUrls(episode.url);
    if (videoUrls.isEmpty) {
      throw Exception('Ten odcinek nie posiada jeszcze aktywnych linków wideo.');
    }
    return episode.copyWith(videoUrls: videoUrls);
  }
}
