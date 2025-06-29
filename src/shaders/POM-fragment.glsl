varying vec2 vUv;
varying vec3 vWorldPosition;
varying vec3 vWorldNormal;
varying vec4 vWorldTangent;
// New: Smooth interpolated TBN from vertex shader
varying vec3 vSmoothWorldNormal;
varying vec3 vSmoothWorldTangent;
varying vec3 vSmoothWorldBitangent;

uniform sampler2D uDiffuseMap;
uniform sampler2D uNormalMap;
uniform sampler2D uDisplacementMap;
uniform sampler2D uVertexDisplacementMap;
uniform float uDisplacementScale;
uniform float uVertexDisplacementScale;
uniform float uParallaxOffset;
uniform float uActiveRadius;
uniform float uMinLayers;
uniform float uMaxLayers;
uniform vec3 uCameraPosition;
uniform vec3 uLightDirection;
uniform float uShadowHardness;
uniform int uDebugMode; // 0=off, 1=tangent, 2=bitangent, 3=normal, 4=view_dir

uniform bool uEnableShadows; // true=shadows enabled, false=shadows disabled
uniform bool uUseDynamicLayers; // true=dynamic layers based on view angle, false=fixed layers
uniform int uPOMMethod; // 0=standard, 1=terrain
uniform float uTextureRepeat; // Number of times to repeat the parallax textures
float pomDisplacementScale ;


// Get TBN matrix - always use smooth interpolated TBN from vertex shader
mat3 getActiveTBNMatrix(vec2 dx, vec2 dy) {
    return mat3(
        normalize(vSmoothWorldTangent),
        normalize(vSmoothWorldBitangent),
        normalize(vSmoothWorldNormal)
    );
}

// Helper function to get displacement height from 0 to pomDisplacementScale
float getHeight(vec2 texCoords, vec2 dx, vec2 dy) {
    vec2 repeatedCoords = texCoords * uTextureRepeat;
    vec2 repeatedDx = dx * uTextureRepeat;
    vec2 repeatedDy = dy * uTextureRepeat;
    return (textureGrad(uDisplacementMap, repeatedCoords, repeatedDx, repeatedDy).r + uParallaxOffset) * pomDisplacementScale ;
}



// Standard basic parallax occlusion mapping - simplest implementation
vec3 standardParallaxOcclusionMap(vec3 V, vec2 dx, vec2 dy, float numLayers) {
    // Basic parallax offset calculation
    vec2 P = V.xy / max(V.z, 0.00001) * pomDisplacementScale;
    vec2 deltaTexCoords = P / numLayers;
    
    // Simple ray marching
    vec2 currentTexCoords = vUv;
    float currentLayerHeight = pomDisplacementScale; // Start from max height like terrain POM
    float layerDepth = pomDisplacementScale / numLayers; // Scale layer depth
    
    // Basic coarse search to find intersection interval
    vec2 prevTexCoords = currentTexCoords;
    float prevLayerHeight = currentLayerHeight;
    
    for(float i = 0.0; i < numLayers; i += 1.0) {
        float currentDepthMapValue = getHeight(currentTexCoords, dx, dy);
        
        if (currentDepthMapValue >= currentLayerHeight) {
            break;
        }
        
        // Store previous values for refinement
        prevTexCoords = currentTexCoords;
        prevLayerHeight = currentLayerHeight;
        
        currentLayerHeight -= layerDepth;
        currentTexCoords -= deltaTexCoords;
    }
    
    // Binary search refinement (Interval Mapping)
    const int numRefinementSteps = 6; // Less refinement for standard version
    for(int i = 0; i < numRefinementSteps; i++) {
        vec2 midTexCoords = mix(currentTexCoords, prevTexCoords, 0.5);
        float midLayerHeight = mix(currentLayerHeight, prevLayerHeight, 0.5);
        float midDepthMapValue = getHeight(midTexCoords, dx, dy);

        if (midDepthMapValue < midLayerHeight) {
            prevTexCoords = midTexCoords;
            prevLayerHeight = midLayerHeight;
        } else {
            currentTexCoords = midTexCoords;
            currentLayerHeight = midLayerHeight;
        }
    }

    // Final linear interpolation for smooth transition
    float afterDepth = getHeight(currentTexCoords, dx, dy) - currentLayerHeight;
    float beforeDepth = getHeight(prevTexCoords, dx, dy) - prevLayerHeight;
    float weight = afterDepth / (afterDepth - beforeDepth);
    vec2 finalTexCoords = mix(currentTexCoords, prevTexCoords, weight);
    
    float alpha = 1.0;
    if (finalTexCoords.x < 0.0 || finalTexCoords.x > 1.0 || 
        finalTexCoords.y < 0.0 || finalTexCoords.y > 1.0) {
        alpha = 0.0;
    }
    
    return vec3(finalTexCoords, alpha);
}

