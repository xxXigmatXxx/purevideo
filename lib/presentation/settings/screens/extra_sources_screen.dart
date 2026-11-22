import 'package:fast_cached_network_image/fast_cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:purevideo/core/services/app_update_service.dart';
import 'package:purevideo/core/services/extra_sources_service.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/data/models/filmweb_model.dart';
import 'package:purevideo/data/repositories/filmweb/filmweb_info_repository.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/settings/widgets/app_update_dialog.dart';
import 'package:purevideo/presentation/settings/widgets/settings_listenable.dart';

class ExtraSourcesScreen extends StatefulWidget {
  const ExtraSourcesScreen({super.key});

  @override
  State<ExtraSourcesScreen> createState() => _ExtraSourcesScreenState();
}

class _ExtraSourcesScreenState extends State<ExtraSourcesScreen>
    with SingleTickerProviderStateMixin {
  final SettingsService _settings = getIt<SettingsService>();
  final ExtraSourcesService _extraSources = getIt<ExtraSourcesService>();
  final AppUpdateService _updateService = getIt<AppUpdateService>();
  final FilmwebInfoRepository _filmweb = getIt<FilmwebInfoRepository>();

  late final TabController _tabController;

  bool _syncing = false;
  bool _hasOwnerCreds = false;
  String? _ownerLogin;
  String _installedVersion = '1.0.97';
  int _installedBuild = 97;

  // Admin OTA Publisher state
  final _updNameCtrl = TextEditingController();
  final _updVersionCtrl = TextEditingController();
  final _updBuildCtrl = TextEditingController();
  final _updDescCtrl = TextEditingController();
  AppUpdateChannel _updChannel = AppUpdateChannel.release;
  AppUpdateSourceType _updSourceType = AppUpdateSourceType.artifact;

  bool _loadingGitHub = false;
  String? _githubLoadErr;
  List<GitHubWorkflowRunItem> _runs = const [];
  GitHubWorkflowRunItem? _selectedRun;
  List<GitHubArtifactItem> _artifacts = const [];
  GitHubArtifactItem? _selectedArtifact;

  List<GitHubReleaseItem> _releases = const [];
  GitHubReleaseItem? _selectedRelease;
  GitHubReleaseAssetItem? _selectedReleaseAsset;

  bool _publishingUpdate = false;
  String _publishUpdateStatus = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadInitialState();
    if (_settings.extraSourcesEnabled) {
      _syncNow(silent: true);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _updNameCtrl.dispose();
    _updVersionCtrl.dispose();
    _updBuildCtrl.dispose();
    _updDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialState() async {
    await _loadOwnerStatus();
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _installedVersion = pkg.version;
          _installedBuild = int.tryParse(pkg.buildNumber) ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadOwnerStatus() async {
    final has = await _extraSources.hasVerifiedOwnerCredentials();
    final login = await _extraSources.getVerifiedOwnerLogin();
    if (mounted) {
      setState(() {
        _hasOwnerCreds = has;
        _ownerLogin = login;
      });
      if (has && _runs.isEmpty && _releases.isEmpty) {
        _loadGitHubSources();
      }
    }
  }

  Future<void> _syncNow({bool silent = false}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final ok = await _extraSources.syncRemoteSources(force: true);
    if (mounted) {
      setState(() => _syncing = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? 'Zsynchronizowano źródła z chmury.'
                : 'Nie udało się pobrać listy źródeł z chmury.'),
          ),
        );
      }
    }
  }

  Future<void> _loadGitHubSources() async {
    setState(() {
      _loadingGitHub = true;
      _githubLoadErr = null;
    });
    try {
      if (_updSourceType == AppUpdateSourceType.artifact) {
        final runs = await _updateService.fetchRecentBuilds();
        if (!mounted) return;
        setState(() {
          _runs = runs;
          _selectedRun = runs.isNotEmpty ? runs.first : null;
          _artifacts = const [];
          _selectedArtifact = null;
        });
        if (runs.isNotEmpty) {
          await _selectRun(runs.first);
        }
      } else {
        final rels = await _updateService.fetchGitHubReleases();
        if (!mounted) return;
        setState(() {
          _releases = rels;
          _selectedRelease = rels.isNotEmpty ? rels.first : null;
          _selectedReleaseAsset =
              (rels.isNotEmpty && rels.first.assets.isNotEmpty)
                  ? rels.first.assets.first
                  : null;
        });
        if (_selectedRelease != null) {
          _autoFillFromRelease(_selectedRelease!);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _githubLoadErr = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loadingGitHub = false);
      }
    }
  }

  Future<void> _selectRun(GitHubWorkflowRunItem run) async {
    setState(() {
      _selectedRun = run;
      _artifacts = const [];
      _selectedArtifact = null;
      _loadingGitHub = true;
      _githubLoadErr = null;
    });
    try {
      final arts = await _updateService.fetchArtifactsForRun(run.id);
      if (!mounted) return;
      setState(() {
        _artifacts = arts;
        _selectedArtifact = arts.isNotEmpty ? arts.first : null;
        _updBuildCtrl.text = run.runNumber.toString();
        if (_updVersionCtrl.text.trim().isEmpty) {
          _updVersionCtrl.text = '1.0.${run.runNumber}';
        }
        if (_updNameCtrl.text.trim().isEmpty) {
          _updNameCtrl.text = 'PureVideo 1.0.${run.runNumber}';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _githubLoadErr = e.toString());
    } finally {
      if (mounted) setState(() => _loadingGitHub = false);
    }
  }

  void _autoFillFromRelease(GitHubReleaseItem rel) {
    final cleanVer = rel.tagName.replaceAll(RegExp(r'^v'), '').trim();
    if (_updVersionCtrl.text.trim().isEmpty && cleanVer.isNotEmpty) {
      _updVersionCtrl.text = cleanVer;
    }
    if (_updNameCtrl.text.trim().isEmpty) {
      _updNameCtrl.text = rel.name;
    }
  }

  Future<String?> _promptPinOrVerifyOwner() async {
    final hasCreds = await _extraSources.hasVerifiedOwnerCredentials();
    if (!mounted) return null;

    if (hasCreds) {
      final pinCtrl = TextEditingController();
      String? err;
      return showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDlgState) => AlertDialog(
            title: const Text('Zatwierdź kodem PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Konto właściciela: ${_ownerLogin ?? ExtraSourcesService.repoOwner}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'PIN administratora',
                    errorText: err,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Anuluj'),
              ),
              FilledButton(
                onPressed: () async {
                  final ok = await _extraSources.verifyPin(pinCtrl.text);
                  if (!ctx.mounted) return;
                  if (ok) {
                    Navigator.of(ctx).pop(pinCtrl.text.trim());
                  } else {
                    setDlgState(() => err = 'Nieprawidłowy kod PIN');
                  }
                },
                child: const Text('Zatwierdź'),
              ),
            ],
          ),
        ),
      );
    }

    final tokenCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String? errText;
    bool busy = false;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Weryfikacja właściciela'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Aby publikować filmy/seriale lub aktualizacje OTA dla użytkowników, potwierdź że jesteś właścicielem repozytorium (xxXigmatXxx). Token jest szyfrowany w Android Keystore wyłącznie na tym urządzeniu.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Token GitHub (PAT z uprawnieniem Contents)',
                    hintText: 'ghp_... lub github_pat_...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ustaw swój PIN administratora (4–8 znaków)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (errText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errText!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDlgState(() {
                        busy = true;
                        errText = null;
                      });
                      final err =
                          await _extraSources.verifyAndSaveOwnerCredentials(
                        githubToken: tokenCtrl.text,
                        pin: pinCtrl.text,
                      );
                      if (!ctx.mounted) return;
                      if (err != null) {
                        setDlgState(() {
                          busy = false;
                          errText = err;
                        });
                      } else {
                        await _loadOwnerStatus();
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop(pinCtrl.text.trim());
                        }
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Zweryfikuj i zapisz'),
            ),
          ],
        ),
      ),
    );
  }

  /// Wizard dialog to add a Movie or Series episode with CDA / Vider.info link
  Future<void> _showAddMediaDialog({
    ExtraMediaEntry? prefillSeries,
    int? prefillSeason,
    int? prefillEpisode,
  }) async {
    bool isSeries = prefillSeries != null ? true : false;
    final searchCtrl = TextEditingController();
    final titleCtrl = TextEditingController(text: prefillSeries?.title ?? '');
    final posterCtrl =
        TextEditingController(text: prefillSeries?.posterUrl ?? '');
    final descCtrl =
        TextEditingController(text: prefillSeries?.description ?? '');
    final linkCtrl = TextEditingController();
    final seasonCtrl =
        TextEditingController(text: (prefillSeason ?? 1).toString());
    final episodeCtrl =
        TextEditingController(text: (prefillEpisode ?? 1).toString());
    final epTitleCtrl = TextEditingController();

    String selectedLang = 'Lektor PL';
    String selectedQuality = 'HD';
    String selectedEntryId = prefillSeries?.id ?? '';
    bool searching = false;
    List<FilmwebPreviewModel> searchResults = const [];
    String? errMsg;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(prefillSeries != null
              ? 'Dodaj odcinek: ${prefillSeries.title}'
              : 'Dodaj film lub serial'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (prefillSeries == null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Film')),
                            selected: !isSeries,
                            onSelected: busy
                                ? null
                                : (_) => setDlgState(() {
                                      isSeries = false;
                                      searchResults = const [];
                                    }),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Serial')),
                            selected: isSeries,
                            onSelected: busy
                                ? null
                                : (_) => setDlgState(() {
                                      isSeries = true;
                                      searchResults = const [];
                                    }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchCtrl,
                            decoration: InputDecoration(
                              labelText: isSeries
                                  ? 'Wyszukaj serial (Filmweb)'
                                  : 'Wyszukaj film (Filmweb)',
                              hintText: 'np. Shrek, Breaking Bad...',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: searching || busy
                              ? null
                              : () async {
                                  final q = searchCtrl.text.trim();
                                  if (q.isEmpty) return;
                                  setDlgState(() {
                                    searching = true;
                                    errMsg = null;
                                  });
                                  try {
                                    final res = await _filmweb.searchMovie(
                                      q,
                                      isSeries: isSeries,
                                    );
                                    if (!ctx.mounted) return;
                                    setDlgState(() {
                                      searchResults = res.take(8).toList();
                                      if (searchResults.isEmpty) {
                                        errMsg =
                                            'Nie znaleziono na Filmwebie — możesz wpisać tytuł ręcznie poniżej.';
                                      }
                                    });
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      setDlgState(() => errMsg =
                                          'Błąd wyszukiwania: $e');
                                    }
                                  } finally {
                                    if (ctx.mounted) {
                                      setDlgState(() => searching = false);
                                    }
                                  }
                                },
                          icon: searching
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search, size: 18),
                          label: const Text('Szukaj'),
                        ),
                      ],
                    ),
                    if (searchResults.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 150,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: searchResults.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, idx) {
                            final item = searchResults[idx];
                            final selected =
                                selectedEntryId == 'fw_${item.id}';
                            return InkWell(
                              onTap: () {
                                setDlgState(() {
                                  selectedEntryId = 'fw_${item.id}';
                                  titleCtrl.text = item.title;
                                  posterCtrl.text = item.posterUrl;
                                  descCtrl.text = item.plot;
                                  errMsg = null;
                                });
                              },
                              child: Container(
                                width: 92,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: selected
                                        ? const Color(0xFFE50914)
                                        : Colors.white24,
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius:
                                            const BorderRadius.vertical(
                                                top: Radius.circular(6)),
                                        child: item.posterUrl.isNotEmpty
                                            ? FastCachedImage(
                                                url: item.posterUrl,
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                              )
                                            : const Icon(Icons.movie),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Text(
                                        '${item.title} (${item.year})',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tytuł filmu / serialu',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: posterCtrl,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'URL plakatu (opcjonalnie)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                  if (isSeries) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: seasonCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Numer sezonu',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: episodeCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Numer odcinka',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: epTitleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tytuł odcinka (opcjonalnie)',
                        hintText: 'np. Pilot',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: linkCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Link wideo (cda.pl lub vider.info)',
                      hintText:
                          'https://www.cda.pl/video/... lub https://vider.info/vid/+f...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedLang,
                          decoration: const InputDecoration(
                            labelText: 'Wersja językowa',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            'Lektor PL',
                            'Dubbing PL',
                            'Napisy PL',
                            'PL',
                            'ENG',
                          ]
                              .map((l) =>
                                  DropdownMenuItem(value: l, child: Text(l)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setDlgState(() => selectedLang = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedQuality,
                          decoration: const InputDecoration(
                            labelText: 'Jakość',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const ['HD', '1080p', '720p', '480p']
                              .map((q) =>
                                  DropdownMenuItem(value: q, child: Text(q)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setDlgState(() => selectedQuality = v);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (errMsg != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errMsg!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Anuluj'),
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final entry = _buildEntryFromDialog(
                        prefillSeries: prefillSeries,
                        selectedEntryId: selectedEntryId,
                        isSeries: isSeries,
                        title: titleCtrl.text,
                        poster: posterCtrl.text,
                        desc: descCtrl.text,
                        linkUrl: linkCtrl.text,
                        lang: selectedLang,
                        quality: selectedQuality,
                        seasonNum: int.tryParse(seasonCtrl.text.trim()) ?? 1,
                        episodeNum: int.tryParse(episodeCtrl.text.trim()) ?? 1,
                        episodeTitle: epTitleCtrl.text,
                        onError: (e) => setDlgState(() => errMsg = e),
                      );
                      if (entry == null) return;
                      await _extraSources.addOrUpdateLocalMedia(entry);
                      if (!_settings.extraSourcesEnabled) {
                        _settings.setExtraSourcesEnabled(true);
                        _extraSources.notifyChanged();
                      }
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
              child: const Text('Tylko u mnie'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final entry = _buildEntryFromDialog(
                        prefillSeries: prefillSeries,
                        selectedEntryId: selectedEntryId,
                        isSeries: isSeries,
                        title: titleCtrl.text,
                        poster: posterCtrl.text,
                        desc: descCtrl.text,
                        linkUrl: linkCtrl.text,
                        lang: selectedLang,
                        quality: selectedQuality,
                        seasonNum: int.tryParse(seasonCtrl.text.trim()) ?? 1,
                        episodeNum: int.tryParse(episodeCtrl.text.trim()) ?? 1,
                        episodeTitle: epTitleCtrl.text,
                        onError: (e) => setDlgState(() => errMsg = e),
                      );
                      if (entry == null) return;

                      final pin = await _promptPinOrVerifyOwner();
                      if (pin == null || pin.isEmpty) return;

                      setDlgState(() {
                        busy = true;
                        errMsg = null;
                      });
                      final err = await _extraSources.publishGlobalMediaChange(
                        upsertMedia: entry,
                        pin: pin,
                      );
                      if (!ctx.mounted) return;
                      if (err != null) {
                        setDlgState(() {
                          busy = false;
                          errMsg = err;
                        });
                      } else {
                        if (!_settings.extraSourcesEnabled) {
                          _settings.setExtraSourcesEnabled(true);
                          _extraSources.notifyChanged();
                        }
                        Navigator.of(ctx).pop();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Opublikowano „${entry.title}” dla wszystkich użytkowników!',
                              ),
                            ),
                          );
                        }
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Opublikuj globalnie'),
            ),
          ],
        ),
      ),
    );
  }

  ExtraMediaEntry? _buildEntryFromDialog({
    required ExtraMediaEntry? prefillSeries,
    required String selectedEntryId,
    required bool isSeries,
    required String title,
    required String poster,
    required String desc,
    required String linkUrl,
    required String lang,
    required String quality,
    required int seasonNum,
    required int episodeNum,
    required String episodeTitle,
    required void Function(String err) onError,
  }) {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      onError('Wpisz lub wyszukaj tytuł filmu/serialu.');
      return null;
    }
    final linkErr = ExtraSourcesService.validateVideoLinkUrl(linkUrl);
    if (linkErr != null) {
      onError(linkErr);
      return null;
    }

    final mediaLink = ExtraMediaLink(
      url: linkUrl.trim(),
      lang: lang,
      quality: quality,
    );

    if (prefillSeries != null) {
      return prefillSeries.mergeSeriesEpisode(
        seasonNumber: seasonNum < 1 ? 1 : seasonNum,
        episodeNumber: episodeNum < 1 ? 1 : episodeNum,
        episodeTitle: episodeTitle.trim(),
        newLinks: [mediaLink],
      );
    }

    final safeSlug = cleanTitle
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final id = selectedEntryId.isNotEmpty
        ? selectedEntryId
        : '${isSeries ? 'ser' : 'mov'}_${safeSlug}_${DateTime.now().millisecondsSinceEpoch}';

    if (!isSeries) {
      final existing = _extraSources.findMediaById(id);
      final combinedLinks = <ExtraMediaLink>[
        if (existing != null && !existing.isSeries) ...existing.links,
        mediaLink,
      ];
      return ExtraMediaEntry(
        id: id,
        title: cleanTitle,
        posterUrl: poster.trim(),
        description: desc.trim(),
        category: 'Popularne filmy',
        isSeries: false,
        links: combinedLinks,
      );
    }

    final sNum = seasonNum < 1 ? 1 : seasonNum;
    final eNum = episodeNum < 1 ? 1 : episodeNum;
    final ep = ExtraEpisodeEntry(
      number: eNum,
      title: episodeTitle.trim().isNotEmpty
          ? episodeTitle.trim()
          : 'Odcinek $eNum',
      links: [mediaLink],
    );
    return ExtraMediaEntry(
      id: id,
      title: cleanTitle,
      posterUrl: poster.trim(),
      description: desc.trim(),
      category: 'Popularne seriale',
      isSeries: true,
      seasons: [ExtraSeasonEntry(number: sNum, episodes: [ep])],
    );
  }

  Future<void> _removeGlobalMedia(ExtraMediaEntry m) async {
    final pin = await _promptPinOrVerifyOwner();
    if (pin == null || pin.isEmpty) return;
    final err = await _extraSources.publishGlobalMediaChange(
      removeMediaId: m.id,
      pin: pin,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Usunięto „${m.title}” z chmury.')),
    );
  }

  Future<void> _showAddWebsiteSourceDialog() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    var selectedType = ExtraSourceType.wordpress;
    var selectedCategory = 'Popularne filmy';
    String? errMsg;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Dodaj stronę ze źródłem'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nazwa źródła',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Adres strony (URL)',
                    hintText: 'https://przyklad.pl',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<ExtraSourceType>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Typ adaptera',
                    border: OutlineInputBorder(),
                  ),
                  items: ExtraSourceType.values
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.displayName),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedType = v);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Kategoria główna',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    'Popularne filmy',
                    'Popularne seriale',
                    'Bajki dla dzieci',
                    'Familijne',
                    'Anime',
                  ]
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedCategory = v);
                  },
                ),
                if (errMsg != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errMsg!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Anuluj'),
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      var url = urlCtrl.text.trim();
                      if (url.endsWith('/')) {
                        url = url.substring(0, url.length - 1);
                      }
                      if (name.isEmpty || !url.startsWith('http')) {
                        setDlgState(
                            () => errMsg = 'Podaj nazwę oraz pełny URL.');
                        return;
                      }
                      final src = ExtraSourceConfig(
                        id: 'src_${DateTime.now().millisecondsSinceEpoch}',
                        name: name,
                        baseUrl: url,
                        type: selectedType,
                        category: selectedCategory,
                      );
                      await _extraSources.addLocalSource(src);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
              child: const Text('Tylko lokalnie'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      var url = urlCtrl.text.trim();
                      if (url.endsWith('/')) {
                        url = url.substring(0, url.length - 1);
                      }
                      if (name.isEmpty || !url.startsWith('http')) {
                        setDlgState(
                            () => errMsg = 'Podaj nazwę oraz pełny URL.');
                        return;
                      }
                      final pin = await _promptPinOrVerifyOwner();
                      if (pin == null || pin.isEmpty) return;
                      setDlgState(() {
                        busy = true;
                        errMsg = null;
                      });
                      final src = ExtraSourceConfig(
                        id: 'src_${DateTime.now().millisecondsSinceEpoch}',
                        name: name,
                        baseUrl: url,
                        type: selectedType,
                        category: selectedCategory,
                        isRemote: true,
                      );
                      final err = await _extraSources.publishGlobalSourcesChange(
                        addSource: src,
                        pin: pin,
                      );
                      if (!ctx.mounted) return;
                      if (err != null) {
                        setDlgState(() {
                          busy = false;
                          errMsg = err;
                        });
                      } else {
                        Navigator.of(ctx).pop();
                      }
                    },
              child: const Text('Opublikuj globalnie'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _publishOtaUpdate() async {
    final name = _updNameCtrl.text.trim();
    final ver = _updVersionCtrl.text.trim();
    final buildNum = int.tryParse(_updBuildCtrl.text.trim()) ?? 0;
    final desc = _updDescCtrl.text.trim();

    if (name.isEmpty || ver.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Podaj nazwę i wersję aktualizacji.')),
      );
      return;
    }

    final pin = await _promptPinOrVerifyOwner();
    if (pin == null || pin.isEmpty) return;

    setState(() {
      _publishingUpdate = true;
      _publishUpdateStatus = 'Rozpoczynanie publikacji...';
    });

    final err = await _updateService.publishUpdate(
      pin: pin,
      name: name,
      version: ver,
      buildNumber: buildNum,
      description: desc,
      channel: _updChannel,
      sourceType: _updSourceType,
      run: _selectedRun,
      artifact: _selectedArtifact,
      release: _selectedRelease,
      releaseAsset: _selectedReleaseAsset,
      onStatus: (st) {
        if (mounted) setState(() => _publishUpdateStatus = st);
      },
    );

    if (!mounted) return;
    setState(() {
      _publishingUpdate = false;
      _publishUpdateStatus = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err ??
              'Opublikowano aktualizację „$name” (${_updChannel == AppUpdateChannel.dev ? 'Deweloperska' : 'Wydanie'})!',
        ),
      ),
    );
  }

  Widget _buildMediaTab(ColorScheme colorScheme) {
    final remoteMedia = _extraSources.getRemoteMedia();
    final localMedia = _extraSources.getLocalMedia();
    final masterEnabled = _settings.extraSourcesEnabled;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: colorScheme.surfaceContainerHighest,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: SwitchListTile(
            value: masterEnabled,
            title: const Text(
              'Włącz Źródła dodatkowe',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Docchi.pl i Bajeczki.org są już w oficjalnych źródłach. Tutaj wyświetlają się wyłącznie dodane ręcznie filmy i seriale (CDA / Vider.info).',
            ),
            secondary: const Icon(Icons.extension_outlined),
            onChanged: (val) {
              _settings.setExtraSourcesEnabled(val);
              _extraSources.notifyChanged();
              if (val) _syncNow(silent: true);
            },
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => _showAddMediaDialog(),
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Dodaj film lub serial (CDA / Vider.info)'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Globalne (dla wszystkich użytkowników)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
              ),
        ),
        const SizedBox(height: 8),
        if (remoteMedia.isEmpty)
          Card(
            color: colorScheme.surfaceContainerHighest,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: const ListTile(
              leading: Icon(Icons.cloud_done_outlined),
              title: Text('Brak dodanych filmów lub seriali w chmurze'),
              subtitle: Text(
                'Pozycje opublikowane przez administratora pojawią się tutaj u wszystkich użytkowników.',
              ),
            ),
          )
        else
          ...remoteMedia.map((m) => _buildMediaCard(m, colorScheme, isRemote: true)),
        if (localMedia.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'Lokalne (tylko to urządzenie)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
          ),
          const SizedBox(height: 8),
          ...localMedia.map((m) => _buildMediaCard(m, colorScheme, isRemote: false)),
        ],
      ],
    );
  }

  Widget _buildMediaCard(
    ExtraMediaEntry m,
    ColorScheme colorScheme, {
    required bool isRemote,
  }) {
    final epCount = m.seasons.fold<int>(0, (acc, s) => acc + s.episodes.length);
    final nextEpNum = m.seasons.isNotEmpty && m.seasons.last.episodes.isNotEmpty
        ? m.seasons.last.episodes.last.number + 1
        : 1;
    final latestSeason = m.seasons.isNotEmpty ? m.seasons.last.number : 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 44,
            height: 62,
            child: m.posterUrl.isNotEmpty
                ? FastCachedImage(url: m.posterUrl, fit: BoxFit.cover)
                : const Icon(Icons.movie),
          ),
        ),
        title: Text(
          m.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          m.isSeries
              ? 'Serial • Sezony: ${m.seasons.length} • Odcinki: $epCount'
              : 'Film • Linki: ${m.links.map((l) => l.hostBadge).toSet().join(', ')}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.isSeries)
              IconButton(
                tooltip: 'Dodaj odcinek',
                icon: const Icon(Icons.playlist_add),
                onPressed: () => _showAddMediaDialog(
                  prefillSeries: m,
                  prefillSeason: latestSeason,
                  prefillEpisode: nextEpNum,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => isRemote
                  ? _removeGlobalMedia(m)
                  : _extraSources.removeLocalMedia(m.id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdatesTab(ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ValueListenableBuilder<AppUpdateInfo?>(
          valueListenable: _updateService.availableUpdate,
          builder: (context, avail, _) {
            return Card(
              color: colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Zainstalowana wersja: v$_installedVersion (build $_installedBuild)',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final res = await _updateService.checkForUpdates(
                                force: true);
                            if (!context.mounted) return;
                            if (res == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Masz najnowszą dostępną wersję.'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Sprawdź teraz'),
                        ),
                        if (avail != null) ...[
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: () =>
                                AppUpdateDialog.show(context, avail),
                            icon: const Icon(Icons.download, size: 18),
                            label: Text('Aktualizuj (${avail.version})'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        Text(
          'Panel Administratora • Publikacja aktualizacji (OTA)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
              ),
        ),
        const SizedBox(height: 8),
        if (!_hasOwnerCreds)
          Card(
            color: colorScheme.surfaceContainerHighest,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Wymagana weryfikacja administratora'),
              subtitle: const Text(
                'Zweryfikuj token GitHub (xxXigmatXxx) i PIN aby wybierać buildy (Artifacts / Releases) i publikować aktualizacje.',
              ),
              trailing: FilledButton(
                onPressed: _promptPinOrVerifyOwner,
                child: const Text('Zweryfikuj'),
              ),
            ),
          )
        else
          Card(
            color: colorScheme.surfaceContainerHighest,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1. Kto ma otrzymać aktualizację (Kanał)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Wydanie (wszyscy)')),
                          selected: _updChannel == AppUpdateChannel.release,
                          onSelected: _publishingUpdate
                              ? null
                              : (_) => setState(
                                    () => _updChannel = AppUpdateChannel.release,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(
                              child: Text('Deweloperska (admin)')),
                          selected: _updChannel == AppUpdateChannel.dev,
                          onSelected: _publishingUpdate
                              ? null
                              : (_) => setState(
                                    () => _updChannel = AppUpdateChannel.dev,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '2. Źródło z GitHub',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Odśwież listę z GitHub',
                        onPressed: _loadingGitHub ? null : _loadGitHubSources,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label:
                              const Center(child: Text('Artifacts (Buildy)')),
                          selected:
                              _updSourceType == AppUpdateSourceType.artifact,
                          onSelected: _publishingUpdate
                              ? null
                              : (_) {
                                  setState(() => _updSourceType =
                                      AppUpdateSourceType.artifact);
                                  _loadGitHubSources();
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('GitHub Release')),
                          selected: _updSourceType ==
                              AppUpdateSourceType.releaseAsset,
                          onSelected: _publishingUpdate
                              ? null
                              : (_) {
                                  setState(() => _updSourceType =
                                      AppUpdateSourceType.releaseAsset);
                                  _loadGitHubSources();
                                },
                        ),
                      ),
                    ],
                  ),
                  if (_loadingGitHub) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(),
                  ],
                  if (_githubLoadErr != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _githubLoadErr!,
                      style: TextStyle(color: colorScheme.error, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_updSourceType == AppUpdateSourceType.artifact) ...[
                    DropdownButtonFormField<GitHubWorkflowRunItem>(
                      isExpanded: true,
                      value: _selectedRun,
                      decoration: const InputDecoration(
                        labelText: 'Wybierz Build (GitHub Actions)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _runs
                          .map((r) => DropdownMenuItem(
                                value: r,
                                child: Text(
                                  '#${r.runNumber} • ${r.commitMessage}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (r) {
                        if (r != null) _selectRun(r);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<GitHubArtifactItem>(
                      isExpanded: true,
                      value: _selectedArtifact,
                      decoration: const InputDecoration(
                        labelText: 'Wybierz Artifact',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _artifacts
                          .map((a) => DropdownMenuItem(
                                value: a,
                                child: Text(
                                  '${a.name} (${(a.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (a) => setState(() => _selectedArtifact = a),
                    ),
                  ] else ...[
                    DropdownButtonFormField<GitHubReleaseItem>(
                      isExpanded: true,
                      value: _selectedRelease,
                      decoration: const InputDecoration(
                        labelText: 'Wybierz Release na GitHubie',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _releases
                          .map((r) => DropdownMenuItem(
                                value: r,
                                child: Text(
                                  '${r.tagName} • ${r.name}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (r) {
                        if (r == null) return;
                        setState(() {
                          _selectedRelease = r;
                          _selectedReleaseAsset =
                              r.assets.isNotEmpty ? r.assets.first : null;
                        });
                        _autoFillFromRelease(r);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<GitHubReleaseAssetItem>(
                      isExpanded: true,
                      value: _selectedReleaseAsset,
                      decoration: const InputDecoration(
                        labelText: 'Wybierz plik APK w Release',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: (_selectedRelease?.assets ??
                              const <GitHubReleaseAssetItem>[])
                          .map((a) => DropdownMenuItem(
                                value: a,
                                child: Text(
                                  '${a.name} (${(a.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (a) =>
                          setState(() => _selectedReleaseAsset = a),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text(
                    '3. Nazwa, wersja i opis aktualizacji',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _updNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nazwa aktualizacji',
                      hintText: 'np. PureVideo 1.0.98',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _updVersionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Wersja (np. 1.0.98)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _updBuildCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Numer buildu',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _updDescCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Opis zmian (dla użytkowników)',
                      hintText: 'Co nowego w tej wersji?',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_publishingUpdate) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    Text(
                      _publishUpdateStatus,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _publishingUpdate ? null : _publishOtaUpdate,
                      icon: const Icon(Icons.publish),
                      label: Text(_publishingUpdate
                          ? 'Publikowanie...'
                          : 'Opublikuj aktualizację'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAdminAndSitesTab(ColorScheme colorScheme) {
    final remoteSources = _extraSources.getRemoteSources();
    final localSources = _extraSources.getLocalSources();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: colorScheme.surfaceContainerHighest,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ListTile(
            leading: Icon(
              _hasOwnerCreds ? Icons.verified_user : Icons.lock_outline,
              color: _hasOwnerCreds ? Colors.greenAccent : null,
            ),
            title: Text(_hasOwnerCreds
                ? 'Panel Administratora aktywny (${_ownerLogin ?? ExtraSourcesService.repoOwner})'
                : 'Weryfikacja właściciela nieaktywna'),
            subtitle: Text(_hasOwnerCreds
                ? 'Masz dostęp do kanału Deweloperskiego, publikacji aktualizacji OTA oraz globalnych źródeł.'
                : 'Wymagana do publikacji globalnych treści, aktualizacji OTA oraz widoczności aktualizacji deweloperskich.'),
            trailing: _hasOwnerCreds
                ? TextButton(
                    onPressed: () async {
                      await _extraSources.clearOwnerVerification();
                      await _loadOwnerStatus();
                      await _updateService.checkForUpdates(force: true);
                    },
                    child: const Text('Wyloguj'),
                  )
                : FilledButton(
                    onPressed: () async {
                      await _promptPinOrVerifyOwner();
                      await _loadOwnerStatus();
                      await _updateService.checkForUpdates(force: true);
                    },
                    child: const Text('Zweryfikuj'),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Dodatkowe strony WWW (opcjonalne)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
              ),
            ),
            TextButton.icon(
              onPressed: _showAddWebsiteSourceDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Dodaj stronę'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (remoteSources.isEmpty && localSources.isEmpty)
          Card(
            color: colorScheme.surfaceContainerHighest,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: const ListTile(
              leading: Icon(Icons.language),
              title: Text('Brak dodatkowych stron WWW'),
              subtitle: Text(
                'Możesz tu opcjonalnie podłączyć zewnętrzny serwis wideo.',
              ),
            ),
          )
        else ...[
          ...remoteSources.map(
            (s) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: const Icon(Icons.public),
                title: Text(s.name),
                subtitle: Text('${s.baseUrl}\n${s.type.displayName}'),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final pin = await _promptPinOrVerifyOwner();
                    if (pin == null || pin.isEmpty) return;
                    await _extraSources.publishGlobalSourcesChange(
                      removeId: s.id,
                      pin: pin,
                    );
                  },
                ),
              ),
            ),
          ),
          ...localSources.map(
            (s) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: const Icon(Icons.smartphone),
                title: Text(s.name),
                subtitle: Text('${s.baseUrl}\nLokalne'),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _extraSources.removeLocalSource(s.id),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Źródła dodatkowe i Admin'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Synchronizuj teraz',
            onPressed: _syncing ? null : () => _syncNow(silent: false),
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.movie_outlined), text: 'Filmy i Seriale'),
            Tab(icon: Icon(Icons.system_update_alt), text: 'Aktualizacje'),
            Tab(icon: Icon(Icons.admin_panel_settings_outlined), text: 'Admin'),
          ],
        ),
      ),
      body: SettingsListenable(
        builder: (context, _, __) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildMediaTab(colorScheme),
              _buildUpdatesTab(colorScheme),
              _buildAdminAndSitesTab(colorScheme),
            ],
          );
        },
      ),
    );
  }
}
