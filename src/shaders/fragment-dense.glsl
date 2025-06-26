varying vec2 vUv;
varying vec3 vWorldPosition;
varying mat3 vTBN;

uniform sampler2D uDiffuseMap;
uniform sampler2D uNormalMap;
uniform vec3 uCameraPosition;
uniform vec3 uLightDirection;
uniform float uTextureRepeat;

void main() {
    // Sample textures directly without parallax mapping
    vec2 repeatedUv = vUv * uTextureRepeat;
    vec4 diffuseColor = texture2D(uDiffuseMap, repeatedUv);
    vec3 tangentNormal = texture2D(uNormalMap, repeatedUv).rgb * 2.0 - 1.0;
    vec3 worldNormal = normalize(vTBN * tangentNormal);

    // Simple lighting calculation
    vec3 worldLightDir = normalize(uLightDirection);
    float diff = max(dot(worldNormal, worldLightDir), 0.0);
    vec3 ambient = vec3(0.1);
    vec3 lighting = ambient + (diffuseColor.rgb * diff);

    gl_FragColor = vec4(lighting, 1.0);
} 