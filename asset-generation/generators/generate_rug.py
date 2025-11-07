"""
Procedural Rug Generator

Creates a circular rug with proper UV mapping for personalized texture.
This script can be run standalone or imported.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python generate_rug.py
"""

import bpy
import bmesh
import math
from pathlib import Path

# ============================================================================
# PARAMETERS - Adjust these to change the rug
# ============================================================================

RUG_CONFIG = {
    # Dimensions
    'shape': 'circle',           # Shape type ('circle' or 'rounded_rect')
    'radius': 1.5,               # Radius for circle (meters)
    'thickness': 0.002,          # Slight thickness for realism (meters)
    
    # Detail
    'segments': 32,              # Number of segments around circumference (more = smoother)
    
    # Material (placeholder - will be overridden by runtime texture)
    'material_name': 'RugMaterial',
    'base_color': (0.8, 0.8, 0.8, 1.0),  # Gray placeholder
    'roughness': 0.9,
}

# ============================================================================
# GENERATOR FUNCTIONS
# ============================================================================

def create_rug_geometry(config):
    """Create the rug mesh geometry with proper UV mapping."""
    mesh = bpy.data.meshes.new("RugMesh")
    bm = bmesh.new()
    
    radius = config['radius']
    thickness = config['thickness']
    segments = config['segments']
    
    # Create top face vertices (circle)
    top_verts = []
    center_top = bm.verts.new((0, 0, thickness))
    top_verts.append(center_top)
    
    for i in range(segments):
        angle = (2 * math.pi * i) / segments
        x = radius * math.cos(angle)
        y = radius * math.sin(angle)
        vert = bm.verts.new((x, y, thickness))
        top_verts.append(vert)
    
    # Create bottom face vertices (circle)
    bottom_verts = []
    center_bottom = bm.verts.new((0, 0, 0))
    bottom_verts.append(center_bottom)
    
    for i in range(segments):
        angle = (2 * math.pi * i) / segments
        x = radius * math.cos(angle)
        y = radius * math.sin(angle)
        vert = bm.verts.new((x, y, 0))
        bottom_verts.append(vert)
    
    # Create top face (circle)
    for i in range(segments):
        v1 = center_top
        v2 = top_verts[i + 1]
        v3 = top_verts[(i + 1) % segments + 1]
        bm.faces.new([v1, v2, v3])
    
    # Create bottom face (circle, reversed winding)
    for i in range(segments):
        v1 = center_bottom
        v2 = bottom_verts[(i + 1) % segments + 1]
        v3 = bottom_verts[i + 1]
        bm.faces.new([v1, v2, v3])
    
    # Create edge faces (connecting top and bottom)
    for i in range(segments):
        v1 = top_verts[i + 1]
        v2 = top_verts[(i + 1) % segments + 1]
        v3 = bottom_verts[(i + 1) % segments + 1]
        v4 = bottom_verts[i + 1]
        bm.faces.new([v1, v2, v3, v4])
    
    # Apply smooth shading
    for face in bm.faces:
        face.smooth = True
    
    # Create UV map (crucial for texture!)
    # Map circle to 0-1 UV space with center at (0.5, 0.5)
    bm.faces.ensure_lookup_table()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    
    # UV map for top face
    for face_idx, face in enumerate(bm.faces):
        if face_idx < segments:  # Top faces
            for loop in face.loops:
                vert = loop.vert
                if vert == center_top:
                    # Center maps to (0.5, 0.5)
                    loop[uv_layer].uv = (0.5, 0.5)
                else:
                    # Map circle edge to UV circle
                    # Normalize position to -1 to 1 range
                    x_norm = vert.co.x / radius
                    y_norm = vert.co.y / radius
                    # Map to 0-1 range (center at 0.5)
                    u = x_norm * 0.5 + 0.5
                    v = y_norm * 0.5 + 0.5
                    loop[uv_layer].uv = (u, v)
        elif face_idx < segments * 2:  # Bottom faces (same UV mapping)
            for loop in face.loops:
                vert = loop.vert
                if vert == center_bottom:
                    loop[uv_layer].uv = (0.5, 0.5)
                else:
                    x_norm = vert.co.x / radius
                    y_norm = vert.co.y / radius
                    u = x_norm * 0.5 + 0.5
                    v = y_norm * 0.5 + 0.5
                    loop[uv_layer].uv = (u, v)
        # Edge faces don't need UV mapping (they're not visible)
    
    # Convert to mesh
    bm.to_mesh(mesh)
    bm.free()
    
    return mesh

def create_rug_material(config):
    """Create the rug material (placeholder - will be overridden by texture)."""
    mat = bpy.data.materials.new(name=config['material_name'])
    mat.use_nodes = True
    
    # Get shader node
    nodes = mat.node_tree.nodes
    nodes.clear()
    
    # Create Principled BSDF
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = config['base_color']
    bsdf.inputs['Roughness'].default_value = config['roughness']
    bsdf.inputs['Metallic'].default_value = 0.0
    
    # Output
    output = nodes.new(type='ShaderNodeOutputMaterial')
    output.location = (200, 0)
    
    # Connect
    mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    
    return mat

def generate_rug(config=RUG_CONFIG, output_path=None):
    """
    Generate a rug asset.
    
    Args:
        config: Configuration dictionary
        output_path: Optional path to save .blend file
    
    Returns:
        The created rug object
    """
    print(f"\n=== GENERATING RUG ===")
    print(f"  Shape: {config['shape']}")
    print(f"  Radius: {config['radius']}m")
    print(f"  Segments: {config['segments']}")
    print(f"  Thickness: {config['thickness']}m")
    
    # Clear scene
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    
    # Create mesh
    mesh = create_rug_geometry(config)
    
    # Create object
    rug = bpy.data.objects.new("Rug", mesh)
    bpy.context.collection.objects.link(rug)
    
    # Create and assign material
    mat = create_rug_material(config)
    rug.data.materials.append(mat)
    
    # Set origin to center bottom
    rug.location = (0, 0, 0)
    
    # Stats
    poly_count = len(rug.data.polygons)
    print(f"  ✓ Created rug: {poly_count} polygons")
    
    # Save if path provided
    if output_path:
        bpy.ops.wm.save_as_mainfile(filepath=output_path)
        print(f"  ✓ Saved: {output_path}")
    
    return rug

def main():
    """Main function for standalone execution."""
    # Determine output path
    script_dir = Path(__file__).parent.parent.parent  # Go up to project root
    output_path = str(script_dir / "assets" / "models" / "library" / "Rug.blend")
    
    # Generate rug
    generate_rug(RUG_CONFIG, output_path)
    
    print(f"\n✅ Rug generation complete\n")

if __name__ == "__main__":
    main()

