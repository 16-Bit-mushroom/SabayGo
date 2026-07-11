import 'package:flutter/material.dart';
import '../models/notification_model.dart';

class NotificationsViewModel extends ChangeNotifier {
  NotificationsViewModel() {
    _loadMockNotifications();
  }

  List<NotificationModel> _notifications = [];
  String _searchQuery = '';

  // --- Derived State ---
  List<NotificationModel> get filteredNotifications {
    if (_searchQuery.isEmpty) {
      return _notifications;
    }
    final query = _searchQuery.toLowerCase();
    return _notifications.where((n) {
      return n.title.toLowerCase().contains(query) || 
             n.message.toLowerCase().contains(query);
    }).toList();
  }

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  // --- Actions ---
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void markAsRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index != -1 && !_notifications[index].isRead) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
      notifyListeners();
    }
  }

  void deleteNotification(String id) {
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  // --- Mock Data ---
  void _loadMockNotifications() {
    final now = DateTime.now(); // Simulated as July 11, 2026
    
    _notifications = [
      NotificationModel(
        id: 'n1',
        type: NotificationType.tailoredTrip,
        title: 'New Trip to Cotabato City!',
        message: 'A new schedule matching your saved destination (Cotabato City) has been posted. Seats are filling up fast!',
        timestamp: now.subtract(const Duration(minutes: 15)),
        relatedTripId: 't1',
      ),
      NotificationModel(
        id: 'n2',
        type: NotificationType.tripCanceled,
        title: 'Trip Canceled',
        message: 'Your 2:00 PM trip to Tagum City was canceled by the operator due to van maintenance. We apologize for the inconvenience.',
        timestamp: now.subtract(const Duration(hours: 2)),
        isRead: true,
      ),
      NotificationModel(
        id: 'n3',
        type: NotificationType.vanDeparted,
        title: 'Missed your ride?',
        message: 'The 10:00 AM van to General Santos City has already departed the terminal.',
        timestamp: now.subtract(const Duration(days: 1)),
        isRead: true,
      ),
      NotificationModel(
        id: 'n4',
        type: NotificationType.tripUpdate,
        title: 'Platform Change',
        message: 'Your upcoming trip to Digos City has been moved to Bay 4 at the Ecoland Terminal.',
        timestamp: now.subtract(const Duration(days: 2)),
        isRead: true,
      ),
      NotificationModel(
        id: 'n5',
        type: NotificationType.terminalPolicy,
        title: 'Ecoland Terminal Update',
        message: 'Starting next week, all passengers must present a digital QR ticket at the terminal gates. Paper tickets will no longer be issued.',
        timestamp: now.subtract(const Duration(days: 5)),
        isRead: true,
      ),
      NotificationModel(
        id: 'n6',
        type: NotificationType.policyUpdate,
        title: 'SabayGo Refund Policy',
        message: 'We have updated our refund policy for passenger-initiated cancellations. Please review the new terms in the app settings.',
        timestamp: now.subtract(const Duration(days: 10)),
        isRead: true,
      ),
    ];
  }
}