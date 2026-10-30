// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

// One rain streak per two vertices.  aDrop.xyz are random numbers in
// [0, 1) placing the drop in a box that wraps around the camera, aDrop.w
// is 0 for the top of the streak and 1 for its bottom.  In snow every
// vertex is a flake of its own, falling slowly and drifting.
layout(location = 0) in vec4 aDrop;

uniform mat4 uViewProj;
uniform vec3 uCamPos;
uniform float uTime;
uniform float uAmount;
uniform int uSnow;
uniform float uPointScale;
uniform float uGround;     // leaves: the ground under the camera

out float vAlpha;
out vec3 vLeaf;      // leaves: colour
out float vSpin;     // leaves: how much of the leaf faces you

const float BOX = 36.0;
const float HEIGHT = 28.0;
const float SPEED = 12.0;

void main()
{
    vec3 base;
    vLeaf = vec3(0.0);
    vSpin = 1.0;
    if (uSnow == 2) {
        // autumn leaves: few, slow, swirling and tumbling
        vec3 r = fract(aDrop.xyz + aDrop.w * vec3(0.37, 0.61, 0.23));
        float t = uTime * (0.6 + 0.4 * r.x);
        base.xz = uCamPos.xz + mod(r.xz * BOX - uCamPos.xz
                  + vec2(sin(t * 0.9 + r.y * 40.0), cos(t * 0.7 + r.z * 30.0)) * 2.0
                  + vec2(t * 0.8, t * 0.3), BOX) - 0.5 * BOX;
        base.y = uCamPos.y - 0.45 * HEIGHT + mod(r.y * HEIGHT - t * 0.9, HEIGHT);
        float d = length(base - uCamPos);
        vAlpha = step(fract(r.x * 57.31 + r.z * 13.7), uAmount)
               * (1.0 - smoothstep(12.0, 18.0, d))
               * (1.0 - smoothstep(16.0, 20.0, base.y - uGround));   // they stay low
        float k = fract(r.z * 91.7);
        vLeaf = k < 0.35 ? vec3(0.85, 0.55, 0.12) : k < 0.65 ? vec3(0.70, 0.30, 0.08)
              : k < 0.85 ? vec3(0.80, 0.68, 0.18) : vec3(0.45, 0.28, 0.12);
        vSpin = 0.25 + 0.75 * abs(sin(t * 3.0 + r.x * 20.0));
        gl_Position = uViewProj * vec4(base, 1.0);
        gl_PointSize = clamp(0.14 * uPointScale / max(gl_Position.w, 0.1), 1.5, 16.0);
        return;
    }
    if (uSnow == 1) {
        vec3 r = fract(aDrop.xyz + aDrop.w * vec3(0.37, 0.61, 0.23));
        float t = uTime * (0.9 + 0.5 * r.x);
        base.xz = uCamPos.xz + mod(r.xz * BOX - uCamPos.xz
                  + vec2(sin(t * 0.7 + r.y * 40.0), cos(t * 0.5 + r.z * 30.0)) * 0.8, BOX) - 0.5 * BOX;
        base.y = uCamPos.y - 0.45 * HEIGHT + mod(r.y * HEIGHT - t * 1.3, HEIGHT);
        float d = length(base - uCamPos);
        vAlpha = step(fract(r.x * 57.31 + r.z * 13.7), uAmount)
               * (1.0 - smoothstep(10.0, 18.0, d));
        gl_Position = uViewProj * vec4(base, 1.0);
        gl_PointSize = clamp(0.05 * uPointScale / max(gl_Position.w, 0.1), 1.5, 9.0);
        return;
    }
    base.xz = uCamPos.xz + mod(aDrop.xz * BOX - uCamPos.xz, BOX) - 0.5 * BOX;
    base.y = uCamPos.y - 0.45 * HEIGHT + mod(aDrop.y * HEIGHT - uTime * SPEED, HEIGHT);
    vec3 p = base + vec3(0.12, -0.75, 0.05) * aDrop.w;
    float d = length(base - uCamPos);
    // fewer drops in light rain; fade with distance
    vAlpha = step(fract(aDrop.x * 57.31 + aDrop.z * 13.7), uAmount)
           * (1.0 - smoothstep(6.0, 17.0, d)) * (1.0 - 0.6 * aDrop.w);
    gl_Position = uViewProj * vec4(p, 1.0);
}
