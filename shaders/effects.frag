// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

in float vAlpha;

uniform vec3 uColor;
uniform int uPoints;

out vec4 fragColor;

void main()
{
    float a = vAlpha;
    if (uPoints == 1) {
        // a soft round puff
        vec2 c = gl_PointCoord * 2.0 - 1.0;
        float r = dot(c, c);
        if (r > 1.0)
            discard;
        a *= (1.0 - r) * (1.0 - r);
    }
    fragColor = vec4(uColor, a);
}
