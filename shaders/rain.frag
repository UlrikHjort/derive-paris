// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

in float vAlpha;

uniform vec3 uColor;

out vec4 fragColor;

void main()
{
    fragColor = vec4(uColor, 0.35 * vAlpha);
}
