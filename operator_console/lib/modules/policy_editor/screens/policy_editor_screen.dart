import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/policy_repository.dart';

/// Cooperative-wide settings, as data rather than a redeploy.
///
/// A value edited here governs trips generated from now on -- it never
/// rewrites a trip already booked under the old value, since policy
/// values are snapshotted onto each trip at generation time.
class PolicyEditorScreen extends StatefulWidget {
  const PolicyEditorScreen({super.key});

  @override
  State<PolicyEditorScreen> createState() => _PolicyEditorScreenState();
}

class _PolicyEditorScreenState extends State<PolicyEditorScreen> {
  late final PolicyRepository _policies = context.read<PolicyRepository>();

  List<Policy>? _list;
  bool _loading = true;
  String? _error;
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _policies.list();
      if (!mounted) return;
      setState(() {
        _list = list;
        for (final p in list) {
          _controllers.putIfAbsent(p.policyKey, () => TextEditingController()).text = p.policyValue;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(Policy policy) async {
    final controller = _controllers[policy.policyKey]!;
    if (controller.text.trim() == policy.policyValue) return;

    setState(() => _saving.add(policy.policyKey));
    try {
      await _policies.update(policy.policyKey, controller.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${policy.policyKey} updated.'),
          backgroundColor: const Color(0xFF8FBCBB),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(policy.policyKey));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Cooperative Policies',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, color: Colors.white70),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Changes here apply to trips generated from now on -- already-booked trips keep the terms they were sold under.',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError(_error!)
                    : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 40),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildList() {
    final policies = _list ?? [];
    return ListView.separated(
      itemCount: policies.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final policy = policies[index];
        final controller = _controllers[policy.policyKey]!;
        final saving = _saving.contains(policy.policyKey);
        return Card(
          elevation: 2,
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(policy.policyKey,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(policy.description, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _save(policy),
                    decoration: InputDecoration(
                      isDense: true,
                      suffixText: policy.dataType == 'decimal' ? '₱' : null,
                      filled: true,
                      fillColor: const Color(0xFF151923),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 40,
                  child: saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          onPressed: () => _save(policy),
                          icon: const Icon(Icons.save_outlined, color: Color(0xFF8FBCBB)),
                          tooltip: 'Save',
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
