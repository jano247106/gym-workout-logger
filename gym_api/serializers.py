from rest_framework import serializers
from django.db.models import Q
from django.utils import timezone
from .models import BodyPart, Exercise, ExerciseBodyPart, WorkoutSet, PerformedWorkout, WorkoutTemplate, TemplateExercise, TemplateSet, UserStatsPreference

class BodyPartSerializer(serializers.ModelSerializer):
    class Meta:
        model = BodyPart
        fields = '__all__'

class ExerciseBodyPartSerializer(serializers.ModelSerializer):
    body_part_name = serializers.ReadOnlyField(source='body_part.name')
    class Meta:
        model = ExerciseBodyPart
        fields = ['body_part_name', 'is_primary']

class ExerciseSerializer(serializers.ModelSerializer):
    muscles = ExerciseBodyPartSerializer(many=True, read_only=True)
    class Meta:
        model = Exercise
        fields = ['id', 'name', 'description', 'image_url', 'machine_id', 'muscles']

# --- Template Serializers ---

class TemplateSetSerializer(serializers.ModelSerializer):
    class Meta:
        model = TemplateSet
        fields = ['id', 'order', 'target_reps', 'target_weight', 'set_type']

class TemplateExerciseSerializer(serializers.ModelSerializer):
    exercise_name = serializers.ReadOnlyField(source='exercise.name')
    exercise_id = serializers.ReadOnlyField(source='exercise.id')
    sets = TemplateSetSerializer(many=True, read_only=True)
    last_weight = serializers.SerializerMethodField()
    last_reps = serializers.SerializerMethodField()
    last_rpe = serializers.SerializerMethodField()

    class Meta:
        model = TemplateExercise
        fields = ['id', 'exercise_id', 'exercise_name', 'order', 'sets', 'last_weight', 'last_reps', 'last_rpe']

    def _get_last_performance_set(self, obj):
        base_qs = WorkoutSet.objects.filter(
            workout__user=obj.template.user,
            exercise=obj.exercise,
        )

        # Prefer a meaningful previous set so empty trailing sets (0x0) do not overwrite progress.
        meaningful = base_qs.filter(Q(reps__gt=0) | Q(weight__gt=0)).order_by('-workout__start_time', '-id').first()
        if meaningful:
            return meaningful

        return base_qs.order_by('-workout__start_time', '-id').first()

    def get_last_weight(self, obj):
        last_set = self._get_last_performance_set(obj)
        return last_set.weight if last_set else 0.0

    def get_last_reps(self, obj):
        last_set = self._get_last_performance_set(obj)
        return last_set.reps if last_set else 0

    def get_last_rpe(self, obj):
        last_set = self._get_last_performance_set(obj)
        if not last_set:
            return None
        return last_set.rpe

class WorkoutTemplateSerializer(serializers.ModelSerializer):
    exercises_in_template = TemplateExerciseSerializer(source='template_exercises', many=True, read_only=True)
    class Meta:
        model = WorkoutTemplate
        fields = ['id', 'name', 'created_at', 'exercises_in_template']

# --- Performed Workout Serializers ---

class WorkoutSetSerializer(serializers.ModelSerializer):
    exercise_name = serializers.ReadOnlyField(source='exercise.name')
    class Meta:
        model = WorkoutSet
        fields = '__all__'

class PerformedWorkoutSerializer(serializers.ModelSerializer):
    sets = WorkoutSetSerializer(many=True, read_only=True)
    template_name = serializers.SerializerMethodField()

    def get_template_name(self, obj):
        if obj.template and obj.template.name:
            return obj.template.name

        if not obj.start_time:
            return 'Custom Training'

        local_dt = timezone.localtime(obj.start_time)
        weekday = local_dt.strftime('%A')
        hour = local_dt.hour

        if hour < 12:
            period = 'Morning'
        elif hour < 18:
            period = 'Afternoon'
        else:
            period = 'Night'

        return f'{weekday} {period} Training'

    class Meta:
        model = PerformedWorkout
        fields = '__all__'

class UserStatsPreferenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserStatsPreference
        fields = ['id', 'tracked_exercises', 'primary_chest_exercise', 'primary_back_exercise', 'primary_legs_exercise']