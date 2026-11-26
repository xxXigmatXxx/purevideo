import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/core/services/app_update_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/core/utils/device_utils.dart';
import 'package:purevideo/core/utils/tv_nav_controller.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/global/widgets/purevideo_logo.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';
import 'package:purevideo/presentation/settings/widgets/app_update_dialog.dart';

class MainScreen extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainScreen({super.key, required this.navigationShell});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  bool _dismissedBanner = false;
  String? _autoPromptedUpdateId;
  final TvNavController _tvNav = TvNavController.instance;

  bool _hasVisibleUpdateBanner() {
    return getIt<AppUpdateService>().availableUpdate.value != null &&
        !_dismissedBanner;
  }

  Widget _buildUpdateBanner(BuildContext context) {
    return ValueListenableBuilder<AppUpdateInfo?>(
      valueListenable: getIt<AppUpdateService>().availableUpdate,
      builder: (context, update, _) {
        if (update == null || _dismissedBanner) {
          return const SizedBox.shrink();
        }
        final isDev = update.channel == AppUpdateChannel.dev;
        return Material(
          color: isDev ? const Color(0xFF4A3800) : const Color(0xFFB71C1C),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: TvFocusable(
                      focusNode: _tvNav.updateBannerNode,
                      ensureVisibleOnFocus: false,
                      focusScale: 1.0,
                      focusBorderColor: Colors.white,
                      focusBorderWidth: 2.5,
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => AppUpdateDialog.show(context, update),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              Icons.system_update,
                              color: isDev ? Colors.amberAccent : Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Dostępna nowa wersja: ${update.name} (v${update.version}) • Kliknij aby pobrać',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TvFocusable(
                    focusNode: _tvNav.updateBannerCloseNode,
                    ensureVisibleOnFocus: false,
                    focusScale: 1.0,
                    focusBorderColor: Colors.white,
                    focusBorderWidth: 2.0,
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      final idx = widget.navigationShell.currentIndex;
                      setState(() => _dismissedBanner = true);
                      _tvNav.focusActiveTopNav(idx);
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final updateNotifier = getIt<AppUpdateService>().availableUpdate;
    updateNotifier.addListener(_onAvailableUpdateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onAvailableUpdateChanged();
    });
  }

  void _onAvailableUpdateChanged() {
    if (!mounted) return;
    final upd = getIt<AppUpdateService>().availableUpdate.value;
    if (upd == null || _autoPromptedUpdateId == upd.id) return;
    _autoPromptedUpdateId = upd.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppUpdateDialog.show(context, upd);
    });
  }

  @override
  void dispose() {
    getIt<AppUpdateService>().availableUpdate.removeListener(
      _onAvailableUpdateChanged,
    );
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      getIt<WatchedService>().dispose();
    }
  }

  void _focusActiveTabContent(int index) {
    switch (index) {
      case 1:
        if (_tvNav.searchInputNode.canRequestFocus) {
          _tvNav.searchInputNode.requestFocus();
        } else if (_tvNav.searchButtonNode.canRequestFocus) {
          _tvNav.searchButtonNode.requestFocus();
        }
        break;
      case 2:
        if (_tvNav.myListFirstNode.canRequestFocus) {
          _tvNav.myListFirstNode.requestFocus();
        }
        break;
      case 3:
        if (_tvNav.settingsFirstNode.canRequestFocus) {
          _tvNav.settingsFirstNode.requestFocus();
        }
        break;
      case 0:
      default:
        _tvNav.focusHomeTab?.call();
        break;
    }
  }

  Object? _handleTvDirectionalFocus(
      DirectionalFocusIntent intent, int currentIndex) {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) {
      _tvNav.focusActiveTopNav(currentIndex);
      return null;
    }

    // 1. Update banner navigation
    if (_tvNav.isUpdateBannerFocused()) {
      switch (intent.direction) {
        case TraversalDirection.down:
          _tvNav.focusActiveTopNav(currentIndex);
          return null;
        case TraversalDirection.right:
          if (_tvNav.updateBannerNode.hasFocus &&
              _tvNav.updateBannerCloseNode.canRequestFocus) {
            _tvNav.updateBannerCloseNode.requestFocus();
          }
          return null;
        case TraversalDirection.left:
          if (_tvNav.updateBannerCloseNode.hasFocus &&
              _tvNav.updateBannerNode.canRequestFocus) {
            _tvNav.updateBannerNode.requestFocus();
          }
          return null;
        case TraversalDirection.up:
          return null;
      }
    }

    // 2. Top Navigation Bar (Accounts, Szukaj, Główna, Seriale, Filmy, Moja lista, Ustawienia)
    if (_tvNav.isTopNavFocused()) {
      final nodes = _tvNav.orderedTopNavNodes;
      final idx = nodes.indexWhere((n) => n.hasFocus);
      switch (intent.direction) {
        case TraversalDirection.left:
          if (idx > 0 && nodes[idx - 1].canRequestFocus) {
            nodes[idx - 1].requestFocus();
          }
          return null;
        case TraversalDirection.right:
          if (idx >= 0 &&
              idx < nodes.length - 1 &&
              nodes[idx + 1].canRequestFocus) {
            nodes[idx + 1].requestFocus();
          }
          return null;
        case TraversalDirection.up:
          if (_hasVisibleUpdateBanner() &&
              _tvNav.updateBannerNode.canRequestFocus) {
            _tvNav.updateBannerNode.requestFocus();
          }
          return null;
        case TraversalDirection.down:
          _focusActiveTabContent(currentIndex);
          return null;
      }
    }

    // 3. Inside tab content (nested Navigator FocusScope):
    // Try standard traversal inside tab; if UP hits top edge, jump cleanly to Top Nav!
    final moved = primary.focusInDirection(intent.direction);
    if (!moved && intent.direction == TraversalDirection.up) {
      if (currentIndex == 0 && (_tvNav.handleHomeUpAtEdge?.call() ?? false)) {
        return null;
      }
      _tvNav.focusActiveTopNav(currentIndex);
    }
    return null;
  }

  void _onSelectBranch(int index, {HomeTabFilter? homeFilter}) {
    final wasSameBranch = index == widget.navigationShell.currentIndex;
    final prevFilter = _tvNav.homeFilter.value;
    if (homeFilter != null) {
      _tvNav.homeFilter.value = homeFilter;
    }
    final isSameView =
        wasSameBranch && (homeFilter == null || prevFilter == homeFilter);
    if (index == 0) {
      _tvNav.scrollHomeToTop?.call();
    }
    if (!wasSameBranch) {
      HapticFeedback.selectionClick();
      widget.navigationShell.goBranch(
        index,
        initialLocation: false,
      );
      if (DeviceUtils.isTv && index != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusActiveTabContent(index);
        });
      }
    } else if (DeviceUtils.isTv && isSameView) {
      // Pressing OK on the already-selected pill moves focus into its content
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusActiveTabContent(index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = DeviceUtils.isWideLayout(context);
    final currentIndex = widget.navigationShell.currentIndex;

    return PopScope(
      canPop: !isWide && currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isWide) {
          if (_tvNav.isUpdateBannerFocused()) {
            _tvNav.focusActiveTopNav(currentIndex);
            return;
          }
          if (currentIndex != 0) {
            _onSelectBranch(0, homeFilter: HomeTabFilter.all);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _tvNav.focusActiveTopNav(0);
            });
            return;
          }
          if (!_tvNav.isTopNavFocused()) {
            _tvNav.scrollHomeToTop?.call();
            _tvNav.focusActiveTopNav(0);
            return;
          }
          // Already at top bar on Home -> allow exit
          SystemNavigator.pop();
        } else if (currentIndex != 0) {
          _onSelectBranch(0);
        }
      },
      child: isWide
          ? Scaffold(
              backgroundColor: const Color(0xFF0A0A0D),
              body: Actions(
                actions: <Type, Action<Intent>>{
                  DirectionalFocusIntent:
                      CallbackAction<DirectionalFocusIntent>(
                    onInvoke: (intent) =>
                        _handleTvDirectionalFocus(intent, currentIndex),
                  ),
                },
                child: Column(
                  children: [
                    _buildUpdateBanner(context),
                  ValueListenableBuilder<HomeTabFilter>(
                    valueListenable: _tvNav.homeFilter,
                    builder: (context, homeFilter, _) {
                      return _TvTopNavigationBar(
                        currentIndex: currentIndex,
                        homeFilter: homeFilter,
                        tvNav: _tvNav,
                        onSelectSearch: () => _onSelectBranch(1),
                        onSelectHome: () =>
                            _onSelectBranch(0, homeFilter: HomeTabFilter.all),
                        onSelectSeries: () => _onSelectBranch(0,
                            homeFilter: HomeTabFilter.series),
                        onSelectMovies: () => _onSelectBranch(0,
                            homeFilter: HomeTabFilter.movies),
                        onSelectMyList: () => _onSelectBranch(2),
                        onSelectSettings: () => _onSelectBranch(3),
                        onOpenAccounts: () => context.pushNamed('accounts'),
                      );
                    },
                  ),
                  Expanded(child: widget.navigationShell),
                ],
                ),
              ),
            )
          : Scaffold(
              body: Column(
                children: [
                  _buildUpdateBanner(context),
                  Expanded(child: widget.navigationShell),
                ],
              ),
              bottomNavigationBar: _CustomBottomNavigationBar(
                currentIndex: currentIndex,
                onTap: (i) => _onSelectBranch(i),
              ),
            ),
    );
  }
}

