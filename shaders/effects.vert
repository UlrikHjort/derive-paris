// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

// Skid marks (triangles on the road) and tyre smoke (points).
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec2 aInfo;   // alpha, size in metres (points)

uniform mat4 uViewProj;
uniform vec3 uCamPos;
uniform float uPointScale;   // pixels per metre at distance 1
uniform int uPoints;
uniform float uFadeFar;               // fades out towards this distance

out float vAlpha;

void main()
{
    vec3 p = aPos;
    float d = length(aPos - uCamPos);
    vAlpha = aInfo.x * (1.0 - smoothstep(0.6 * uFadeFar, uFadeFar, d));
    if (uPoints == 1) {
        // a puff is drawn at one depth: bring it forward by its radius so
        // it does not cut a hard line into the road; fade very close ones
        p += (uCamPos - aPos) / max(d, 0.01) * min(0.6 * aInfo.y, 0.5 * d);
        vAlpha *= smoothstep(1.0, 4.0, d);
    }
    gl_Position = uViewProj * vec4(p, 1.0);
    if (uPoints == 1)
        gl_PointSize = aInfo.y * uPointScale / max(gl_Position.w, 0.3);
}
