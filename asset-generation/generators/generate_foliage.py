"""
Procedural Foliage Generator

Creates plant foliage with leaves and branches.
This script can be run standalone or imported.

Usage:
    blender --background --python generate_foliage.py
"""

import bpy
import bmesh
import math
import random
from pathlib import Path

# ============================================================================
# PARAMETERS - Adjust these to change the foliage
# ============================================================================

FOLIAGE_CONFIG = {
    # Overall structure
    'height': 0.70,             # Total plant height (meters)
    'spread': 0.35,             # Horizontal spread (meters)
    
    # Leaves
    'leaf_count': 58,           # Number of leaves
    'leaf_length': 0.08,        # Average leaf length (meters)
    'leaf_width': 0.035,        # Average leaf width (meters)
    'leaf_thickness': 0.002,    # Leaf thickness for volume (meters)
    'leaf_variation': 0.2,      # Size variation (0-1)
    
    # Branches
    'main_stems': 4,            # Number of main stems from base
    'branches_per_stem': 2,     # Secondary branches per stem
    'branch_thickness': 0.003,  # Branch radius (meters)
    'branch_segments': 4,       # Detail in branches
    
    # Distribution
    'vertical_clustering': 0.7, # How much leaves cluster vertically (0-1)
    'random_seed': 42,          # For reproducible randomness
    
    # Materials
    'leaf_color': (0.15, 0.45, 0.12, 1.0),  # Rich green
    'leaf_roughness': 0.4,
    'leaf_specular': 0.3,
    'branch_color': (0.25, 0.18, 0.12, 1.0),  # Brown
    'branch_roughness': 0.9,
}

# ============================================================================
# GENERATOR FUNCTIONS
# ============================================================================

