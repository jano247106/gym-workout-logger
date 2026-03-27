import 'package:flutter/material.dart';
import '../models/workout_models.dart';

class ExerciseCard extends StatelessWidget {
  final SelectedExercise exercise;
  final VoidationCallback onDelete;
  final VoidationCallback onAddSet;
  final Function(int) onRemoveSet;
  final Function(int, String) onSetTypeChanged;

  ExerciseCard({
    required this.exercise, 
    required this.onDelete, 
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onSetTypeChanged,
    required Key key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            title: Text(exercise.name, style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: IconButton(icon: Icon(Icons.delete, color: Colors.red), onPressed: onDelete),
          ),
          for (int i = 0; i < exercise.sets.length; i++)
            _buildSetRow(i),
          TextButton.icon(onPressed: onAddSet, icon: Icon(Icons.add), label: Text("Add Set")),
        ],
      ),
    );
  }

  Widget _buildSetRow(int index) {
    final set = exercise.sets[index];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          CircleAvatar(radius: 12, child: Text("${index + 1}", style: TextStyle(fontSize: 10))),
          SizedBox(width: 8),
          DropdownButton<String>(
            value: set.type,
            onChanged: (v) {
              if (v != null) {
                onSetTypeChanged(index, v);
              }
            },
            items: [
              DropdownMenuItem(value: 'N', child: Text("Normal")),
              DropdownMenuItem(value: 'W', child: Text("Warmup")),
              DropdownMenuItem(value: 'F', child: Text("Failure")),
              DropdownMenuItem(value: 'D', child: Text("Dropset")),
            ],
          ),
          SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: set.weight == 0 ? "" : set.weight.toString(),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(hintText: "kg", isDense: true, border: OutlineInputBorder()),
              onChanged: (v) => set.weight = double.tryParse(v) ?? 0.0,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: set.reps == 0 ? "" : set.reps.toString(),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: "reps", isDense: true, border: OutlineInputBorder()),
              onChanged: (v) => set.reps = int.tryParse(v) ?? 0,
            ),
          ),
          IconButton(icon: Icon(Icons.close, size: 16), onPressed: () => onRemoveSet(index)),
        ],
      ),
    );
  }
}

typedef VoidationCallback = void Function();