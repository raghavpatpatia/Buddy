import 'package:flutter/material.dart';

import '../../../shared/ui.dart';
import '../data/openrouter_brain.dart';

/// Free OpenRouter key: backup for food ideas when Gemini is over its limit, before the on-device model.
class OpenRouterCard extends StatefulWidget {
  const OpenRouterCard({super.key});
  @override
  State<OpenRouterCard> createState() => _OpenRouterCardState();
}

class _OpenRouterCardState extends State<OpenRouterCard> {
  bool? _hasKey;
  final _keyCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    OpenRouterBrain.instance.apiKey().then((k) => mounted ? setState(() => _hasKey = k != null) : null);
  }

  @override
  void dispose() {
    _keyCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.alt_route),
            title: Text('Free OpenRouter key', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Backup when Gemini is busy or over its daily limit. Only free models are used, so it never costs anything.'),
          ),
          if (_hasKey == true)
            Row(children: [
              const Icon(Icons.key, size: 18, color: Colors.green),
              const SizedBox(width: 6),
              const Expanded(child: Text('OpenRouter key saved (encrypted)')),
              TextButton(
                onPressed: () async {
                  await OpenRouterBrain.instance.setApiKey(null);
                  setState(() => _hasKey = false);
                },
                child: const Text('Remove'),
              ),
            ])
          else
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _keyCtl,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'OpenRouter API key', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  if (_keyCtl.text.trim().isEmpty) return;
                  await OpenRouterBrain.instance.setApiKey(_keyCtl.text);
                  _keyCtl.clear();
                  setState(() => _hasKey = true);
                },
                child: const Text('Save'),
              ),
            ]),
        ]),
      );
}
