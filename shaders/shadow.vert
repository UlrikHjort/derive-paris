// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

layout(location = 0) in vec3 aPos;

uniform mat4 uLightViewProj;
uniform mat4 uModel;

out vec3 vWorld;

void main()
{
    vec4 world = uModel * vec4(aPos, 1.0);
    vWorld = world.xyz;
    gl_Position = uLightViewProj * world;
}
