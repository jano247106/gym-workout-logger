from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import ExerciseViewSet, BodyPartViewSet, WorkoutViewSet, WorkoutTemplateViewSet, StatsViewSet

router = DefaultRouter()
router.register(r'exercises', ExerciseViewSet)
router.register(r'bodyparts', BodyPartViewSet)
router.register(r'workouts', WorkoutViewSet)
router.register(r'templates', WorkoutTemplateViewSet)
router.register(r'stats', StatsViewSet, basename='stats')

urlpatterns = [
    path('', include(router.urls)),
]