// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
// The panels over the 3D view: one triangle covering the screen
#version 330 core

out vec2 vUV;

void main()
{
    vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);   // (0,0) (2,0) (0,2)
    vUV = vec2(p.x, 1.0 - p.y);   // (0,1) at the bottom left, (1,0) at the top right: rows run downwards
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