vec3 terrainParallaxOcclusionMap(vec3 V, vec2 dx, vec2 dy, float numLayers) {
    // Smooth V.z influence for stable parallax
    float smoothVz = smoothstep(0.0, 1.0, abs(V.z)); // Smooth S-curve transition
    float reducedVz = mix(0.55, 1.0, abs(V.z)); // Blend with smoother transition
    // vec2 P = V.xy / V.z * pomDisplacementScale;
    vec2 P = V.xy / reducedVz * pomDisplacementScale;
    vec2 deltaTexCoords = P / numLayers;

    // Step along the displaced surface
    vec2 currentTexCoords = vUv;
    float currentLayerHeight = pomDisplacementScale; // Start from max height
    float currentDepthMapValue = getHeight(currentTexCoords, dx, dy);

    // Step through layers, but adjust step size based on surface slope
    vec2 prevTexCoords = vUv;
    float prevLayerHeight = pomDisplacementScale;
    
    for(float i = 0.0; i < numLayers; i += 1.0) {
        if(currentDepthMapValue >= currentLayerHeight) break;
        
        // Store previous values for refinement
        prevTexCoords = currentTexCoords;
        prevLayerHeight = currentLayerHeight;
        
        // Sample surface height at next position to get surface slope
        vec2 nextTexCoords = currentTexCoords - deltaTexCoords;
        float nextDepthMapValue = getHeight(nextTexCoords, dx, dy);
        
        // Calculate surface slope and adjust our stepping
        float surfaceSlope = (nextDepthMapValue - currentDepthMapValue);
        
        // Step along the surface contour - adjust layer height based on surface slope
        float dynamicLayerDepth = (pomDisplacementScale / numLayers) * (1.0 + surfaceSlope * 2.0);
        currentLayerHeight -= dynamicLayerDepth;
        
        currentTexCoords = nextTexCoords;
        currentDepthMapValue = nextDepthMapValue;
    }

    // Refined search using binary search (Interval Mapping)
    const int numRefinementSteps = 8;
    for(int i = 0; i < numRefinementSteps; i++) {
        vec2 midTexCoords = mix(currentTexCoords, prevTexCoords, 0.5);
        float midLayerHeight = mix(currentLayerHeight, prevLayerHeight, 0.5);
        float midDepthMapValue = getHeight(midTexCoords, dx, dy);

        if (midDepthMapValue < midLayerHeight) {
            prevTexCoords = midTexCoords;
            prevLayerHeight = midLayerHeight;
        } else {
            currentTexCoords = midTexCoords;
            currentLayerHeight = midLayerHeight;
        }
    }

    // Final linear interpolation on the highly refined interval
    float afterDepth = getHeight(currentTexCoords, dx, dy) - currentLayerHeight;
    float beforeDepth = getHeight(prevTexCoords, dx, dy) - prevLayerHeight;
    float weight = afterDepth / (afterDepth - beforeDepth);
    vec2 finalTexCoords = mix(currentTexCoords, prevTexCoords, weight);

    // Check bounds and set alpha
    float alpha = 1.0;
    if (finalTexCoords.x < 0.0 || finalTexCoords.x > 1.0 || finalTexCoords.y < 0.0 || finalTexCoords.y > 1.0) {
        alpha = 0.0;
    }

    return vec3(finalTexCoords, alpha);
}

