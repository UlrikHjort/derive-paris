// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec2 aUV;
layout(location = 3) in float aMat;
layout(location = 4) in float aSeed;

uniform mat4 uViewProj;
uniform mat4 uModel;
uniform mat4 uShadowMatrix;
uniform float uFlood;        // metres the Seine stands above its usual level
uniform vec2 uSeine[64];     // its middle line (xz), for the water that rises
uniform int uSeineN;

out vec3 vWorld;
out vec3 vNormal;
out vec2 vUV;
out vec4 vShadowPos;
flat out float vMat;
flat out float vSeed;

void main()
{
    vec4 world = uModel * vec4(aPos, 1.0);
    // the Seine in flood: its water (and not a pond's) stands higher
    if (uFlood > 0.0 && abs(aMat - 6.0) < 0.5) {
        float d = 1.0e9;
        for (int i = 0; i < uSeineN - 1; i++) {
            vec2 a = uSeine[i];
            vec2 ab = uSeine[i + 1] - a;
            float t = clamp(dot(world.xz - a, ab) / max(dot(ab, ab), 1.0e-4), 0.0, 1.0);
            d = min(d, length(world.xz - a - t * ab));
        }
        world.y += uFlood * (1.0 - smoothstep(150.0, 200.0, d));
    }
    vWorld = world.xyz;
    vNormal = mat3(uModel) * aNormal;
    vUV = aUV;
    vMat = aMat;
    vSeed = aSeed;
    vShadowPos = uShadowMatrix * world;
    gl_Position = uViewProj * world;
}
