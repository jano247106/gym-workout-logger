import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'exercise_picker_screen.dart';

class WorkoutSessionScreen extends StatefulWidget {
  final dynamic template;
  final int? initialWorkoutId;

  const WorkoutSessionScreen({
    super.key,
    required this.template,
    this.initialWorkoutId,
  });

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  final List<_SessionExercise> _exercises = [];
  Timer? _timer;
  Timer? _autosaveDebounce;
  Timer? _restTimer;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  Duration _restTimeRemaining = Duration.zero;
  int? _workoutId;
  _SessionSet? _activeRestSet;
  bool _isSaving = false;
  bool _isFinishing = false;
  bool _isUpdatingTemplate = false;
  bool _isDiscarding = false;
  bool _isRestoredSession = false;
  bool _pendingAutosave = false;
  String _lastTemplateSnapshot = '';
  static const int _defaultRestSeconds = 90;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _buildSessionFromTemplate();
    _startTimer();
    _restoreOrCreateWorkoutOnServer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _autosaveDebounce?.cancel();
    _restTimer?.cancel();
    for (final ex in _exercises) {
      for (final s in ex.sets) {
        s.dispose();
      }
    }
    super.dispose();
  }

  void _buildSessionFromTemplate() {
    final List templateExercises = widget.template['exercises_in_template'] ?? [];

    for (final ex in templateExercises) {
      final List rawSets = ex['sets'] ?? [];
      final sets = rawSets
          .map<_SessionSet>((s) => _SessionSet(
                type: (s['set_type'] ?? 'N').toString(),
                weight: (s['target_weight'] ?? 0).toDouble(),
                reps: s['target_reps'] ?? 0,
                rpe: s['rpe'] ?? 0,
                templateWeight: (s['target_weight'] ?? 0).toDouble(),
                templateReps: s['target_reps'] ?? 0,
                isCompleted: false,
              ))
          .toList();

      _exercises.add(
        _SessionExercise(
          exerciseId: ex['exercise_id'] ?? 0,
          name: ex['exercise_name'] ?? 'Exercise',
          lastWeight: (ex['last_weight'] ?? 0).toDouble(),
          lastReps: ex['last_reps'] ?? 0,
          lastRpe: ex['last_rpe'],
          sets: sets.isEmpty
              ? [
                  _SessionSet(
                    type: 'N',
                    weight: 0,
                    reps: 0,
                    rpe: 0,
                    templateWeight: 0,
                    templateReps: 10,
                    isCompleted: false,
                  )
                ]
              : sets,
        ),
      );
    }

    _lastTemplateSnapshot = _buildTemplateStructureSnapshot();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _startedAt == null) return;
      setState(() {
        _elapsed = DateTime.now().difference(_startedAt!);
      });
    });
  }

  void _startRestTimer(_SessionSet set) {
    /// Start a rest timer after completing a set.
    /// Default duration is 90 seconds.
    _stopRestTimer();
    _activeRestSet = set;
    _restTimeRemaining = Duration(seconds: _defaultRestSeconds);

    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_restTimeRemaining.inSeconds > 0) {
          _restTimeRemaining = Duration(seconds: _restTimeRemaining.inSeconds - 1);
        } else {
          _stopRestTimer();
        }
      });
    });
  }

  void _stopRestTimer() {
    /// Stop the rest timer and clear the active set.
    _restTimer?.cancel();
    _restTimer = null;
    _activeRestSet = null;
    _restTimeRemaining = Duration.zero;
  }

  Future<void> _createWorkoutOnServer() async {
    try {
      final response = await http.post(
        ApiConfig.uri('/api/workouts/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'template': widget.template['id'],
          'note': '',
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _workoutId = data['id'];
          });
          if (_pendingAutosave) {
            _pendingAutosave = false;
            _saveDraft();
          }
        }
      }
    } catch (_) {
      // Keep session running even if start call fails; finish will fallback to create.
    }
  }

  Future<void> _restoreOrCreateWorkoutOnServer() async {
    if (widget.initialWorkoutId != null) {
      try {
        final response = await http.get(
          ApiConfig.uri('/api/workouts/${widget.initialWorkoutId}/'),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final workout = json.decode(response.body);
          _restoreFromActiveWorkout(workout);
          return;
        }
      } catch (_) {
        // Fall through to template-based restore / create.
      }
    }

    final templateId = widget.template['id'];

    // Empty workout (no template): restore active empty session if any.
    if (templateId == null) {
      try {
        final response = await http.get(
          ApiConfig.uri('/api/workouts/?is_active=true'),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final List workouts = json.decode(response.body);
          final emptyActive = workouts.cast<dynamic>().firstWhere(
            (w) => w['template'] == null,
            orElse: () => null,
          );
          if (emptyActive != null) {
            _restoreFromActiveWorkout(emptyActive);
            return;
          }
        }
      } catch (_) {
        // Fallback to creating a fresh workout.
      }

      await _createWorkoutOnServer();
      return;
    }

    try {
      final response = await http.get(
        ApiConfig.uri('/api/workouts/?template_id=$templateId&is_active=true'),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final List workouts = json.decode(response.body);
        if (workouts.isNotEmpty) {
          _restoreFromActiveWorkout(workouts.first);
          return;
        }
      }
    } catch (_) {
      // If restore fails, fallback to creating a fresh workout.
    }

    await _createWorkoutOnServer();
  }

  void _restoreFromActiveWorkout(dynamic workoutData) {
    final List sets = workoutData['sets'] ?? [];

    final Map<int, dynamic> templateExerciseById = {};
    final List templateExercises = widget.template['exercises_in_template'] ?? [];
    for (final ex in templateExercises) {
      templateExerciseById[ex['exercise_id'] ?? 0] = ex;
    }

    final Map<int, _SessionExercise> grouped = {};
    final List<int> order = [];

    for (final s in sets) {
      final int exerciseId = s['exercise'] ?? 0;
      if (!grouped.containsKey(exerciseId)) {
        final tpl = templateExerciseById[exerciseId];
        grouped[exerciseId] = _SessionExercise(
          exerciseId: exerciseId,
          name: s['exercise_name'] ?? tpl?['exercise_name'] ?? 'Exercise',
          lastWeight: (tpl?['last_weight'] ?? 0).toDouble(),
          lastReps: tpl?['last_reps'] ?? 0,
          lastRpe: tpl?['last_rpe'],
          sets: [],
        );
        order.add(exerciseId);
      }

      grouped[exerciseId]!.sets.add(
        _SessionSet(
          type: (s['set_type'] ?? 'N').toString(),
          weight: (s['weight'] ?? 0).toDouble(),
          reps: s['reps'] ?? 0,
          rpe: s['rpe'] ?? 0,
          templateWeight: (s['weight'] ?? 0).toDouble(),
          templateReps: s['reps'] ?? 0,
          isCompleted: s['is_completed'] ?? false,
        ),
      );
    }

    if (grouped.isEmpty) {
      if (mounted) {
        setState(() {
          _workoutId = workoutData['id'];
          _isRestoredSession = true;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _workoutId = workoutData['id'];
        _isRestoredSession = true;
        _exercises
          ..clear()
          ..addAll(order.map((id) => grouped[id]!).toList());
      });
      _scheduleAutosave();
    }
  }

  String _formatElapsed(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final mins = (d.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$mins:$secs';
  }

  String _formatRestTime(Duration d) {
    /// Format rest timer as MM:SS.
    final mins = d.inMinutes.toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  List<Map<String, dynamic>> _buildSetsPayload() {
    final setsPayload = <Map<String, dynamic>>[];
    for (final ex in _exercises) {
      for (final s in ex.sets) {
        setsPayload.add({
          'exercise': ex.exerciseId,
          'weight': s.weight,
          'reps': s.reps,
          'rpe': s.rpe,
          'is_completed': s.isCompleted,
          'set_type': s.type,
        });
      }
    }
    return setsPayload;
  }

  List<Map<String, dynamic>> _buildTemplateExercisesPayload() {
    return _exercises.map((ex) {
      return {
        'id': ex.exerciseId,
        'sets': ex.sets
            .map(
              (s) => {
                'type': s.type,
                'weight': s.templateWeight,
                'reps': s.templateReps,
              },
            )
            .toList(),
      };
    }).toList();
  }

  String _buildTemplateStructureSnapshot() {
    return json.encode(_buildTemplateExercisesPayload());
  }

  bool _hasUnsavedTemplateStructureChanges() {
    if (widget.template['id'] == null) {
      return false;
    }
    return _buildTemplateStructureSnapshot() != _lastTemplateSnapshot;
  }

  void _scheduleAutosave() {
    if (_isSaving || _isFinishing || _isDiscarding) return;

    if (_workoutId == null) {
      _pendingAutosave = true;
      return;
    }

    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(const Duration(milliseconds: 700), () {
      _saveDraft();
    });
  }

  int _totalSets() {
    return _exercises.fold<int>(0, (sum, ex) => sum + ex.sets.length);
  }

  int _completedSets() {
    int completed = 0;
    for (final ex in _exercises) {
      for (final s in ex.sets) {
        if (s.isCompleted) {
          completed += 1;
        }
      }
    }
    return completed;
  }

  double _progressValue() {
    final total = _totalSets();
    if (total == 0) return 0;
    return _completedSets() / total;
  }

  Future<void> _saveDraft() async {
    final payload = json.encode({
      'template': widget.template['id'],
      'sets': _buildSetsPayload(),
      'is_finished': false,
    });

    try {
      if (_workoutId != null) {
        await http.put(
          ApiConfig.uri('/api/workouts/$_workoutId/'),
          headers: {'Content-Type': 'application/json'},
          body: payload,
        );
      } else {
        final response = await http.post(
          ApiConfig.uri('/api/workouts/'),
          headers: {'Content-Type': 'application/json'},
          body: payload,
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = json.decode(response.body);
          if (mounted) {
            setState(() {
              _workoutId = data['id'];
            });
          }
        }
      }
    } catch (_) {
      // Silent fail: leaving screen should not be blocked by network issues.
    }
  }

  Future<bool> _handleBackPress() async {
    if (_isFinishing) return true;
    await _saveDraft();
    return true;
  }

  Future<void> _pickRpe(_SessionSet set) async {
    double selected = set.rpe.toDouble();

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, localSetState) {
            return AlertDialog(
              title: const Text('Set RPE'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selected.round().toString(),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: selected,
                    min: 0,
                    max: 10,
                    divisions: 10,
                    label: selected.round().toString(),
                    onChanged: (value) {
                      localSetState(() {
                        selected = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, selected.round()),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;
    setState(() {
      set.rpe = result;
    });
    _scheduleAutosave();
  }

  Future<void> _pickSetType(_SessionSet set) async {
    final options = <Map<String, dynamic>>[
      {'value': 'N', 'label': 'Normal', 'color': Colors.grey},
      {'value': 'W', 'label': 'Warmup', 'color': Colors.orange},
      {'value': 'F', 'label': 'Failure', 'color': Colors.red},
      {'value': 'D', 'label': 'Dropset', 'color': Colors.blue},
    ];

    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          child: SafeArea(
            child: Column(
              children: [
                AppBar(
                  title: const Text('Select Set Type'),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: options.length,
                    separatorBuilder: (_, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = options[index];
                      final isSelected = set.type.toUpperCase() == item['value'];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: (item['color'] as Color).withValues(alpha: 0.2),
                          child: Text(
                            item['value'] as String,
                            style: TextStyle(color: item['color'] as Color, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(item['label'] as String),
                        trailing: isSelected ? const Icon(Icons.check) : null,
                        onTap: () => Navigator.pop(context, item['value'] as String),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null) return;
    setState(() {
      set.type = selected;
    });
    _scheduleAutosave();
  }

  Future<bool?> _askFinishTemplateDecision() async {
    return showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save Template Changes?'),
          content: const Text(
            'You changed exercise order or set structure in this workout.\n\n'
            'Do you want to update the original workout template before finishing?\n'
            'Previous performance results will be preserved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Finish Only'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save & Finish'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _updateTemplateFromSession({bool showFeedback = true}) async {
    if (_isUpdatingTemplate || _isSaving) return false;
    final templateId = widget.template['id'];
    if (templateId == null) return false;

    if (showFeedback) {
      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Update Workout Template?'),
            content: const Text(
              'This will update the selected workout template with the current exercise order and set structure. '
              'Previous performance results will be preserved.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Update'),
              ),
            ],
          );
        },
      );

      if (shouldUpdate != true) return false;
    }

    setState(() => _isUpdatingTemplate = true);
    bool success = false;

    try {
      final response = await http.put(
        ApiConfig.uri('/api/templates/$templateId/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': widget.template['name'],
          'exercises': _buildTemplateExercisesPayload(),
        }),
      );

      if (!mounted) return false;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        success = true;
        _lastTemplateSnapshot = _buildTemplateStructureSnapshot();
        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Template updated from current workout structure.')),
          );
        }
      } else {
        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Template update failed (${response.statusCode}).')),
          );
        }
      }
    } catch (e) {
      if (mounted && showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Template update error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingTemplate = false);
    }

    return success;
  }

  void _copyPreviousToSet(_SessionExercise ex, _SessionSet set) {
    final prevWeight = ex.lastWeight;
    final prevReps = ex.lastReps;
    final prevRpe = ex.lastRpe;

    set.weight = prevWeight;
    set.reps = prevReps;
    if (prevRpe != null) {
      set.rpe = prevRpe;
    }
    set.weightController.text = prevWeight == 0 ? '' : prevWeight.toStringAsFixed(1);
    set.repsController.text = prevReps == 0 ? '' : prevReps.toString();

    setState(() {});
    _scheduleAutosave();
  }

  void _addSet(int exerciseIndex) {
    setState(() {
      _exercises[exerciseIndex].sets.add(
        _SessionSet(
          type: 'N',
          weight: 0,
          reps: 0,
          rpe: 0,
          templateWeight: 0,
          templateReps: 10,
          isCompleted: false,
        ),
      );
    });
    _scheduleAutosave();
  }

  void _removeSet(int exerciseIndex, int setIndex) {
    final set = _exercises[exerciseIndex].sets.removeAt(setIndex);
    set.dispose();
    setState(() {});
    _scheduleAutosave();
  }

  Future<void> _addExercise() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ExercisePickerScreen()),
    );

    if (!mounted || result == null) return;

    setState(() {
      _exercises.add(
        _SessionExercise(
          exerciseId: result['id'] ?? 0,
          name: result['name'] ?? 'Exercise',
          lastWeight: 0,
          lastReps: 0,
          lastRpe: null,
          sets: [
            _SessionSet(
              type: 'N',
              weight: 0,
              reps: 0,
              rpe: 0,
              templateWeight: 0,
              templateReps: 10,
              isCompleted: false,
            )
          ],
        ),
      );
    });
    _scheduleAutosave();
  }

  void _removeExercise(int exerciseIndex) {
    final exercise = _exercises.removeAt(exerciseIndex);
    for (final s in exercise.sets) {
      s.dispose();
    }
    setState(() {});
    _scheduleAutosave();
  }

  void _moveExercise(int oldIndex, int newIndex) {
    if (newIndex < 0 || newIndex >= _exercises.length) return;

    setState(() {
      final ex = _exercises.removeAt(oldIndex);
      _exercises.insert(newIndex, ex);
    });
    _scheduleAutosave();
  }

  String _formatPreviousLabel(_SessionExercise ex) {
    return '${ex.lastWeight.toStringAsFixed(1)} x ${ex.lastReps}';
  }

  Future<void> _discardWorkout() async {
    if (_isSaving || _isFinishing || _isUpdatingTemplate || _isDiscarding) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Discard Workout?'),
          content: const Text('This will cancel the current workout and no sets from this session will be saved.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _isDiscarding = true);

    try {
      if (_workoutId != null) {
        await http.delete(ApiConfig.uri('/api/workouts/$_workoutId/'));
      }
      if (mounted) Navigator.pop(context, false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Discard failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDiscarding = false);
    }
  }

  Future<void> _finishWorkout() async {
    if (_isSaving) return;

    if (_hasUnsavedTemplateStructureChanges()) {
      final decision = await _askFinishTemplateDecision();
      if (decision == null) return;

      if (decision == true) {
        final synced = await _updateTemplateFromSession(showFeedback: false);
        if (!synced) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not save template changes. Workout was not finished.')),
            );
          }
          return;
        }
      }
    }

    setState(() {
      _isSaving = true;
      _isFinishing = true;
    });

    try {
      final payload = json.encode({
        'template': widget.template['id'],
        'sets': _buildSetsPayload(),
        'is_finished': true,
      });

      http.Response response;
      if (_workoutId != null) {
        response = await http.put(
          ApiConfig.uri('/api/workouts/$_workoutId/'),
          headers: {'Content-Type': 'application/json'},
          body: payload,
        );
      } else {
        response = await http.post(
          ApiConfig.uri('/api/workouts/'),
          headers: {'Content-Type': 'application/json'},
          body: payload,
        );
      }

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Finish failed (${response.statusCode}).')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isFinishing = false;
        });
      }
    }
  }

  bool _isNormalType(String type) {
    final normalized = type.toUpperCase();
    return normalized != 'W' &&
        normalized != 'WARMUP' &&
        normalized != 'F' &&
        normalized != 'FAILURE' &&
        normalized != 'D' &&
        normalized != 'DROPSET';
  }

  Widget _buildTypeBadge(String type, {int? normalOrder}) {
    String label;
    Color color;

    switch (type.toUpperCase()) {
      case 'W':
      case 'WARMUP':
        label = 'W';
        color = Colors.orange;
        break;
      case 'F':
      case 'FAILURE':
        label = 'F';
        color = Colors.red;
        break;
      case 'D':
      case 'DROPSET':
        label = 'D';
        color = Colors.blue;
        break;
      default:
        label = normalOrder?.toString() ?? 'N';
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildExerciseMenu(int exIndex) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'remove') {
          _removeExercise(exIndex);
        } else if (value == 'up') {
          _moveExercise(exIndex, exIndex - 1);
        } else if (value == 'down') {
          _moveExercise(exIndex, exIndex + 1);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'up',
          enabled: exIndex > 0,
          child: const Text('Move up'),
        ),
        PopupMenuItem(
          value: 'down',
          enabled: exIndex < _exercises.length - 1,
          child: const Text('Move down'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'remove',
          child: Text('Remove exercise'),
        ),
      ],
    );
  }

  Widget _buildSetRow(_SessionExercise ex, int exIndex, int setIndex, int? normalOrder) {
    final set = ex.sets[setIndex];

    return Dismissible(
      key: ValueKey('set_${set.id}_${ex.exerciseId}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _removeSet(exIndex, setIndex),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _pickSetType(set),
              child: _buildTypeBadge(set.type, normalOrder: normalOrder),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 78,
              child: InkWell(
                onTap: () => _copyPreviousToSet(ex, set),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Prev', style: TextStyle(fontSize: 11, color: Colors.black54)),
                      const SizedBox(height: 2),
                      Text(
                        _formatPreviousLabel(ex),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: TextField(
                controller: set.weightController,
                onChanged: (_) {
                  setState(() {});
                  _scheduleAutosave();
                },
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'kg',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: TextField(
                controller: set.repsController,
                onChanged: (_) {
                  setState(() {});
                  _scheduleAutosave();
                },
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'reps',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              child: InkWell(
                onTap: () => _pickRpe(set),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      const Text('RPE', style: TextStyle(fontSize: 9, color: Colors.black54)),
                      Text(
                        set.rpe.toString(),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 28,
              child: Checkbox(
                value: set.isCompleted,
                onChanged: (value) {
                  setState(() {
                    set.isCompleted = value ?? false;
                    // Start rest timer when set is marked as completed
                    if (set.isCompleted) {
                      _startRestTimer(set);
                    } else {
                      _stopRestTimer();
                    }
                  });
                  _scheduleAutosave();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completedSets = _completedSets();
    final totalSets = _totalSets();
    final progress = _progressValue();

    return PopScope(
      canPop: _isFinishing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _handleBackPress();
        if (!mounted) return;
        if (shouldPop) Navigator.of(this.context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.template['name'] ?? 'Workout Session'),
          actions: [
            IconButton(
              tooltip: 'Update Template',
              onPressed: widget.template['id'] == null || _isUpdatingTemplate || _isSaving || _isDiscarding
                  ? null
                  : _updateTemplateFromSession,
              icon: _isUpdatingTemplate
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_as_outlined),
            ),
            IconButton(
              tooltip: 'Discard Workout',
              onPressed: _isDiscarding ? null : _discardWorkout,
              icon: _isDiscarding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  _formatElapsed(_elapsed),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            )
          ],
        ),
        body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isRestoredSession)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.5)),
                    ),
                    child: const Text(
                      'Restored from unfinished workout',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                Text(
                  'Progress: $completedSets / $totalSets sets',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(8),
                ),
              ],
            ),
          ),
          if (_activeRestSet != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade300, width: 2),
              ),
              child: Column(
                children: [
                  const Text(
                    'Rest Time',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            if (_restTimeRemaining.inSeconds >= 15) {
                              _restTimeRemaining = Duration(seconds: _restTimeRemaining.inSeconds - 15);
                            }
                          });
                        },
                        icon: const Icon(Icons.remove_circle, size: 32, color: Colors.red),
                        tooltip: 'Decrease by 15s',
                      ),
                      const SizedBox(width: 16),
                      Text(
                        _formatRestTime(_restTimeRemaining),
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _restTimeRemaining = Duration(seconds: _restTimeRemaining.inSeconds + 15);
                          });
                        },
                        icon: const Icon(Icons.add_circle, size: 32, color: Colors.green),
                        tooltip: 'Increase by 15s',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _stopRestTimer,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Skip Rest'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade200,
                          foregroundColor: Colors.black87,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _restTimeRemaining = Duration(seconds: _defaultRestSeconds);
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade100,
                          foregroundColor: Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _exercises.length + 1,
              itemBuilder: (context, exIndex) {
                if (exIndex == _exercises.length) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      onPressed: _addExercise,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Exercise'),
                    ),
                  );
                }

                final ex = _exercises[exIndex];
                return Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                ex.name,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[900],
                                ),
                              ),
                            ),
                            _buildExerciseMenu(exIndex),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Last performance: ${ex.lastWeight.toStringAsFixed(1)} kg x ${ex.lastReps} reps',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const Divider(),
                        Builder(
                          builder: (_) {
                            int normalSetCounter = 0;
                            return Column(
                              children: [
                                for (int setIndex = 0; setIndex < ex.sets.length; setIndex++)
                                  Builder(
                                    builder: (_) {
                                      final set = ex.sets[setIndex];
                                      final isNormal = _isNormalType(set.type);
                                      final normalOrder = isNormal ? ++normalSetCounter : null;
                                      return _buildSetRow(ex, exIndex, setIndex, normalOrder);
                                    },
                                  ),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () => _addSet(exIndex),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Set'),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _isSaving ? null : _finishWorkout,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('FINISH WORKOUT', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
      ),
    );
  }
}

