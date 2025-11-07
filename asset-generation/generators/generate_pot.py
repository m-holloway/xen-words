"""
Procedural Pot Generator

Creates a tapered pot with configurable parameters.
This script can be run standalone or imported.

Usage:
    blender --background --python generate_pot.py
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
    'rim_height': 0.01,         # Height of rim lip (meters)
    'rim_flare': 0.04,          # How much rim flares out (meters)
    
    # Detail
    'segments': 16,             # Number of segments around circumference
    'height_segments': 3,       # Vertical subdivisions for shape
    
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
    """Create the pot mesh geometry."""
    mesh = bpy.data.meshes.new("PotMesh")
    bm = bmesh.new()
    
    # Calculate profile (vertical cross-section)
    bottom_r = config['bottom_radius']
    top_r = config['top_radius']
    rim_r = top_r + config['rim_flare']
    height = config['height']
    rim_height = config['rim_height']
    segments = config['segments']
    
    # Create vertical profile points
    profile_points = [
        (bottom_r, 0.0),                        # Bottom outer edge
        (top_r, height - rim_height),           # Body top
        (rim_r, height - rim_height * 0.5),     # Rim flare
        (rim_r, height),                        # Rim top outer
        (top_r - 0.01, height),                 # Rim top inner
        (top_r - 0.01, height - rim_height),    # Inside rim
        (bottom_r - 0.02, 0.02),                # Inside bottom
    ]
    
    # Create vertices by rotating profile around Z axis
    verts_by_ring = []
    for radius, z in profile_points:
        ring = []
        for i in range(segments):
            angle = (2 * math.pi * i) / segments
            x = radius * math.cos(angle)
            y = radius * math.sin(angle)
            vert = bm.verts.new((x, y, z))
            ring.append(vert)
        verts_by_ring.append(ring)
    
    # Create faces between rings
    for ring_idx in range(len(verts_by_ring) - 1):
        ring1 = verts_by_ring[ring_idx]
        ring2 = verts_by_ring[ring_idx + 1]
        
        for i in range(segments):
            v1 = ring1[i]
            v2 = ring1[(i + 1) % segments]
            v3 = ring2[(i + 1) % segments]
            v4 = ring2[i]
            bm.faces.new([v1, v2, v3, v4])
    
    # Create rim top face (horizontal)
    rim_outer_ring = verts_by_ring[3]
    rim_inner_ring = verts_by_ring[4]
    for i in range(segments):
        v1 = rim_outer_ring[i]
        v2 = rim_outer_ring[(i + 1) % segments]
        v3 = rim_inner_ring[(i + 1) % segments]
        v4 = rim_inner_ring[i]
        bm.faces.new([v1, v2, v3, v4])
    
    # Create bottom face
    bottom_ring = verts_by_ring[0]
    center = bm.verts.new((0, 0, 0))
    
    if config['drainage_hole']:
        # Create drainage hole
        hole_r = config['drainage_radius']
        hole_verts = []
        for i in range(8):  # 8 segments for hole
            angle = (2 * math.pi * i) / 8
            x = hole_r * math.cos(angle)
            y = hole_r * math.sin(angle)
            vert = bm.verts.new((x, y, 0))
            hole_verts.append(vert)
        
        # Bottom face as ring between hole and outer edge
        for i in range(8):
            # Triangles from hole to outer
            v1 = hole_verts[i]
            v2 = hole_verts[(i + 1) % 8]
            # Find closest outer vertices
            outer_i = int((i / 8) * segments)
            v3 = bottom_ring[outer_i]
            bm.faces.new([v1, v2, v3])
    else:
        # Solid bottom
        for i in range(segments):
            v1 = bottom_ring[i]
            v2 = bottom_ring[(i + 1) % segments]
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

