// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

// Points of light in the sky: fireworks and the lights of aeroplanes.
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec4 aColor;   // rgb, brightness
layout(location = 2) in float aSize;   // metres

uniform mat4 uViewProj;
uniform float uPointScale;             // pixels per metre at distance 1

out vec4 vColor;

void main()
{
    gl_Position = uViewProj * vec4(aPos, 1.0);
    float px = aSize * uPointScale / max(gl_Position.w, 1.0);
    // far away a light stays a dot of at least two pixels, a little dimmer
    vColor = vec4(aColor.rgb, aColor.a * min(1.0, px / 2.0 + 0.4));
    gl_PointSize = clamp(px, 2.0, 64.0);
}
