import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math_64.dart' hide Vector4;
import 'package:vector_math/vector_math.dart' as vm;
import 'shaders.dart';

class BoxRenderer extends StatefulWidget {
  final Color boxColor;
  final Color backgroundColor;

  const BoxRenderer({
    super.key,
    this.boxColor = const Color(0xFF2196F3), // Blue color
    this.backgroundColor = const Color(0xFF000000), // Black color
  });

  @override
  State<BoxRenderer> createState() => _BoxRendererState();
}

class _BoxRendererState extends State<BoxRenderer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  double _rotationX = 0.2;
  double _rotationY = 0.0;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(begin: 0, end: 1).animate(_controller)
      ..addListener(() {
        setState(() {
          _rotationY = _animation.value * 2 * 3.14159265359;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _baseScale = 1.0;
  Offset? _lastFocalPoint;

  @override
  Widget build(context) => GestureDetector(
    onScaleStart: (details) {
      _baseScale = _scale;
      _lastFocalPoint = details.localFocalPoint;
    },
    onScaleUpdate: (details) {
      setState(() {
        if (details.scale != 1.0) {
          _scale = (_baseScale * details.scale).clamp(0.5, 3.0);
        }

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
    final physicalWidth = (size.width * devicePixelRatio).toInt();
    final physicalHeight = (size.height * devicePixelRatio).toInt();

    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      physicalWidth,
      physicalHeight,
    );

    final depthTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      physicalWidth,
      physicalHeight,
      format: gpu.PixelFormat.d32FloatS8UInt,
      enableRenderTargetUsage: true,
    );

    final renderTarget = gpu.RenderTarget(
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
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: depthTexture,
        depthClearValue: 1.0,
        depthLoadAction: gpu.LoadAction.clear,
        depthStoreAction: gpu.StoreAction.dontCare,
      ),
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(renderTarget);

    final mvpMatrix = _createMVPMatrix(size);

    final vert = shaderLibrary['BoxVertex']!;
    final frag = shaderLibrary['BoxFragment']!;

    _drawBox(renderPass, vert, frag, mvpMatrix);

    commandBuffer.submit();

    final resultImage = texture.asImage();
    canvas.drawImageRect(
      resultImage,
      Rect.fromLTWH(0, 0, physicalWidth.toDouble(), physicalHeight.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );
  }

  Matrix4 _createMVPMatrix(Size size) {
    final aspectRatio = size.width / size.height;
    final projectionMatrix = makePerspectiveMatrix(
      radians(45.0),
      aspectRatio,
      0.1,
      100.0,
    );

    final viewMatrix = Matrix4.identity();
    setViewMatrix(
      viewMatrix,
      Vector3(0.0, 0.0, 3.0),
      Vector3(0.0, 0.0, 0.0),
      Vector3(0.0, 1.0, 0.0),
    );

    final modelMatrix = Matrix4.identity()
      ..scaleByVector3(Vector3.all(scale))
      ..rotateY(rotationY)
      ..rotateX(rotationX);

    return projectionMatrix * viewMatrix * modelMatrix;
  }

  void _drawBox(
    gpu.RenderPass renderPass,
    gpu.Shader vert,
    gpu.Shader frag,
    Matrix4 mvpMatrix,
  ) {
    final vertices = _createBoxVertices();

    final uniformBytes = Float32List.fromList(mvpMatrix.storage);
    final uniformByteData = ByteData.sublistView(uniformBytes);

    final pipeline = gpu.gpuContext.createRenderPipeline(vert, frag);
    renderPass.bindPipeline(pipeline);

    if (gpu.gpuContext.createDeviceBufferWithCopy(uniformByteData)
        case gpu.DeviceBuffer uniformBuffer) {
      final uniformSlot = vert.getUniformSlot('Uniforms');
      final uniformView = gpu.BufferView(
        uniformBuffer,
        offsetInBytes: 0,
        lengthInBytes: uniformBuffer.sizeInBytes,
      );
      renderPass.bindUniform(uniformSlot, uniformView);
    }

    if (gpu.gpuContext.createDeviceBufferWithCopy(
          ByteData.sublistView(vertices),
        )
        case gpu.DeviceBuffer verticesBuffer) {
      final verticesView = gpu.BufferView(
        verticesBuffer,
        offsetInBytes: 0,
        lengthInBytes: verticesBuffer.sizeInBytes,
      );

      renderPass.setCullMode(gpu.CullMode.backFace);
      renderPass.setWindingOrder(gpu.WindingOrder.counterClockwise);
      renderPass.setDepthWriteEnable(true);
      renderPass.setDepthCompareOperation(gpu.CompareFunction.less);

      renderPass.bindVertexBuffer(verticesView, 36);
      renderPass.draw();
    }
  }

  Float32List _createBoxVertices() {
    final r = boxColor.r;
    final g = boxColor.g;
    final b = boxColor.b;

    // 6 faces * 2 triangles * 3 vertices = 36 vertices
    // Each vertex: position (x,y,z), normal (nx,ny,nz), color (r,g,b)
    return Float32List.fromList([
      // Front face - triangle 1
      -0.5, -0.5, 0.5, 0.0, 0.0, 1.0, r, g, b,
      0.5, -0.5, 0.5, 0.0, 0.0, 1.0, r, g, b,
      0.5, 0.5, 0.5, 0.0, 0.0, 1.0, r, g, b,
      // Front face - triangle 2
      -0.5, -0.5, 0.5, 0.0, 0.0, 1.0, r, g, b,
      0.5, 0.5, 0.5, 0.0, 0.0, 1.0, r, g, b,
      -0.5, 0.5, 0.5, 0.0, 0.0, 1.0, r, g, b,

      // Back face - triangle 1
      0.5, -0.5, -0.5, 0.0, 0.0, -1.0, r, g, b,
      -0.5, -0.5, -0.5, 0.0, 0.0, -1.0, r, g, b,
      -0.5, 0.5, -0.5, 0.0, 0.0, -1.0, r, g, b,
      // Back face - triangle 2
      0.5, -0.5, -0.5, 0.0, 0.0, -1.0, r, g, b,
      -0.5, 0.5, -0.5, 0.0, 0.0, -1.0, r, g, b,
      0.5, 0.5, -0.5, 0.0, 0.0, -1.0, r, g, b,

      // Top face - triangle 1
      -0.5, 0.5, 0.5, 0.0, 1.0, 0.0, r, g, b,
      0.5, 0.5, 0.5, 0.0, 1.0, 0.0, r, g, b,
      0.5, 0.5, -0.5, 0.0, 1.0, 0.0, r, g, b,
      // Top face - triangle 2
      -0.5, 0.5, 0.5, 0.0, 1.0, 0.0, r, g, b,
      0.5, 0.5, -0.5, 0.0, 1.0, 0.0, r, g, b,
      -0.5, 0.5, -0.5, 0.0, 1.0, 0.0, r, g, b,

      // Bottom face - triangle 1
      -0.5, -0.5, -0.5, 0.0, -1.0, 0.0, r, g, b,
      0.5, -0.5, -0.5, 0.0, -1.0, 0.0, r, g, b,
      0.5, -0.5, 0.5, 0.0, -1.0, 0.0, r, g, b,
      // Bottom face - triangle 2
      -0.5, -0.5, -0.5, 0.0, -1.0, 0.0, r, g, b,
      0.5, -0.5, 0.5, 0.0, -1.0, 0.0, r, g, b,
      -0.5, -0.5, 0.5, 0.0, -1.0, 0.0, r, g, b,

      // Right face - triangle 1
      0.5, -0.5, 0.5, 1.0, 0.0, 0.0, r, g, b,
      0.5, -0.5, -0.5, 1.0, 0.0, 0.0, r, g, b,
      0.5, 0.5, -0.5, 1.0, 0.0, 0.0, r, g, b,
      // Right face - triangle 2
      0.5, -0.5, 0.5, 1.0, 0.0, 0.0, r, g, b,
      0.5, 0.5, -0.5, 1.0, 0.0, 0.0, r, g, b,
      0.5, 0.5, 0.5, 1.0, 0.0, 0.0, r, g, b,

      // Left face - triangle 1
      -0.5, -0.5, -0.5, -1.0, 0.0, 0.0, r, g, b,
      -0.5, -0.5, 0.5, -1.0, 0.0, 0.0, r, g, b,
      -0.5, 0.5, 0.5, -1.0, 0.0, 0.0, r, g, b,
      // Left face - triangle 2
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
