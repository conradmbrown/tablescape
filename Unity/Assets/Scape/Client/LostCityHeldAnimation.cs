using System;
using System.Collections.Generic;
using UnityEngine;
namespace Scape.Client {
public sealed class LostCityAnimationPart:MonoBehaviour {public int slot=-1;}
public sealed partial class LostCityClient {
    public List<GameObject> CreateAnimationHeld(Transform parent,Part part,int slot,Actor actor){
        var result=new List<GameObject>();if(part==null)return result;
        // Original player assembly recolours the combined body and held models.
        var source=new List<int>(part.recolS??Array.Empty<int>());var destination=new List<int>(part.recolD??Array.Empty<int>());
        var body=actor.parts!=null&&actor.parts.Length>0?actor.parts[0]:null;
        if(body?.recolS!=null&&body.recolS.Length>=5)for(int i=body.recolS.Length-5;i<body.recolS.Length;i++){source.Add(body.recolS[i]);destination.Add(body.recolD[i]);}
        var colour=new Part{recolS=source.ToArray(),recolD=destination.ToArray()};
        foreach(int id in part.models??Array.Empty<int>()){
            if(!models.TryGetValue(id,out var prefab)){Debug.LogError("Missing original held animation model "+id);continue;}
            var child=Instantiate(prefab,parent);child.name="animation-held-"+slot+"-model-"+id;child.layer=parent.gameObject.layer==10?10:9;
            child.transform.localPosition=new Vector3(0,-part.offsetY,0);child.AddComponent<LostCityAnimationPart>().slot=slot;
            Recolour(child,colour,id);result.Add(child);
        }
        return result;
    }
}
}
