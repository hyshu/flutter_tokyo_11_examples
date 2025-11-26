import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

// 3D 数学用ライブラリ（行列、ベクトル演算など）
import 'package:vector_math/vector_math_64.dart' hide Vector4;
import 'package:vector_math/vector_math.dart' as vm;

// 事前コンパイル済みシェーダーを提供するコード
import 'shaders.dart';

/// 3D ボックスをレンダリングするWidget
/// ドラッグで回転、ピンチでズームが可能
class BoxRenderer extends StatefulWidget {
  final Color boxColor;
  final Color backgroundColor;

  const BoxRenderer({
    super.key,
    this.boxColor = const Color(0xFF2196F3),
    this.backgroundColor = const Color(0xFF000000),
  });

  @override
  State<BoxRenderer> createState() => _BoxRendererState();
}

class _BoxRendererState extends State<BoxRenderer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  // 3D 空間での回転角度（ラジアン）
  double _rotationX = 0.2;
  double _rotationY = 0.0;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    // 10秒で1周する自動回転アニメーション
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(begin: 0, end: 1).animate(_controller)
      ..addListener(() {
        setState(() {
          // Y軸周りに360度（2π）回転
          _rotationY = _animation.value * 2 * 3.14159265359;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ジェスチャー操作用の状態
  double _baseScale = 1.0;
  Offset? _lastFocalPoint;

  @override
  Widget build(context) => GestureDetector(
    // ピンチ・ドラッグ操作の開始
    onScaleStart: (details) {
      _baseScale = _scale;
      _lastFocalPoint = details.localFocalPoint;
    },
    onScaleUpdate: (details) {
      setState(() {
        // ピンチでズーム（0.5〜3.0倍の範囲）
        if (details.scale != 1.0) {
          _scale = (_baseScale * details.scale).clamp(0.5, 3.0);
        }

        // ドラッグで回転（X軸は±1.5ラジアンに制限）
        if (_lastFocalPoint != null) {
          final delta = details.localFocalPoint - _lastFocalPoint!;
          _rotationX += delta.dy * 0.01;
          _rotationY += delta.dx * 0.01;
          _rotationX = _rotationX.clamp(-1.5, 1.5);
        }

        _lastFocalPoint = details.localFocalPoint;
      });
    },
    onScaleEnd: (details) => _lastFocalPoint = null,
    // CustomPaint で GPU レンダリングを実行
    child: CustomPaint(
      painter: BoxPainter(
        rotationX: _rotationX,
        rotationY: _rotationY,
        scale: _scale,
        boxColor: widget.boxColor,
        backgroundColor: widget.backgroundColor,
        devicePixelRatio: View.of(context).devicePixelRatio,
      ),
      size: Size.infinite,
    ),
  );
}

/// Flutter GPU を使って 3D ボックスを描画する CustomPainter
///
/// Flutter GPU の描画フロー:
/// 1. テクスチャ（描画先）を作成
/// 2. RenderTarget（レンダリング設定）を構成
/// 3. CommandBuffer でレンダリングコマンドを記録
/// 4. RenderPass でシェーダーと頂点データをバインドして描画
/// 5. 結果を Canvas に転送
class BoxPainter extends CustomPainter {
  final double rotationX;
  final double rotationY;
  final double scale;
  final Color boxColor;
  final Color backgroundColor;
  final double devicePixelRatio;

  BoxPainter({
    required this.rotationX,
    required this.rotationY,
    required this.scale,
    required this.boxColor,
    required this.backgroundColor,
    required this.devicePixelRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Retina ディスプレイ対応: 論理ピクセルを物理ピクセルに変換
    final physicalWidth = (size.width * devicePixelRatio).toInt();
    final physicalHeight = (size.height * devicePixelRatio).toInt();

    // カラーテクスチャ: 描画結果を格納する GPU メモリ領域
    // devicePrivate: GPU 専用メモリ（最速だが CPU からアクセス不可）
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      physicalWidth,
      physicalHeight,
    );

    // デプステクスチャ: 奥行き情報を格納（3D で手前/奥の判定に使用）
    // d32FloatS8UInt: 32bit 深度 + 8bit ステンシル形式
    final depthTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      physicalWidth,
      physicalHeight,
      format: gpu.PixelFormat.d32FloatS8UInt,
      enableRenderTargetUsage: true,
    );

    // RenderTarget: 描画先の設定をまとめたオブジェクト
    final renderTarget = gpu.RenderTarget(
      // カラーアタッチメント: 色の描画先とクリア色を指定
      colorAttachments: [
        gpu.ColorAttachment(
          texture: texture,
          clearValue: vm.Vector4(
            backgroundColor.r,
            backgroundColor.g,
            backgroundColor.b,
            backgroundColor.a,
          ),
        ),
      ],
      // デプスアタッチメント: 深度バッファの設定
      // depthClearValue: 1.0 = 最も遠い位置で初期化
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: depthTexture,
        depthClearValue: 1.0,
        depthLoadAction: gpu.LoadAction.clear,
        depthStoreAction: gpu.StoreAction.dontCare,
      ),
    );

    // CommandBuffer: GPU に送信するコマンドを記録するバッファ
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    // RenderPass: 1回の描画パス（複数のドローコールをまとめる）
    final renderPass = commandBuffer.createRenderPass(renderTarget);

    // MVP 行列: Model-View-Projection 変換行列（3D→2D 変換）
    final mvpMatrix = _createMVPMatrix(size);

    // シェーダーを取得（頂点シェーダーとフラグメントシェーダー）
    final vert = shaderLibrary['BoxVertex']!;
    final frag = shaderLibrary['BoxFragment']!;

    _drawBox(renderPass, vert, frag, mvpMatrix);

    // コマンドを GPU に送信して実行
    commandBuffer.submit();

    // GPU テクスチャを Flutter の Image に変換して Canvas に描画
    final resultImage = texture.asImage();
    canvas.drawImageRect(
      resultImage,
      Rect.fromLTWH(0, 0, physicalWidth.toDouble(), physicalHeight.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );
  }

  /// MVP (Model-View-Projection) 行列を作成
  /// 3D オブジェクトを 2D 画面に投影するための変換行列
  Matrix4 _createMVPMatrix(Size size) {
    final aspectRatio = size.width / size.height;

    // Projection 行列: 3D 空間を 2D 画面に投影（遠近法）
    // 45度の視野角、near=0.1〜far=100.0 の範囲を描画
    final projectionMatrix = makePerspectiveMatrix(
      radians(45.0),
      aspectRatio,
      0.1,
      100.0,
    );

    // View 行列: カメラの位置と向き
    // カメラは z=3.0 の位置から原点を見ている
    final viewMatrix = Matrix4.identity();
    setViewMatrix(
      viewMatrix,
      Vector3(0.0, 0.0, 3.0), // カメラ位置
      Vector3(0.0, 0.0, 0.0), // 注視点
      Vector3(0.0, 1.0, 0.0), // 上方向ベクトル
    );

    // Model 行列: オブジェクトの変換（スケール、回転）
    final modelMatrix = Matrix4.identity()
      ..scaleByVector3(Vector3.all(scale))
      ..rotateY(rotationY)
      ..rotateX(rotationX);

    // MVP = Projection × View × Model の順で合成
    return projectionMatrix * viewMatrix * modelMatrix;
  }

  /// ボックスを描画する
  void _drawBox(
    gpu.RenderPass renderPass,
    gpu.Shader vert,
    gpu.Shader frag,
    Matrix4 mvpMatrix,
  ) {
    final vertices = _createBoxVertices();

    // Uniform データ: シェーダーに渡す定数（ここでは MVP 行列）
    final uniformBytes = Float32List.fromList(mvpMatrix.storage);
    final uniformByteData = ByteData.sublistView(uniformBytes);

    // RenderPipeline: 頂点シェーダーとフラグメントシェーダーを組み合わせた描画設定
    final pipeline = gpu.gpuContext.createRenderPipeline(vert, frag);
    renderPass.bindPipeline(pipeline);

    // Uniform バッファを GPU にアップロードしてシェーダーにバインド
    if (gpu.gpuContext.createDeviceBufferWithCopy(uniformByteData)
        case gpu.DeviceBuffer uniformBuffer) {
      // シェーダー内の 'Uniforms' という名前のスロットを取得
      final uniformSlot = vert.getUniformSlot('Uniforms');
      final uniformView = gpu.BufferView(
        uniformBuffer,
        offsetInBytes: 0,
        lengthInBytes: uniformBuffer.sizeInBytes,
      );
      renderPass.bindUniform(uniformSlot, uniformView);
    }

    // 頂点データを GPU にアップロードして描画
    if (gpu.gpuContext.createDeviceBufferWithCopy(
          ByteData.sublistView(vertices),
        )
        case gpu.DeviceBuffer verticesBuffer) {
      final verticesView = gpu.BufferView(
        verticesBuffer,
        offsetInBytes: 0,
        lengthInBytes: verticesBuffer.sizeInBytes,
      );

      // カリング設定: 裏面を描画しない（パフォーマンス最適化）
      renderPass.setCullMode(gpu.CullMode.backFace);
      // 頂点の巻き順: 反時計回りを表面とみなす
      renderPass.setWindingOrder(gpu.WindingOrder.counterClockwise);
      // 深度テスト: 手前のピクセルだけを描画
      renderPass.setDepthWriteEnable(true);
      renderPass.setDepthCompareOperation(gpu.CompareFunction.less);

      // 頂点バッファをバインドして描画（36頂点 = 12三角形 = 6面）
      renderPass.bindVertexBuffer(verticesView, 36);
      renderPass.draw();
    }
  }

  /// ボックスの頂点データを作成
  /// 6面 × 2三角形 × 3頂点 = 36頂点
  /// 各頂点は 9 つの float: 位置(x,y,z) + 法線(nx,ny,nz) + 色(r,g,b)
  Float32List _createBoxVertices() {
    final r = boxColor.r;
    final g = boxColor.g;
    final b = boxColor.b;

    return Float32List.fromList([
      // 前面 (z=+0.5) - 法線は +Z 方向
      -0.5, -0.5, 0.5, 0.0, 0.0, 1.0, r, g, b,
      0.5, -0.5, 0.5, 0.0, 0.0, 1.0, r, g, b,
      0.5, 0.5, 0.5, 0.0, 0.0, 1.0, r, g, b,
      -0.5, -0.5, 0.5, 0.0, 0.0, 1.0, r, g, b,
      0.5, 0.5, 0.5, 0.0, 0.0, 1.0, r, g, b,
      -0.5, 0.5, 0.5, 0.0, 0.0, 1.0, r, g, b,

      // 背面 (z=-0.5) - 法線は -Z 方向
      0.5, -0.5, -0.5, 0.0, 0.0, -1.0, r, g, b,
      -0.5, -0.5, -0.5, 0.0, 0.0, -1.0, r, g, b,
      -0.5, 0.5, -0.5, 0.0, 0.0, -1.0, r, g, b,
      0.5, -0.5, -0.5, 0.0, 0.0, -1.0, r, g, b,
      -0.5, 0.5, -0.5, 0.0, 0.0, -1.0, r, g, b,
      0.5, 0.5, -0.5, 0.0, 0.0, -1.0, r, g, b,

      // 上面 (y=+0.5) - 法線は +Y 方向
      -0.5, 0.5, 0.5, 0.0, 1.0, 0.0, r, g, b,
      0.5, 0.5, 0.5, 0.0, 1.0, 0.0, r, g, b,
      0.5, 0.5, -0.5, 0.0, 1.0, 0.0, r, g, b,
      -0.5, 0.5, 0.5, 0.0, 1.0, 0.0, r, g, b,
      0.5, 0.5, -0.5, 0.0, 1.0, 0.0, r, g, b,
      -0.5, 0.5, -0.5, 0.0, 1.0, 0.0, r, g, b,

      // 下面 (y=-0.5) - 法線は -Y 方向
      -0.5, -0.5, -0.5, 0.0, -1.0, 0.0, r, g, b,
      0.5, -0.5, -0.5, 0.0, -1.0, 0.0, r, g, b,
      0.5, -0.5, 0.5, 0.0, -1.0, 0.0, r, g, b,
      -0.5, -0.5, -0.5, 0.0, -1.0, 0.0, r, g, b,
      0.5, -0.5, 0.5, 0.0, -1.0, 0.0, r, g, b,
      -0.5, -0.5, 0.5, 0.0, -1.0, 0.0, r, g, b,

      // 右面 (x=+0.5) - 法線は +X 方向
      0.5, -0.5, 0.5, 1.0, 0.0, 0.0, r, g, b,
      0.5, -0.5, -0.5, 1.0, 0.0, 0.0, r, g, b,
      0.5, 0.5, -0.5, 1.0, 0.0, 0.0, r, g, b,
      0.5, -0.5, 0.5, 1.0, 0.0, 0.0, r, g, b,
      0.5, 0.5, -0.5, 1.0, 0.0, 0.0, r, g, b,
      0.5, 0.5, 0.5, 1.0, 0.0, 0.0, r, g, b,

      // 左面 (x=-0.5) - 法線は -X 方向
      -0.5, -0.5, -0.5, -1.0, 0.0, 0.0, r, g, b,
      -0.5, -0.5, 0.5, -1.0, 0.0, 0.0, r, g, b,
      -0.5, 0.5, 0.5, -1.0, 0.0, 0.0, r, g, b,
      -0.5, -0.5, -0.5, -1.0, 0.0, 0.0, r, g, b,
      -0.5, 0.5, 0.5, -1.0, 0.0, 0.0, r, g, b,
      -0.5, 0.5, -0.5, -1.0, 0.0, 0.0, r, g, b,
    ]);
  }

  @override
  bool shouldRepaint(covariant BoxPainter oldDelegate) =>
      oldDelegate.rotationX != rotationX ||
      oldDelegate.rotationY != rotationY ||
      oldDelegate.scale != scale ||
      oldDelegate.boxColor != boxColor ||
      oldDelegate.backgroundColor != backgroundColor;
}
