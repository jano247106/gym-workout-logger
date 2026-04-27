import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import '../config/api_config.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _prs = {};
  Map<String, dynamic> _preferences = {};
  List<Map<String, dynamic>> _allExercises = [];
  Set<int> _selectedExerciseIds = {};
  List<Map<String, dynamic>> _volumeTrend = [];
  int _streakDays = 0;
  String _selectedPeriod = '30d';

  int _daysForPeriod(String period) {
    switch (period) {
      case '30d':
        return 30;
      case '6m':
        return 180;
      case '1y':
        return 365;
      case 'all':
        return 0;
      default:
        return 30;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      setState(() => _isLoading = true);

      final trendResponse = await http.get(
        ApiConfig.uri(
          '/api/stats/volume_trend/?days=${_daysForPeriod(_selectedPeriod)}',
        ),
      );

      final streakResponse = await http.get(
        ApiConfig.uri('/api/stats/streak/'),
      );

      // Load PRs
      final prsResponse = await http.get(ApiConfig.uri('/api/stats/prs/'));

      // Load preferences
      final prefResponse = await http.get(
        ApiConfig.uri('/api/stats/preferences/'),
      );

      // Load all exercises for selection
      final exResponse = await http.get(ApiConfig.uri('/api/exercises/'));

      if (!mounted) return;

      if (trendResponse.statusCode == 200 &&
          streakResponse.statusCode == 200 &&
          prsResponse.statusCode == 200 &&
          prefResponse.statusCode == 200 &&
          exResponse.statusCode == 200) {
        final trendData = json.decode(trendResponse.body);
        final streakData =
            json.decode(streakResponse.body) as Map<String, dynamic>;
        final prefData = json.decode(prefResponse.body) as Map<String, dynamic>;
        final exData = json.decode(exResponse.body) as List;

        final tracked = (prefData['tracked_exercises'] as List?) ?? [];

        setState(() {
          _volumeTrend = List<Map<String, dynamic>>.from(
            (trendData['trend'] as List).map(
              (item) => {
                'date': item['date'].toString(),
                'volume': (item['volume'] as num).toDouble(),
              },
            ),
          );
          _streakDays =
              (streakData['streak_days'] as num?)?.toInt() ??
              (streakData['streak_weeks'] as num?)?.toInt() ??
              0;
          _prs = json.decode(prsResponse.body);
          _preferences = prefData;
          _allExercises = exData
              .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
              .toList();
          _selectedExerciseIds = tracked.map((e) => (e as num).toInt()).toSet();
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading stats: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats & Progress'),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadStats),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWorkoutStreakCard(),
                    const SizedBox(height: 24),

                    _buildVolumeTrendChart(),
                    const SizedBox(height: 24),

                    // TOP PRs SECTION
                    _buildTopPRsSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildWorkoutStreakCard() {
    final streakText = _streakDays == 1 ? '1 day' : '$_streakDays days';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.local_fire_department,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Workout Streak',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    streakText,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeTrendChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total Volume Trend',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                _buildPeriodChip('30 days', '30d'),
                _buildPeriodChip('6 months', '6m'),
                _buildPeriodChip('1 year', '1y'),
                _buildPeriodChip('All time', 'all'),
              ],
            ),
            const SizedBox(height: 16),
            if (_volumeTrend.isEmpty)
              const SizedBox(
                height: 220,
                child: Center(
                  child: Text('No volume data for selected period'),
                ),
              )
            else
              _buildTrendChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodChip(String label, String value) {
    final selected = _selectedPeriod == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (isSelected) {
        if (!isSelected || _selectedPeriod == value) return;
        setState(() => _selectedPeriod = value);
        _loadStats();
      },
    );
  }

  Widget _buildTrendChart() {
    final spots = <FlSpot>[];
    for (int i = 0; i < _volumeTrend.length; i++) {
      spots.add(FlSpot(i.toDouble(), (_volumeTrend[i]['volume'] as double)));
    }

    double minVolume = _volumeTrend
        .map((e) => e['volume'] as double)
        .reduce((a, b) => a < b ? a : b);
    double maxVolume = _volumeTrend
        .map((e) => e['volume'] as double)
        .reduce((a, b) => a > b ? a : b);

    if (maxVolume == minVolume) {
      maxVolume = minVolume + 1;
    }

    final yIntervalRaw = ((maxVolume - minVolume) / 2).abs();
    final yInterval = yIntervalRaw == 0 ? 1.0 : yIntervalRaw;

    final xIntervalRaw = ((_volumeTrend.length - 1) / 4).ceilToDouble();
    final xInterval = xIntervalRaw <= 0 ? 1.0 : xIntervalRaw;
    final labelModulo = ((_volumeTrend.length - 1) / 4).ceil().clamp(
      1,
      1000000,
    );

    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (_volumeTrend.length - 1).toDouble(),
          minY: minVolume,
          maxY: minVolume + (2 * yInterval),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yInterval,
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: yInterval,
                getTitlesWidget: (value, meta) {
                  final low = minVolume;
                  final mid = minVolume + yInterval;
                  final high = minVolume + (2 * yInterval);
                  final eps = yInterval * 0.25;
                  if ((value - low).abs() < eps) return Text('${low.toInt()}');
                  if ((value - mid).abs() < eps) return Text('${mid.toInt()}');
                  if ((value - high).abs() < eps)
                    return Text('${high.toInt()}');
                  return const SizedBox.shrink();
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: xInterval,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= _volumeTrend.length)
                    return const SizedBox.shrink();
                  if (idx % labelModulo != 0 &&
                      idx != _volumeTrend.length - 1) {
                    return const SizedBox.shrink();
                  }
                  final rawDate = _volumeTrend[idx]['date'].toString();
                  final label = rawDate.length >= 10
                      ? rawDate.substring(5, 10)
                      : rawDate;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(label, style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              left: BorderSide(color: Colors.grey[300]!),
              bottom: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 3,
              isStrokeCapRound: true,
              gradient: LinearGradient(
                colors: [Colors.blue[400]!, Colors.green[400]!],
              ),
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.blue[200]!.withValues(alpha: 0.30),
                    Colors.green[200]!.withValues(alpha: 0.10),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPRsSection() {
    final prsSource = _getFilteredPrs();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '🏆 Top PRs',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: _openExerciseSelection,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (prsSource.isEmpty)
              const Center(child: Text('No PRs recorded yet'))
            else
              ..._buildTopPRCards(prsSource),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTopPRCards(Map<String, dynamic> prsSource) {
    final List<Widget> cards = [];

    for (var i = 0; i < min(prsSource.length, 3); i++) {
      final entry = prsSource.entries.toList()[i];
      final bodyPart = entry.key;
      final exercises = (entry.value as List);

      if (exercises.isNotEmpty) {
        final topExercise = exercises[0];
        cards.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bodyPart,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        topExercise['exercise_name'] ?? 'Unknown',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${topExercise['weight']}kg × ${topExercise['reps']}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        'Predicted 1RM: ${topExercise['est_1rm']}kg',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
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

    return cards;
  }

  Map<String, dynamic> _getFilteredPrs() {
    if (_selectedExerciseIds.isEmpty) {
      return _prs;
    }

    final filtered = <String, dynamic>{};
    for (final entry in _prs.entries) {
      final bodyPart = entry.key;
      final list = (entry.value as List)
          .where(
            (ex) => _selectedExerciseIds.contains(
              (ex['exercise_id'] as num?)?.toInt(),
            ),
          )
          .toList();
      if (list.isNotEmpty) {
        filtered[bodyPart] = list;
      }
    }
    return filtered;
  }

  Future<void> _openExerciseSelection() async {
    if (_allExercises.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exercise list is not loaded yet.')),
      );
      return;
    }

    final tempSelected = Set<int>.from(_selectedExerciseIds);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select Exercises for PR / 1RM'),
              content: SizedBox(
                width: double.maxFinite,
                height: 420,
                child: Column(
                  children: [
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setDialogState(() {
                              tempSelected.clear();
                            });
                          },
                          child: const Text('Show all'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            setDialogState(() {
                              tempSelected
                                ..clear()
                                ..addAll(
                                  _allExercises
                                      .map((e) => (e['id'] as num?)?.toInt())
                                      .whereType<int>(),
                                );
                            });
                          },
                          child: const Text('Select all'),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _allExercises.length,
                        itemBuilder: (context, index) {
                          final ex = _allExercises[index];
                          final exId = (ex['id'] as num?)?.toInt();
                          final exName = (ex['name'] ?? 'Exercise').toString();
                          final checked =
                              exId != null && tempSelected.contains(exId);

                          return CheckboxListTile(
                            dense: true,
                            value: checked,
                            title: Text(exName),
                            onChanged: exId == null
                                ? null
                                : (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        tempSelected.add(exId);
                                      } else {
                                        tempSelected.remove(exId);
                                      }
                                    });
                                  },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    try {
      final response = await http.post(
        ApiConfig.uri('/api/stats/preferences/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'tracked_exercises': tempSelected.toList()}),
      );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          _selectedExerciseIds = tempSelected;
          _preferences = {
            ..._preferences,
            'tracked_exercises': tempSelected.toList(),
          };
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exercise selection saved.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saving failed (${response.statusCode}).')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saving failed: $e')));
    }
  }
}

int min(int a, int b) => a < b ? a : b;
