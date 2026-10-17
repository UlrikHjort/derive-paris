// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

in float vAlpha;

uniform vec3 uColor;
uniform int uSnow;

out vec4 fragColor;

void main()
{
    if (uSnow == 1) {
        vec2 c = gl_PointCoord * 2.0 - 1.0;
        float r = dot(c, c);
        if (r > 1.0)
            discard;
        fragColor = vec4(uColor, 0.85 * vAlpha * (1.0 - r * r));
        return;
    }
    fragColor = vec4(uColor, 0.35 * vAlpha);
}
