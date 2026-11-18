import 'package:flutter/material.dart';

import 'package:lumina/ui/features/home/view_models/home_view_model.dart';
import 'package:lumina/ui/core/theme.dart';
import 'package:lumina/ui/core/widgets.dart';

/// Makes a new scene: one brightness and white for every light (a preset),
/// or each light as it is now (a scene stored on the bulbs).
/// The lights follow the sliders while the sheet is open, and go back to how
/// they were unless a preset is saved.
Future<void> showNewSceneSheet(BuildContext context, HomeViewModel viewModel) async {
  viewModel.beginNewScene();
  // false: a preset was saved; true: save each light instead; null: closed.
  final eachLight = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _NewSceneSheet(viewModel: viewModel),
  );
  await viewModel.endNewScene(saved: eachLight == false);
  if (eachLight == true && context.mounted) await _saveEachLight(context, viewModel);
}

class _NewSceneSheet extends StatefulWidget {
  final HomeViewModel viewModel;
  const _NewSceneSheet({required this.viewModel});

  @override
  State<_NewSceneSheet> createState() => _NewSceneSheetState();
}

class _NewSceneSheetState extends State<_NewSceneSheet> {
  HomeViewModel get c => widget.viewModel;
  late final _name = TextEditingController(text: c.nextPresetName);
  late int _level = c.allLevel, _kelvin = c.allKelvin;

  /// Why the last Save didn't work, such as a name already in use.
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _setLevel(int v) {
    setState(() => _level = v);
    c.preview(level: v);
  }

  void _setKelvin(int v) {
    setState(() => _kelvin = v);
    c.preview(kelvin: v);
  }

  Future<void> _save() async {
    final error = await c.savePreset(_name.text, level: _level, kelvin: _kelvin);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, false);
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final warmth = c.ready.any((l) => l.hasCtl);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New scene', style: display(22)),
                const SizedBox(height: 4),
                Text(
                  c.isConnected
                      ? 'Pick a brightness and white for every light. Your lights follow along.'
                      : 'Pick a brightness and white for every light.',
                  style: TextStyle(color: p.muted),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                LightSliders(
                  level: _level,
                  kelvin: _kelvin,
                  showWarmth: warmth,
                  onLevel: _setLevel,
                  onKelvin: _setKelvin,
                ),
                if (warmth) ...[
                  const SizedBox(height: 4),
                  WhiteToneSwatches(kelvin: _kelvin, onPick: _setKelvin),
                ],
                if (_error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error, style: TextStyle(color: p.danger)),
                  ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _save, child: const Text('Save scene')),
                if (c.showScenes) ...[
                  const SizedBox(height: 8),
                  Divider(color: p.line),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.bookmark_outline_rounded, color: p.muted),
                    title: const Text('Save each light as it is now'),
                    subtitle: Text(
                      'Keeps each light’s own brightness and white. Stored on the bulbs.',
                      style: TextStyle(color: p.muted),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(context, true),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Names and saves a scene from each light's current look.
Future<void> _saveEachLight(BuildContext context, HomeViewModel c) async {
  final name = TextEditingController(text: c.nextSceneName);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Save each light', style: display(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Saves how every light looks now, so you can bring it back with one tap.'),
          const SizedBox(height: 12),
          TextField(
            controller: name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (_) => Navigator.pop(ctx, true),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok == true) await c.saveScene(name.text);
}
