import 'package:flutter/material.dart';

import '../../../shared/ui.dart';
import '../data/gemini_brain.dart';

/// Free Google Gemini key: used for fast food ideas, before the on-device model.
class GeminiCard extends StatefulWidget {
  const GeminiCard({super.key});
  @override
  State<GeminiCard> createState() => _GeminiCardState();
}

class _GeminiCardState extends State<GeminiCard> {
  bool? _hasKey;
  final _keyCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    GeminiBrain.instance.apiKey().then((k) => mounted ? setState(() => _hasKey = k != null) : null);
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
            leading: Icon(Icons.bolt),
            title: Text('Free Gemini key', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Fast food ideas in about 2 seconds. Without it, Buddy uses the slower on-device model.'),
          ),
          if (_hasKey == true)
            Row(children: [
              const Icon(Icons.key, size: 18, color: Colors.green),
              const SizedBox(width: 6),
              const Expanded(child: Text('Gemini key saved (encrypted)')),
              TextButton(
                onPressed: () async {
                  await GeminiBrain.instance.setApiKey(null);
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
                  decoration: const InputDecoration(labelText: 'Gemini API key', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  if (_keyCtl.text.trim().isEmpty) return;
                  await GeminiBrain.instance.setApiKey(_keyCtl.text);
                  _keyCtl.clear();
                  setState(() => _hasKey = true);
                },
                child: const Text('Save'),
              ),
            ]),
        ]),
      );
}
