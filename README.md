# Goal: Paralax oclusion mapping shader with three.js



## Context

1. UV Mapping
UVs define how 2D textures map onto 3D surfaces.

Each vertex has UV coordinates (usually between 0 and 1).

In shaders, vUv is used to sample textures.

2. Tangent Space
A local coordinate system on the surface of a mesh:

Tangent: aligns with U (X)

Bitangent: aligns with V (Y)

Normal: points out (Z)

Used because normal and height maps are defined in this space.

Vectors like view direction and light direction must be transformed into tangent space for consistent calculations.

3. Normal Mapping
Uses a texture (RGB) to encode per-pixel surface orientation.

Flat surface = (0, 0, 1) normal → encoded as (0.5, 0.5, 1.0) in normal map texture.

Shaders decode this using * 2.0 - 1.0.

4. Why We Use Tangent Space
Texture-based maps (normals, height) are defined in tangent space.

To compare world-space vectors (viewDir, lightDir) to these maps, we must transform them using the TBN matrix.

🧱 TBN Matrix
A 3x3 matrix built from tangent, bitangent, and normal vectors.

Transforms vectors from world/view space to tangent space:

🌍 Coordinate Spaces
Model space: Local coordinates of the object.

World space: Scene-wide coordinates.

View space: Coordinates relative to the camera.

TBN must match the space you’re working in (typically view or world).

5. Parallax Occlusion Mapping (POM)
A technique that enhances parallax mapping to create more realistic depth on a flat surface.

It uses a height map to simulate 3D geometry.

The shader traces a ray in tangent space to find where it intersects the surface defined by the height map.

This allows for self-occlusion and more accurate depth perception than normal mapping alone.

