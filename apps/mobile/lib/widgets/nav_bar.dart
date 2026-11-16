import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';

/// Bottom bar: Home, the big plus, Chat.
class NavBar extends StatelessWidget {
  const NavBar({
    super.key,
    required this.onHome,
    required this.onPlus,
    required this.onChat,
    this.homeSelected = true,
  });

  final VoidCallback onHome;
  final VoidCallback onPlus;
  final VoidCallback onChat;
  final bool homeSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: const BoxDecoration(
        color: OG.card,
        border: Border(top: BorderSide(color: OG.ink, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: _Tab(
              icon: Icons.home_outlined,
              label: 'Home',
              selected: homeSelected,
              onTap: onHome,
            ),
          ),
          SizedBox(
            width: 84,
            height: 88,
            child: OgButton(
              variant: OgVariant.accent,
              minHeight: 84,
              radius: 22,
              padding: EdgeInsets.zero,
              onPressed: onPlus,
              child: const Icon(Icons.add, size: 44),
            ),
          ),
          Expanded(
            child: _Tab(
              icon: Icons.chat_bubble_outline,
              label: 'Chat',
              selected: !homeSelected,
              onTap: onChat,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color c = selected ? OG.ink : OG.mute;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 30, color: c),
            const SizedBox(height: 2),
            Text(
              label,
              style: OG.body(
                size: 14,
                weight: selected ? FontWeight.w800 : FontWeight.w600,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
