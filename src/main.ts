import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import GUI from 'lil-gui';
import vertexShader from './shaders/vertex.glsl?raw';
import fragmentShader from './shaders/fragment.glsl?raw';
import vertexShaderDense from './shaders/vertex-dense.glsl?raw';
import fragmentShaderDense from './shaders/fragment-dense.glsl?raw';

// Initial displacement values
// const INITIAL_DISPLACEMENT_SCALE = 0.05;
const INITIAL_DISPLACEMENT_SCALE = 0.05;
const INITIAL_VERTEX_DISPLACEMENT_SCALE = 0.2;

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.001, 100);
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(window.innerWidth, window.innerHeight);
document.body.appendChild(renderer.domElement);

const maxAnisotropy = renderer.capabilities.getMaxAnisotropy();

// Set initial camera angle to 45 degrees
const initialAngle = 90; // degrees
const radius = 2;
camera.position.y = Math.sin(-initialAngle * Math.PI / 180) * radius;
camera.position.z = Math.cos(-initialAngle * Math.PI / 180) * radius;
camera.position.x = 0.0;
camera.lookAt(0, 0, 0);

const geometry = new THREE.PlaneGeometry(1, 1, 18, 18);
geometry.computeTangents();

const loader = new THREE.TextureLoader();
const diffuseMap = loader.load('/gray_rocks/gray_rocks_diff_2k.jpg');
diffuseMap.anisotropy = maxAnisotropy;
const normalMap = loader.load('/gray_rocks/gray_rocks_nor_gl_2k.jpg');
normalMap.anisotropy = maxAnisotropy;
const displacementMap = loader.load('/gray_rocks/gray_rocks_disp_2k.jpg');
displacementMap.anisotropy = maxAnisotropy;
const vertexDisplacementMap = loader.load('/hill.jpg');
vertexDisplacementMap.anisotropy = maxAnisotropy;

const material = new THREE.ShaderMaterial({
    vertexShader,
    fragmentShader,
    transparent: true,
    uniforms: {
        uDiffuseMap: { value: diffuseMap },
        uNormalMap: { value: normalMap },
        uDisplacementMap: { value: displacementMap },
        uVertexDisplacementMap: { value: vertexDisplacementMap },
        uDisplacementScale: { value: INITIAL_DISPLACEMENT_SCALE },
        uDisplacementBias: { value: -0.025 },
        uVertexDisplacementScale: { value: INITIAL_VERTEX_DISPLACEMENT_SCALE },
        uLightDirection: { value: new THREE.Vector3(1.0, 1.0, 1.0) },
        uCameraPosition: { value: new THREE.Vector3() },
        uShadowHardness: { value: 8.0 },
        uDebugMode: { value: 0 },
        uUseSmoothTBN: { value: true },
        uEnableShadows: { value: false },
    },
});

const plane = new THREE.Mesh(geometry, material);
// Position the POM mesh to the left
plane.position.x = -0.5;
scene.add(plane);

// Create dense mesh for comparison
const denseGeometry = new THREE.PlaneGeometry(1, 1, 512, 512); // Much denser geometry
denseGeometry.computeTangents();

const denseMaterial = new THREE.ShaderMaterial({
    vertexShader: vertexShaderDense,
    fragmentShader: fragmentShaderDense,
    uniforms: {
        uDiffuseMap: { value: diffuseMap },
        uNormalMap: { value: normalMap },
        uDisplacementMap: { value: displacementMap },
        uVertexDisplacementMap: { value: vertexDisplacementMap },
        uDisplacementScale: { value: INITIAL_DISPLACEMENT_SCALE },
        uVertexDisplacementScale: { value: INITIAL_VERTEX_DISPLACEMENT_SCALE },
        uLightDirection: { value: new THREE.Vector3(1.0, 1.0, 1.0) },
        uCameraPosition: { value: new THREE.Vector3() },
    },
});

const densePlane = new THREE.Mesh(denseGeometry, denseMaterial);
// Position the dense mesh to the right
densePlane.position.x = 0.5;
scene.add(densePlane);

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;

const gui = new GUI();
const textureLoader = new THREE.TextureLoader();

