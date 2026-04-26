from django.db import models
from django.contrib.auth.models import User

from django.db import models
from django.contrib.auth.models import User

class BodyPart(models.Model):
    name = models.CharField(max_length=50)
    def __str__(self): return self.name

class Exercise(models.Model):
    name = models.CharField(max_length=100)
    description = models.TextField(blank=True, null=True)
    image_url = models.URLField(blank=True, null=True) 
    machine_id = models.CharField(max_length=20, blank=True, null=True)
    def __str__(self): return self.name

class ExerciseBodyPart(models.Model):
    exercise = models.ForeignKey(Exercise, on_delete=models.CASCADE, related_name='muscles')
    body_part = models.ForeignKey(BodyPart, on_delete=models.CASCADE)
    is_primary = models.BooleanField(default=True) 

class WorkoutTemplate(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    name = models.CharField(max_length=100)
    created_at = models.DateTimeField(auto_now_add=True)
    def __str__(self): return self.name

class TemplateExercise(models.Model):
    template = models.ForeignKey(WorkoutTemplate, on_delete=models.CASCADE, related_name='template_exercises')
    exercise = models.ForeignKey(Exercise, on_delete=models.CASCADE)
    order = models.PositiveIntegerField(default=0)

class TemplateSet(models.Model):
    SET_TYPES = [('W', 'Warmup'), ('N', 'Normal'), ('F', 'Failure'), ('D', 'Dropset')]
    template_exercise = models.ForeignKey(TemplateExercise, on_delete=models.CASCADE, related_name='sets')
    order = models.PositiveIntegerField(default=1)
    target_reps = models.PositiveIntegerField(default=10)
    target_weight = models.FloatField(default=0.0)
    set_type = models.CharField(max_length=1, choices=SET_TYPES, default='N')

class PerformedWorkout(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    template = models.ForeignKey(WorkoutTemplate, on_delete=models.SET_NULL, null=True, blank=True)
    start_time = models.DateTimeField(auto_now_add=True)
    end_time = models.DateTimeField(null=True, blank=True)
    note = models.TextField(blank=True)

class WorkoutSet(models.Model):
    SET_TYPES = [
        ('N', 'Normal'),
        ('W', 'Warm-up'),
        ('D', 'Drop Set'),
        ('F', 'Failure'),
    ]
    
    workout = models.ForeignKey(PerformedWorkout, related_name='sets', on_delete=models.CASCADE)
    exercise = models.ForeignKey(Exercise, on_delete=models.CASCADE)
    weight = models.FloatField()
    reps = models.IntegerField()
    rpe = models.IntegerField(null=True, blank=True)
    is_completed = models.BooleanField(default=False)
    set_type = models.CharField(max_length=1, choices=SET_TYPES, default='N')

    def __str__(self):
        return f"{self.set_type} - {self.exercise.name}: {self.weight}kg"

class UserStatsPreference(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='stats_preference')
    # Top exercises to track (JSON array of exercise IDs)
    tracked_exercises = models.JSONField(default=list, blank=True)
    # Primary exercises for main muscle groups (chest, back, legs)
    primary_chest_exercise = models.ForeignKey(Exercise, on_delete=models.SET_NULL, null=True, blank=True, related_name='primary_chest')
    primary_back_exercise = models.ForeignKey(Exercise, on_delete=models.SET_NULL, null=True, blank=True, related_name='primary_back')
    primary_legs_exercise = models.ForeignKey(Exercise, on_delete=models.SET_NULL, null=True, blank=True, related_name='primary_legs')
    
    def __str__(self):
        return f"Stats Preferences for {self.user.username}"