def create_leaf_geometry():
    """Create a single leaf mesh (organic teardrop shape with thickness)."""
    mesh = bpy.data.meshes.new("LeafMesh")
    bm = bmesh.new()
    
    # Create leaf profile (teardrop shape)
    # Two layers for thickness
    segments = 8
    
    for layer in [0, 1]:  # Bottom and top layer
        z_offset = -0.001 if layer == 0 else 0.001
        
        # Tip (pointed)
        tip = bm.verts.new((0, 1.0, z_offset))
        
        # Middle section (widest part)
        for i in range(segments):
            angle = (math.pi * i) / (segments - 1)  # Half circle
            x = math.sin(angle) * 0.5  # Width
            y = 0.5 - (0.5 * (i / (segments - 1)))  # Length
            # Teardrop taper
            width_factor = math.sin(angle) * (1.0 - (i / (segments - 1)) * 0.3)
            vert = bm.verts.new((x * width_factor, y, z_offset))
        
        # Base (rounded)
        base = bm.verts.new((0, 0, z_offset))
    
    # Create faces
    # (This is simplified - a real implementation would create proper faces)
    verts = list(bm.verts)
    
    # Top surface
    for i in range(len(verts) // 2 - 1):
        if i < len(verts) // 2 - 2:
            bm.faces.new([verts[i], verts[i + 1], verts[i + 1 + len(verts) // 2], verts[i + len(verts) // 2]])
    
    # Smooth shading
    for face in bm.faces:
        face.smooth = True
    
    bm.to_mesh(mesh)
    bm.free()
    
    return mesh

def create_branch_structure(config):
    """Create the branch structure."""
    mesh = bpy.data.meshes.new("BranchMesh")
    bm = bmesh.new()
    
    random.seed(config['random_seed'])
    
    height = config['height']
    stems = config['main_stems']
    branches_per = config['branches_per_stem']
    thickness = config['branch_thickness']
    
    # Create main stems radiating from center
    stem_endpoints = []
    for i in range(stems):
        angle = (2 * math.pi * i) / stems
        # Stem goes up and out
        end_x = math.cos(angle) * config['spread'] * 0.6
        end_y = math.sin(angle) * config['spread'] * 0.6
        end_z = height * 0.7
        stem_endpoints.append((end_x, end_y, end_z))
        
        # Create stem as simple cylinder
        # (Simplified - real implementation would create proper geometry)
        base = bm.verts.new((0, 0, 0))
        end = bm.verts.new((end_x, end_y, end_z))
        
        # Add secondary branches
        for j in range(branches_per):
            t = (j + 1) / (branches_per + 1)
            branch_base_x = end_x * t
            branch_base_y = end_y * t
            branch_base_z = end_z * t
            
            # Branch extends further out and up
            branch_angle = angle + (random.random() - 0.5) * 0.5
            branch_end_x = end_x + math.cos(branch_angle) * config['spread'] * 0.3
            branch_end_y = end_y + math.sin(branch_angle) * config['spread'] * 0.3
            branch_end_z = end_z + height * 0.2
            
            branch_base = bm.verts.new((branch_base_x, branch_base_y, branch_base_z))
            branch_end = bm.verts.new((branch_end_x, branch_end_y, branch_end_z))
            stem_endpoints.append((branch_end_x, branch_end_y, branch_end_z))
    
    bm.to_mesh(mesh)
    bm.free()
    
    return mesh, stem_endpoints

def create_materials(config):
    """Create leaf and branch materials."""
    # Leaf material
    leaf_mat = bpy.data.materials.new(name="LeafMaterial")
    leaf_mat.use_nodes = True
    nodes = leaf_mat.node_tree.nodes
    nodes.clear()
    
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = config['leaf_color']
    bsdf.inputs['Roughness'].default_value = config['leaf_roughness']
    bsdf.inputs['Specular IOR Level'].default_value = config['leaf_specular']
    
    output = nodes.new(type='ShaderNodeOutputMaterial')
    leaf_mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    
    # Branch material
    branch_mat = bpy.data.materials.new(name="BranchMaterial")
    branch_mat.use_nodes = True
    nodes = branch_mat.node_tree.nodes
    nodes.clear()
    
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = config['branch_color']
    bsdf.inputs['Roughness'].default_value = config['branch_roughness']
    
    output = nodes.new(type='ShaderNodeOutputMaterial')
    branch_mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    
    return leaf_mat, branch_mat

def generate_foliage(config=FOLIAGE_CONFIG, output_path=None):
    """
    Generate foliage asset.
    
    Args:
        config: Configuration dictionary
        output_path: Optional path to save .blend file
    
    Returns:
        The created foliage object
    """
    print(f"\n=== GENERATING FOLIAGE ===")
    print(f"  Height: {config['height']}m")
    print(f"  Leaf count: {config['leaf_count']}")
    print(f"  Main stems: {config['main_stems']}")
    
    # Clear scene
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    
    # Create materials
    leaf_mat, branch_mat = create_materials(config)
    
    # Create branch structure
    branch_mesh, attachment_points = create_branch_structure(config)
    branch_obj = bpy.data.objects.new("Branches", branch_mesh)
    bpy.context.collection.objects.link(branch_obj)
    branch_obj.data.materials.append(branch_mat)
    
    # Create leaf geometry (single mesh, instanced)
    leaf_base_mesh = create_leaf_geometry()
    
    # Create leaves attached to branches
    random.seed(config['random_seed'])
    leaves = []
    
    for i in range(config['leaf_count']):
        # Pick attachment point
        attach_point = random.choice(attachment_points)
        
        # Create leaf instance
        leaf_obj = bpy.data.objects.new(f"Leaf_{i}", leaf_base_mesh)
        bpy.context.collection.objects.link(leaf_obj)
        
        # Position
        offset_x = (random.random() - 0.5) * 0.05
        offset_y = (random.random() - 0.5) * 0.05
        offset_z = (random.random() - 0.5) * 0.05
        leaf_obj.location = (
            attach_point[0] + offset_x,
            attach_point[1] + offset_y,
            attach_point[2] + offset_z
        )
        
        # Rotation
        leaf_obj.rotation_euler = (
            random.random() * math.pi,
            random.random() * math.pi,
            random.random() * 2 * math.pi
        )
        
        # Scale variation
        scale_var = 1.0 + (random.random() - 0.5) * config['leaf_variation']
        base_scale = config['leaf_length']
        leaf_obj.scale = (
            base_scale * scale_var * config['leaf_width'] / config['leaf_length'],
            base_scale * scale_var,
            1.0
        )
        
        leaf_obj.data.materials.append(leaf_mat)
        leaves.append(leaf_obj)
    
    # Join all into single object
    bpy.context.view_layer.objects.active = branch_obj
    for leaf in leaves:
        leaf.select_set(True)
    branch_obj.select_set(True)
    
    bpy.ops.object.join()
    foliage = bpy.context.active_object
    foliage.name = "Foliage"
    foliage.location = (0, 0, 0)
    
    # Stats
    poly_count = len(foliage.data.polygons)
    print(f"  ✓ Created foliage: {poly_count} polygons")
    
    # Save if path provided
    if output_path:
        bpy.ops.wm.save_as_mainfile(filepath=output_path)
        print(f"  ✓ Saved: {output_path}")
    
    return foliage

def main():
    """Main function for standalone execution."""
    # Determine output path
    script_dir = Path(__file__).parent.parent.parent  # Go up to project root
    output_path = str(script_dir / "assets" / "models" / "library" / "Foliage.blend")
    
    # Generate foliage
    generate_foliage(FOLIAGE_CONFIG, output_path)
    
    print(f"\n✅ Foliage generation complete\n")

if __name__ == "__main__":
    main()

