from rest_framework import viewsets, status
from rest_framework.response import Response
from rest_framework.decorators import action
from django.contrib.auth.models import User
from .models import Exercise, BodyPart, PerformedWorkout, WorkoutTemplate, TemplateExercise, TemplateSet, WorkoutSet, UserStatsPreference
from .serializers import ExerciseSerializer, BodyPartSerializer, PerformedWorkoutSerializer, WorkoutTemplateSerializer, UserStatsPreferenceSerializer
from django.db import transaction
from django.utils import timezone
from django.db.models import Max, Sum, Q
from datetime import timedelta

class ExerciseViewSet(viewsets.ModelViewSet):
    queryset = Exercise.objects.all()
    serializer_class = ExerciseSerializer

class BodyPartViewSet(viewsets.ModelViewSet):
    queryset = BodyPart.objects.all()
    serializer_class = BodyPartSerializer

class WorkoutViewSet(viewsets.ModelViewSet):
    queryset = PerformedWorkout.objects.all()
    serializer_class = PerformedWorkoutSerializer

    def get_queryset(self):
        qs = PerformedWorkout.objects.all().order_by('-start_time', '-id')

        template_id = self.request.query_params.get('template_id')
        if template_id:
            qs = qs.filter(template_id=template_id)

        is_active = self.request.query_params.get('is_active')
        if is_active in ['1', 'true', 'True']:
            qs = qs.filter(end_time__isnull=True)
        elif is_active in ['0', 'false', 'False']:
            qs = qs.filter(end_time__isnull=False)

        return qs

    def _save_workout_sets(self, workout, sets_data):
        WorkoutSet.objects.filter(workout=workout).delete()
        for s_data in sets_data:
            exercise_id = s_data.get('exercise')
            if not exercise_id:
                continue

            WorkoutSet.objects.create(
                workout=workout,
                exercise_id=exercise_id,
                weight=s_data.get('weight', 0.0),
                reps=s_data.get('reps', 0),
                rpe=s_data.get('rpe'),
                is_completed=s_data.get('is_completed', False),
                set_type=s_data.get('set_type', 'N'),
            )

    def create(self, request, *args, **kwargs):
        user = User.objects.first()
        if not user:
            return Response({"error": "No user found in database"}, status=status.HTTP_400_BAD_REQUEST)

        template_id = request.data.get('template')
        template = WorkoutTemplate.objects.filter(id=template_id).first() if template_id else None
        sets_data = request.data.get('sets', [])

        with transaction.atomic():
            workout = PerformedWorkout.objects.create(
                user=user,
                template=template,
                note=request.data.get('note', ''),
            )

            if sets_data:
                self._save_workout_sets(workout, sets_data)

            if request.data.get('is_finished'):
                workout.end_time = timezone.now()
                workout.save(update_fields=['end_time'])

        serializer = self.get_serializer(workout)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    def update(self, request, *args, **kwargs):
        workout = self.get_object()
        sets_data = request.data.get('sets')

        with transaction.atomic():
            if 'note' in request.data:
                workout.note = request.data.get('note', '')

            if 'template' in request.data:
                template_id = request.data.get('template')
                workout.template = WorkoutTemplate.objects.filter(id=template_id).first() if template_id else None

            workout.save()

            if sets_data is not None:
                self._save_workout_sets(workout, sets_data)

            if request.data.get('is_finished') and workout.end_time is None:
                workout.end_time = timezone.now()
                workout.save(update_fields=['end_time'])

        serializer = self.get_serializer(workout)
        return Response(serializer.data, status=status.HTTP_200_OK)

    def destroy(self, request, *args, **kwargs):
        workout = self.get_object()
        workout.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

