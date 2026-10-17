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

out float vAlpha;

const float BOX = 36.0;
const float HEIGHT = 28.0;
const float SPEED = 12.0;

void main()
{
    vec3 base;
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
