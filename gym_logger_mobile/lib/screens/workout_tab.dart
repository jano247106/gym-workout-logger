import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../screens/template_detail_screen.dart';
import '../screens/create_template_screen.dart';
import '../screens/workout_session_screen.dart';

class WorkoutTab extends StatefulWidget {
  @override
  _WorkoutTabState createState() => _WorkoutTabState();
}

class _WorkoutTabState extends State<WorkoutTab> {
  List templates = [];
  List activeSessions = [];
  bool isLoading = true;

  Map<String, dynamic> _buildEmptyTemplate() {
    return {
      'id': null,
      'name': 'Empty Workout',
      'exercises_in_template': [],
    };
  }

  Future<void> _openCreateTemplate() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (c) => const CreateTemplateScreen()),
    );
    fetchTemplates();
  }

  Future<void> _openEditTemplate(dynamic template) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (c) => CreateTemplateScreen(initialTemplate: template)),
    );
    fetchTemplates();
  }

  Future<void> _deleteTemplate(dynamic template) async {
    final response = await http.delete(
      Uri.parse('http://10.0.2.2:8000/api/templates/${template['id']}/'),
    );

    if (!mounted) return;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Template deleted.')),
      );
      fetchTemplates();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed (${response.statusCode}).')),
      );
    }
  }

  Future<void> _confirmDeleteTemplate(dynamic template) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Delete template?'),
          content: Text('This action cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete')),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await _deleteTemplate(template);
    }
  }

  Future<void> fetchTemplates() async {
    try {
      final templatesResponse = await http.get(Uri.parse('http://10.0.2.2:8000/api/templates/'));
      final activeResponse = await http.get(Uri.parse('http://10.0.2.2:8000/api/workouts/?is_active=true'));

      if (templatesResponse.statusCode == 200 && activeResponse.statusCode == 200) {
        if (mounted) {
          setState(() {
            templates = json.decode(templatesResponse.body);
            activeSessions = json.decode(activeResponse.body);
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print("Chyba API: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _continueSession(dynamic session) async {
    final templateId = session['template'];

    if (templateId == null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WorkoutSessionScreen(
            template: _buildEmptyTemplate(),
            initialWorkoutId: session['id'],
          ),
        ),
      );
      fetchTemplates();
      return;
    }

    dynamic template;
    for (final t in templates) {
      if (t['id'] == templateId) {
        template = t;
        break;
      }
    }

    if (template == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Template for this active session was not found.')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WorkoutSessionScreen(
          template: template,
          initialWorkoutId: session['id'],
        ),
      ),
    );
    fetchTemplates();
  }

  Future<void> _endSession(dynamic session) async {
    final response = await http.put(
      Uri.parse('http://10.0.2.2:8000/api/workouts/${session['id']}/'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'is_finished': true}),
    );

    if (!mounted) return;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Active session ended.')),
      );
      fetchTemplates();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('End session failed (${response.statusCode}).')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    fetchTemplates();
  }

  void _openTemplateDetail(dynamic template) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TemplateDetailScreen(template: template),
      ),
    ).then((_) => fetchTemplates());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Workout", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: fetchTemplates,
        child: isLoading 
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(16),
              children: [
                Text("Quick Start", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => WorkoutSessionScreen(
                          template: _buildEmptyTemplate(),
                        ),
                      ),
                    );
                    fetchTemplates();
                  },
                  icon: Icon(Icons.add),
                  label: Text("Start Empty Workout"),
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(double.infinity, 50),
                    backgroundColor: Colors.grey[200],
                    foregroundColor: Colors.black,
                  ),
                ),
                SizedBox(height: 32),
                if (activeSessions.isNotEmpty) ...[
                  Text("Active Sessions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  ...activeSessions.map((s) {
                    final startedAt = (s['start_time'] ?? '').toString();
                    return Card(
                      margin: EdgeInsets.only(bottom: 10),
                      color: Colors.amber[50],
                      child: ListTile(
                        leading: Icon(Icons.play_circle_fill, color: Colors.orange[700]),
                        title: Text((s['template_name'] ?? 'Untitled workout').toString()),
                        subtitle: Text(startedAt.isEmpty ? 'In progress' : 'Started: $startedAt'),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: () => _continueSession(s),
                              child: Text('Continue'),
                            ),
                            TextButton(
                              onPressed: () => _endSession(s),
                              child: Text('End'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  SizedBox(height: 18),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("My Templates", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      onPressed: _openCreateTemplate,
                      icon: Icon(Icons.add, size: 18),
                      label: Text("Create New"),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                if (templates.isEmpty)
                  Center(child: Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Text("No templates found."),
                  ))
                else
                  ...templates.map((t) {
                    List exercises = t['exercises_in_template'] ?? [];
                    return Card(
                      margin: EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      child: ListTile(
                        leading: Icon(Icons.description, color: Colors.blue),
                        title: Text(t['name'], style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${exercises.length} exercises"),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'Edit template',
                              icon: Icon(Icons.edit_outlined),
                              onPressed: () => _openEditTemplate(t),
                            ),
                            IconButton(
                              tooltip: 'Delete template',
                              icon: Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _confirmDeleteTemplate(t),
                            ),
                            Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => _openTemplateDetail(t),
                      ),
                    );
                  }).toList(),
              ],
            ),
      ),
    );
  }
}