class _TvTopNavigationBar extends StatelessWidget {
  final int currentIndex;
  final HomeTabFilter homeFilter;
  final TvNavController tvNav;
  final VoidCallback onSelectSearch;
  final VoidCallback onSelectHome;
  final VoidCallback onSelectSeries;
  final VoidCallback onSelectMovies;
  final VoidCallback onSelectMyList;
  final VoidCallback onSelectSettings;
  final VoidCallback onOpenAccounts;

  const _TvTopNavigationBar({
    required this.currentIndex,
    required this.homeFilter,
    required this.tvNav,
    required this.onSelectSearch,
    required this.onSelectHome,
    required this.onSelectSeries,
    required this.onSelectMovies,
    required this.onSelectMyList,
    required this.onSelectSettings,
    required this.onOpenAccounts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0A0A0D),
            Color(0xE80A0A0D),
            Color(0x880A0A0D),
          ],
        ),
      ),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Row(
          children: [
            // Left: Profile / Konta switcher
            FocusTraversalOrder(
              order: const NumericFocusOrder(0),
              child: TvFocusable(
                focusNode: tvNav.topNavAccountsNode,
                borderRadius: BorderRadius.circular(10),
                focusScale: 1.04,
                ensureVisibleOnFocus: false,
                onTap: onOpenAccounts,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [kPureVideoRed, Color(0xFF7D0008)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
            // Center: Floating Netflix-style Pill Nav Bar
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: _TopNavPill(
                    focusNode: tvNav.topNavSearchNode,
                    icon: Icons.search_rounded,
                    isSelected: currentIndex == 1,
                    onTap: onSelectSearch,
                  ),
                ),
                const SizedBox(width: 6),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: _TopNavPill(
                    focusNode: tvNav.topNavHomeNode,
                    label: 'Główna',
                    isSelected:
                        currentIndex == 0 && homeFilter == HomeTabFilter.all,
                    onTap: onSelectHome,
                  ),
                ),
                const SizedBox(width: 6),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(3),
                  child: _TopNavPill(
                    focusNode: tvNav.topNavSeriesNode,
                    label: 'Seriale',
                    isSelected:
                        currentIndex == 0 && homeFilter == HomeTabFilter.series,
                    onTap: onSelectSeries,
                  ),
                ),
                const SizedBox(width: 6),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(4),
                  child: _TopNavPill(
                    focusNode: tvNav.topNavMoviesNode,
                    label: 'Filmy',
                    isSelected:
                        currentIndex == 0 && homeFilter == HomeTabFilter.movies,
                    onTap: onSelectMovies,
                  ),
                ),
                const SizedBox(width: 6),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(5),
                  child: _TopNavPill(
                    focusNode: tvNav.topNavMyListNode,
                    label: 'Moja lista',
                    isSelected: currentIndex == 2,
                    onTap: onSelectMyList,
                  ),
                ),
                const SizedBox(width: 6),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(6),
                  child: _TopNavPill(
                    focusNode: tvNav.topNavSettingsNode,
                    label: 'Ustawienia',
                    isSelected: currentIndex == 3,
                    onTap: onSelectSettings,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Right: Unified PureVideo Wordmark matching icon & TV banner 1:1
            const PureVideoWordmark(height: 24),
          ],
        ),
      ),
    );
  }
}

