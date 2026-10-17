// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

// The Eiffel Tower's beacon: each beam is a long strip turned towards
// the camera.  aInfo.x runs 0 .. 1 along the beam, aInfo.y -1 .. 1 across.
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec2 aInfo;

uniform mat4 uViewProj;

out vec2 vInfo;

void main()
{
    vInfo = aInfo;
    gl_Position = uViewProj * vec4(aPos, 1.0);
}