float getShadow(vec3 surfacePos, vec3 tangentLightDir, vec2 dx, vec2 dy, float numLayers) {
    if (tangentLightDir.z <= 0.0) return 0.0;
    
    float shadow = 0.0;
    float rayStep = 1.0 / float(numLayers);
    vec2 texStep = rayStep * (tangentLightDir.xy / max(tangentLightDir.z, 0.00001)) * pomDisplacementScale;
    float currentRayHeight = surfacePos.z + rayStep;
    vec2 currentTexCoords = surfacePos.xy + texStep;
    
    // Use repeated coordinates and derivatives for shadow sampling
    vec2 repeatedDx = dx * uTextureRepeat;
    vec2 repeatedDy = dy * uTextureRepeat;

   
    
    for (float i = 0.0; i < numLayers; i++) {
        if (currentRayHeight > 1.0 || currentTexCoords.x < -0.5 || currentTexCoords.x > 1.5 || 
            currentTexCoords.y < -0.5 || currentTexCoords.y > 1.5) break;
        
        // Sample height using repeated coordinates
        vec2 repeatedTexCoords = currentTexCoords * uTextureRepeat;
        float heightAtSample = textureGrad(uDisplacementMap, repeatedTexCoords, repeatedDx, repeatedDy).r + uParallaxOffset;
        
        if (currentRayHeight < heightAtSample) {
            shadow += 1.0;
        }
        
        currentRayHeight += rayStep;
        currentTexCoords += texStep;
    }
    
    return 1.0 - min(shadow / uShadowHardness, 1.0);
}

// angle mask for POM - takes the angle between the world normal and the view direction
float angleMask(vec3 worldNormal, vec3 worldViewDir) {
    float angle = dot(worldNormal, worldViewDir);
    // 0-1
    return pow(1.0 - smoothstep(0.0, 1.0, angle), 2.0);
}

// distance mask for POM - takes the distance between the world position and the camera position
float distanceMask(vec3 worldPosition, vec3 cameraPosition) {
    float distance = length(worldPosition - cameraPosition);
    // 0-1
    return 1.0 - pow(smoothstep(0.0, 1.0, distance), 0.125);
}


