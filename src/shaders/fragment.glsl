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
    float totalScale = uVertexDisplacementScale + uDisplacementScale;
    // Avoid division by zero when scales are zero
    if (totalScale < 0.001) {
        return 0.5; // Return neutral height when no displacement
    }
    return (vertexHeight + detailHeight) / totalScale;
}

// Helper function to get displacement height from 0 to uDisplacementScale
float simpleGetTotalSurfaceHeight(vec2 texCoords, vec2 dx, vec2 dy) {
    return textureGrad(uDisplacementMap, texCoords, dx, dy).r * uDisplacementScale * 2.0;
}

vec3 simpleParallaxOcclusionMap(vec3 V, vec2 dx, vec2 dy) {
    // Use a fixed number of layers for simplicity
    const float numLayers = 32.0;
    float layerDepth = uDisplacementScale / numLayers;
    
    // Calculate parallax offset without V.z trick
    // Use view angle to determine step size - steeper angles need larger steps
    float viewAngle = abs(V.z); // How perpendicular the view is to the surface
    float parallaxScale = (1.0 - viewAngle) * 1.0; // Scale based on viewing angle
    vec2 deltaTexCoords = normalize(V.xy) * parallaxScale * uDisplacementScale / numLayers;

    // Simple layer stepping - find first intersection
    vec2 currentTexCoords = vUv;
    float currentLayerHeight = uDisplacementScale; // Start from max height
    float currentDepthMapValue = simpleGetTotalSurfaceHeight(currentTexCoords, dx, dy);

    // Step through layers until we find an intersection
    while(currentDepthMapValue < currentLayerHeight && currentLayerHeight > 0.0) {
        currentLayerHeight -= layerDepth;
        currentTexCoords -= deltaTexCoords;
        currentDepthMapValue = simpleGetTotalSurfaceHeight(currentTexCoords, dx, dy);
    }

    // Check bounds and set alpha
    float alpha = 1.0;
    if (currentTexCoords.x < 0.0 || currentTexCoords.x > 1.0 || currentTexCoords.y < 0.0 || currentTexCoords.y > 1.0) {
        alpha = 0.0;
    }

    return vec3(currentTexCoords, alpha);
}

vec3 parallaxOcclusionMap(vec3 V, vec2 dx, vec2 dy) {
    // Determine number of layers based on view angle for performance
    const float minLayers = 16.0;
    const float maxLayers = 32.0*8.0;
    float numLayers = mix(maxLayers, minLayers, abs(dot(vec3(0.0, 0.0, 1.0), V)));

    float layerDepth = 1.0 / numLayers;
    vec2 P = V.xy / V.z * (uVertexDisplacementScale + uDisplacementScale);
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
    
    // Check if we need parallax mapping at all
    float totalDisplacementScale = uVertexDisplacementScale + uDisplacementScale;
    vec2 parallaxUv;
    float alpha = 1.0;
    
    if (totalDisplacementScale < 0.001) {
        // No displacement, use original UVs
        parallaxUv = vUv;
    } else {
        // Apply parallax occlusion mapping
        vec3 pomResult = simpleParallaxOcclusionMap(tangentViewDir, dx, dy);
        parallaxUv = pomResult.xy;
        alpha = pomResult.z;
    }

    if (alpha < 0.5) {
        discard;
    }

    vec3 tangentNormal = textureGrad(uNormalMap, parallaxUv, dx, dy).rgb * 2.0 - 1.0;
    vec3 worldNormal = normalize(vTBN * tangentNormal);
    vec4 diffuseColor = textureGrad(uDiffuseMap, parallaxUv, dx, dy);

    float height = getTotalSurfaceHeight(parallaxUv, dx, dy);
    vec3 tangentSurfacePos = vec3(parallaxUv, height);
    vec3 tangentLightDir = normalize(transpose(vTBN) * uLightDirection);
    float shadow;
    if (totalDisplacementScale < 0.001) {
        // No displacement, no self-shadowing
        shadow = 1.0;
    } else {
        shadow = getShadow(tangentSurfacePos, tangentLightDir, dx, dy);
    }
    // shadow = 1.0;

    vec3 worldLightDir = normalize(uLightDirection);
    float diff = max(dot(worldNormal, worldLightDir), 0.0);
    vec3 ambient = vec3(0.1);
    vec3 lighting = (ambient * shadow) + (diffuseColor.rgb * diff * shadow);

    gl_FragColor = vec4(lighting, alpha);
    // gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
} 