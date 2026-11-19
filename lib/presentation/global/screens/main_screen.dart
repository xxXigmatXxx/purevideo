import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/core/utils/device_utils.dart';
import 'package:purevideo/di/injection_container.dart';

class MainScreen extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const MainScreen({super.key, required this.navigationShell});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      getIt<WatchedService>().dispose();
    }
  }

  void _onSelectBranch(int index) {
    if (index == widget.navigationShell.currentIndex) return;
    HapticFeedback.mediumImpact();
    widget.navigationShell.goBranch(
      index,
      initialLocation: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = DeviceUtils.isWideLayout(context);
    final currentIndex = widget.navigationShell.currentIndex;

    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && currentIndex != 0) {
          _onSelectBranch(0);
        }
      },
      child: isWide
          ? Scaffold(
              backgroundColor: Colors.black,
              body: Row(
                children: [
                  _TvSideNavigationRail(
                    currentIndex: currentIndex,
                    onTap: _onSelectBranch,
                  ),
                  Expanded(child: widget.navigationShell),
                ],
              ),
            )
          : Scaffold(
              body: widget.navigationShell,
              bottomNavigationBar: _CustomBottomNavigationBar(
                currentIndex: currentIndex,
                onTap: _onSelectBranch,
              ),
            ),
    );
  }
}

class _TvSideNavigationRail extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _TvSideNavigationRail({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        border: Border(
          right: BorderSide(color: Color(0xFF262626), width: 0.8),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            const Text(
              'P',
              style: TextStyle(
                color: Color(0xFFE50914),
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 24),
            _SideNavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_filled,
              label: 'Główna',
              isSelected: currentIndex == 0,
              onTap: () => onTap(0),
            ),
            const SizedBox(height: 12),
            _SideNavItem(
              icon: Icons.search_outlined,
              activeIcon: Icons.search,
              label: 'Szukaj',
              isSelected: currentIndex == 1,
              onTap: () => onTap(1),
            ),
            const SizedBox(height: 12),
            _SideNavItem(
              icon: Icons.video_library_outlined,
              activeIcon: Icons.video_library,
              label: 'Moje',
              isSelected: currentIndex == 2,
              onTap: () => onTap(2),
            ),
            const SizedBox(height: 12),
            _SideNavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: 'Ustawienia',
              isSelected: currentIndex == 3,
              onTap: () => onTap(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideNavItem extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SideNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SideNavItem> createState() => _SideNavItemState();
}

class _SideNavItemState extends State<_SideNavItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = Colors.white;
    final inactiveColor = Colors.white.withAlpha(140);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        onFocusChange: (f) {
          if (mounted) setState(() => _focused = f);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 76,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: _focused
                ? Colors.white.withAlpha(34)
                : (widget.isSelected
                    ? const Color(0xFFE50914).withAlpha(35)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: _focused
                ? Border.all(color: Colors.white, width: 2)
                : (widget.isSelected
                    ? Border.all(
                        color: const Color(0xFFE50914).withAlpha(140),
                        width: 1,
                      )
                    : null),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isSelected ? widget.activeIcon : widget.icon,
                size: 24,
                color: widget.isSelected || _focused
                    ? activeColor
                    : inactiveColor,
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight:
                      widget.isSelected ? FontWeight.w700 : FontWeight.w500,
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

class _CustomBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  const _CustomBottomNavigationBar({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        border: Border(
          top: BorderSide(color: Color(0xFF262626), width: 0.6),
        ),
      ),
      height: 60 + MediaQuery.of(context).padding.bottom,
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _NavBarItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_filled,
              label: 'Strona główna',
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
