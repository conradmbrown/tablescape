using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    // Revision 274 LocType.getModel hillskew: SW, SE, NE, NW in cache units.
    // Deform after model reflection/rotation/scaling, keeping vertical posts upright.
    void ContourScenery(GameObject root,Actor actor){
        var h=actor.hillHeights;if(h==null||h.Length!=4)return;
        if(h[0]==h[1]&&h[0]==h[2]&&h[0]==h[3])return;
        int average=(h[0]+h[1]+h[2]+h[3])/4;
        foreach(var filter in root.GetComponentsInChildren<MeshFilter>()){
            var owner=filter.GetComponent<LostCityOwnedMesh>()??filter.gameObject.AddComponent<LostCityOwnedMesh>();
            if(!owner.mesh)owner.mesh=Instantiate(filter.sharedMesh);
            var mesh=owner.mesh;var vertices=mesh.vertices;
            for(int i=0;i<vertices.Length;i++){
                var offset=filter.transform.TransformPoint(vertices[i])-root.transform.position;
                // Shape 11's extra scene rotation occurs after cache model contouring.
                if(actor.shape==11)offset=Quaternion.Euler(0,-45,0)*offset;
                int x=Mathf.RoundToInt((offset.x+actor.offsetX)*128),z=Mathf.RoundToInt((offset.z+actor.offsetZ)*128);
                int south=h[0]+(h[1]-h[0])*(x+64)/128;
                int north=h[3]+(h[2]-h[3])*(x+64)/128;
                int height=south+(north-south)*(z+64)/128;
                vertices[i]+=filter.transform.InverseTransformVector(Vector3.up*((average-height)/128f));
            }
            mesh.vertices=vertices;mesh.RecalculateNormals();mesh.RecalculateBounds();filter.sharedMesh=mesh;
            var collider=filter.GetComponent<MeshCollider>();if(collider){collider.sharedMesh=null;collider.sharedMesh=mesh;}
        }
    }
}
}
