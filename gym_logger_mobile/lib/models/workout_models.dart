class ExerciseSet {
  String type;
  double weight;
  int reps;

  ExerciseSet({this.type = 'N', this.weight = 0.0, this.reps = 0});

  Map<String, dynamic> toJson() => {
    'type': type,
    'weight': weight,
    'reps': reps,
  };
}

class SelectedExercise {
  final int id;
  final String name;
  List<ExerciseSet> sets;

  SelectedExercise({required this.id, required this.name, required this.sets});

  Map<String, dynamic> toJson() => {
    'id': id,
    'sets': sets.map((s) => s.toJson()).toList(),
  };
}