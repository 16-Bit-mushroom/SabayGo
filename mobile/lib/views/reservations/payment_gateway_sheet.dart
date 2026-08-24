import 'package:flutter/material.dart';

class PaymentGatewaySheet extends StatefulWidget {
  final double fare;
  final VoidCallback onPaymentSuccess;

  const PaymentGatewaySheet({
    super.key,
    required this.fare,
    required this.onPaymentSuccess,
  });

  @override
  State<PaymentGatewaySheet> createState() => _PaymentGatewaySheetState();
}

class _PaymentGatewaySheetState extends State<PaymentGatewaySheet> {
  String? _selectedMethod;
  bool _isProcessing = false;

  void _processPayMongoCheckout() async {
    if (_selectedMethod == null) return;

    setState(() => _isProcessing = true);

    // Simulated API call to PayMongo Source/Payment Intent Endpoint
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _isProcessing = false);
      Navigator.pop(context); // Close payment sheet
      widget.onPaymentSuccess(); // Complete the booking process
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(
              'Select Payment Method', 
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              'Secure automated fare processing via PayMongo',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // --- Total Summary Box ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Boarding Fare', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(
                    '₱${widget.fare.toStringAsFixed(2)}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.primaryColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // --- E-Wallet Gateways ---
            _buildPaymentOption(
              id: 'gcash',
              name: 'GCash',
              subtitle: 'Pay via GCash account',
              icon: Icons.account_balance_wallet,
              color: Colors.blue.shade700,
            ),
            const SizedBox(height: 12),
            _buildPaymentOption(
              id: 'maya',
              name: 'Maya',
              subtitle: 'Pay via Maya account',
              icon: Icons.wallet,
              color: Colors.green.shade600,
            ),
            const SizedBox(height: 28),

            // --- Pay Button ---
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_selectedMethod == null || _isProcessing) ? null : _processPayMongoCheckout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A859),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        _selectedMethod == null ? 'SELECT GATEWAY' : 'PROCEED TO PAY',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentOption({
    required String id,
    required String name,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedMethod == id;
    return InkWell(
      onTap: _isProcessing ? null : () => setState(() => _selectedMethod = id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? color.withOpacity(0.05) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),
            Radio<String>(
              value: id,
              groupValue: _selectedMethod,
              activeColor: color,
              onChanged: _isProcessing ? null : (val) => setState(() => _selectedMethod = val),
            ),
          ],
        ),
      ),
    );
  }
}