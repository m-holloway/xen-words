"""
Procedural Pot Generator

Creates a tapered pot with configurable parameters.
This script can be run standalone or imported.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python generate_pot.py
"""

import bpy
import bmesh
import math
from pathlib import Path

# ============================================================================
# PARAMETERS - Adjust these to change the pot
# ============================================================================

POT_CONFIG = {
    # Dimensions
    'bottom_radius': 0.18,      # Radius at pot bottom (meters)
    'top_radius': 0.24,         # Radius at pot top/rim (meters)
    'height': 0.35,             # Total pot height (meters)
    'wall_thickness': 0.02,     # Wall thickness (meters)
    
    # Detail
    'segments': 16,             # Number of segments around circumference
    
    # Features
    'drainage_hole': True,      # Include drainage hole in bottom
    'drainage_radius': 0.015,   # Radius of drainage hole (meters)
    
    # Material
    'material_name': 'ConcretePotMaterial',
    'base_color': (0.6, 0.6, 0.6, 1.0),  # Light gray
    'roughness': 0.8,
}

# ============================================================================
# GENERATOR FUNCTIONS
# ============================================================================

def create_pot_geometry(config):
    """Create the pot mesh geometry using simple extrusion."""
    mesh = bpy.data.meshes.new("PotMesh")
    bm = bmesh.new()
    
    bottom_r = config['bottom_radius']
    top_r = config['top_radius']
    height = config['height']
    thickness = config['wall_thickness']
    segments = config['segments']
    
    # Create outer rim vertices (top)
    outer_top_ring = []
    for i in range(segments):
        angle = (2 * math.pi * i) / segments
        x = top_r * math.cos(angle)
        y = top_r * math.sin(angle)
        vert = bm.verts.new((x, y, height))
        outer_top_ring.append(vert)
    
    # Create outer bottom vertices
    outer_bottom_ring = []
    for i in range(segments):
        angle = (2 * math.pi * i) / segments
        x = bottom_r * math.cos(angle)
        y = bottom_r * math.sin(angle)
        vert = bm.verts.new((x, y, 0))
        outer_bottom_ring.append(vert)
    
    # Create inner rim vertices (top)
    inner_top_ring = []
    for i in range(segments):
        angle = (2 * math.pi * i) / segments
        x = (top_r - thickness) * math.cos(angle)
        y = (top_r - thickness) * math.sin(angle)
        vert = bm.verts.new((x, y, height))
        inner_top_ring.append(vert)
    
    # Create inner bottom vertices
    inner_bottom_ring = []
    for i in range(segments):
        angle = (2 * math.pi * i) / segments
        x = (bottom_r - thickness) * math.cos(angle)
        y = (bottom_r - thickness) * math.sin(angle)
        vert = bm.verts.new((x, y, thickness * 0.5))
        inner_bottom_ring.append(vert)
    
    # Create outer wall faces
    for i in range(segments):
        v1 = outer_bottom_ring[i]
        v2 = outer_bottom_ring[(i + 1) % segments]
        v3 = outer_top_ring[(i + 1) % segments]
        v4 = outer_top_ring[i]
        bm.faces.new([v1, v2, v3, v4])
    
    # Create inner wall faces (reversed winding)
    for i in range(segments):
        v1 = inner_bottom_ring[i]
        v2 = inner_top_ring[i]
        v3 = inner_top_ring[(i + 1) % segments]
        v4 = inner_bottom_ring[(i + 1) % segments]
        bm.faces.new([v1, v2, v3, v4])
    
    # Create rim top faces (connecting outer and inner)
    for i in range(segments):
        v1 = outer_top_ring[i]
        v2 = outer_top_ring[(i + 1) % segments]
        v3 = inner_top_ring[(i + 1) % segments]
        v4 = inner_top_ring[i]
        bm.faces.new([v1, v2, v3, v4])
    
    # Create bottom
    if config['drainage_hole']:
        # Create drainage hole ring
        hole_r = config['drainage_radius']
        hole_verts = []
        hole_segments = 8
        for i in range(hole_segments):
            angle = (2 * math.pi * i) / hole_segments
            x = hole_r * math.cos(angle)
            y = hole_r * math.sin(angle)
            vert = bm.verts.new((x, y, 0))
            hole_verts.append(vert)
        
        # Create bottom face as triangles from outer bottom to hole
        # This is a simple approach - connect hole to outer bottom
        for i in range(segments):
            # Outer segment
            v1 = outer_bottom_ring[i]
            v2 = outer_bottom_ring[(i + 1) % segments]
            
            # Find corresponding inner vertex
            v3 = inner_bottom_ring[(i + 1) % segments]
            v4 = inner_bottom_ring[i]
            
            bm.faces.new([v1, v2, v3, v4])
        
        # Connect inner bottom to hole
        for i in range(segments):
            hole_i = int((i / segments) * hole_segments) % hole_segments
            hole_next = (hole_i + 1) % hole_segments
            
            v1 = inner_bottom_ring[i]
            v2 = inner_bottom_ring[(i + 1) % segments]
            v3 = hole_verts[hole_next]
            v4 = hole_verts[hole_i]
            
            try:
                bm.faces.new([v1, v2, v3, v4])
            except:
                # If quad fails, try triangles
                try:
                    bm.faces.new([v1, v2, v3])
                    bm.faces.new([v1, v3, v4])
                except:
                    pass
    else:
        # Solid bottom - connect outer bottom to inner bottom
        for i in range(segments):
            v1 = outer_bottom_ring[i]
            v2 = outer_bottom_ring[(i + 1) % segments]
            v3 = inner_bottom_ring[(i + 1) % segments]
            v4 = inner_bottom_ring[i]
            bm.faces.new([v1, v2, v3, v4])
        
        # Fill inner bottom with center vertex
        center = bm.verts.new((0, 0, 0))
        for i in range(segments):
            v1 = inner_bottom_ring[i]
            v2 = inner_bottom_ring[(i + 1) % segments]
            bm.faces.new([center, v1, v2])
    
    # Apply smooth shading
    for face in bm.faces:
        face.smooth = True
    
    # Convert to mesh
    bm.to_mesh(mesh)
    bm.free()
    
    return mesh

