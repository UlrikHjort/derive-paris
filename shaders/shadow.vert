#version 330 core

layout(location = 0) in vec3 aPos;

uniform mat4 uLightViewProj;
uniform mat4 uModel;

void main()
{
    gl_Position = uLightViewProj * uModel * vec4(aPos, 1.0);
}
