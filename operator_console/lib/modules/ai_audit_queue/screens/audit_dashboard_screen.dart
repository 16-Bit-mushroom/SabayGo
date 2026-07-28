import 'package:flutter/material.dart';

class AuditDashboardScreen extends StatefulWidget {
  const AuditDashboardScreen({super.key});

  @override
  State<AuditDashboardScreen> createState() => _AuditDashboardScreenState();
}

class _AuditDashboardScreenState extends State<AuditDashboardScreen> {
  int _selectedIndex = 0;
  
  final List<Map<String, dynamic>> _auditLogs = [
    {
      'auditId': 'AUD-8832',
      'route': 'Ecoland Terminal - Cotabato City',
      'driver': 'Juan Dela Cruz',
      'bookedCount': 12,
      'yoloCount': 14,
      'variance': 2,
      'status': 'Pending',
      'imageUrl': 'https://via.placeholder.com/600x400/2E3440/ECEFF4?text=YOLOv8+Snapshot+(2+Unaccounted)',
    },
    {
      'auditId': 'AUD-8833',
      'route': 'SM Ecoland - Digos City',
      'driver': 'Pedro Penduko',
      'bookedCount': 14,
      'yoloCount': 14,
      'variance': 0,
      'status': 'Resolved',
      'imageUrl': 'https://via.placeholder.com/600x400/2E3440/A3BE8C?text=Cabin+Clear+(Match)',
    },
    {
      'auditId': 'AUD-8834',
      'route': 'Ecoland Terminal - Kidapawan',
      'driver': 'Mario Reyes',
      'bookedCount': 9,
      'yoloCount': 10,
      'variance': 1,
      'status': 'Pending',
      'imageUrl': 'https://via.placeholder.com/600x400/2E3440/ECEFF4?text=YOLOv8+Snapshot+(1+Unaccounted)',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;
        final selectedLog = _auditLogs[_selectedIndex];
        final isAlert = selectedLog['variance'] > 0;

        return Padding(
          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Live YOLOv8 Audit Queue',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 24),
              
              Expanded(
                child: isDesktop 
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: _buildDataGrid()),
                          const SizedBox(width: 24),
                          Expanded(flex: 2, child: _buildProofPanel(selectedLog, isAlert)),
                        ],
                      )
                    // Mobile/Tablet Stacked Layout
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildDataGrid(),
                            const SizedBox(height: 24),
                            _buildProofPanel(selectedLog, isAlert),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDataGrid() {
    return Card(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        // FIX: Allows horizontal scrolling if screen is too narrow
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFF2C3244)),
              dataRowMinHeight: 50,
              dataRowMaxHeight: 60,
              headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70),
              columns: const [
                DataColumn(label: Text('Audit ID')),
                DataColumn(label: Text('Driver')),
                DataColumn(label: Text('QR Count')),
                DataColumn(label: Text('YOLO Count')),
                DataColumn(label: Text('Variance')),
                DataColumn(label: Text('Status')),
              ],
              rows: List<DataRow>.generate(
                _auditLogs.length,
                (index) {
                  final log = _auditLogs[index];
                  final rowAlert = log['variance'] > 0;
                  return DataRow(
                    selected: _selectedIndex == index,
                    onSelectChanged: (selected) {
                      if (selected != null && selected) {
                        setState(() => _selectedIndex = index);
                      }
                    },
                    cells: [
                      DataCell(Text(log['auditId'], style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white))),
                      DataCell(Text(log['driver'], style: const TextStyle(color: Colors.white70))),
                      DataCell(Text(log['bookedCount'].toString(), style: const TextStyle(color: Colors.white70))),
                      DataCell(
                        Text(
                          log['yoloCount'].toString(),
                          style: TextStyle(
                              color: rowAlert ? Theme.of(context).colorScheme.error : Colors.white, 
                              fontWeight: rowAlert ? FontWeight.bold : FontWeight.normal),
                        ),
                      ),
                      DataCell(
                        Text(
                          '+${log['variance']}',
                          style: TextStyle(
                              color: rowAlert ? Theme.of(context).colorScheme.error : Colors.white, 
                              fontWeight: rowAlert ? FontWeight.bold : FontWeight.normal),
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: rowAlert ? Theme.of(context).colorScheme.error.withOpacity(0.2) : const Color(0xFFA3BE8C).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: rowAlert ? Theme.of(context).colorScheme.error : const Color(0xFFA3BE8C),
                            )
                          ),
                          child: Text(
                            log['status'], 
                            style: TextStyle(
                              color: rowAlert ? Theme.of(context).colorScheme.error : const Color(0xFFA3BE8C), 
                              fontSize: 12, 
                              fontWeight: FontWeight.bold
                            )
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProofPanel(Map<String, dynamic> selectedLog, bool isAlert) {
    return Card(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        // FIX: Prevents bottom overflow on smaller screens
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // Hug content tightly
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Audit: ${selectedLog['auditId']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  if (isAlert) Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
                ],
              ),
              const SizedBox(height: 16),
              
              // The YOLOv8 Image Area
              Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF151923),
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: NetworkImage(selectedLog['imageUrl']),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              const Text('AI Reconciliation Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white54, letterSpacing: 1.2)),
              const Divider(color: Colors.white10),
              _buildDetailRow('Route', selectedLog['route']),
              _buildDetailRow('Digital Manifest', selectedLog['bookedCount'].toString()),
              _buildDetailRow('Physical Reality', selectedLog['yoloCount'].toString(), isAlert: isAlert),
              _buildDetailRow('Detected Leakage', '+${selectedLog['variance']} Passengers', isAlert: isAlert),
              
              const SizedBox(height: 32),
              
              // Operator Actions
              if (isAlert && selectedLog['status'] == 'Pending')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _auditLogs[_selectedIndex]['status'] = 'Resolved';
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.gavel),
                    label: const Text('Flag Driver & Resolve', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                      disabledBackgroundColor: const Color(0xFF2C3244),
                      disabledForegroundColor: Colors.white54,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Cleared / No Action Needed', style: TextStyle(fontSize: 15)),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isAlert = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w400, color: Colors.white70)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isAlert ? Theme.of(context).colorScheme.error : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}