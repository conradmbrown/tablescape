using System;
using System.IO;
using UnityEditor;
using UnityEngine;

// Asset-import verification only. This is deliberately not called a gameplay test.
public static class ScapeAssetVerification
{
    public static void Run()
    {
        try {
            string folder="Assets/LostCity274/models";
            if (!Directory.Exists(folder)) throw new InvalidDataException("Prepare the original revision-274 assets first");
            int models=0, vertices=0, triangles=0;
            foreach (string path in Directory.GetFiles(folder,"*.ob2")) {
                var prefab=AssetDatabase.LoadAssetAtPath<GameObject>(path.Replace('\\','/'));
                if (!prefab) throw new InvalidDataException("Model import failed: "+path);
                var filter=prefab.GetComponent<MeshFilter>();
                var renderer=prefab.GetComponent<MeshRenderer>();
                if (!filter || !filter.sharedMesh || !renderer) throw new InvalidDataException("Model components missing: "+path);
                var mesh=filter.sharedMesh;
                if (mesh.subMeshCount!=renderer.sharedMaterials.Length) throw new InvalidDataException("Material/submesh mismatch: "+path);
                foreach (var material in renderer.sharedMaterials) {
                    if (!material || !material.shader || material.shader.name!="Scape/CacheSurface") throw new InvalidDataException("Missing material: "+path);
                    if (material.name!="cache-texture--1" && !material.mainTexture) throw new InvalidDataException("Missing original texture: "+path);
                }
                foreach (var v in mesh.vertices)
                    if (float.IsNaN(v.x)||float.IsInfinity(v.x)||float.IsNaN(v.y)||float.IsInfinity(v.y)||float.IsNaN(v.z)||float.IsInfinity(v.z)) throw new InvalidDataException("Nonfinite vertex: "+path);
                vertices+=mesh.vertexCount; triangles+=mesh.triangles.Length/3; models++;
            }
            if (models==0) throw new InvalidDataException("No original models imported");
            Debug.Log($"SCAPE_ASSET_IMPORT_PASSED revision=274 models={models} vertices={vertices} triangles={triangles}; gameplay NOT tested");
        }
        catch (Exception e) { Debug.LogException(e); EditorApplication.Exit(1); throw; }
    }
}
