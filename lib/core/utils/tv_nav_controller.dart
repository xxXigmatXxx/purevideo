import 'package:flutter/material.dart';

enum HomeTabFilter { all, series, movies }

/// Coordinates TV Top Navigation Bar, Update Banner, Home filter state,
/// and reliable cross-FocusScope D-pad traversal across StatefulShellRoute tabs.
class TvNavController {
  TvNavController._();
  static final TvNavController instance = TvNavController._();

  final ValueNotifier<HomeTabFilter> homeFilter =
      ValueNotifier<HomeTabFilter>(HomeTabFilter.all);

  // Update banner focus nodes
  final FocusNode updateBannerNode = FocusNode(debugLabel: 'tv_update_banner');
  final FocusNode updateBannerCloseNode =
      FocusNode(debugLabel: 'tv_update_close');

  // Top navigation bar focus nodes (left -> right visual order)
  final FocusNode topNavAccountsNode =
      FocusNode(debugLabel: 'tv_nav_accounts');
  final FocusNode topNavSearchNode = FocusNode(debugLabel: 'tv_nav_search');
  final FocusNode topNavHomeNode = FocusNode(debugLabel: 'tv_nav_home');
  final FocusNode topNavSeriesNode = FocusNode(debugLabel: 'tv_nav_series');
  final FocusNode topNavMoviesNode = FocusNode(debugLabel: 'tv_nav_movies');
  final FocusNode topNavMyListNode = FocusNode(debugLabel: 'tv_nav_mylist');
  final FocusNode topNavSettingsNode =
      FocusNode(debugLabel: 'tv_nav_settings');

  // Tab content entry focus nodes
  final FocusNode homeHeroPlayNode = FocusNode(debugLabel: 'tv_home_hero_play');
  final FocusNode homeGridFirstNode = FocusNode(debugLabel: 'tv_home_grid_first');
  final FocusNode searchInputNode = FocusNode(debugLabel: 'tv_search_input');
  final FocusNode searchButtonNode = FocusNode(debugLabel: 'tv_search_button');
  final FocusNode myListFirstNode = FocusNode(debugLabel: 'tv_mylist_first');
  final FocusNode settingsFirstNode = FocusNode(debugLabel: 'tv_settings_first');

  VoidCallback? scrollHomeToTop;
  VoidCallback? focusHomeTab;
  bool Function()? handleHomeUpAtEdge;

  List<FocusNode> get orderedTopNavNodes => [
        topNavAccountsNode,
        topNavSearchNode,
        topNavHomeNode,
        topNavSeriesNode,
        topNavMoviesNode,
        topNavMyListNode,
        topNavSettingsNode,
      ];

  bool isUpdateBannerFocused() =>
      updateBannerNode.hasFocus || updateBannerCloseNode.hasFocus;

  bool isTopNavFocused() => orderedTopNavNodes.any((n) => n.hasFocus);

  void focusActiveTopNav(int branchIndex) {
    FocusNode target;
    switch (branchIndex) {
      case 1:
        target = topNavSearchNode;
        break;
      case 2:
        target = topNavMyListNode;
        break;
      case 3:
        target = topNavSettingsNode;
        break;
      case 0:
      default:
        switch (homeFilter.value) {
          case HomeTabFilter.series:
            target = topNavSeriesNode;
            break;
          case HomeTabFilter.movies:
            target = topNavMoviesNode;
            break;
          case HomeTabFilter.all:
            target = topNavHomeNode;
            break;
        }
        break;
    }
    if (target.canRequestFocus) {
      target.requestFocus();
    }
  }
}
