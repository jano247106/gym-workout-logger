import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _workouts = [];
  bool _isLoading = true;
  String _filterPeriod = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchCompletedWorkouts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchCompletedWorkouts();
    }
  }

  Future<void> _fetchCompletedWorkouts() async {
    try {
      setState(() => _isLoading = true);
      final response = await http.get(
        ApiConfig.uri('/api/workouts/?is_active=false'),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final dynamic decodedBody = json.decode(response.body);
        final List<dynamic> data = (decodedBody is List) 
            ? decodedBody 
            : (decodedBody['results'] as List<dynamic>? ?? []);
        setState(() {
          _workouts = data.map((w) => _enrichWorkout(w as Map<String, dynamic>)).toList();
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading workouts: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Map<String, dynamic> _enrichWorkout(Map<String, dynamic> workout) {
    // Calculate duration in minutes
    final startTime = DateTime.parse(workout['start_time'] as String);
    final endTime = DateTime.parse(workout['end_time'] as String? ?? workout['start_time']);
    final duration = endTime.difference(startTime).inMinutes;

    // Calculate total volume (weight × reps for each set)
    final sets = (workout['sets'] as List<dynamic>?) ?? [];
    double totalVolume = 0.0;
    int totalSets = 0;
    int completedSets = 0;

    for (var set in sets) {
      final setMap = set as Map<String, dynamic>;
      final weight = (setMap['weight'] as num?)?.toDouble() ?? 0.0;
      final reps = (setMap['reps'] as num?)?.toInt() ?? 0;
      final isCompleted = (setMap['is_completed'] as bool?) ?? false;
      
      totalVolume += weight * reps;
      totalSets++;
      if (isCompleted) completedSets++;
    }

    return {
      ...workout,
      'duration_minutes': duration,
      'total_volume': totalVolume,
      'total_sets': totalSets,
      'completed_sets': completedSets,
    };
  }

  bool _isWorkoutInPeriod(Map<String, dynamic> workout) {
    final startTime = DateTime.parse(workout['start_time'] as String);
    final now = DateTime.now();
    
    switch (_filterPeriod) {
      case 'week':
        return now.difference(startTime).inDays <= 7;
      case 'month':
        return now.difference(startTime).inDays <= 30;
      case 'all':
      default:
        return true;
    }
  }

  Future<void> _deleteWorkout(dynamic workoutId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Workout?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(
        ApiConfig.uri('/api/workouts/$workoutId/'),
      );

      if (!mounted) return;

      if (response.statusCode == 204 || response.statusCode == 200) {
        setState(() {
          _workouts.removeWhere((w) => w['id'] == workoutId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workout deleted')),
        );
      } else {
        throw Exception('Failed to delete workout');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredWorkouts = _workouts.where(_isWorkoutInPeriod).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout History'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All Time',
                    selected: _filterPeriod == 'all',
                    onTap: () => setState(() => _filterPeriod = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Last 7 Days',
                    selected: _filterPeriod == 'week',
                    onTap: () => setState(() => _filterPeriod = 'week'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Last 30 Days',
                    selected: _filterPeriod == 'month',
                    onTap: () => setState(() => _filterPeriod = 'month'),
                  ),
                ],
              ),
            ),
          ),
          // Workouts list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetchCompletedWorkouts,
                    child: filteredWorkouts.isEmpty
                        ? SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Center(
                              child: SizedBox(
                                height: 300,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.fitness_center, size: 64, color: Colors.grey),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No workouts yet',
                                      style: Theme.of(context).textTheme.titleLarge,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: filteredWorkouts.length,
                            itemBuilder: (ctx, idx) => _WorkoutCard(
                              workout: filteredWorkouts[idx],
                              onDelete: () => _deleteWorkout(filteredWorkouts[idx]['id']),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: Colors.transparent,
      side: BorderSide(
        color: selected ? Colors.blue : Colors.grey,
        width: selected ? 2 : 1,
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  final Map<String, dynamic> workout;
  final VoidCallback onDelete;

  const _WorkoutCard({required this.workout, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final startTime = DateTime.parse(workout['start_time'] as String);
    final dateFormat = DateFormat('EEE, MMM d, yyyy - HH:mm');
    final templateName = (workout['template_name'] as String?) ?? 'No Template';
    final duration = workout['duration_minutes'] as int;
    final totalVolume = (workout['total_volume'] as num).toStringAsFixed(1);
    final totalSets = workout['total_sets'] as int;
    final completedSets = workout['completed_sets'] as int;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with template name and date
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          templateName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(startTime),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                              ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    itemBuilder: (BuildContext context) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete, color: Colors.red, size: 20),
                            const SizedBox(width: 12),
                            const Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'delete') {
                        onDelete();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatItem(
                    icon: Icons.schedule,
                    label: 'Duration',
                    value: '${duration}m',
                  ),
                  _StatItem(
                    icon: Icons.fitness_center,
                    label: 'Total Volume',
                    value: '$totalVolume kg',
                  ),
                  _StatItem(
                    icon: Icons.done,
                    label: 'Sets',
                    value: '$completedSets/$totalSets',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey,
              ),
        ),
      ],
    );
  }
}
