# COMMAND FOR RUNNING TESTS
# python manage.py test gym_api.tests

from django.test import TestCase, Client
from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework.test import APITestCase
from rest_framework import status
from .models import (
    BodyPart, Exercise, ExerciseBodyPart, WorkoutTemplate, 
    TemplateExercise, TemplateSet, PerformedWorkout, WorkoutSet, 
    UserStatsPreference
)
from .serializers import TemplateExerciseSerializer, PerformedWorkoutSerializer
from .views import StatsViewSet


class BodyPartModelTests(TestCase):
    """Test BodyPart model creation and string representation."""
    
    def test_bodypart_creation(self):
        """Verify that a BodyPart can be created with a name."""
        body_part = BodyPart.objects.create(name="Chest")
        self.assertEqual(body_part.name, "Chest")
        self.assertEqual(str(body_part), "Chest")
    
    def test_bodypart_string_representation(self):
        """Verify that BodyPart __str__ returns the name."""
        body_part = BodyPart.objects.create(name="Back")
        self.assertEqual(str(body_part), "Back")


class ExerciseModelTests(TestCase):
    """Test Exercise model creation and attributes."""
    
    def test_exercise_creation_minimal(self):
        """Verify that an Exercise can be created with just a name."""
        exercise = Exercise.objects.create(name="Bench Press")
        self.assertEqual(exercise.name, "Bench Press")
        self.assertIsNone(exercise.description)
        self.assertIsNone(exercise.image_url)
    
    def test_exercise_creation_full(self):
        """Verify that an Exercise can be created with all optional fields."""
        exercise = Exercise.objects.create(
            name="Barbell Squat",
            description="Heavy leg exercise",
            image_url="http://example.com/squat.jpg",
            machine_id="SM-001"
        )
        self.assertEqual(exercise.name, "Barbell Squat")
        self.assertEqual(exercise.description, "Heavy leg exercise")
        self.assertEqual(exercise.machine_id, "SM-001")
    
    def test_exercise_string_representation(self):
        """Verify that Exercise __str__ returns the name."""
        exercise = Exercise.objects.create(name="Deadlift")
        self.assertEqual(str(exercise), "Deadlift")


class ExerciseBodyPartTests(TestCase):
    """Test ExerciseBodyPart relationship model."""
    
    def setUp(self):
        """Set up test data for ExerciseBodyPart tests."""
        self.chest = BodyPart.objects.create(name="Chest")
        self.triceps = BodyPart.objects.create(name="Triceps")
        self.exercise = Exercise.objects.create(name="Bench Press")
    
    def test_exercise_bodypart_creation_primary(self):
        """Verify that ExerciseBodyPart can mark an exercise as primary for a body part."""
        ebp = ExerciseBodyPart.objects.create(
            exercise=self.exercise,
            body_part=self.chest,
            is_primary=True
        )
        self.assertTrue(ebp.is_primary)
        self.assertEqual(ebp.exercise, self.exercise)
        self.assertEqual(ebp.body_part, self.chest)
    
    def test_exercise_bodypart_creation_secondary(self):
        """Verify that ExerciseBodyPart can mark an exercise as secondary for a body part."""
        ebp = ExerciseBodyPart.objects.create(
            exercise=self.exercise,
            body_part=self.triceps,
            is_primary=False
        )
        self.assertFalse(ebp.is_primary)
    
    def test_exercise_multiple_body_parts(self):
        """Verify that an exercise can target multiple body parts."""
        ebp1 = ExerciseBodyPart.objects.create(
            exercise=self.exercise,
            body_part=self.chest,
            is_primary=True
        )
        ebp2 = ExerciseBodyPart.objects.create(
            exercise=self.exercise,
            body_part=self.triceps,
            is_primary=False
        )
        self.assertEqual(self.exercise.muscles.count(), 2)


