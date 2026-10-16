// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

// Fullscreen triangle generated from gl_VertexID
out vec2 vNdc;

void main()
{
    vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2) * 2.0 - 1.0;
    vNdc = p;
    gl_Position = vec4(p, 0.9999, 1.0);
}
