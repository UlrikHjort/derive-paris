// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

in float vAlpha;
in vec3 vLeaf;
in float vSpin;

uniform vec3 uColor;
uniform int uSnow;

out vec4 fragColor;

void main()
{
    if (uSnow == 2) {
        // a leaf turning over: an ellipse that narrows and widens
        vec2 c = gl_PointCoord * 2.0 - 1.0;
        c.x /= max(vSpin, 0.15);
        if (dot(c, c) > 1.0)
            discard;
        fragColor = vec4(vLeaf * uColor * (0.8 + 0.2 * c.y), vAlpha);
        return;
    }
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
