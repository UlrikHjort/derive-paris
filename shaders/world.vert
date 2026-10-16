#version 330 core

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec2 aUV;
layout(location = 3) in float aMat;
layout(location = 4) in float aSeed;

uniform mat4 uViewProj;
uniform mat4 uModel;
uniform mat4 uShadowMatrix;

out vec3 vWorld;
out vec3 vNormal;
out vec2 vUV;
out vec4 vShadowPos;
flat out float vMat;
flat out float vSeed;

void main()
{
    vec4 world = uModel * vec4(aPos, 1.0);
    vWorld = world.xyz;
    vNormal = mat3(uModel) * aNormal;
    vUV = aUV;
    vMat = aMat;
    vSeed = aSeed;
    vShadowPos = uShadowMatrix * world;
    gl_Position = uViewProj * world;
}
