import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import GUI from 'lil-gui';
import vertexShader from './shaders/vertex.glsl?raw';
import fragmentShader from './shaders/fragment.glsl?raw';

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.001, 100);
const renderer = new THREE.WebGLRenderer();
renderer.setSize(window.innerWidth, window.innerHeight);
document.body.appendChild(renderer.domElement);

camera.position.z = 1;

const geometry = new THREE.PlaneGeometry(1, 1, 100, 100);
geometry.computeTangents();
const material = new THREE.ShaderMaterial({
    vertexShader,
    fragmentShader,
    uniforms: {
        uDiffuseMap: { value: new THREE.TextureLoader().load('/gray_rocks/gray_rocks_diff_2k.jpg') },
        uNormalMap: { value: new THREE.TextureLoader().load('/gray_rocks/gray_rocks_nor_gl_2k.jpg') },
        uDisplacementMap: { value: new THREE.TextureLoader().load('/gray_rocks/gray_rocks_disp_2k.jpg') },
        uDisplacementScale: { value: 0.05 },
        uDisplacementBias: { value: -0.025 },
        uLightDirection: { value: new THREE.Vector3(1.0, 1.0, 1.0) },
        uCameraPosition: { value: new THREE.Vector3() },
    },
});

const plane = new THREE.Mesh(geometry, material);
scene.add(plane);

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
                material.uniforms.uDiffuseMap.value = textureLoader.load(url);
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
                material.uniforms.uNormalMap.value = textureLoader.load(url);
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
                material.uniforms.uDisplacementMap.value = textureLoader.load(url);
            }
        };
        input.click();
    },
};

gui.add(textureUpload, 'diffuse').name('Upload Diffuse');
gui.add(textureUpload, 'normal').name('Upload Normal');
gui.add(textureUpload, 'displacement').name('Upload Displacement');

gui.add(material.uniforms.uDisplacementScale, 'value', 0, 0.2, 0.001).name('Displacement Scale');
gui.add(material.uniforms.uDisplacementBias, 'value', -0.1, 0.1, 0.001).name('Displacement Bias');

const lightFolder = gui.addFolder('Light Direction');
lightFolder.add(material.uniforms.uLightDirection.value, 'x', -1, 1, 0.01).name('X');
lightFolder.add(material.uniforms.uLightDirection.value, 'y', -1, 1, 0.01).name('Y');

window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
});

function animate() {
    requestAnimationFrame(animate);
    controls.update();
    material.uniforms.uCameraPosition.value.copy(camera.position);
    renderer.render(scene, camera);
}

animate();
