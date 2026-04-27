# Github:
https://github.com/jano247106/KRY-project

# Gym Logger
Gym Logger is a full-stack workout tracking project with a Django backend and a Flutter mobile app.

## Backend
From `Projekt\gym_logger`, run:

```bash
python manage.py runserver 0.0.0.0:8000
```

## Flutter App
From `Projekt\gym_logger\gym_logger_mobile`, run:

```bash
flutter run
```

## Notes
- The backend should be running before starting the Flutter app.
- On Android emulators, the app connects to the backend through `10.0.2.2:8000`.
- On Windows desktop builds, the app uses `127.0.0.1:8000`.
