varying vec2 vUv;
varying vec3 vWorldPosition;
varying mat3 vTBN;

uniform sampler2D uDiffuseMap;
uniform sampler2D uNormalMap;
uniform sampler2D uDisplacementMap;
uniform float uDisplacementScale;
uniform float uDisplacementBias;
uniform vec3 uLightDirection;
uniform vec3 uCameraPosition;

vec2 parallaxOcclusionMap(vec3 V) {
    float numLayers = 32.0;
    float layerDepth = 1.0 / numLayers;
    
    vec2 P = V.xy / V.z * uDisplacementScale;
    vec2 deltaTexCoords = P / numLayers;
    
    vec2  currentTexCoords     = vUv;
    float currentDepthMapValue = texture2D(uDisplacementMap, currentTexCoords).r;
    
    while(layerDepth * numLayers > currentDepthMapValue) {
        currentTexCoords -= deltaTexCoords;
        currentDepthMapValue = texture2D(uDisplacementMap, currentTexCoords).r;
        numLayers -= 1.0;
    }
    
    vec2 prevTexCoords = currentTexCoords + deltaTexCoords;
    float afterDepth  = currentDepthMapValue - layerDepth * numLayers;
    float beforeDepth = texture2D(uDisplacementMap, prevTexCoords).r - (layerDepth * (numLayers + 1.0));
    float weight = afterDepth / (afterDepth - beforeDepth);
    
    return prevTexCoords * weight + currentTexCoords * (1.0 - weight);
}

void main() {
    vec3 worldViewDir = normalize(uCameraPosition - vWorldPosition);
    vec3 tangentViewDir = normalize(transpose(vTBN) * worldViewDir);

    vec2 parallaxUv = parallaxOcclusionMap(tangentViewDir);
    
    if (parallaxUv.x > 1.0 || parallaxUv.y > 1.0 || parallaxUv.x < 0.0 || parallaxUv.y < 0.0) {
        discard;
    }

    vec3 tangentNormal = texture2D(uNormalMap, parallaxUv).rgb * 2.0 - 1.0;
    vec3 worldNormal = normalize(vTBN * tangentNormal);
    vec4 diffuseColor = texture2D(uDiffuseMap, parallaxUv);

    vec3 worldLightDir = normalize(uLightDirection);
    float diff = max(dot(worldNormal, worldLightDir), 0.0);
    vec3 lighting = vec3(0.1) + diffuseColor.rgb * diff;

    gl_FragColor = vec4(lighting, 1.0);
} 