class _TopNavPill extends StatefulWidget {
  final FocusNode? focusNode;
  final IconData? icon;
  final String? label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TopNavPill({
    this.focusNode,
    this.icon,
    this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TopNavPill> createState() => _TopNavPillState();
}

class _TopNavPillState extends State<_TopNavPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = _focused
        ? Colors.white.withAlpha(64)
        : (widget.isSelected
            ? Colors.white.withAlpha(42)
            : Colors.transparent);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        focusNode: widget.focusNode,
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(999),
        onFocusChange: (f) {
          if (mounted) setState(() => _focused = f);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: widget.icon != null && widget.label == null ? 14 : 18,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 2.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null)
                Icon(
                  widget.icon,
                  size: 20,
                  color: widget.isSelected || _focused
                      ? Colors.white
                      : Colors.white70,
                ),
              if (widget.icon != null && widget.label != null)
                const SizedBox(width: 6),
              if (widget.label != null)
                Text(
                  widget.label!,
                  style: TextStyle(
                    color: widget.isSelected || _focused
                        ? Colors.white
                        : Colors.white70,
                    fontSize: 14.5,
                    fontWeight: widget.isSelected || _focused
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _CustomBottomNavigationBar({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        border: Border(
          top: BorderSide(
            color: Colors.white.withAlpha(20),
            width: 0.6,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavBarItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_filled,
                label: 'Główna',
                isSelected: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavBarItem(
                icon: Icons.search_outlined,
                activeIcon: Icons.search,
                label: 'Szukaj',
                isSelected: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              _NavBarItem(
                icon: Icons.video_library_outlined,
                activeIcon: Icons.video_library,
                label: 'Moje PureVideo',
                isSelected: currentIndex == 2,
                onTap: () => onTap(2),
              ),
              _NavBarItem(
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                label: 'Ustawienia',
                isSelected: currentIndex == 3,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_NavBarItem> createState() => _NavBarItemState();
}

class _NavBarItemState extends State<_NavBarItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = Colors.white;
    final inactiveColor = Colors.white.withAlpha(130);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        onFocusChange: (f) {
          if (mounted) setState(() => _focused = f);
        },
        child: Container(
          width: 82,
          decoration: _focused
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 1.8),
                  color: Colors.white.withAlpha(24),
                )
              : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isSelected ? widget.activeIcon : widget.icon,
                size: 24,
                color: widget.isSelected || _focused
                    ? activeColor
                    : inactiveColor,
              ),
              const SizedBox(height: 3),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: widget.isSelected || _focused
                      ? activeColor
                      : inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
