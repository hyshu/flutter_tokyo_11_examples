#version 460 core
// FlutterFragCoord() を呼ぶために必要
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize; // Widgetサイズ
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    // 座標を0.0〜1.0の値に変換 (正規化)
    vec2 uv = FlutterFragCoord().xy / uSize;
    
    // 背景の色を取得
    vec4 color = texture(uTexture, uv);

    float average = (color.r + color.g + color.b) / 3.0;
    fragColor = vec4(average, average, average, color.a);
}