class _SessionExercise {
  final int exerciseId;
  final String name;
  final double lastWeight;
  final int lastReps;
  final int? lastRpe;
  final List<_SessionSet> sets;

  _SessionExercise({
    required this.exerciseId,
    required this.name,
    required this.lastWeight,
    required this.lastReps,
    required this.lastRpe,
    required this.sets,
  });
}

class _SessionSet {
  static int _nextId = 1;

  final int id;
  String type;
  double weight;
  int reps;
  int rpe;
  double templateWeight;
  int templateReps;
  bool isCompleted;
  final TextEditingController weightController;
  final TextEditingController repsController;

  _SessionSet({
    required this.type,
    required this.weight,
    required this.reps,
    required this.rpe,
    required this.templateWeight,
    required this.templateReps,
    this.isCompleted = false,
  })  : id = _nextId++,
        weightController = TextEditingController(text: weight == 0 ? '' : weight.toString()),
        repsController = TextEditingController(text: reps == 0 ? '' : reps.toString()) {
    weightController.addListener(() {
      weight = double.tryParse(weightController.text) ?? 0.0;
    });
    repsController.addListener(() {
      reps = int.tryParse(repsController.text) ?? 0;
    });
  }

  void dispose() {
    weightController.dispose();
    repsController.dispose();
  }
}
