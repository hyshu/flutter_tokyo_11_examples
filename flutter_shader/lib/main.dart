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
  // フラグメントシェーダーを保持する変数
  // シェーダーはGPUで実行される小さなプログラムで、ピクセル単位で色を計算する
  ui.FragmentShader? _shader;

  // シェーダーエフェクトを適用する領域の位置（ドラッグで移動可能）
  Offset _position = const Offset(100, 100);

  @override
  void initState() {
    super.initState();
    // アプリ起動時にシェーダーを読み込む
    _loadShader();
  }

  Future<void> _loadShader() async {
    // FragmentProgram.fromAsset で .frag ファイル（GLSLで書かれたシェーダー）を読み込む
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
          // Stackを画面全体に広げるために必要
          SizedBox.expand(),

          Text(
            'Hello Flutter Shader!',
            style: TextStyle(color: Colors.red, fontSize: 80),
          ),

          // シェーダーが読み込まれている場合のみ表示
          if (_shader case final shader?)
            // Positioned, GestureDetector, ClipRect を使って
            // BackdropFilterをドラッグ可能にする
            Positioned(
              left: _position.dx,
              top: _position.dy,
              child: GestureDetector(
                // ドラッグ操作を検知して位置を更新
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) =>
                    setState(() => _position += details.delta),
                child: ClipRect(
                  // BackdropFilterを使うと背後にあるWidgetにフィルターを適用できる
                  // ここでは ImageFilter.shader() を使ってシェーダーエフェクトを適用
                  // monochrome.fragのuTextureに自動的に背後にあるWidgetを画像化したものを渡す
                  child: BackdropFilter(
                    filter: ImageFilter.shader(shader),
                    // 200x200 の透明な領域がシェーダーの適用範囲
                    // この領域内にある背景のWidgetにシェーダーエフェクトがかかる
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
