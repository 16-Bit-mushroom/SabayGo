import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import '../widgets/promo_card.dart';
import '../widgets/payment_method_tile.dart';

class PaymentScreen extends StatelessWidget {
  // Mock State - These will eventually come from your ViewModel
  final String selectedPaymentId;
  final bool isPromoApplied;
  final VoidCallback onBackPressed;
  final Function(String) onPaymentMethodSelected;
  final VoidCallback onTogglePromo;
  final VoidCallback onProceedToBook;

  const PaymentScreen({
    Key? key,
    required this.onBackPressed,
    this.selectedPaymentId =
        'gcash', // Defaulting to digital wallet for your P2P setup
    this.isPromoApplied = true,
    required this.onPaymentMethodSelected,
    required this.onTogglePromo,
    required this.onProceedToBook,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: onBackPressed,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Select Payment Method", style: TextStyle(fontSize: 18)),
            Text(
              "Downtown Plaza · 5.2 km",
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Center(
              child: Text(
                "● ● ● ○",
                style: TextStyle(
                  color: AppColors.primaryAction,
                  letterSpacing: 2,
                ),
              ),
            ), // Mock Breadcrumb
          ),
        ],
      ),
      body: Column(
        children: [
          // Scrollable Area
          // Scrollable Area
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                const Text(
                  "Promotions & Vouchers",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                PromoCard(
                  code: "NEWUSER30",
                  description: "₱30 off · Valid until Dec 31, 2026",
                  isApplied: isPromoApplied,
                  onTap: onTogglePromo,
                ),

                const SizedBox(height: 24),
                const Text(
                  "CREDIT / DEBIT CARD",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      children: [
                        PaymentMethodTile(
                          title: "•••• •••• •••• 4291",
                          subtitle: "Visa · Expires 09/27",
                          leadingIcon: const Text(
                            "VISA",
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                          isSelected: selectedPaymentId == 'visa',
                          onTap: () => onPaymentMethodSelected('visa'),
                        ),
                        const Divider(height: 1, indent: 56),
                        PaymentMethodTile(
                          title: "•••• •••• •••• 8834",
                          subtitle: "Mastercard · Expires 03/26",
                          leadingIcon: const Icon(
                            Icons.credit_card,
                            size: 16,
                            color: Colors.orange,
                          ),
                          isSelected: selectedPaymentId == 'mastercard',
                          onTap: () => onPaymentMethodSelected('mastercard'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                const Text(
                  "DIGITAL WALLET",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      children: [
                        PaymentMethodTile(
                          title: "GCash",
                          subtitle: "09171234567 · ₱3,420 balance",
                          leadingIcon: const Text(
                            "G",
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          isSelected: selectedPaymentId == 'gcash',
                          onTap: () => onPaymentMethodSelected('gcash'),
                        ),
                        const Divider(height: 1, indent: 56),
                        PaymentMethodTile(
                          title: "Maya",
                          subtitle: "09281234567 · ₱1,880 balance",
                          leadingIcon: const Text(
                            "M",
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          isSelected: selectedPaymentId == 'maya',
                          onTap: () => onPaymentMethodSelected('maya'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                const Text(
                  "CASH",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: PaymentMethodTile(
                      title: "Pay with Cash",
                      subtitle: "Pay driver directly on arrival",
                      leadingIcon: const Icon(
                        Icons.money,
                        size: 16,
                        color: Colors.grey,
                      ),
                      isSelected: selectedPaymentId == 'cash',
                      onTap: () => onPaymentMethodSelected('cash'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Fixed Bottom Summary Sheet
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        "Base fare",
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      Text(
                        "₱180.00",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        "Toll fees",
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      Text(
                        "₱15.00",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (isPromoApplied) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          "Discount (NEWUSER30)",
                          style: TextStyle(color: AppColors.success),
                        ),
                        Text(
                          "-₱30.00",
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Divider(height: 1),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        "Total",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        "₱165.00",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppColors.primaryAction,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: onProceedToBook,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryAction,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Proceed to Book · ₱165.00",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.surface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

 
    );
  }
}
