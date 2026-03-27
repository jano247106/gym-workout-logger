from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('gym_api', '0006_remove_workouttemplate_exercises'),
    ]

    operations = [
        migrations.AddField(
            model_name='workoutset',
            name='is_completed',
            field=models.BooleanField(default=False),
        ),
    ]
