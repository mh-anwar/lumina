import 'package:flutter/material.dart';

import 'package:lumina/domain/models/connection.dart';
import 'package:lumina/domain/models/light.dart';
import 'package:lumina/domain/models/preset.dart';
import 'package:lumina/ui/features/add_light/views/add_light_sheet.dart';
import 'package:lumina/ui/features/home/view_models/home_view_model.dart';
import 'package:lumina/ui/features/home/views/light_sheet.dart';
import 'package:lumina/ui/features/home/views/new_scene_sheet.dart';
import 'package:lumina/ui/features/home/views/settings_screen.dart';
import 'package:lumina/ui/core/theme.dart';
import 'package:lumina/ui/core/widgets.dart';

/// The home screen: all lights, scenes, and a tile for each light.
class HomeScreen extends StatefulWidget {
  final HomeViewModel viewModel;
  const HomeScreen({super.key, required this.viewModel});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  HomeViewModel get c => widget.viewModel;
  bool _editingScenes = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame: start() may notify at once (when the home is
    // already loaded), and notifying during build is not allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) => c.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    c.lifecycleChanged(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (!c.loaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                      sliver: SliverMainAxisGroup(slivers: _slivers(context)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _slivers(BuildContext context) {
    final ready = c.ready;
    return [
      SliverToBoxAdapter(child: _Header(viewModel: c)),
      SliverToBoxAdapter(child: _StatusBanner(viewModel: c)),
      if (c.lights.isEmpty)
        SliverToBoxAdapter(child: _EmptyState(viewModel: c))
      else ...[
        if (ready.length > 1)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: SizedBox(
                height: 116,
                child: LightTile(
                  name: 'All lights',
                  status: c.allStatus,
                  on: c.onCount > 0,
                  level: c.allLevel,
                  color: kelvinColor(c.allKelvin),
                  icon: Icons.home_outlined,
                  onTap: c.toggleAll,
                  onLevel: (v) => c.setAll(level: v),
                  onOpen: () => showLightSheet(context, c),
                ),
              ),
            ),
          ),
        if (ready.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              'Scenes',
              trailing: c.scenes.isEmpty && c.customPresets.isEmpty
                  ? null
                  : TextButton(
                      onPressed: () => setState(() => _editingScenes = !_editingScenes),
                      child: Text(_editingScenes ? 'Done' : 'Edit'),
                    ),
            ),
          ),
          SliverToBoxAdapter(child: _sceneRow(context)),
        ],
        const SliverToBoxAdapter(child: SectionHeader('Lights')),
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisExtent: 140,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          delegate: SliverChildListDelegate([
            for (final l in c.lights) _lightTile(context, l),
            _AddTile(onTap: c.busy ? null : () => _addLight(context)),
          ]),
        ),
      ],
    ];
  }

  Widget _lightTile(BuildContext context, Light l) {
    final s = c.stateOf(l);
    final attention = c.needsAction(l);
    VoidCallback? tap;
    if (l.wasReset) {
      tap = c.busy ? null : () => c.setUpAgain(l);
    } else if (!l.configured) {
      tap = c.busy ? null : () => c.finishSetup(l);
    } else {
      tap = () => c.setPower(l, !s.on);
    }
    return LightTile(
      key: ValueKey(l.addr),
      name: l.name,
      status: c.statusLine(l),
      on: l.configured && s.on,
      level: l.level,
      color: kelvinColor(l.kelvin),
      attention: attention,
      action: c.actionLabel(l),
      onTap: tap,
      onLevel: l.usable && (l.hasLightness || l.hasCtl) ? (v) => c.setLight(l, level: v) : null,
      onOpen: () => showLightSheet(context, c, addr: l.addr),
    );
  }

  Widget _sceneRow(BuildContext context) {
    final p = Palette.of(context);
    final editing = _editingScenes;
    // New first, then the user's own, so they show without scrolling.
    final cards = <Widget>[
      if (!editing)
        SceneCard(
          label: 'New',
          swatch: Icon(Icons.add_rounded, size: 24, color: p.text),
          onTap: () => showNewSceneSheet(context, c),
        ),
      for (final e in c.scenes.entries)
        SceneCard(
          label: e.value,
          swatch: Icon(Icons.bookmark_outline_rounded, size: 24, color: p.muted),
          onTap: () => c.recallScene(e.key),
          onDelete: editing ? () => _deleteScene(context, e.key, e.value) : null,
        ),
      for (final preset in c.customPresets)
        SceneCard(
          label: preset.name,
          swatch: PresetSwatch(preset),
          onTap: () => c.applyPreset(preset),
          onDelete: editing ? () => _deletePreset(context, preset) : null,
        ),
      if (!editing)
        for (final preset in presets)
          SceneCard(
            label: preset.name,
            swatch: PresetSwatch(preset),
            onTap: () => c.applyPreset(preset),
          ),
    ];
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => cards[i],
      ),
    );
  }

  Future<void> _addLight(BuildContext context) => showAddLightSheet(context, onPicked: c.addLight);

  Future<void> _deleteScene(BuildContext context, int scene, String name) async {
    final ok = await confirm(
      context,
      'Delete $name?',
      'The scene is removed from every light.',
      action: 'Delete',
      danger: true,
    );
    if (!ok) return;
    await c.forgetScene(scene);
    _stopEditingIfEmpty();
  }

  Future<void> _deletePreset(BuildContext context, Preset preset) async {
    final ok = await confirm(
      context,
      'Delete ${preset.name}?',
      'The scene is removed from this phone.',
      action: 'Delete',
      danger: true,
    );
    if (!ok) return;
    await c.deletePreset(preset);
    _stopEditingIfEmpty();
  }

  void _stopEditingIfEmpty() {
    if (c.scenes.isEmpty && c.customPresets.isEmpty && mounted) {
      setState(() => _editingScenes = false);
    }
  }
}

