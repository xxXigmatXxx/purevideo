import 'package:flutter/material.dart';

enum HomeTabFilter { all, series, movies }

/// Coordinates TV Top Navigation Bar, Home filter state, and focus return without side-rail bugs.
class TvNavController {
  TvNavController._();
  static final TvNavController instance = TvNavController._();

  final ValueNotifier<HomeTabFilter> homeFilter =
      ValueNotifier<HomeTabFilter>(HomeTabFilter.all);

  final FocusNode topNavSearchNode = FocusNode(debugLabel: 'tv_nav_search');
  final FocusNode topNavHomeNode = FocusNode(debugLabel: 'tv_nav_home');
  final FocusNode topNavSeriesNode = FocusNode(debugLabel: 'tv_nav_series');
  final FocusNode topNavMoviesNode = FocusNode(debugLabel: 'tv_nav_movies');
  final FocusNode topNavMyListNode = FocusNode(debugLabel: 'tv_nav_mylist');
  final FocusNode topNavSettingsNode = FocusNode(debugLabel: 'tv_nav_settings');

  VoidCallback? scrollHomeToTop;

  bool isTopNavFocused() {
    return topNavSearchNode.hasFocus ||
        topNavHomeNode.hasFocus ||
        topNavSeriesNode.hasFocus ||
        topNavMoviesNode.hasFocus ||
        topNavMyListNode.hasFocus ||
        topNavSettingsNode.hasFocus;
  }

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
