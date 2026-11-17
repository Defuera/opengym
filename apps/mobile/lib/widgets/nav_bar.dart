import 'package:flutter/material.dart';

import '../theme.dart';

/// Bottom bar: Home and Chat.
class NavBar extends StatelessWidget {
  const NavBar({
    super.key,
    required this.onHome,
    required this.onChat,
    this.homeSelected = true,
  });

  final VoidCallback onHome;
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