/// The title, the connection, and the way to settings.
class _Header extends StatelessWidget {
  final HomeViewModel viewModel;
  const _Header({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = viewModel;
    final connecting = c.connection == Connection.connecting;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text('Home', style: display(30))),
                const SizedBox(height: 2),
                SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      if (connecting)
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      else
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.isConnected ? const Color(0xFF3BB273) : p.off,
                          ),
                        ),
                      const SizedBox(width: 8),
                      Text(c.connectionLabel, style: TextStyle(color: p.muted, fontSize: 14)),
                      if (c.connection == Connection.off && c.lights.isNotEmpty)
                        TextButton(
                          onPressed: c.busy ? null : c.connect,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text('Connect'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(viewModel: c))),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}

/// What just happened, or what went wrong.
class _StatusBanner extends StatelessWidget {
  final HomeViewModel viewModel;
  const _StatusBanner({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = viewModel;
    final error = c.statusIsError;
    return Semantics(
      liveRegion: true,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: c.status.isEmpty
            ? const SizedBox(width: double.infinity)
            : Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: error ? p.danger.withValues(alpha: 0.1) : p.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: error ? p.danger.withValues(alpha: 0.35) : p.line),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c.busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Icon(
                        error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
                        size: 20,
                        color: error ? p.danger : p.muted,
                      ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(c.status, style: const TextStyle(fontSize: 14.5))),
                  ],
                ),
              ),
      ),
    );
  }
}

/// No lights yet: how to add the first one, or restore a backup.
class _EmptyState extends StatelessWidget {
  final HomeViewModel viewModel;
  const _EmptyState({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = viewModel;
    Widget step(int n, String text) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.bg),
            child: Text('$n', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No lights yet', style: display(20)),
          const SizedBox(height: 4),
          Text(
            'Set up your first bulb. It takes about 10 seconds.',
            style: TextStyle(color: p.muted),
          ),
          step(1, 'Turn the bulb on, then off and on five times quickly until it flashes.'),
          step(2, 'Tap Add a light and pick the bulb.'),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: c.busy ? null : () => showAddLightSheet(context, onPicked: c.addLight),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a light'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => showRestoreDialog(context, c),
            child: const Text('Restore from a backup'),
          ),
        ],
      ),
    );
  }
}

/// The last tile in the grid.
class _AddTile extends StatelessWidget {
  final VoidCallback? onTap;
  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.line, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: p.muted, size: 28),
            const SizedBox(height: 6),
            Text(
              'Add a light',
              style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