class WorkoutTemplateTests(TestCase):
    """Test WorkoutTemplate model and creation."""
    
    def setUp(self):
        """Set up test data for WorkoutTemplate tests."""
        self.user = User.objects.create_user(username="testuser", password="pass123")
    
    def test_workout_template_creation(self):
        """Verify that a WorkoutTemplate can be created with user and name."""
        template = WorkoutTemplate.objects.create(
            user=self.user,
            name="Push Day"
        )
        self.assertEqual(template.name, "Push Day")
        self.assertEqual(template.user, self.user)
        self.assertIsNotNone(template.created_at)
    
    def test_workout_template_string_representation(self):
        """Verify that WorkoutTemplate __str__ returns the name."""
        template = WorkoutTemplate.objects.create(
            user=self.user,
            name="Leg Day"
        )
        self.assertEqual(str(template), "Leg Day")


class TemplateExerciseTests(TestCase):
    """Test TemplateExercise model for exercise ordering in templates."""
    
    def setUp(self):
        """Set up test data for TemplateExercise tests."""
        self.user = User.objects.create_user(username="testuser", password="pass123")
        self.template = WorkoutTemplate.objects.create(user=self.user, name="Full Body")
        self.exercise1 = Exercise.objects.create(name="Squat")
        self.exercise2 = Exercise.objects.create(name="Bench Press")
    
    def test_template_exercise_ordering(self):
        """Verify that exercises can be ordered within a template."""
        te1 = TemplateExercise.objects.create(
            template=self.template,
            exercise=self.exercise1,
            order=1
        )
        te2 = TemplateExercise.objects.create(
            template=self.template,
            exercise=self.exercise2,
            order=2
        )
        exercises = self.template.template_exercises.order_by('order')
        self.assertEqual(exercises[0].exercise.name, "Squat")
        self.assertEqual(exercises[1].exercise.name, "Bench Press")


class TemplateSetTests(TestCase):
    """Test TemplateSet model for set configuration in templates."""
    
    def setUp(self):
        """Set up test data for TemplateSet tests."""
        self.user = User.objects.create_user(username="testuser", password="pass123")
        self.template = WorkoutTemplate.objects.create(user=self.user, name="Full Body")
        self.exercise = Exercise.objects.create(name="Squat")
        self.template_exercise = TemplateExercise.objects.create(
            template=self.template,
            exercise=self.exercise,
            order=1
        )
    
    def test_template_set_creation(self):
        """Verify that TemplateSet stores target reps, weight, and set type."""
        tset = TemplateSet.objects.create(
            template_exercise=self.template_exercise,
            order=1,
            target_reps=5,
            target_weight=100.0,
            set_type='N'
        )
        self.assertEqual(tset.target_reps, 5)
        self.assertEqual(tset.target_weight, 100.0)
        self.assertEqual(tset.set_type, 'N')
    
    def test_template_set_types(self):
        """Verify that all set type choices are valid."""
        for set_type_code, set_type_name in TemplateSet.SET_TYPES:
            tset = TemplateSet.objects.create(
                template_exercise=self.template_exercise,
                order=1,
                set_type=set_type_code
            )
            self.assertEqual(tset.set_type, set_type_code)


class PerformedWorkoutTests(TestCase):
    """Test PerformedWorkout model for tracking completed workouts."""
    
    def setUp(self):
        """Set up test data for PerformedWorkout tests."""
        self.user = User.objects.create_user(username="testuser", password="pass123")
        self.template = WorkoutTemplate.objects.create(user=self.user, name="Push Day")
    
    def test_performed_workout_creation(self):
        """Verify that a PerformedWorkout records start time automatically."""
        workout = PerformedWorkout.objects.create(
            user=self.user,
            template=self.template,
            note="Good session"
        )
        self.assertEqual(workout.user, self.user)
        self.assertEqual(workout.template, self.template)
        self.assertEqual(workout.note, "Good session")
        self.assertIsNotNone(workout.start_time)
        self.assertIsNone(workout.end_time)
    
    def test_performed_workout_end_time(self):
        """Verify that end_time can be set to mark workout completion."""
        workout = PerformedWorkout.objects.create(user=self.user)
        self.assertIsNone(workout.end_time)
        workout.end_time = timezone.now()
        workout.save()
        self.assertIsNotNone(workout.end_time)
    
    def test_performed_workout_without_template(self):
        """Verify that a PerformedWorkout can be created without a template (custom workout)."""
        workout = PerformedWorkout.objects.create(user=self.user, template=None)
        self.assertIsNone(workout.template)


