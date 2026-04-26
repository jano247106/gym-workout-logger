from django.contrib import admin
from .models import *

class ExerciseBodyPartInline(admin.TabularInline):
    model = ExerciseBodyPart
    extra = 1

class TemplateExerciseInline(admin.TabularInline):
    model = TemplateExercise
    extra = 1

@admin.register(Exercise)
class ExerciseAdmin(admin.ModelAdmin):
    inlines = [ExerciseBodyPartInline]

@admin.register(WorkoutTemplate)
class WorkoutTemplateAdmin(admin.ModelAdmin):
    inlines = [TemplateExerciseInline]

admin.site.register(BodyPart)
admin.site.register(PerformedWorkout)
admin.site.register(WorkoutSet)
admin.site.register(TemplateExercise)
admin.site.register(UserStatsPreference)