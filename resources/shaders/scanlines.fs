#version 330


in vec2 fragTexCoord;
in vec4 fragColor;


uniform sampler2D texture0;
uniform vec4 colDiffuse;


out vec4 finalColor;




const float renderWidth = 800;
const float renderHeight = 450;
float offset = 0.0;

uniform float time;

void main()
{
    float frequency = renderHeight/3.0;
/*

    float tval = 0; //time
    vec2 uv = 0.5 + (fragTexCoord - 0.5)*(0.9 + 0.01*sin(0.5*tval));

    vec4 color = texture(texture0, fragTexCoord);

    color = clamp(color*0.5 + 0.5*color*color*1.2, 0.0, 1.0);
    color *= 0.5 + 0.5*16.0*uv.x*uv.y*(1.0 - uv.x)*(1.0 - uv.y);
    color *= vec4(0.8, 1.0, 0.7, 1);
    color *= 0.9 + 0.1*sin(10.0*tval + uv.y*1000.0);
    color *= 0.97 + 0.03*sin(110.0*tval);

    fragColor = color;
*/

    float globalPos = (fragTexCoord.y + offset)*frequency;
    float wavePos = cos((fract(globalPos) - 0.5)*3.14);


    vec4 texelColor = texture(texture0, fragTexCoord);

    finalColor = mix(vec4(0.0, 0.3, 0.0, 0.0), texelColor, wavePos);
}