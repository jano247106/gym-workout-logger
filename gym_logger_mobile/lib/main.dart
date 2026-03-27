import 'package:flutter/material.dart';
import 'screens/main_navigation.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.blue,
    ),
    home: MainNavigation(),
  ));
}