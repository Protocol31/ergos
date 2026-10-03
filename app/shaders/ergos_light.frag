#version 460 core
// ERGOS: la luz que sostiene la mano. Núcleo incandescente + plasma de sanidad
// + rayos que respiran + anillo de onda. Solo efectos, sin símbolos.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;      // tamaño del lienzo en px
uniform float uTime;     // segundos
uniform float uProgress; // 0 -> 1: ignición y expansión de la luz
uniform vec2 uCenter;    // posición de la luz (0..1)

out vec4 fragColor;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * noise(p);
    p = p * 2.03 + vec2(1.7, 9.2);
    a *= 0.5;
  }
  return v;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float m = min(uSize.x, uSize.y);
  vec2 p = (frag - uCenter * uSize) / m;
  float r = length(p);
  float ang = atan(p.y, p.x);

  float ignite = smoothstep(0.0, 1.0, uProgress);
  float radius = 0.018 + 0.085 * ignite;
  float breathe = 0.5 + 0.5 * sin(uTime * 1.6);

  // núcleo incandescente
  float core = exp(-pow(r / (radius * (0.9 + 0.1 * breathe)), 2.0));

  // halo suave verde -> lima
  float halo = exp(-r * 4.2) * (0.25 + 0.55 * ignite);

  // plasma fluido (dominio deformado por ruido)
  vec2 q = p * 5.0 + vec2(uTime * 0.12, -uTime * 0.18);
  float warp = fbm(q + fbm(q * 1.3 + uTime * 0.05));
  float plasma = smoothstep(0.38, 0.92, warp) * exp(-r * 6.0) * ignite;

  // rayos que se abren como luz a través del vitral
  float rays = pow(abs(sin(ang * 7.0 + uTime * 0.25 + warp * 2.5)), 22.0);
  rays += 0.5 * pow(abs(sin(ang * 13.0 - uTime * 0.18 + warp * 1.5)), 40.0);
  rays *= exp(-r * 2.6) * ignite;

  // onda de sanidad que se expande desde la mano
  float wave = fract(uTime * 0.22);
  float ring = exp(-pow((r - wave * 0.9) / 0.012, 2.0)) * (1.0 - wave) * ignite;

  vec3 deep = vec3(0.03, 0.32, 0.24);
  vec3 sage = vec3(0.62, 0.80, 0.70);
  vec3 glow = vec3(0.90, 0.96, 0.55);

  vec3 col = deep * halo * 1.6
           + sage * (plasma * 0.9 + ring * 0.8)
           + glow * (core * 1.7 + rays * 0.55 + halo * 0.35);

  float a = clamp(max(max(col.r, col.g), col.b), 0.0, 1.0);
  fragColor = vec4(col * a, a); // alfa premultiplicado
}
