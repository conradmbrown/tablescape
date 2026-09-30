using System;
using UnityEngine;
using Scape.Assets;
namespace Scape.Client {
public sealed partial class LostCityClient {
    // Revision 274 Model.calculateNormals/light/getColour. Preserve original vertex
    // sharing and flat-face flags: Unity's imported triangles have split vertices.
    void LightScenery(GameObject root,Actor actor){
        int childIndex=0;
        foreach(var part in actor.parts??new[]{new Part{models=actor.models,recolS=actor.recolS,recolD=actor.recolD}})
        foreach(int id in part.models??Array.Empty<int>()){
            if(!models.ContainsKey(id))continue;
            var filter=root.transform.GetChild(childIndex++).GetComponent<MeshFilter>();
            int index=Array.IndexOf(catalogue.ids,id);var data=catalogue.modelMetadata[index];
            bool coloured=false;foreach(int type in data.renderTypes)if((type&2)==0){coloured=true;break;}if(!coloured)continue;
            var owner=filter.GetComponent<LostCityOwnedMesh>()??filter.gameObject.AddComponent<LostCityOwnedMesh>();
            if(!owner.mesh)owner.mesh=Instantiate(filter.sharedMesh);
            var mesh=owner.mesh;var vertices=mesh.vertices;var colours=mesh.colors;
            var sums=new Vector3Int[data.sourceVertexCount];var counts=new int[sums.Length];var faces=new Vector3Int[data.sourceFaceCount];
            for(int f=0;f<faces.Length;f++){
                Vector3Int Point(int corner){var p=filter.transform.TransformVector(vertices[f*3+corner])*128;return new Vector3Int(Mathf.RoundToInt(p.x),-Mathf.RoundToInt(p.y),Mathf.RoundToInt(p.z));}
                var ab=Point(1)-Point(0);var ac=Point(2)-Point(0);
                int nx=ab.y*ac.z-ac.y*ab.z,ny=ab.z*ac.x-ac.z*ab.x,nz=ab.x*ac.y-ac.x*ab.y;
                if(part.mirror){nx=-nx;ny=-ny;nz=-nz;}
                while(Math.Abs(nx)>8192||Math.Abs(ny)>8192||Math.Abs(nz)>8192){nx>>=1;ny>>=1;nz>>=1;}
                int length=Math.Max(1,(int)Math.Sqrt((double)nx*nx+(double)ny*ny+(double)nz*nz));
                var normal=new Vector3Int(nx*256/length,ny*256/length,nz*256/length);faces[f]=normal;
                if((data.renderTypes[f]&1)==0)for(int j=0;j<3;j++){int v=data.cornerVertices[f*3+j];sums[v]+=normal;counts[v]++;}
            }
            int scale=Math.Max(1,actor.lightContrast*71>>8);
            for(int f=0;f<faces.Length;f++){
                // Textured surfaces retain their original texture sampling/materials.
                if((data.renderTypes[f]&2)!=0)continue;
                int hsl=data.faceColours[f];
                for(int k=0;k<Math.Min(part.recolS?.Length??0,part.recolD?.Length??0);k++)if(hsl==part.recolS[k])hsl=part.recolD[k];
                for(int j=0;j<3;j++){
                    int v=data.cornerVertices[f*3+j];bool flat=(data.renderTypes[f]&1)!=0;
                    var n=flat?faces[f]:sums[v];int divisor=flat?scale+scale/2:scale*Math.Max(1,counts[v]);
                    int light=actor.lightAmbient+(-50*n.x-10*n.y-50*n.z)/divisor;
                    int lit=(hsl&0xff80)+Mathf.Clamp((light*(hsl&127))>>7,2,126);
                    var colour=LostCityModel.PaletteColour(lit);colour.a=colours[f*3+j].a;colours[f*3+j]=colour;
                }
            }
            mesh.colors=colours;filter.sharedMesh=mesh;
            var collider=filter.GetComponent<MeshCollider>();if(collider)collider.sharedMesh=mesh;
        }
    }
}
}
