import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/audio_manager.dart';
import '../models/connection_state.dart' as model;
import '../models/server_info.dart';
import 'server_list_view.dart';
import 'streaming_view.dart';
import 'manual_connect_dialog.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<AudioRelayManager>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AudioRelay'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: 'Manual connect',
            onPressed: () => _showManualConnect(context),
          ),
        ],
      ),
      body: _buildBody(context, manager),
    );
  }

  Widget _buildBody(BuildContext context, AudioRelayManager manager) {
    switch (manager.connectionState) {
      case model.ConnectionState.disconnected:
      case model.ConnectionState.discovering:
        return ServerListView(
          servers: manager.discoveredServers,
          onConnect: (server) => manager.connect(server),
          onRefresh: () => manager.startDiscovery(),
          isSearching: manager.connectionState == model.ConnectionState.discovering,
        );

      case model.ConnectionState.connecting:
        return const _ConnectingView();

      case model.ConnectionState.connected:
        return _StatusView(
          icon: Icons.check_circle,
          color: Colors.green,
          title: 'Connected!',
          subtitle: 'Starting audio stream...',
          showSpinner: true,
          action: ElevatedButton(
            onPressed: () => manager.disconnect(),
            child: const Text('Disconnect'),
          ),
        );

      case model.ConnectionState.streaming:
        return StreamingView(manager: manager);

      case model.ConnectionState.reconnecting:
        return _StatusView(
          icon: Icons.sync,
          color: Colors.orange,
          title: 'Reconnecting...',
          subtitle: 'Attempting to restore connection',
          showSpinner: true,
          action: ElevatedButton(
            onPressed: () => manager.disconnect(),
            child: const Text('Cancel'),
          ),
        );

      case model.ConnectionState.error:
        return _StatusView(
          icon: Icons.error_outline,
          color: Colors.red,
          title: 'Connection Error',
          subtitle: manager.errorMessage ?? 'An error occurred',
          action: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  if (manager.currentServer != null) {
                    manager.connect(manager.currentServer!);
                  }
                },
                child: const Text('Retry'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => manager.disconnect(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        );
    }
  }

  void _showManualConnect(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ManualConnectSheet(),
    );
  }
}

class _ConnectingView extends StatelessWidget {
  const _ConnectingView();

  @override
  Widget build(BuildContext context) {
    final manager = context.read<AudioRelayManager>();
    return _StatusView(
      icon: Icons.wifi_find,
      color: Colors.blue,
      title: 'Connecting...',
      subtitle: 'Establishing connection',
      showSpinner: true,
      action: OutlinedButton(
        onPressed: () => manager.disconnect(),
        child: const Text('Cancel'),
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final bool showSpinner;
  final Widget? action;

  const _StatusView({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.showSpinner = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 24),
            if (showSpinner) ...[
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
            ],
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