class WorkoutSetTests(TestCase):
    """Test WorkoutSet model for individual set tracking."""
    
    def setUp(self):
        """Set up test data for WorkoutSet tests."""
        self.user = User.objects.create_user(username="testuser", password="pass123")
        self.workout = PerformedWorkout.objects.create(user=self.user)
        self.exercise = Exercise.objects.create(name="Bench Press")
    
    def test_workout_set_creation(self):
        """Verify that a WorkoutSet records weight, reps, and RPE."""
        wset = WorkoutSet.objects.create(
            workout=self.workout,
            exercise=self.exercise,
            weight=100.0,
            reps=8,
            rpe=8,
            set_type='N'
        )
        self.assertEqual(wset.weight, 100.0)
        self.assertEqual(wset.reps, 8)
        self.assertEqual(wset.rpe, 8)
        self.assertFalse(wset.is_completed)
    
    def test_workout_set_completion(self):
        """Verify that a WorkoutSet can be marked as completed."""
        wset = WorkoutSet.objects.create(
            workout=self.workout,
            exercise=self.exercise,
            weight=80.0,
            reps=10
        )
        self.assertFalse(wset.is_completed)
        wset.is_completed = True
        wset.save()
        self.assertTrue(wset.is_completed)
    
    def test_workout_set_string_representation(self):
        """Verify that WorkoutSet __str__ contains set type, exercise, and weight."""
        wset = WorkoutSet.objects.create(
            workout=self.workout,
            exercise=self.exercise,
            weight=100.0,
            reps=5,
            set_type='N'
        )
        self.assertIn("Bench Press", str(wset))
        self.assertIn("100", str(wset))


class UserStatsPreferenceTests(TestCase):
    """Test UserStatsPreference model for user preferences."""
    
    def setUp(self):
        """Set up test data for UserStatsPreference tests."""
        self.user = User.objects.create_user(username="testuser", password="pass123")
        self.chest_ex = Exercise.objects.create(name="Bench Press")
        self.back_ex = Exercise.objects.create(name="Deadlift")
        self.leg_ex = Exercise.objects.create(name="Squat")
    
    def test_stats_preference_creation(self):
        """Verify that UserStatsPreference can be created with primary exercises."""
        prefs = UserStatsPreference.objects.create(
            user=self.user,
            primary_chest_exercise=self.chest_ex,
            primary_back_exercise=self.back_ex,
            primary_legs_exercise=self.leg_ex
        )
        self.assertEqual(prefs.primary_chest_exercise, self.chest_ex)
        self.assertEqual(prefs.primary_back_exercise, self.back_ex)
        self.assertEqual(prefs.primary_legs_exercise, self.leg_ex)
    
    def test_stats_preference_tracked_exercises(self):
        """Verify that tracked_exercises JSON field stores exercise IDs."""
        prefs = UserStatsPreference.objects.create(
            user=self.user,
            tracked_exercises=[1, 2, 3]
        )
        self.assertEqual(prefs.tracked_exercises, [1, 2, 3])


