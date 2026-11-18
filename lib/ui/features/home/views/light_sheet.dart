import 'package:flutter/material.dart';

import 'package:lumina/domain/models/light.dart';
import 'package:lumina/ui/features/home/view_models/home_view_model.dart';
import 'package:lumina/ui/core/theme.dart';
import 'package:lumina/ui/core/widgets.dart';

/// Opens the controls for one light, or for all lights when [addr] is null.
Future<void> showLightSheet(BuildContext context, HomeViewModel viewModel, {int? addr}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _LightSheet(viewModel: viewModel, addr: addr),
  );
}

class _LightSheet extends StatefulWidget {
  final HomeViewModel viewModel;
  final int? addr;
  const _LightSheet({required this.viewModel, required this.addr});

  @override
  State<_LightSheet> createState() => _LightSheetState();
}

class _LightSheetState extends State<_LightSheet> {
  HomeViewModel get c => widget.viewModel;

  /// The answer to the last action taken in this sheet.
  String? _note;
  bool _noteIsError = false;

  Light? get _light {
    final addr = widget.addr;
    return addr == null ? null : c.lights.where((l) => l.addr == addr).firstOrNull;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final p = Palette.of(context);
    final l = _light;
    if (widget.addr != null && l == null) return const SizedBox.shrink(); // removed
    final name = l == null ? 'All lights' : l.name;
    final status = l == null ? c.allStatus : c.statusLine(l);
    final usable = l == null || l.usable;
    final on = l == null ? c.onCount > 0 : c.stateOf(l).on;
    final dimmable = l == null ? c.ready.isNotEmpty : l.usable && (l.hasLightness || l.hasCtl);
    final note = _note;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: display(22), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        style: TextStyle(color: usable ? p.muted : p.danger, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                if (l != null)
                  IconButton(
                    tooltip: 'Rename',
                    onPressed: () => _rename(context, l),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                if (usable)
                  Switch(value: on, onChanged: (v) => l == null ? c.toggleAll() : c.setPower(l, v)),
              ],
            ),
            if (l != null && !usable) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: c.busy ? null : () => l.wasReset ? c.setUpAgain(l) : c.finishSetup(l),
                child: Text(c.actionLabel(l) ?? ''),
              ),
            ],
            if (dimmable) ...[
              const SizedBox(height: 16),
              LightSliders(
                level: l == null ? c.allLevel : l.level,
                kelvin: l == null ? c.allKelvin : l.kelvin,
                showWarmth: l == null ? c.ready.any((x) => x.hasCtl) : l.hasCtl,
                onLevel: (v) {
                  if (l == null) {
                    c.setAll(level: v);
                  } else {
                    c.setLight(l, level: v);
                  }
                },
                onKelvin: _setKelvin,
              ),
              if (l == null ? c.ready.any((x) => x.hasCtl) : l.hasCtl) ...[
                const SizedBox(height: 4),
                WhiteToneSwatches(kelvin: l == null ? c.allKelvin : l.kelvin, onPick: _setKelvin),
              ],
            ],
            if (l != null && l.usable && l.has('ctlSetup')) ...[
              const SizedBox(height: 8),
              Divider(color: p.line),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.power_settings_new_rounded, color: p.muted),
                title: const Text('When the switch turns it on'),
                subtitle: Text(
                  'Make the light come on like it is now: ${l.level}%'
                  '${l.hasCtl ? ', ${HomeViewModel.warmth(l.kelvin).toLowerCase()}' : ''}.',
                  style: TextStyle(color: p.muted),
                ),
                trailing: TextButton(onPressed: () => _useAsDefault(l), child: const Text('Save')),
              ),
            ],
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  note,
                  style: TextStyle(color: _noteIsError ? p.danger : p.muted, fontSize: 13.5),
                ),
              ),
            if (l != null) ...[
              const SizedBox(height: 8),
              Divider(color: p.line),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => _remove(context, l),
                  style: TextButton.styleFrom(foregroundColor: p.danger),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Remove light'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _setKelvin(int kelvin) {
    final l = _light;
    if (l == null) {
      c.setAll(kelvin: kelvin);
    } else {
      c.setLight(l, kelvin: kelvin);
    }
  }

  Future<void> _useAsDefault(Light l) async {
    await c.useAsDefault(l);
    if (!mounted) return;
    setState(() {
      _note = c.status;
      _noteIsError = c.statusIsError;
    });
  }

  Future<void> _rename(BuildContext context, Light l) async {
    final t = TextEditingController(text: l.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Name this light', style: display(20)),
        content: TextField(
          controller: t,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) await c.rename(l, t.text);
  }

  Future<void> _remove(BuildContext context, Light l) async {
    final ok = await confirm(
      context,
      'Remove ${l.name}?',
      c.isConnected ? 'The bulb will be reset so it can be added again later.' : 'You are not connected, so the bulb keeps its setup. Reset it afterwards (five quick off/on cycles) if you want to add it again.',
      action: 'Remove',
      danger: true,
    );
    if (!ok) return;
    if (context.mounted) Navigator.pop(context);
    await c.remove(l);
  }
}