class WorkoutTemplateViewSet(viewsets.ModelViewSet):
    queryset = WorkoutTemplate.objects.all()
    serializer_class = WorkoutTemplateSerializer

    def _save_template_exercises(self, template, exercises_data):
        TemplateExercise.objects.filter(template=template).delete()

        for index, ex_data in enumerate(exercises_data):
            exercise = Exercise.objects.get(id=ex_data['id'])
            template_ex = TemplateExercise.objects.create(
                template=template,
                exercise=exercise,
                order=index + 1,
            )

            for s_index, s_data in enumerate(ex_data.get('sets', [])):
                TemplateSet.objects.create(
                    template_exercise=template_ex,
                    order=s_index + 1,
                    target_reps=s_data.get('reps', 10),
                    target_weight=s_data.get('weight', 0.0),
                    set_type=s_data.get('type', 'N'),
                )

    def create(self, request, *args, **kwargs):
        template_name = request.data.get('name')
        exercises_data = request.data.get('exercises', [])
        
        # TODO: Implement proper user authentication
        user = User.objects.first() 
        if not user:
            return Response({"error": "No user found in database"}, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            template = WorkoutTemplate.objects.create(name=template_name, user=user)
            self._save_template_exercises(template, exercises_data)

        serializer = self.get_serializer(template)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    def update(self, request, *args, **kwargs):
        template = self.get_object()
        template_name = request.data.get('name', template.name)
        exercises_data = request.data.get('exercises', [])

        with transaction.atomic():
            template.name = template_name
            template.save(update_fields=['name'])
            self._save_template_exercises(template, exercises_data)

        serializer = self.get_serializer(template)
        return Response(serializer.data, status=status.HTTP_200_OK)

    def destroy(self, request, *args, **kwargs):
        template = self.get_object()
        template.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

class StatsViewSet(viewsets.ViewSet):
    """API endpoint for stats - volume trends, PRs, 1RM calculations"""
    
    def _calculate_1rm_brzycki(self, weight, reps):
        """Calculate estimated 1RM using Brzycki formula"""
        if reps == 1:
            return weight
        if reps > 36:
            return weight  # Formula not reliable for high reps
        return round(weight * (36 / (37 - reps)), 2)
    
    def _get_exercise_bodypart(self, exercise):
        """Get primary body part for exercise"""
        ebp = exercise.muscles.filter(is_primary=True).first()
        return ebp.body_part.name if ebp else None

    @action(detail=False, methods=['get'])
    def streak(self, request):
        """Get consecutive training days streak based on completed workouts."""
        user = User.objects.first()
        if not user:
            return Response({"error": "No user"}, status=status.HTTP_400_BAD_REQUEST)

        workouts = (
            PerformedWorkout.objects.filter(
                user=user,
                end_time__isnull=False,
                sets__is_completed=True,
            )
            .distinct()
            .values_list('start_time', flat=True)
        )

        training_days = set()
        for dt in workouts:
            local_dt = timezone.localtime(dt)
            training_days.add(local_dt.date())

        if not training_days:
            return Response({
                'streak_days': 0,
                'latest_training_day': None,
            })

        current = max(training_days)
        streak = 0
        while current in training_days:
            streak += 1
            current -= timedelta(days=1)

        return Response({
            'streak_days': streak,
            'latest_training_day': max(training_days),
        })
    
    @action(detail=False, methods=['get'])
    def volume_trend(self, request):
        """Get total volume trend for last 30 days"""
        user = User.objects.first()
        if not user:
            return Response({"error": "No user"}, status=status.HTTP_400_BAD_REQUEST)
        
        days = int(request.query_params.get('days', 30))

        # Get completed workouts in selected period, or all-time when days <= 0.
        workouts_query = PerformedWorkout.objects.filter(
            user=user,
            end_time__isnull=False
        )

        if days > 0:
            now = timezone.now()
            start_date = now - timedelta(days=days)
            workouts_query = workouts_query.filter(start_time__gte=start_date)

        workouts = workouts_query.order_by('start_time')
        
        trend = []
        for workout in workouts:
            total_volume = 0
            for s in workout.sets.filter(is_completed=True):
                total_volume += s.weight * s.reps
            
            trend.append({
                'date': workout.start_time.date(),
                'volume': total_volume
            })
        
        return Response({'trend': trend})
    
    @action(detail=False, methods=['get'])
    def prs(self, request):
        """Get Personal Records grouped by exercise"""
        user = User.objects.first()
        if not user:
            return Response({"error": "No user"})
        
        # Get all exercises with their weight PRs
        prs = {}
        sets = WorkoutSet.objects.filter(workout__user=user).order_by('exercise_id', '-weight')
        
        for ex_id in set(s.exercise_id for s in sets):
            pr_set = WorkoutSet.objects.filter(
                workout__user=user, 
                exercise_id=ex_id,
                is_completed=True
            ).order_by('-weight').first()
            
            if pr_set:
                exercise = pr_set.exercise
                est_1rm = self._calculate_1rm_brzycki(pr_set.weight, pr_set.reps)
                bodypart = self._get_exercise_bodypart(exercise)
                
                if bodypart not in prs:
                    prs[bodypart] = []
                
                prs[bodypart].append({
                    'exercise_id': exercise.id,
                    'exercise_name': exercise.name,
                    'weight': pr_set.weight,
                    'reps': pr_set.reps,
                    'est_1rm': est_1rm,
                    'date': pr_set.workout.start_time.date()
                })
        
        return Response(prs)
    
    @action(detail=False, methods=['get', 'post'])
    def preferences(self, request):
        """Get or update user stats preferences"""
        user = User.objects.first()
        if not user:
            return Response({"error": "No user"})
        
        if request.method == 'POST':
            # Update preferences
            prefs, _ = UserStatsPreference.objects.get_or_create(user=user)
            if 'tracked_exercises' in request.data:
                prefs.tracked_exercises = request.data['tracked_exercises']
            if 'primary_chest_exercise' in request.data:
                prefs.primary_chest_exercise_id = request.data['primary_chest_exercise']
            if 'primary_back_exercise' in request.data:
                prefs.primary_back_exercise_id = request.data['primary_back_exercise']
            if 'primary_legs_exercise' in request.data:
                prefs.primary_legs_exercise_id = request.data['primary_legs_exercise']
            prefs.save()
            
            return Response(UserStatsPreferenceSerializer(prefs).data)
        
        # GET preferences
        prefs, _ = UserStatsPreference.objects.get_or_create(user=user)
        return Response(UserStatsPreferenceSerializer(prefs).data)
