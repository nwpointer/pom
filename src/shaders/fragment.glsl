varying vec2 vUv;
varying vec3 vWorldPosition;
varying mat3 vTBN;

uniform sampler2D uDiffuseMap;
uniform sampler2D uNormalMap;
uniform sampler2D uDisplacementMap;
uniform sampler2D uVertexDisplacementMap;
uniform float uDisplacementScale;
uniform float uVertexDisplacementScale;
uniform vec3 uCameraPosition;
uniform vec3 uLightDirection;
uniform float uShadowHardness;

// Helper function to get total surface height (vertex displacement + detail displacement)
float getTotalSurfaceHeight(vec2 texCoords, vec2 dx, vec2 dy) {
    float vertexHeight = textureGrad(uVertexDisplacementMap, texCoords, dx, dy).r * uVertexDisplacementScale;
    float detailHeight = textureGrad(uDisplacementMap, texCoords, dx, dy).r * uDisplacementScale;
    return (vertexHeight + detailHeight) / (uVertexDisplacementScale + uDisplacementScale);
}

vec3 parallaxOcclusionMap(vec3 V, vec2 dx, vec2 dy) {
    // Determine number of layers based on view angle for performance
    const float minLayers = 16.0;
    const float maxLayers = 32.0*8.0;
    float numLayers = mix(maxLayers, minLayers, abs(dot(vec3(0.0, 0.0, 1.0), V)));

    float layerDepth = 1.0 / numLayers;
    vec2 P = V.xy / V.z * (uDisplacementScale + uVertexDisplacementScale);
    vec2 deltaTexCoords = P / numLayers;

    // Coarse search to find an interval containing the intersection
    vec2  currentTexCoords = vUv;
    float currentLayerHeight = 1.0;
    float currentDepthMapValue = getTotalSurfaceHeight(currentTexCoords, dx, dy);

    while(currentDepthMapValue < currentLayerHeight) {
        currentLayerHeight -= layerDepth;
        currentTexCoords -= deltaTexCoords;
        currentDepthMapValue = getTotalSurfaceHeight(currentTexCoords, dx, dy);
    }

    // Refined search using binary search (Interval Mapping)
    vec2 prevTexCoords = currentTexCoords + deltaTexCoords;
    float prevLayerHeight = currentLayerHeight + layerDepth;
    const int numRefinementSteps = 8;
    for(int i = 0; i < numRefinementSteps; i++) {
        vec2 midTexCoords = mix(currentTexCoords, prevTexCoords, 0.5);
        float midLayerHeight = mix(currentLayerHeight, prevLayerHeight, 0.5);
        float midDepthMapValue = getTotalSurfaceHeight(midTexCoords, dx, dy);

        if (midDepthMapValue < midLayerHeight) {
            prevTexCoords = midTexCoords;
            prevLayerHeight = midLayerHeight;
        } else {
            currentTexCoords = midTexCoords;
            currentLayerHeight = midLayerHeight;
        }
    }

    // Final linear interpolation on the highly refined interval
    float afterDepth = getTotalSurfaceHeight(currentTexCoords, dx, dy) - currentLayerHeight;
    float beforeDepth = getTotalSurfaceHeight(prevTexCoords, dx, dy) - prevLayerHeight;
    float weight = afterDepth / (afterDepth - beforeDepth);
    vec2 finalTexCoords = mix(currentTexCoords, prevTexCoords, weight);

    float alpha = 1.0;
    if (finalTexCoords.x < 0.0 || finalTexCoords.x > 1.0 || finalTexCoords.y < 0.0 || finalTexCoords.y > 1.0) {
        alpha = 0.0;
    }

    return vec3(finalTexCoords, alpha);
}

float getShadow(vec3 surfacePos, vec3 tangentLightDir, vec2 dx, vec2 dy) {
    if (tangentLightDir.z <= 0.0) return 0.0;
    float shadow = 0.0;
    const int numSamples = 32;
    float rayStep = 1.0 / float(numSamples);
    vec2 texStep = rayStep * (tangentLightDir.xy / tangentLightDir.z) * (uDisplacementScale + uVertexDisplacementScale);
    float currentRayHeight = surfacePos.z + rayStep;
    vec2 currentTexCoords = surfacePos.xy + texStep;
    for (int i = 0; i < numSamples; i++) {
        if (currentRayHeight > 1.0 || currentTexCoords.x < 0.0 || currentTexCoords.x > 1.0 || currentTexCoords.y < 0.0 || currentTexCoords.y > 1.0) break;
        float heightAtSample = getTotalSurfaceHeight(currentTexCoords, dx, dy);
        if (currentRayHeight < heightAtSample) {
            shadow += 1.0;
        }
        currentRayHeight += rayStep;
        currentTexCoords += texStep;
    }
    return 1.0 - min(shadow / uShadowHardness, 1.0);
}

void main() {
    vec3 worldViewDir = normalize(uCameraPosition - vWorldPosition);
    vec3 tangentViewDir = normalize(transpose(vTBN) * worldViewDir);
    vec2 dx = dFdx(vUv);
    vec2 dy = dFdy(vUv);
    vec3 pomResult = parallaxOcclusionMap(tangentViewDir, dx, dy);
    vec2 parallaxUv = pomResult.xy;
    float alpha = pomResult.z;

    if (alpha < 0.5) {
        discard;
    }

    vec3 tangentNormal = textureGrad(uNormalMap, parallaxUv, dx, dy).rgb * 2.0 - 1.0;
    vec3 worldNormal = normalize(vTBN * tangentNormal);
    vec4 diffuseColor = textureGrad(uDiffuseMap, parallaxUv, dx, dy);

    float height = getTotalSurfaceHeight(parallaxUv, dx, dy);
    vec3 tangentSurfacePos = vec3(parallaxUv, height);
    
    vec3 tangentLightDir = normalize(transpose(vTBN) * uLightDirection);
    float shadow = getShadow(tangentSurfacePos, tangentLightDir, dx, dy);

    vec3 worldLightDir = normalize(uLightDirection);
    float diff = max(dot(worldNormal, worldLightDir), 0.0);
    vec3 ambient = vec3(0.1);
    vec3 lighting = (ambient * shadow) + (diffuseColor.rgb * diff * shadow);

    gl_FragColor = vec4(lighting, alpha);
} 