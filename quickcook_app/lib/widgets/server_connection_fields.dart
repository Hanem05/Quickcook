import 'package:flutter/material.dart';
import '../services/api_host_config.dart';

/// Server IP/port inputs for physical Android when API URL is not baked into the APK.
class ServerConnectionFields extends StatelessWidget {
  const ServerConnectionFields({
    super.key,
    required this.hostController,
    required this.portController,
  });

  final TextEditingController hostController;
  final TextEditingController portController;

  @override
  Widget build(BuildContext context) {
    if (!ApiHostConfig.needsServerSetup) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.dns_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Server connection',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Your phone must reach the PC running QuickCook on the same Wi‑Fi '
                '(Docker / Laravel on port 8001). Use your PC\'s IP from ipconfig.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: hostController,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'Server IP (e.g. 192.168.1.10)',
            prefixIcon: Icon(Icons.lan_outlined),
            counterText: '',
          ),
          validator: (value) {
            if (!ApiHostConfig.needsServerSetup) return null;
            final host = ApiHostConfig.parseServerInput(value ?? '').host;
            if (host.isEmpty) {
              return 'Server IP is required';
            }
            return null;
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: portController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Port',
            prefixIcon: Icon(Icons.numbers_outlined),
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
