"""
Asset Analyzer

Analyzes 3D assets and reports statistics, issues, and optimization opportunities.

Usage:
    blender --background asset.blend --python asset_analyzer.py
    blender --background --python asset_analyzer.py -- library/PottedPlant.blend
"""

import bpy
import sys
from pathlib import Path

# ============================================================================
# ANALYSIS FUNCTIONS
# ============================================================================

def analyze_geometry(obj):
    """Analyze mesh geometry."""
    if obj.type != 'MESH' or not obj.data:
        return None
    
    mesh = obj.data
    
    return {
        'vertices': len(mesh.vertices),
        'edges': len(mesh.edges),
        'faces': len(mesh.polygons),
        'triangles': sum(1 for f in mesh.polygons if len(f.vertices) == 3),
        'quads': sum(1 for f in mesh.polygons if len(f.vertices) == 4),
        'ngons': sum(1 for f in mesh.polygons if len(f.vertices) > 4),
    }

def analyze_materials(obj):
    """Analyze materials."""
    if obj.type != 'MESH' or not obj.data:
        return []
    
    materials = []
    for mat in obj.data.materials:
        if mat:
            # Count faces using this material
            face_count = sum(1 for f in obj.data.polygons if f.material_index == obj.data.materials.find(mat.name))
            
            materials.append({
                'name': mat.name,
                'faces': face_count,
                'nodes': len(mat.node_tree.nodes) if mat.use_nodes else 0,
            })
    
    return materials

def calculate_bounds(obj):
    """Calculate bounding box."""
    if obj.type != 'MESH' or not obj.data:
        return None
    
    bbox = [obj.matrix_world @ v.co for v in obj.data.vertices]
    
    if not bbox:
        return None
    
    min_x = min(v.x for v in bbox)
    max_x = max(v.x for v in bbox)
    min_y = min(v.y for v in bbox)
    max_y = max(v.y for v in bbox)
    min_z = min(v.z for v in bbox)
    max_z = max(v.z for v in bbox)
    
    return {
        'min': (min_x, min_y, min_z),
        'max': (max_x, max_y, max_z),
        'size': (max_x - min_x, max_y - min_y, max_z - min_z),
        'center': ((min_x + max_x) / 2, (min_y + max_y) / 2, (min_z + max_z) / 2),
    }

def check_issues(obj):
    """Check for common issues."""
    issues = []
    
    if obj.type != 'MESH' or not obj.data:
        return issues
    
    mesh = obj.data
    
    # Check for non-manifold edges
    non_manifold = sum(1 for e in mesh.edges if not e.is_manifold)
    if non_manifold > 0:
        issues.append(f"⚠ {non_manifold} non-manifold edges")
    
    # Check for loose vertices
    loose_verts = sum(1 for v in mesh.vertices if len(v.link_edges) == 0)
    if loose_verts > 0:
        issues.append(f"⚠ {loose_verts} loose vertices")
    
    # Check for unapplied transforms
    if obj.scale != (1.0, 1.0, 1.0):
        issues.append(f"⚠ Unapplied scale: {obj.scale}")
    
    if obj.rotation_euler != (0.0, 0.0, 0.0):
        issues.append(f"⚠ Unapplied rotation: {obj.rotation_euler}")
    
    # Check material count
    if len(mesh.materials) > 4:
        issues.append(f"⚠ Many materials ({len(mesh.materials)}) - consider consolidation")
    
    # Check poly count for mobile
    poly_count = len(mesh.polygons)
    if poly_count > 5000:
        issues.append(f"⚠ High poly count ({poly_count}) for mobile")
    elif poly_count > 2000:
        issues.append(f"ℹ Moderate poly count ({poly_count}) - monitor performance")
    
    return issues

def analyze_file(filepath):
    """Analyze a .blend file."""
    print(f"\n{'='*70}")
    print(f"  ASSET ANALYSIS: {Path(filepath).name}")
    print(f"{'='*70}\n")
    
    # Load file
    try:
        bpy.ops.wm.open_mainfile(filepath=filepath)
    except Exception as e:
        print(f"✗ Failed to load file: {e}")
        return
    
    # Analyze each mesh object
    mesh_objects = [obj for obj in bpy.data.objects if obj.type == 'MESH']
    
    if not mesh_objects:
        print("✗ No mesh objects found\n")
        return
    
    print(f"Found {len(mesh_objects)} mesh object(s)\n")
    
    total_polys = 0
    total_materials = set()
    
    for obj in mesh_objects:
        print(f"─── {obj.name} ───")
        
        # Geometry
        geom = analyze_geometry(obj)
        if geom:
            print(f"  Geometry:")
            print(f"    Vertices: {geom['vertices']}")
            print(f"    Faces: {geom['faces']} ({geom['triangles']} tris, {geom['quads']} quads, {geom['ngons']} ngons)")
            total_polys += geom['faces']
        
        # Materials
        materials = analyze_materials(obj)
        if materials:
            print(f"  Materials: {len(materials)}")
            for mat in materials:
                print(f"    - {mat['name']}: {mat['faces']} faces, {mat['nodes']} nodes")
                total_materials.add(mat['name'])
        
        # Bounds
        bounds = calculate_bounds(obj)
        if bounds:
            print(f"  Bounds:")
            print(f"    Size: {bounds['size'][0]:.3f} × {bounds['size'][1]:.3f} × {bounds['size'][2]:.3f} m")
            print(f"    Center: ({bounds['center'][0]:.3f}, {bounds['center'][1]:.3f}, {bounds['center'][2]:.3f})")
        
        # Issues
        issues = check_issues(obj)
        if issues:
            print(f"  Issues:")
            for issue in issues:
                print(f"    {issue}")
        else:
            print(f"  ✓ No issues detected")
        
        print()
    
    # Summary
    print(f"{'─'*70}")
    print(f"SUMMARY:")
    print(f"  Total objects: {len(mesh_objects)}")
    print(f"  Total polygons: {total_polys}")
    print(f"  Unique materials: {len(total_materials)}")
    
    # Mobile performance estimate
    if total_polys < 500:
        perf = "✓ Excellent for mobile"
    elif total_polys < 2000:
        perf = "✓ Good for mobile"
    elif total_polys < 5000:
        perf = "⚠ Moderate - test on target devices"
    else:
        perf = "✗ High - may cause performance issues"
    
    print(f"  Mobile performance: {perf}")
    print(f"{'='*70}\n")

def main():
    """Main function."""
    # Check for file argument
    if "--" in sys.argv:
        idx = sys.argv.index("--")
        if len(sys.argv) > idx + 1:
            filepath = sys.argv[idx + 1]
            
            # Make absolute if relative
            if not Path(filepath).is_absolute():
                script_dir = Path(__file__).parent.parent.parent
                filepath = str(script_dir / filepath)
            
            analyze_file(filepath)
            return
    
    # Analyze current file
    if bpy.data.filepath:
        analyze_file(bpy.data.filepath)
    else:
        print("No file specified. Usage:")
        print("  blender --background asset.blend --python asset_analyzer.py")
        print("  blender --background --python asset_analyzer.py -- library/PottedPlant.blend")

if __name__ == "__main__":
    main()

