import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../stores/connection_store.dart';
import '../theme.dart';
import '../widgets/cta_button.dart';
import '../widgets/labeled_field.dart';
import '../widgets/note_box.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/og_button.dart';
import '../widgets/status_line.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.deps});

  final AppDeps deps;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  bool _tested = false;

  @override
  void initState() {
    super.initState();
    final ConnectionStore c = widget.deps.connection;
    _url = TextEditingController(text: c.settings.serverUrl);
    _token = TextEditingController(text: c.settings.token);
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() => _tested = true);
    await widget.deps.connection.save(_url.text, _token.text);
  }

  String _result(ConnectionStore c) {
    if (c.connected) {
      return 'Connected. Changes you make are sent as soon as you are online.';
    }
    return c.error ?? 'Not connected.';
  }

  @override
  Widget build(BuildContext context) {
    final ConnectionStore c = widget.deps.connection;
    return ListenableBuilder(
      listenable: c,
      builder: (BuildContext context, Widget? child) {
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          OgIconButton(
                            icon: Icons.chevron_left,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text('Settings', style: OG.display(32))),
                        ],
                      ),
                      const SizedBox(height: 18),
                      LabeledField(
                        label: 'Convex URL',
                        controller: _url,
                        hint: 'https://<name>.convex.cloud',
                        keyboardType: TextInputType.url,
                      ),
                      const SizedBox(height: 14),
                      LabeledField(
                        label: 'Token',
                        controller: _token,
                        hint: 'Paste the token',
                        obscure: true,
                      ),
                      const SizedBox(height: 14),
                      OgButton(
                        onPressed: c.checking ? null : _test,
                        child: Text(c.checking ? 'Testing…' : 'Test connection'),
                      ),
                      if (_tested && !c.checking) ...<Widget>[
                        const SizedBox(height: 14),
                        StatusLine(text: _result(c), connected: c.connected),
                      ],
                      const SizedBox(height: 22),
                      const NoteBox(
                        title: 'Where do I find these?',
                        message: 'The Convex URL is the address of your hosted '
                            'backend. It ends in .convex.cloud. The token is the '
                            'app token you set for that backend. Without them the '
                            'app still works: everything is saved on this phone '
                            'and is sent when you connect.',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: CtaButton(
                    label: 'Done',
                    icon: Icons.check,
                    onPressed: () {
                      // Save what was typed; the check runs in the background.
                      c.save(_url.text, _token.text);
                      Navigator.of(context).pop();
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
}
