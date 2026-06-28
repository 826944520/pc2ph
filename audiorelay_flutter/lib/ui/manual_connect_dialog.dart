import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/audio_manager.dart';
import '../models/server_info.dart';

class ManualConnectSheet extends StatefulWidget {
  const ManualConnectSheet({super.key});

  @override
  State<ManualConnectSheet> createState() => _ManualConnectSheetState();
}

class _ManualConnectSheetState extends State<ManualConnectSheet> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '59200');
  final _audioPortController = TextEditingController(text: '59100');

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _audioPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Manual Connect',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),

          // IP Address
          TextField(
            controller: _ipController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'IP Address',
              hintText: 'e.g. 192.168.1.100',
              prefixIcon: Icon(Icons.language),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          // Port
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    prefixIcon: Icon(Icons.settings_ethernet),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _audioPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Audio Port',
                    prefixIcon: Icon(Icons.headphones),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Connect button
          FilledButton(
            onPressed: _ipController.text.isEmpty ? null : _connect,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Connect'),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _connect() {
    final server = ServerInfo(
      id: 'manual:${_ipController.text}:${_portController.text}',
      name: 'Manual Server',
      host: _ipController.text.trim(),
      port: int.tryParse(_portController.text) ?? 59200,
      audioPort: int.tryParse(_audioPortController.text) ?? 59100,
    );

    Navigator.of(context).pop();
    context.read<AudioRelayManager>().connect(server);
  }
}
