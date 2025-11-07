"""
Procedural Fusuma Panel Generator

Creates solid fusuma panels (painted sliding panels) for foreground framing.
Fusuma are solid panels (no grid) used to frame spaces in Japanese architecture.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python generate_fusuma.py
"""

import bpy
import bmesh
import numpy as np
from pathlib import Path

# ============================================================================
# PARAMETERS
# ============================================================================

FUSUMA_CONFIG = {
    # Dimensions
    'width': 1.2,              # Width of each fusuma panel (meters)
    'height': 2.5,             # Height of fusuma panel (meters)
    
    # Material colors
    'frame_color': (0.45, 0.35, 0.25, 1.0),  # Dark wood tone (matches backdrop)
    'panel_color': (0.98, 0.97, 0.95, 1.0),  # Slightly off-white (painted surface)
    'frame_roughness': 0.7,
    'panel_roughness': 0.9,
}

# ============================================================================
# GENERATOR FUNCTIONS
# ============================================================================

def create_fusuma_geometry(config):
    """Create simple flat plane for fusuma panel."""
    mesh = bpy.data.meshes.new("FusumaMesh")
    bm = bmesh.new()
    
    width = config['width']
    height = config['height']
    
    # Create simple flat plane
    bm.verts.new((-width/2, 0, height/2))   # Top-left
    bm.verts.new((width/2, 0, height/2))   # Top-right
    bm.verts.new((width/2, 0, -height/2))   # Bottom-right
    bm.verts.new((-width/2, 0, -height/2))   # Bottom-left
    
    face = bm.faces.new(bm.verts)
    
    # Create UV layer
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for loop in face.loops:
        u = (loop.vert.co.x + width/2) / width
        v = (loop.vert.co.z + height/2) / height
        loop[uv_layer].uv = (u, v)
    
    face.smooth = True
    
    bm.to_mesh(mesh)
    bm.free()
    
    return mesh

def create_fusuma_texture(config):
    """Create texture for fusuma panel (solid with frame)."""
    texture_size = 512  # Smaller for simple solid panel
    
    frame_color = np.array(config['frame_color'][:3])
    panel_color = np.array(config['panel_color'][:3])
    
    texture = np.ones((texture_size, texture_size, 4), dtype=np.float32)
    texture[:, :, :3] = panel_color  # Solid color
    
    # Draw frame
    frame_width_px = 8
    texture[:frame_width_px, :, :3] = frame_color  # Top
    texture[-frame_width_px:, :, :3] = frame_color  # Bottom
    texture[:, :frame_width_px, :3] = frame_color  # Left
    texture[:, -frame_width_px:, :3] = frame_color  # Right
    
    texture[:, :, 3] = 1.0  # Opaque
    
    return texture

def create_fusuma_material(config):
    """Create material for fusuma panel."""
    mat = bpy.data.materials.new(name="FusumaMaterial")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    
    # Create texture
    texture_data = create_fusuma_texture(config)
    image = bpy.data.images.new(name="FusumaTexture", width=texture_data.shape[1], height=texture_data.shape[0])
    image.pixels = texture_data.flatten()
    image.pack()
    
    # Image texture node
    tex_image = nodes.new(type='ShaderNodeTexImage')
    tex_image.location = (0, 0)
    tex_image.image = image
    
    # UV coordinates
    tex_coord = nodes.new(type='ShaderNodeTexCoord')
    tex_coord.location = (-200, 0)
    mat.node_tree.links.new(tex_coord.outputs['UV'], tex_image.inputs['Vector'])
    
    # Principled BSDF
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.location = (300, 0)
    bsdf.inputs['Roughness'].default_value = config['panel_roughness']
    bsdf.inputs['Metallic'].default_value = 0.0
    
    mat.node_tree.links.new(tex_image.outputs['Color'], bsdf.inputs['Base Color'])
    
    # Output
    output = nodes.new(type='ShaderNodeOutputMaterial')
    output.location = (500, 0)
    mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    
    return mat

def generate_fusuma(config=FUSUMA_CONFIG, output_path=None):
    """Generate a fusuma panel asset."""
    print(f"\n=== GENERATING FUSUMA PANEL ===")
    print(f"  Width: {config['width']}m")
    print(f"  Height: {config['height']}m")
    
    # Clear scene
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    
    # Create mesh
    mesh = create_fusuma_geometry(config)
    
    # Create object
    fusuma = bpy.data.objects.new("Fusuma", mesh)
    bpy.context.collection.objects.link(fusuma)
    
    # Create and assign material
    mat = create_fusuma_material(config)
    fusuma.data.materials.append(mat)
    
    fusuma.location = (0, 0, 0)
    
    poly_count = len(fusuma.data.polygons)
    print(f"  ✓ Created fusuma panel: {poly_count} polygon(s)")
    
    if output_path:
        bpy.ops.wm.save_as_mainfile(filepath=output_path)
        print(f"  ✓ Saved: {output_path}")
    
    return fusuma

def main():
    """Main function for standalone execution."""
    script_dir = Path(__file__).parent.parent.parent
    output_path = str(script_dir / "assets" / "models" / "library" / "Fusuma.blend")
    
    generate_fusuma(FUSUMA_CONFIG, output_path)
    
    print(f"\n✅ Fusuma generation complete\n")

if __name__ == "__main__":
    main()

