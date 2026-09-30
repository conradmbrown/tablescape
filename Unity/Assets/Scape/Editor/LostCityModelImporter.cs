using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEditor.AssetImporters;
using UnityEngine;
using Scape.Assets;

[ScriptedImporter(4, "ob2")]
public sealed class LostCityModelImporter : ScriptedImporter
{
    static string[] GatherDependenciesFromSourceFile(string path)
    {
        var dependencies = new HashSet<string> { "Assets/Scape/Shaders/CacheSurface.shader" };
        var model = LostCityModel.Decode(File.ReadAllBytes(path));
        for (int i = 0; i < model.colour.Length; i++)
            if ((model.renderType[i] & 2) != 0)
                dependencies.Add("Assets/LostCity274/textures/" + model.colour[i] + ".png");
        var result = new string[dependencies.Count]; dependencies.CopyTo(result); return result;
    }
    public override void OnImportAsset(AssetImportContext ctx)
    {
        var source = LostCityModel.Decode(File.ReadAllBytes(ctx.assetPath));
        int count = source.a.Length * 3;
        var vertices = new Vector3[count]; var colours = new Color[count]; var uv = new Vector2[count]; var labels = new Vector2[count];
        var groups = new SortedDictionary<int, List<int>>();
        for (int f = 0; f < source.a.Length; f++) {
            bool textured = (source.renderType[f] & 2) != 0;
            int texture = textured ? source.colour[f] : -1;
            if (!groups.TryGetValue(texture, out var indices)) { indices = new List<int>(); groups.Add(texture, indices); }
            Color colour = textured ? Color.white : LostCityModel.PaletteColour(source.colour[f]);
            colour.a = (255-source.alpha[f])/255f;
            int[] corners = { source.a[f], source.b[f], source.c[f] };
            for (int j = 0; j < 3; j++) {
                int index=f*3+j, original=corners[j]; vertices[index]=source.vertices[original]; colours[index]=colour; labels[index]=new Vector2((source.vertexLabel?[original]??-1)+1,(source.faceLabel?[f]??-1)+1);
                if (textured) uv[index]=source.TextureUv(f,original);
            }
            // y-down to y-up reflection reverses the original winding.
            indices.Add(f*3); indices.Add(f*3+2); indices.Add(f*3+1);
        }
        var mesh=new Mesh {name=Path.GetFileNameWithoutExtension(ctx.assetPath), indexFormat=UnityEngine.Rendering.IndexFormat.UInt32};
        mesh.vertices=vertices; mesh.colors=colours; mesh.uv=uv; mesh.uv2=labels; mesh.subMeshCount=groups.Count;
        var shader=AssetDatabase.LoadAssetAtPath<Shader>("Assets/Scape/Shaders/CacheSurface.shader");
        if (shader==null) throw new InvalidDataException("Missing Scape/CacheSurface shader");
        var materials=new List<Material>(); int sub=0;
        foreach (var group in groups) {
            mesh.SetTriangles(group.Value,sub++);
            var material=new Material(shader) {name="cache-texture-"+group.Key};
            if (group.Key>=0) {
                string path="Assets/LostCity274/textures/"+group.Key+".png";
                ctx.DependsOnSourceAsset(path);
                var texture=AssetDatabase.LoadAssetAtPath<Texture2D>(path);
                if (texture==null) throw new InvalidDataException("Missing original texture: "+path);
                material.mainTexture=texture;
            }
            ctx.AddObjectToAsset("material-"+group.Key,material); materials.Add(material);
        }
        mesh.RecalculateNormals(); mesh.RecalculateBounds(); ctx.AddObjectToAsset("mesh",mesh);
        var metadata=ScriptableObject.CreateInstance<LostCityModelAsset>();
        metadata.mesh=mesh; metadata.vertexLabels=source.vertexLabel; metadata.faceLabels=source.faceLabel;
        metadata.priorities=source.priority; metadata.faceColours=source.colour; metadata.renderTypes=source.renderType; metadata.faceAlpha=source.alpha;
        metadata.cornerVertices=new int[count];for(int f=0;f<source.a.Length;f++){metadata.cornerVertices[f*3]=source.a[f];metadata.cornerVertices[f*3+1]=source.b[f];metadata.cornerVertices[f*3+2]=source.c[f];}
        metadata.sourceVertexCount=source.vertices.Length; metadata.sourceFaceCount=source.a.Length;
        ctx.AddObjectToAsset("original-metadata",metadata);
        var root=new GameObject(mesh.name); root.AddComponent<MeshFilter>().sharedMesh=mesh; root.AddComponent<MeshRenderer>().sharedMaterials=materials.ToArray();
        ctx.AddObjectToAsset("model",root); ctx.SetMainObject(root);
    }
}