const textureUpload = {
    diffuse: () => {
        const input = document.createElement('input');
        input.type = 'file';
        input.onchange = (e) => {
            const file = (e.target as HTMLInputElement).files?.[0];
            if (file) {
                const url = URL.createObjectURL(file);
                const texture = textureLoader.load(url, (texture) => {
                    texture.anisotropy = maxAnisotropy;
                    texture.needsUpdate = true;
                });
                material.uniforms.uDiffuseMap.value = texture;
                denseMaterial.uniforms.uDiffuseMap.value = texture;
            }
        };
        input.click();
    },
    normal: () => {
        const input = document.createElement('input');
        input.type = 'file';
        input.onchange = (e) => {
            const file = (e.target as HTMLInputElement).files?.[0];
            if (file) {
                const url = URL.createObjectURL(file);
                const texture = textureLoader.load(url, (texture) => {
                    texture.anisotropy = maxAnisotropy;
                    texture.needsUpdate = true;
                });
                material.uniforms.uNormalMap.value = texture;
                denseMaterial.uniforms.uNormalMap.value = texture;
            }
        };
        input.click();
    },
    displacement: () => {
        const input = document.createElement('input');
        input.type = 'file';
        input.onchange = (e) => {
            const file = (e.target as HTMLInputElement).files?.[0];
            if (file) {
                const url = URL.createObjectURL(file);
                const texture = textureLoader.load(url, (texture) => {
                    texture.anisotropy = maxAnisotropy;
                    texture.needsUpdate = true;
                });
                material.uniforms.uDisplacementMap.value = texture;
                denseMaterial.uniforms.uDisplacementMap.value = texture;
            }
        };
        input.click();
    },
    vertexDisplacement: () => {
        const input = document.createElement('input');
        input.type = 'file';
        input.onchange = (e) => {
            const file = (e.target as HTMLInputElement).files?.[0];
            if (file) {
                const url = URL.createObjectURL(file);
                const texture = textureLoader.load(url, (texture) => {
                    texture.anisotropy = maxAnisotropy;
                    texture.needsUpdate = true;
                });
                material.uniforms.uVertexDisplacementMap.value = texture;
                denseMaterial.uniforms.uVertexDisplacementMap.value = texture;
            }
        };
        input.click();
    }
};

gui.add(textureUpload, 'diffuse').name('Upload Diffuse');
gui.add(textureUpload, 'normal').name('Upload Normal');
gui.add(textureUpload, 'displacement').name('Upload Parallax');
gui.add(textureUpload, 'vertexDisplacement').name('Upload Displacement');

gui.add(material.uniforms.uDisplacementScale, 'value', 0, 0.2, 0.001).name('Parallax Scale').onChange((value: number) => {
    denseMaterial.uniforms.uDisplacementScale.value = value;
});
gui.add(material.uniforms.uDisplacementBias, 'value', -0.1, 0.1, 0.001).name('Parallax Bias');
gui.add(material.uniforms.uVertexDisplacementScale, 'value', 0, 0.5, 0.001).name('Displacement Scale').onChange((value: number) => {
    denseMaterial.uniforms.uVertexDisplacementScale.value = value;
});
gui.add(material.uniforms.uShadowHardness, 'value', 1.0, 32.0, 1.0).name('Shadow Hardness');
gui.add(material.uniforms.uEnableShadows, 'value').name('Enable Shadows');

// Add debug mode control
const debugModeOptions = {
    'Normal Rendering': 0,
    'Tangent Vectors (T)': 1,
    'Bitangent Vectors (B)': 2,
    'Normal Vectors (N)': 3,
    'View Direction': 4,
    'Parallax UV Offset': 5,
    'Height Map': 6
};

gui.add(material.uniforms.uDebugMode, 'value', debugModeOptions).name('Debug Mode');

// Add TBN calculation method control
gui.add(material.uniforms.uUseSmoothTBN, 'value').name('Smooth TBN (vs Physically Accurate)');

// Add camera angle control
const cameraControl = {
    angle: initialAngle
};

function updateCameraPosition(angle: number) {
    const angleRad = -angle * Math.PI / 180;
    camera.position.x = 0.0;
    camera.position.y = Math.sin(angleRad) * radius;
    camera.position.z = Math.cos(angleRad) * radius;
    camera.lookAt(0, 0, 0);
}

gui.add(cameraControl, 'angle', 0, 360, 1).name('Camera Angle (°)').onChange((value: number) => {
    updateCameraPosition(value);
});

// Add wireframe toggle
const wireframeControl = {
    wireframe: false
};
gui.add(wireframeControl, 'wireframe').name('Wireframe').onChange((value: boolean) => {
    material.wireframe = value;
    denseMaterial.wireframe = value;
});

const lightFolder = gui.addFolder('Light Direction');
lightFolder.add(material.uniforms.uLightDirection.value, 'x', -1, 1, 0.01).name('X').onChange((value: number) => {
    denseMaterial.uniforms.uLightDirection.value.x = value;
});
lightFolder.add(material.uniforms.uLightDirection.value, 'y', -1, 1, 0.01).name('Y').onChange((value: number) => {
    denseMaterial.uniforms.uLightDirection.value.y = value;
});

window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
});

function animate() {
    requestAnimationFrame(animate);
    controls.update();
    material.uniforms.uCameraPosition.value.copy(camera.position);
    denseMaterial.uniforms.uCameraPosition.value.copy(camera.position);
    renderer.render(scene, camera);
}

animate();
