import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';

void main() => runApp(const MainApp());

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  ui.FragmentShader? _shader;
  Offset _position = const Offset(100, 100);

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    final program = await ui.FragmentProgram.fromAsset(
      'shaders/monochrome.frag',
    );
    setState(() => _shader = program.fragmentShader());
  }

  @override
  Widget build(context) => MaterialApp(
    home: Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(),
          Text(
            'Hello Flutter Shader!',
            style: TextStyle(color: Colors.red, fontSize: 80),
          ),
          if (_shader case final shader?)
            Positioned(
              left: _position.dx,
              top: _position.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) =>
                    setState(() => _position += details.delta),
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.shader(shader),
                    child: SizedBox(width: 200, height: 200),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
