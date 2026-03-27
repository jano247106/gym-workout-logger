import 'package:flutter/material.dart';
import 'workout_session_screen.dart';

class TemplateDetailScreen extends StatelessWidget {
  final dynamic template;

  TemplateDetailScreen({required this.template});

  @override
  Widget build(BuildContext context) {
    if (template == null) {
      return Scaffold(
        appBar: AppBar(title: Text("New Workout")),
        body: Center(child: Text("Empty workout screen")),
      );
    }

    final List exercises = template['exercises_in_template'] ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(template['name'])),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: exercises.length,
              itemBuilder: (context, index) {
                final ex = exercises[index];
                final List sets = ex['sets'] ?? [];
                final lastWeight = ((ex['last_weight'] ?? 0) as num).toDouble();
                final lastReps = ex['last_reps'] ?? 0;

                return Card(
                  margin: EdgeInsets.only(bottom: 16),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ex['exercise_name'], 
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue[900])
                        ),
                        SizedBox(height: 4),
                        Text(
                          "Last performance: ${lastWeight.toStringAsFixed(1)} kg x $lastReps reps",
                          style: TextStyle(color: Colors.black54),
                        ),
                        Divider(),
                        for (var s in sets)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Text("${s['order']}. ", style: TextStyle(color: Colors.grey)),
                                _buildTypeBadge(s['set_type']),
                                SizedBox(width: 12),
                                Text(
                                  "${s['target_weight']} kg  ×  ${s['target_reps']} reps",
                                  style: TextStyle(fontSize: 15),
                                ),
                              ],
                            ),
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
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => WorkoutSessionScreen(template: template),
                  ),
                );
              },
              child: Text("START WORKOUT", style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 55),
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTypeBadge(String? type) {
    String label = "N";
    Color color = Colors.grey;
    final normalized = (type ?? '').trim().toUpperCase();

    switch (normalized) {
      case 'W': label = "Warmup"; color = Colors.orange; break;
      case 'WARMUP': label = "Warmup"; color = Colors.orange; break;
      case 'F': label = "Failure"; color = Colors.red; break;
      case 'FAILURE': label = "Failure"; color = Colors.red; break;
      case 'D': label = "Dropset"; color = Colors.blue; break;
      case 'DROPSET': label = "Dropset"; color = Colors.blue; break;
      case 'NORMAL': label = "Normal"; color = Colors.grey; break;
      default: label = "Normal"; color = Colors.grey;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1), 
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5))
      ),
      child: Text(
        label, 
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)
      ),
    );
  }
}