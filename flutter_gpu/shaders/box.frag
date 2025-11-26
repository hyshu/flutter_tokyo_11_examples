in vec3 v_normal;
in vec3 v_color;

out vec4 frag_color;

void main() {
  vec3 lightDirection = normalize(vec3(0.5, 0.5, 1.0));
  float diffuse = max(dot(normalize(v_normal), lightDirection), 0.0);
  vec3 ambient = vec3(0.3, 0.3, 0.3);
  vec3 finalColor = v_color * (ambient + diffuse * 0.7);
  frag_color = vec4(finalColor, 1.0);
}