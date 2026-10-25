// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
// The panels' picture (premultiplied alpha, as cairo draws it)
#version 330 core

in vec2 vUV;
uniform sampler2D uHud;
out vec4 fragColor;

void main()
{
    fragColor = texture(uHud, vUV);
}
