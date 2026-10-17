// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

in vec2 vInfo;

uniform vec3 uColor;
uniform float uStrength;

out vec4 fragColor;

void main()
{
    float along = vInfo.x;
    // bright at the lamp, fading into the night; soft edges
    float a = pow(1.0 - along, 1.6) * exp(-vInfo.y * vInfo.y * 3.0)
            * (0.35 + 0.65 * exp(-along * 18.0)) * uStrength;
    fragColor = vec4(uColor * a, 1.0);
}
