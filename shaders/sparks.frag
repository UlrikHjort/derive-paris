// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

in vec4 vColor;

out vec4 fragColor;

void main()
{
    vec2 c = gl_PointCoord * 2.0 - 1.0;
    float r = dot(c, c);
    if (r > 1.0)
        discard;
    // a bright core with a soft glow around it
    float a = vColor.a * (exp(-r * 4.0) + 0.5 * exp(-r * 18.0));
    fragColor = vec4(vColor.rgb * a, 1.0);
}
