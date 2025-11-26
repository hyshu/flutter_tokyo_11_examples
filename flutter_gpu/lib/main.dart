import 'package:flutter/material.dart';
import 'box_renderer.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(context) => MaterialApp(
    title: 'Flutter GPU Template',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      useMaterial3: true,
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(context) => Scaffold(
    backgroundColor: Colors.grey[900],
    appBar: AppBar(
      title: const Text('Flutter GPU Box Renderer'),
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
    ),
    body: const Center(
      child: SizedBox(
        width: 400,
        height: 400,
        child: BoxRenderer(
          boxColor: Colors.blue,
          backgroundColor: Colors.black,
        ),
      ),
    ),
  );
}
