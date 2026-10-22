import 'dart:convert';

import 'package:flutter/material.dart';

import '../../astro/model/places.dart';
import '../controller/job_profile_form.dart';
import '../model/job_profile.dart';
import '../model/roles.dart';

/// Asks for current job, experience, target roles, field, skills and place; returns the new profile or null.
/// [onReset] adds a "Start over" button that clears the profile and saved jobs.
Future<JobProfile?> showJobProfileSheet(BuildContext context, JobProfile p, {VoidCallback? onReset}) => showModalBottomSheet<JobProfile>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  builder: (_) => _ProfileSheet(p, onReset),
);

const _fields = ['Game development', 'Fintech', 'AI / ML', 'Web apps', 'Mobile apps', 'E-commerce', 'Health tech'];

class _ProfileSheet extends StatefulWidget {
  final JobProfile profile;
  final VoidCallback? onReset;
  const _ProfileSheet(this.profile, this.onReset);
  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late final form = JobProfileForm(widget.profile);
  late final title = TextEditingController(text: widget.profile.currentTitle);
  late final focus = TextEditingController(text: widget.profile.focus);
  late final city = TextEditingController(text: widget.profile.city);
  late final country = TextEditingController(text: widget.profile.country);
  final skill = TextEditingController();
  final cityFocus = FocusNode();

  @override
  void dispose() {
    for (final t in [title, focus, city, country, skill]) {
      t.dispose();
    }
    cityFocus.dispose();
    form.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    final r = await form.detect();
    if (!mounted) return;
    if (r == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t find your location. Type your city instead.')));
      return;
    }
    city.text = r.$1;
    country.text = r.$2;
  }

  void _addSkill() {
    form.addSkills(skill.text);
    skill.clear();
  }

  JobProfile _draft() => form.build(title: title.text, focus: focus.text, city: city.text, country: country.text);

  bool get _dirty => skill.text.trim().isNotEmpty || jsonEncode(_draft().toJson()) != jsonEncode(widget.profile.toJson());

  Future<void> _confirmClose() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your job profile edits will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Discard')),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  Future<void> _startOver() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Start over?'),
        content: const Text('This clears your job profile and saved jobs.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Start over')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.pop(context);
    widget.onReset!();
  }

  void _save() {
    if (skill.text.trim().isNotEmpty) _addSkill();
    Navigator.pop(context, _draft());
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_dirty) {
          _confirmClose();
        } else {
          Navigator.pop(context);
        }
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ListenableBuilder(
          listenable: form,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  children: [
                    Text(widget.profile.setUp ? 'Your job profile' : 'Let\'s find you a job', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      'Buddy uses this to search job sites and rank every opening for you. It stays on your phone.',
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    _label(context, 'Your current job'),
                    TextField(
                      controller: title,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'e.g. Game Developer, Student', border: OutlineInputBorder(), counterText: ''),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: Text('Experience', style: tt.bodyLarge)),
                        IconButton.filledTonal(
                          tooltip: 'Fewer years',
                          onPressed: form.years > 0 ? () => form.setYears(form.years - 1) : null,
                          icon: const Icon(Icons.remove),
                        ),
                        SizedBox(
                          width: 72,
                          child: Text(
                            form.years == 0 ? '< 1 yr' : '${form.years} yr${form.years == 1 ? '' : 's'}',
                            textAlign: TextAlign.center,
                            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'More years',
                          onPressed: form.years < 40 ? () => form.setYears(form.years + 1) : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    _label(context, 'Roles you want', hint: 'Pick one or more'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final r in roleOptions)
                          FilterChip(label: Text(r.label), selected: form.roles.contains(r.id), onSelected: (_) => form.toggleRole(r.id)),
                      ],
                    ),
                    _label(context, 'Field', hint: 'What kind of work or industry'),
                    TextField(
                      controller: focus,
                      maxLength: 60,
                      decoration: InputDecoration(
                        hintText: 'Any field',
                        border: const OutlineInputBorder(),
                        counterText: '',
                        suffixIcon: ListenableBuilder(
                          listenable: focus,
                          builder: (_, _) => focus.text.isEmpty
                              ? const SizedBox.shrink()
                              : IconButton(tooltip: 'Any field', onPressed: focus.clear, icon: const Icon(Icons.clear)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListenableBuilder(
                      listenable: focus,
                      builder: (_, _) => Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final f in _fields)
                            ChoiceChip(label: Text(f), selected: focus.text.trim().toLowerCase() == f.toLowerCase(), onSelected: (_) => focus.text = f),
                        ],
                      ),
                    ),
                    _label(context, 'Your skills', hint: '${form.skills.length}/${JobProfileForm.maxSkills}'),
                    TextField(
                      controller: skill,
                      textInputAction: TextInputAction.done,
                      onEditingComplete: _addSkill,
                      decoration: InputDecoration(
                        hintText: 'Type a skill, e.g. C++',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(tooltip: 'Add skill', onPressed: _addSkill, icon: const Icon(Icons.add_circle)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (form.skills.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final s in form.skills) InputChip(label: Text(s), onDeleted: () => form.removeSkill(s))],
                      ),
                    const SizedBox(height: 6),
                    ListenableBuilder(
                      listenable: focus,
                      builder: (_, _) => Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in form.suggestions(focus.text))
                            ActionChip(
                              avatar: const Icon(Icons.add, size: 16),
                              label: Text(s),
                              visualDensity: VisualDensity.compact,
                              onPressed: form.skills.length < JobProfileForm.maxSkills ? () => form.addSkills(s) : null,
                            ),
                        ],
                      ),
                    ),
                    _label(context, 'Where'),
                    RawAutocomplete<String>(
                      textEditingController: city,
                      focusNode: cityFocus,
                      optionsBuilder: (v) {
                        final q = v.text.trim().toLowerCase();
                        if (q.isEmpty) return const [];
                        return places.map((p) => p.$1).where((n) => n.toLowerCase().startsWith(q) && n.toLowerCase() != q).take(6);
                      },
                      fieldViewBuilder: (context, ctl, node, _) => TextField(
                        controller: ctl,
                        focusNode: node,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'City', border: OutlineInputBorder(), prefixIcon: Icon(Icons.place_outlined)),
                      ),
                      optionsViewBuilder: (context, onSelected, options) => Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: 240, maxWidth: MediaQuery.sizeOf(context).width - 40),
                            child: ListView(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              children: [for (final o in options) ListTile(dense: true, title: Text(o), onTap: () => onSelected(o))],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: country,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Country', border: OutlineInputBorder(), prefixIcon: Icon(Icons.flag_outlined)),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: form.locating ? null : _detect,
                        icon: form.locating
                            ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.my_location),
                        label: const Text('Use my location'),
                      ),
                    ),
                    _label(context, 'Search'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in JobScope.values)
                          ChoiceChip(
                            label: Text(switch (s) {
                              JobScope.near => 'Near me',
                              JobScope.country => 'My country',
                              JobScope.remote => 'Remote',
                              JobScope.worldwide => 'Anywhere',
                            }),
                            selected: form.scope == s,
                            onSelected: (_) => form.setScope(s),
                          ),
                      ],
                    ),
                    if (widget.onReset != null && widget.profile.setUp) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: TextButton.icon(
                          onPressed: _startOver,
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Start over'),
                          style: TextButton.styleFrom(foregroundColor: cs.error),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.search), label: const Text('Find jobs')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text, {String? hint}) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Row(
      children: [
        Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(hint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
      ],
    ),
  );
}
