using System.Collections.Generic;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    static void ProjectMeshes(GameObject root,Vector3 origin,Vector3 normal,out float min,out float max){
        min=float.PositiveInfinity;max=float.NegativeInfinity;
        foreach(var filter in root.GetComponentsInChildren<MeshFilter>())foreach(var vertex in filter.sharedMesh.vertices){
            float d=Vector3.Dot(filter.transform.TransformPoint(vertex)-origin,normal);min=Mathf.Min(min,d);max=Mathf.Max(max,d);
        }
    }
    void AttachDiagonalDecor(Chunk chunk){
        var walls=new Dictionary<Vector2Int,GameObject>();
        foreach(var key in chunk.keys)if(entities.TryGetValue(key,out var root)){
            var a=root.GetComponent<LostCityPick>().actor;if(a.shape==9)walls[new Vector2Int((int)a.x,(int)a.z)]=root;
        }
        foreach(var key in chunk.keys)if(entities.TryGetValue(key,out var root)){
            var a=root.GetComponent<LostCityPick>().actor;if(a.shape<6||a.shape>8||!walls.TryGetValue(new Vector2Int((int)a.x,(int)a.z),out var wall))continue;
            foreach(Transform face in root.transform){
                var normal=face.TransformDirection(Vector3.right).normalized;var origin=root.transform.position;
                ProjectMeshes(wall,origin,normal,out _,out float wallSurface);
                ProjectMeshes(face.gameObject,origin,normal,out float backing,out _);
                // The software scene renderer drew these decorations over the wall even
                // when recessed inside its mesh. Seat their backing on the actual wall
                // surface for Unity's depth buffer, retaining the original carved relief.
                if(!float.IsInfinity(wallSurface)&&!float.IsInfinity(backing))face.position+=normal*(wallSurface-backing+.001f);
            }
        }
    }
}
}