class WorkoutAPITests(APITestCase):
    """Test WorkoutViewSet API endpoints."""
    
    def setUp(self):
        """Set up test data for API tests."""
        self.user = User.objects.create_user(username="testuser", password="pass123")
        self.exercise = Exercise.objects.create(name="Bench Press")
        self.template = WorkoutTemplate.objects.create(user=self.user, name="Push Day")
    
    def test_create_performed_workout(self):
        """Verify that a POST request creates a PerformedWorkout."""
        url = '/api/workouts/'
        data = {
            'template': self.template.id,
            'note': 'Great workout',
            'sets': [
                {'exercise': self.exercise.id, 'weight': 100, 'reps': 8, 'set_type': 'N'}
            ]
        }
        response = self.client.post(url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(PerformedWorkout.objects.count(), 1)
    
    def test_get_workouts_filtered_by_active(self):
        """Verify that workouts can be filtered by active status."""
        active_workout = PerformedWorkout.objects.create(user=self.user, template=self.template)
        completed_workout = PerformedWorkout.objects.create(
            user=self.user,
            template=self.template,
            end_time=timezone.now()
        )
        
        url = '/api/workouts/?is_active=true'
        response = self.client.get(url, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
    
    def test_delete_workout(self):
        """Verify that a DELETE request removes a PerformedWorkout."""
        workout = PerformedWorkout.objects.create(user=self.user, template=self.template)
        url = f'/api/workouts/{workout.id}/'
        response = self.client.delete(url)
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(PerformedWorkout.objects.filter(id=workout.id).exists())


class WorkoutTemplateAPITests(APITestCase):
    """Test WorkoutTemplateViewSet API endpoints."""
    
    def setUp(self):
        """Set up test data for template API tests."""
        self.user = User.objects.create_user(username="testuser", password="pass123")
        self.exercise1 = Exercise.objects.create(name="Squat")
        self.exercise2 = Exercise.objects.create(name="Leg Press")
    
    def test_create_workout_template(self):
        """Verify that a POST request creates a WorkoutTemplate with exercises."""
        url = '/api/templates/'
        data = {
            'name': 'Leg Day',
            'exercises': [
                {
                    'id': self.exercise1.id,
                    'sets': [
                        {'reps': 5, 'weight': 150, 'type': 'N'},
                        {'reps': 5, 'weight': 150, 'type': 'N'}
                    ]
                },
                {
                    'id': self.exercise2.id,
                    'sets': [
                        {'reps': 8, 'weight': 100, 'type': 'N'}
                    ]
                }
            ]
        }
        response = self.client.post(url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(WorkoutTemplate.objects.count(), 1)
    
    def test_delete_workout_template(self):
        """Verify that a DELETE request removes a WorkoutTemplate and its exercises."""
        template = WorkoutTemplate.objects.create(user=self.user, name="Test Template")
        TemplateExercise.objects.create(template=template, exercise=self.exercise1, order=1)
        
        url = f'/api/templates/{template.id}/'
        response = self.client.delete(url)
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(WorkoutTemplate.objects.filter(id=template.id).exists())
        self.assertEqual(TemplateExercise.objects.filter(template=template).count(), 0)


class BrzycskiFormulaTests(TestCase):
    """Test 1RM Brzycki formula calculations in stats."""
    
    def test_brzycki_1rm_formula(self):
        """Verify that Brzycki formula correctly calculates estimated 1RM.
        
        Formula: 1RM = weight * (36 / (37 - reps))
        Example: 100kg x 5 reps ≈ 112.5kg 1RM
        """
        stats_view = StatsViewSet()
        
        # Test: 100kg x 5 reps should be ~112.5kg 1RM
        result = stats_view._calculate_1rm_brzycki(weight=100, reps=5)
        self.assertAlmostEqual(result, 112.5, places=1)
        
        # Test: 100kg x 1 rep should be 100kg 1RM
        result = stats_view._calculate_1rm_brzycki(weight=100, reps=1)
        self.assertEqual(result, 100)
        
        # Test: 80kg x 10 reps should be ~106.7kg 1RM
        result = stats_view._calculate_1rm_brzycki(weight=80, reps=10)
        self.assertAlmostEqual(result, 106.7, places=1)
    
    def test_brzycki_formula_high_reps(self):
        """Verify that Brzycki formula returns weight for very high reps (>36)."""
        stats_view = StatsViewSet()
        
        # For reps > 36, formula is unreliable, so it returns the weight
        result = stats_view._calculate_1rm_brzycki(weight=50, reps=50)
        self.assertEqual(result, 50)
