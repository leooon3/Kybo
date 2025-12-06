import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _service = NotificationService();

  final Map<String, int> _meals = {
    'Colazione': 0,
    'Spuntino Mattina': 1,
    'Pranzo': 2,
    'Merenda': 3,
    'Cena': 4,
    'Spuntino Serale': 5,
  };

  Map<String, TimeOfDay?> _scheduledTimes = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    await _service.requestPermissions();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, TimeOfDay?> loaded = {};

    for (var entry in _meals.entries) {
      final hour = prefs.getInt('${entry.key}_hour');
      final minute = prefs.getInt('${entry.key}_minute');
      final isSet = prefs.getBool('${entry.key}_enabled') ?? false;

      if (isSet && hour != null && minute != null) {
        loaded[entry.key] = TimeOfDay(hour: hour, minute: minute);
      } else {
        loaded[entry.key] = null;
      }
    }

    if (mounted) {
      setState(() {
        _scheduledTimes = loaded;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleMeal(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    if (value) {
      final initialTime = const TimeOfDay(hour: 12, minute: 00);
      final picked = await showTimePicker(
        context: context,
        initialTime: initialTime,
      );

      if (picked != null) {
        await prefs.setInt('${key}_hour', picked.hour);
        await prefs.setInt('${key}_minute', picked.minute);
        await prefs.setBool('${key}_enabled', true);

        await _service.scheduleDailyNotification(
          id: _meals[key]!,
          title: "È ora di mangiare!",
          body: "Tempo per: $key",
          time: picked,
        );

        if (mounted) {
          setState(() {
            _scheduledTimes[key] = picked;
          });
        }
      }
    } else {
      await prefs.setBool('${key}_enabled', false);
      await _service.cancelNotification(_meals[key]!);

      if (mounted) {
        setState(() {
          _scheduledTimes[key] = null;
        });
      }
    }
  }

  Future<void> _editTime(String key) async {
    final currentTime =
        _scheduledTimes[key] ?? const TimeOfDay(hour: 12, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: currentTime,
    );

    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('${key}_hour', picked.hour);
      await prefs.setInt('${key}_minute', picked.minute);
      await prefs.setBool('${key}_enabled', true);

      await _service.cancelNotification(_meals[key]!);
      await _service.scheduleDailyNotification(
        id: _meals[key]!,
        title: "È ora di mangiare!",
        body: "Tempo per: $key",
        time: picked,
      );

      if (mounted) {
        setState(() {
          _scheduledTimes[key] = picked;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifiche Pasti"),
        actions: [
          // [ADDED] Test Button
          IconButton(
            icon: const Icon(Icons.notification_important),
            tooltip: "Test Immediato",
            onPressed: () {
              _service.showInstantNotification();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Invio notifica di prova...")),
              );
            },
          ),
        ],
      ),
      body: ListView(
        children: _meals.keys.map((key) {
          final time = _scheduledTimes[key];
          final isEnabled = time != null;

          return SwitchListTile(
            title: Text(key),
            subtitle: Text(
              isEnabled
                  ? "Programmato alle ${time.format(context)}"
                  : "Disattivato",
            ),
            value: isEnabled,
            onChanged: (val) => _toggleMeal(key, val),
            secondary: isEnabled
                ? IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _editTime(key),
                  )
                : const Icon(Icons.notifications_off),
          );
        }).toList(),
      ),
    );
  }
}