def create_pot_material(config):
    """Create the pot material."""
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

def generate_pot(config=POT_CONFIG, output_path=None):
    """
    Generate a pot asset.
    
    Args:
        config: Configuration dictionary
        output_path: Optional path to save .blend file
    
    Returns:
        The created pot object
    """
    print(f"\n=== GENERATING POT ===")
    print(f"  Bottom radius: {config['bottom_radius']}m")
    print(f"  Top radius: {config['top_radius']}m")
    print(f"  Height: {config['height']}m")
    print(f"  Segments: {config['segments']}")
    
    # Clear scene
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    
    # Create mesh
    mesh = create_pot_geometry(config)
    
    # Create object
    pot = bpy.data.objects.new("Pot", mesh)
    bpy.context.collection.objects.link(pot)
    
    # Create and assign material
    mat = create_pot_material(config)
    pot.data.materials.append(mat)
    
    # Set origin to bottom center
    pot.location = (0, 0, 0)
    
    # Stats
    poly_count = len(pot.data.polygons)
    print(f"  ✓ Created pot: {poly_count} polygons")
    
    # Save if path provided
    if output_path:
        bpy.ops.wm.save_as_mainfile(filepath=output_path)
        print(f"  ✓ Saved: {output_path}")
    
    return pot

def main():
    """Main function for standalone execution."""
    # Determine output path
    script_dir = Path(__file__).parent.parent.parent  # Go up to project root
    output_path = str(script_dir / "assets" / "models" / "library" / "Pot.blend")
    
    # Generate pot
    generate_pot(POT_CONFIG, output_path)
    
    print(f"\n✅ Pot generation complete\n")

if __name__ == "__main__":
    main()
