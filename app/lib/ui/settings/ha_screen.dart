import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../di/hint_term_providers.dart';
import '../../di/home_assistant.dart';
import '../../di/providers.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'ha_device_sections.dart';
import 'reconnect_text.dart';
import 'settings_page.dart';

/// Settings → Home Assistant: address and token (search in the Wi-Fi via
/// mDNS, otherwise by hand), connection state, choice of the devices that
/// go to the model, disconnect.
class HaScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const HaScreen({super.key});

  @override
  ConsumerState<HaScreen> createState() => _HaScreenState();
}

class _HaScreenState extends ConsumerState<HaScreen> {
  final _address = TextEditingController();
  final _token = TextEditingController();
  final _filter = TextEditingController();
  HaEndpoint? _endpoint;
  bool _loaded = false;
  bool _busy = false;
  bool _searching = false;
  String? _error;
  List<HaServer>? _servers;
  List<HaEntity>? _all;
  Set<String> _approved = {};
  Set<String> _confirm = {};
  Set<String> _noAsk = {};
  List<HaEntity> _gone = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = ref.read(haStoreProvider);
    final endpoint = await store.endpoint();
    final approved = await store.load();
    if (!mounted) return;
    setState(() {
      _endpoint = endpoint;
      _approved = {for (final e in approved) e.entityId};
      _confirm = {
        for (final e in approved)
          if (e.alwaysConfirm) e.entityId,
      };
      _noAsk = {
        for (final e in approved)
          if (e.noConfirm) e.entityId,
      };
      _gone = [
        for (final e in approved)
          if (e.missing) e,
      ];
      _loaded = true;
    });
    if (endpoint != null) await _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final all = await ref.read(haApiProvider).entities();
      // WP135 A: name, room and "no longer there" of the approved devices
      // follow Home Assistant (a new device is never approved here).
      final store = ref.read(haStoreProvider);
      final synced = await haSyncStore(store, all, DateTime.now());
      ref.invalidate(haApprovedEntitiesProvider);
      if (mounted) {
        setState(() {
          _all = all;
          _gone = [
            for (final e in synced)
              if (e.missing) e,
          ];
        });
      }
    } on PortException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _refresh() async {
    final registry = ref.read(toolRegistryProvider);
    registry.clearError('ha');
    await registry.refresh('ha');
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _servers = null;
    });
    final found = await ref.read(haDiscoveryProvider).discover();
    if (mounted) {
      setState(() {
        _searching = false;
        _servers = found;
      });
    }
  }

  Future<void> _connect() async {
    if (_address.text.trim().isEmpty || _token.text.trim().isEmpty) {
      setState(() => _error = context.l10n.haInputMissing);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await haConnect(
      api: ref.read(haApiProvider),
      store: ref.read(haStoreProvider),
      address: _address.text,
      token: _token.text,
    );
    if (error == null) {
      SecretField.finishAutofill();
      _token.clear();
      ref.invalidate(haApprovedEntitiesProvider);
      await _load();
      await _refresh();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _disconnect() async {
    final store = ref.read(haStoreProvider);
    final ok = await confirm(
      context,
      title: context.l10n.haDisconnectTitle,
      message: context.l10n.haDisconnectMessage,
      yes: context.l10n.haDisconnect,
    );
    if (!ok) return;
    await haDisconnect(store);
    ref.invalidate(haApprovedEntitiesProvider);
    await _refresh();
    if (!mounted) return;
    setState(() {
      _endpoint = null;
      _all = null;
      _approved = {};
      _confirm = {};
      _noAsk = {};
      _error = null;
    });
  }

  Future<void> _toggle(HaEntity e, bool on) async {
    final next = {..._approved};
    on ? next.add(e.entityId) : next.remove(e.entityId);
    setState(() => _approved = next);
    await _save();
  }

  /// „Immer bestätigen“ of a switch: its calls then go through the
  /// confirmation (`ha__call_secure`).
  /// Removes a device Home Assistant no longer lists.
  Future<void> _removeGone(HaEntity e) async {
    final next = {..._approved}..remove(e.entityId);
    setState(() {
      _approved = next;
      _gone = [
        for (final g in _gone)
          if (g.entityId != e.entityId) g,
      ];
    });
    await _save();
  }

  Future<void> _toggleConfirm(HaEntity e, bool on) async {
    final next = {..._confirm};
    on ? next.add(e.entityId) : next.remove(e.entityId);
    setState(() => _confirm = next);
    await _save();
  }

  /// „Ohne Rückfrage“ of a blind (WP135 E).
  Future<void> _toggleNoAsk(HaEntity e, bool on) async {
    final next = {..._noAsk};
    on ? next.add(e.entityId) : next.remove(e.entityId);
    setState(() => _noAsk = next);
    await _save();
  }

  Future<void> _save() async {
    final byId = {for (final x in _all ?? const <HaEntity>[]) x.entityId: x};
    final store = ref.read(haStoreProvider);
    // Keep approved entities Home Assistant no longer lists: the user
    // removes them by switching them off, not by a flaky answer.
    final old = {for (final x in await store.load()) x.entityId: x};
    await store.save([
      for (final id in _approved)
        if (byId[id] ?? old[id] case final e?)
          e
              .withConfirm(_confirm.contains(id))
              .withNoConfirm(_noAsk.contains(id)),
    ]);
    // The hint names of the recognizer follow the approval.
    ref.invalidate(haApprovedEntitiesProvider);
    await _refresh();
  }

  Future<void> _retry() async {
    final integration = haIntegrationOf(ref.read(integrationsProvider));
    if (integration == null) return;
    setState(() => _busy = true);
    final error = await integration.reconnect();
    if (!mounted) return;
    setState(() => _busy = false);
    showHint(
      context,
      reconnectHint(context.l10n, error, context.l10n.haReachable),
    );
  }

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(toolRegistryProvider);
    return SettingsPage(
      title: context.l10n.haTitle,
      intro: context.l10n.haIntro,
      children: [
        if (!_loaded)
          const SizedBox.shrink()
        else if (_endpoint == null)
          ..._connectForm()
        else ...[
          StreamBuilder<void>(
            stream: registry.changes,
            builder: (context, _) => _stateCard(registry),
          ),
          ..._deviceList(),
        ],
      ],
    );
  }

  List<Widget> _connectForm() => [
    TextField(
      key: const ValueKey('haAddress'),
      controller: _address,
      style: WText.body,
      keyboardType: TextInputType.url,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: context.l10n.haAddressLabel,
        hintText: 'http://homeassistant.local:8123',
      ),
    ),
    SecretField(
      key: const ValueKey('haToken'),
      controller: _token,
      label: context.l10n.haTokenLabel,
      helperText: context.l10n.haTokenHelp,
      mono: true,
    ),
    InfoBox(context.l10n.haHttpNote),
    if (_error != null)
      Text(
        _error!,
        key: const ValueKey('haError'),
        style: WText.caption.copyWith(color: WColors.error),
      ),
    PrimaryButton(
      _busy ? context.l10n.haConnecting : context.l10n.haConnect,
      onPressed: _busy ? null : () => unawaited(_connect()),
    ),
    WideButton(
      _searching ? context.l10n.haSearching : context.l10n.haSearch,
      onPressed: _searching ? null : () => unawaited(_search()),
    ),
    if (_servers != null)
      _servers!.isEmpty
          ? Text(context.l10n.haNothingFound, style: WText.caption)
          : SettingsSection(
              title: context.l10n.haFound,
              children: [
                for (final s in _servers!)
                  SettingsRow(
                    title: s.name,
                    detail: s.url,
                    onTap: () => setState(() => _address.text = s.url),
                  ),
              ],
            ),
  ];

  Widget _stateCard(ToolRegistry registry) {
    final info = registry.integrations.where((i) => i.id == 'ha').firstOrNull;
    final failed = info?.status == IntegrationStatus.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.l18,
      children: [
        SectionCard(
          children: [
            SettingsRow(
              title: failed
                  ? context.l10n.haErrorTitle
                  : context.l10n.haConnected,
              detail: failed
                  ? integrationErrorText(
                      context.l10n,
                      'ha',
                      info?.error,
                      info?.errorKind,
                    )
                  : _endpoint?.url,
              trailing: CheckStatusIcon(
                failed ? CheckStatus.failed : CheckStatus.ok,
                size: WSize.statusIconSmall,
                semanticLabel: failed
                    ? context.l10n.error
                    : context.l10n.bringFine,
              ),
            ),
            SettingsRow(title: context.l10n.haApproved(_approved.length)),
          ],
        ),
        if (failed)
          PrimaryButton(
            _busy ? context.l10n.haConnecting : context.l10n.retry,
            onPressed: _busy ? null : () => unawaited(_retry()),
          ),
        WideButton(
          context.l10n.haDisconnect,
          onPressed: () => unawaited(_disconnect()),
        ),
      ],
    );
  }

  List<Widget> _deviceList() {
    final all = _all;
    if (all == null) {
      return [if (_error != null) Text(_error!, style: WText.caption)];
    }
    final query = _filter.text.trim().toLowerCase();
    final shown = [
      for (final e in all)
        if (query.isEmpty ||
            e.name.toLowerCase().contains(query) ||
            (e.area ?? '').toLowerCase().contains(query) ||
            e.entityId.contains(query))
          e,
    ];
    final byArea = <String, List<HaEntity>>{};
    for (final e in shown) {
      (byArea[e.area ?? context.l10n.haNoRoom] ??= []).add(e);
    }
    return [
      Text(context.l10n.haDevices, style: WText.sectionTitle),
      InfoBox(context.l10n.haDevicesHelp),
      TextField(
        key: const ValueKey('haFilter'),
        controller: _filter,
        style: WText.body,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: context.l10n.haFilter),
      ),
      if (all.isEmpty) Text(context.l10n.haNoDevices, style: WText.caption),
      if (_gone.isNotEmpty)
        HaGoneSection(gone: _gone, onRemove: (e) => unawaited(_removeGone(e))),
      for (final MapEntry(:key, :value) in byArea.entries)
        HaAreaSection(
          title: key,
          entities: value,
          approved: _approved,
          alwaysConfirm: _confirm,
          noAsk: _noAsk,
          onToggle: (e, on) => unawaited(_toggle(e, on)),
          onToggleConfirm: (e, on) => unawaited(_toggleConfirm(e, on)),
          onToggleNoAsk: (e, on) => unawaited(_toggleNoAsk(e, on)),
        ),
      WideButton(
        context.l10n.haReload,
        onPressed: () => unawaited(_loadDevices()),
      ),
    ];
  }
}
