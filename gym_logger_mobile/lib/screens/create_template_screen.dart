import 'package:flutter/material.dart';
import '../models/workout_models.dart';
import '../widgets/exercise_card.dart';
import 'exercise_picker_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CreateTemplateScreen extends StatefulWidget {
  final dynamic initialTemplate;

  const CreateTemplateScreen({super.key, this.initialTemplate});

  @override
  _CreateTemplateScreenState createState() => _CreateTemplateScreenState();
}

class _CreateTemplateScreenState extends State<CreateTemplateScreen> {
  final TextEditingController _nameController = TextEditingController();
  List<SelectedExercise> selectedExercises = [];
  bool _isSaving = false;

  bool get _isEditing => widget.initialTemplate != null;

  @override
  void initState() {
    super.initState();
    _prefillIfEditing();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _prefillIfEditing() {
    final tpl = widget.initialTemplate;
    if (tpl == null) return;

    _nameController.text = tpl['name'] ?? '';
    final List exercisesInTemplate = tpl['exercises_in_template'] ?? [];
    selectedExercises = exercisesInTemplate
        .where((ex) => ex['exercise_id'] != null)
        .map<SelectedExercise>((ex) {
          final List sets = ex['sets'] ?? [];
          return SelectedExercise(
            id: ex['exercise_id'],
            name: ex['exercise_name'] ?? 'Exercise',
            sets: sets
                .map<ExerciseSet>(
                  (s) => ExerciseSet(
                    type: (s['set_type'] ?? 'N').toString(),
                    weight: (s['target_weight'] ?? 0).toDouble(),
                    reps: s['target_reps'] ?? 0,
                  ),
                )
                .toList(),
          );
        })
        .toList();
  }

  void _addExercise() async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (c) => ExercisePickerScreen()));
    if (result != null) {
      setState(() {
        selectedExercises.add(SelectedExercise(
          id: result['id'], 
          name: result['name'], 
          sets: [ExerciseSet()]
        ));
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    final payload = json.encode({
      "name": _nameController.text,
      "exercises": selectedExercises.map((e) => e.toJson()).toList(),
    });

    try {
      final response = _isEditing
          ? await http.put(
              Uri.parse('http://10.0.2.2:8000/api/templates/${widget.initialTemplate['id']}/'),
              headers: {"Content-Type": "application/json"},
              body: payload,
            )
          : await http.post(
              Uri.parse('http://10.0.2.2:8000/api/templates/'),
              headers: {"Content-Type": "application/json"},
              body: payload,
            );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Save failed (${response.statusCode}).")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Network error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? "Edit Template" : "New Template"),
        actions: [
          IconButton(
            icon: _isSaving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.check),
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(controller: _nameController, decoration: InputDecoration(labelText: "Template Name")),
            Expanded(
              child: ReorderableListView(
                onReorder: (old, nw) => setState(() {
                  if (nw > old) nw -= 1;
                  selectedExercises.insert(nw, selectedExercises.removeAt(old));
                }),
                children: [
                  for (int i = 0; i < selectedExercises.length; i++)
                    ExerciseCard(
                      key: ValueKey("ex_${selectedExercises[i].id}_$i"),
                      exercise: selectedExercises[i],
                      onDelete: () => setState(() => selectedExercises.removeAt(i)),
                      onAddSet: () => setState(() => selectedExercises[i].sets.add(ExerciseSet())),
                      onRemoveSet: (setIdx) => setState(() => selectedExercises[i].sets.removeAt(setIdx)),
                      onSetTypeChanged: (setIdx, newType) => setState(() {
                        selectedExercises[i].sets[setIdx].type = newType;
                      }),
                    ),
                ],
              ),
            ),
            ElevatedButton(onPressed: _addExercise, child: Text("ADD EXERCISES")),
          ],
        ),
      ),
    );
  }
}