void main() {
    
    vec3 worldViewDir = normalize(uCameraPosition - vWorldPosition);
    vec2 dx = dFdx(vUv);
    vec2 dy = dFdy(vUv);
    
    // Use active TBN matrix (smooth or physically accurate)
    mat3 tbnMatrix = getActiveTBNMatrix(dx, dy);
    vec3 tangentViewDir = normalize(transpose(tbnMatrix) * worldViewDir);
    
    // Calculate number of layers based on dynamic/fixed setting
    float numLayers;
    vec3 N = tbnMatrix[2]; // Normal
    float angleMaskValue = angleMask(N, worldViewDir);
    float distanceMaskValue = distanceMask(vWorldPosition, uCameraPosition);
    float r = (uActiveRadius / 10.0);
    float transition = smoothstep(r, r + 0.3, distanceMaskValue);
    pomDisplacementScale = uDisplacementScale * transition;
    float combinedMask = (angleMaskValue) * distanceMaskValue;
    if (uUseDynamicLayers) {
        numLayers = mix(uMinLayers, uMaxLayers, combinedMask);
    } else {
        numLayers = uMaxLayers;
    }
    
    // Check if we need parallax mapping at all
    vec2 parallaxUv;
    float alpha = 1.0;
    
    if (pomDisplacementScale < 0.00001 || distanceMaskValue < (uActiveRadius / 10.0)) {
        // No parallax displacement, use original UVs (skip POM calculation)
        parallaxUv = vUv;
    } else {
        // Apply selected parallax occlusion mapping method
        vec3 pomResult;
        if (uPOMMethod == 0) {
            // Standard POM - simplest implementation
            pomResult = standardParallaxOcclusionMap(tangentViewDir, dx, dy, numLayers);
        } else {
            // Terrain POM - with surface slope adjustments
            pomResult = terrainParallaxOcclusionMap(tangentViewDir, dx, dy, numLayers);
        }
        parallaxUv = pomResult.xy;
        alpha = pomResult.z;
    }

    if (alpha < 0.5) {
        discard;
    }

    vec2 repeatedParallaxUv = parallaxUv * uTextureRepeat;
    vec2 repeatedDx = dx * uTextureRepeat;
    vec2 repeatedDy = dy * uTextureRepeat;
    
    vec3 tangentNormal = textureGrad(uNormalMap, repeatedParallaxUv, repeatedDx, repeatedDy).rgb * 2.0 - 1.0;
    vec3 worldNormal = normalize(tbnMatrix * tangentNormal);
    vec4 diffuseColor = textureGrad(uDiffuseMap, repeatedParallaxUv, repeatedDx, repeatedDy);

    // Calculate surface position in tangent space for shadows using repeated coordinates
    float height = textureGrad(uDisplacementMap, repeatedParallaxUv, repeatedDx, repeatedDy).r + uParallaxOffset;
    vec3 tangentSurfacePos = vec3(parallaxUv, height);
    
    // Ensure light source is always above the maximum possible surface height
    // Maximum possible height is 1.0 (texture value) + uParallaxOffset
    float maxSurfaceHeight = 1.0 + uParallaxOffset;
    
    // Calculate the minimum light Z to ensure it's above max surface height
    // Add extra margin (0.5) to ensure robust shadow calculation
    float minLightZ = maxSurfaceHeight + 0.5;
    
    // Get world light direction and ensure it has sufficient upward component
    vec3 worldLightDir = normalize(uLightDirection);
    
    // If the light Z is too low, boost it to ensure proper tangent space transformation
    if (worldLightDir.z < minLightZ) {
        worldLightDir = normalize(vec3(worldLightDir.xy, minLightZ));
    }
    
    vec3 tangentLightDir = normalize(transpose(tbnMatrix) * worldLightDir);
    
    // Additional safety: ensure tangent space light Z is always positive with minimum threshold
    float minTangentLightZ = 0.2; // Minimum threshold for stable shadow calculations
    if (tangentLightDir.z < minTangentLightZ) {
        tangentLightDir = normalize(vec3(tangentLightDir.xy, minTangentLightZ));
    }
    
    float shadow;
    
    if (!uEnableShadows || uDisplacementScale < 0.00001) {
        // Shadows disabled or no parallax displacement, no self-shadowing
        shadow = 1.0;
    } else {
        shadow = getShadow(tangentSurfacePos, tangentLightDir, dx, dy, numLayers);
    }

    // Debug mode visualization
    if (uDebugMode > 0) {
        vec3 debugColor = vec3(0.0);
        // Use the same displacement-aware TBN matrix for debug visualization
        vec3 T = tbnMatrix[0]; // Tangent
        vec3 B = tbnMatrix[1]; // Bitangent  
        vec3 N = tbnMatrix[2]; // Normal
        
        if (uDebugMode == 1) {
            // Visualize Tangent (Red channel dominant)
            debugColor = T * 0.5 + 0.5; // Remap from [-1,1] to [0,1]
        } else if (uDebugMode == 2) {
            // Visualize Bitangent (Green channel dominant)
            debugColor = B * 0.5 + 0.5; // Remap from [-1,1] to [0,1]
        } else if (uDebugMode == 3) {
            // Visualize Normal (Blue channel dominant)
            debugColor = N * 0.5 + 0.5; // Remap from [-1,1] to [0,1]
        } else if (uDebugMode == 4) {
            // Visualize View Direction in tangent space
            debugColor = tangentViewDir * 0.5 + 0.5; // Remap from [-1,1] to [0,1]
        } else if (uDebugMode == 5) {
            // Visualize Parallax UV offset
            vec2 uvOffset = parallaxUv - vUv;
            debugColor = vec3(uvOffset * 10.0, 0.0); // Scale up offset for visibility
        } else if (uDebugMode == 6) {
            // Visualize Height Map
            float height = getHeight(parallaxUv, dx, dy) / uDisplacementScale;
            debugColor = vec3(height);
        }
        else if (uDebugMode == 7) {
            // Visualize Angle Mask
            float angleMask = angleMask(N, worldViewDir);
            float distanceMask = distanceMask(vWorldPosition, uCameraPosition);
            float combinedMask = (angleMask) * distanceMask + distanceMask * distanceMask;
            // float r = (uActiveRadius / 20.0);
            // float transition = smoothstep(r, r + 0.5, distanceMask);
            debugColor = vec3(transition);
        }
        
        gl_FragColor = vec4(debugColor, alpha);
        return;
    }

    float diff = max(dot(worldNormal, worldLightDir), 0.0);
    vec3 ambient = vec3(0.1);
    vec3 lighting = (ambient * shadow) + (diffuseColor.rgb * diff * shadow);

    gl_FragColor = vec4(lighting, alpha);
    // gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
} 