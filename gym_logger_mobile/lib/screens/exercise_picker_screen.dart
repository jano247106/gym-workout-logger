import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';

class ExercisePickerScreen extends StatefulWidget {
  @override
  _ExercisePickerScreenState createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<ExercisePickerScreen> {
  List allExercises = [];
  List filteredExercises = [];
  bool isLoading = true;

  Future<void> fetchExercises() async {
    try {
      final response = await http.get(ApiConfig.uri('/api/exercises/'));
      if (response.statusCode == 200) {
        setState(() {
          allExercises = json.decode(response.body);
          filteredExercises = allExercises;
          isLoading = false;
        });
      }
    } catch (e) {
      print("Error: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    fetchExercises();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Select Exercise")),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: filteredExercises.length,
              itemBuilder: (context, index) {
                var ex = filteredExercises[index];
                return ListTile(
                  title: Text(ex['name']),
                  subtitle: Text(ex['muscles'].map((m) => m['body_part_name']).join(', ')),
                  onTap: () {
                    Navigator.pop(context, ex);
                  },
                );
              },
            ),
    );
  }
}