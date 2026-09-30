using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Networking;

// Attach to a tabletop root in Unity 6. Uses metres; 16 tiles occupy 0.8 m.
// Unity source only: not yet compiled or tested on a headset.
public class ScapeSceneClient : MonoBehaviour
{
    public string endpoint = "http://127.0.0.1:8768/v1/scene";
    public float metresPerTile = 0.05f;
    public Material surfaceMaterial; // Standard or URP Lit, mapped by PolySpatial.
    public string status = "Disconnected";
    [Serializable] public class Frame { public int schema; public string source, session; public long sequence; public MeshData[] meshes; }
    [Serializable] public class MeshData { public string id; public float[] vertices, color; public int[] triangles; }
    GameObject current;
    string session;
    long sequence = -1;
    readonly List<Mesh> ownedMeshes = new List<Mesh>();
    IEnumerator Start()
    {
        if (surfaceMaterial == null) { status="Assign a Standard or URP Lit material"; yield break; }
        while (enabled)
        {
            using (var req = UnityWebRequest.Get(endpoint))
            {
                req.timeout=5;
                yield return req.SendWebRequest();
                if(req.result != UnityWebRequest.Result.Success) status="Disconnected: retaining last scene";
                else if(req.downloadHandler.data.Length > 16000000) status="Rejected oversized scene";
                else { try { Apply(JsonUtility.FromJson<Frame>(req.downloadHandler.text)); } catch(Exception e) { status="Rejected scene: "+e.Message; } }
            }
            yield return new WaitForSeconds(1);
        }
    }
    static bool Finite(float x) { return !float.IsNaN(x) && !float.IsInfinity(x); }
    void Apply(Frame f)
    {
        if(f==null || f.schema!=1 || string.IsNullOrEmpty(f.session) || string.IsNullOrEmpty(f.source) || f.sequence<0 || f.meshes==null || f.meshes.Length<1 || f.meshes.Length>4096) throw new Exception("invalid envelope");
        if(f.session==session && f.sequence<=sequence) { status=f.source+" | frame "+sequence+" (unchanged)"; return; }
        int count=0;
        foreach(var d in f.meshes) {
            if(d==null || d.vertices==null || d.vertices.Length<9 || d.vertices.Length%3!=0 || d.triangles==null || d.triangles.Length<3 || d.triangles.Length%3!=0 || d.color==null || d.color.Length!=3) throw new Exception("invalid mesh");
            count+=d.vertices.Length;if(count>1500000)throw new Exception("vertex budget");
            foreach(float v in d.vertices)if(!Finite(v)||Mathf.Abs(v)>512)throw new Exception("invalid coordinate");
            foreach(int i in d.triangles)if(i<0||i>=d.vertices.Length/3)throw new Exception("invalid index");
            foreach(float c in d.color)if(!Finite(c)||c<0||c>1)throw new Exception("invalid color");
        }
        var next=new GameObject("Scape scene");next.transform.SetParent(transform,false);next.SetActive(false);
        var pending=new List<Mesh>();
        try {
            foreach(var d in f.meshes) {
                var v=new Vector3[d.vertices.Length/3];for(int i=0;i<v.Length;i++)v[i]=new Vector3(d.vertices[i*3],d.vertices[i*3+2],d.vertices[i*3+1])*metresPerTile;
                var indices=(int[])d.triangles.Clone();for(int i=0;i<indices.Length;i+=3){int t=indices[i+1];indices[i+1]=indices[i+2];indices[i+2]=t;}
                var mesh=new Mesh();pending.Add(mesh);mesh.indexFormat=UnityEngine.Rendering.IndexFormat.UInt32;mesh.vertices=v;mesh.triangles=indices;mesh.RecalculateNormals();mesh.RecalculateBounds();
                var go=new GameObject(d.id??"mesh");go.transform.SetParent(next.transform,false);go.AddComponent<MeshFilter>().sharedMesh=mesh;var renderer=go.AddComponent<MeshRenderer>();renderer.sharedMaterial=surfaceMaterial;
                var props=new MaterialPropertyBlock();var color=new Color(d.color[0],d.color[1],d.color[2]);props.SetColor("_BaseColor",color);props.SetColor("_Color",color);renderer.SetPropertyBlock(props);
            }
        } catch {Destroy(next);foreach(var m in pending)Destroy(m);throw;}
        if(current)Destroy(current);foreach(var m in ownedMeshes)Destroy(m);ownedMeshes.Clear();ownedMeshes.AddRange(pending);current=next;next.SetActive(true);session=f.session;sequence=f.sequence;status=f.source+" | frame "+sequence;
    }
    void OnDestroy(){if(current)Destroy(current);foreach(var m in ownedMeshes)Destroy(m);}
}
