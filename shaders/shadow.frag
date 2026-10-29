// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

in vec3 vWorld;

uniform vec4 uErase[5];      // Paris in 1973: what casts no shadow yet (see world.frag)
uniform vec4 uEraseB[5];
uniform int uEraseN;

void main()
{
    for (int i = 0; i < uEraseN; i++) {
        vec2 d = vWorld.xz - uErase[i].xy;
        float u = dot(d, uEraseB[i].xy);
        float v = dot(d, vec2(-uEraseB[i].y, uEraseB[i].x));
        if (abs(u) < uErase[i].z && abs(v) < uErase[i].w && vWorld.y > uEraseB[i].z) discard;
    }
}
