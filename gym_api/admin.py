from django.contrib import admin
from .models import *

# 1. Definícia Inlinov (musia byť vyššie ako hlavné admin triedy)
class ExerciseBodyPartInline(admin.TabularInline):
    model = ExerciseBodyPart
    extra = 1

class TemplateExerciseInline(admin.TabularInline):
    model = TemplateExercise
    extra = 1

# 2. Registrácia Exercise s Inlinom
@admin.register(Exercise)
class ExerciseAdmin(admin.ModelAdmin):
    inlines = [ExerciseBodyPartInline]

# 3. Registrácia WorkoutTemplate s Inlinom (TU BOLA CHYBA)
@admin.register(WorkoutTemplate)
class WorkoutTemplateAdmin(admin.ModelAdmin):
    inlines = [TemplateExerciseInline]

# 4. Ostatné modely, ktoré nemajú špeciálne triedy, zaregistruj takto:
admin.site.register(BodyPart)
admin.site.register(PerformedWorkout)
admin.site.register(WorkoutSet)
admin.site.register(TemplateExercise) # Môžeš si zaregistrovať aj túto, aby si ju videl samostatne

# !!! SKONTROLUJ, či na konci nemáš tento riadok a ak áno, VYMAŽ HO:
# admin.site.register(WorkoutTemplate)  <-- TOTO SPÔSOBUJE TÚ CHYBU