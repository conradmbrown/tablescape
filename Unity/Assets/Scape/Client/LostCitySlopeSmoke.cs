using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    bool slopeTestFocus;
    IEnumerator SlopeSmoke(){
        foreach(string arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-capture="))captureBase=arg.Substring(16);
        username="unitysl"+Guid.NewGuid().ToString("N").Substring(0,4);StartCoroutine(Join());
        yield return AwaitState(()=>state!=null,30,"slope_login");
        if(smokeFailed){Application.Quit(1);yield break;}
        yield return AwaitState(()=>chunks.Count>=49&&!terrainBusy,120,"slope_world_loaded");
        if(smokeFailed){Application.Quit(1);yield break;}
        // Original cache types: fencing, gardenfencing, railing and fence terminators.
        int slopes=0,fences=0,verticesChecked=0,unchanged=0;float maxError=0,maxDisplacement=0,bestSlope=0;GameObject chosen=null;
        foreach(var entry in entities){
            var root=entry.Value;var pick=root.GetComponent<LostCityPick>();if(pick.kind!="loc")continue;
            var a=pick.actor;var h=a.hillHeights;bool sloped=h!=null&&h.Length==4&&(h[0]!=h[1]||h[0]!=h[2]||h[0]!=h[3]);
            if(sloped){slopes++;if(Array.IndexOf(new[]{980,981,997,1007,1008},a.id)>=0){fences++;float rise=Mathf.Max(h)-Mathf.Min(h);if(a.id==980&&rise>bestSlope){bestSlope=rise;chosen=root;}}}else unchanged++;
            foreach(var filter in root.GetComponentsInChildren<MeshFilter>()){
                int id=int.Parse(filter.name.Substring(6));var source=models[id].GetComponent<MeshFilter>().sharedMesh;var original=source.vertices;var actual=filter.sharedMesh.vertices;
                var part=Array.Find(a.parts??Array.Empty<Part>(),p=>Array.IndexOf(p.models,id)>=0&&Mathf.Abs(Mathf.DeltaAngle(p.yaw,filter.transform.localEulerAngles.y))<.1f);bool mirror=part!=null&&part.mirror;
                if(original.Length!=actual.Length){maxError=999;continue;}
                if(sloped&&filter.GetComponent<MeshCollider>().sharedMesh!=filter.sharedMesh)maxError=999;
                for(int i=0;i<original.Length;i++){
                    var local=original[i];if(mirror)local.z=-local.z;
                    var before=filter.transform.TransformPoint(local);var after=filter.transform.TransformPoint(actual[i]);float delta=0;
                    if(sloped){
                        var offset=before-root.transform.position;if(a.shape==11)offset=Quaternion.Euler(0,-45,0)*offset;
                        // Independent floating-point bilinear reference; cache truncates intermediate units.
                        double u=offset.x+a.offsetX+.5,v=offset.z+a.offsetZ+.5;
                        double height=(h[0]*(1-u)+h[1]*u)*(1-v)+(h[3]*(1-u)+h[2]*u)*v;
                        delta=(float)(((h[0]+h[1]+h[2]+h[3])/4.0-height)/128.0);
                    }
                    maxError=Mathf.Max(maxError,Vector3.Distance(after,before+Vector3.up*delta));maxDisplacement=Mathf.Max(maxDisplacement,Mathf.Abs(after.y-before.y));verticesChecked++;
                }
            }
        }
        bool passed=slopes>0&&fences>0&&unchanged>0&&maxDisplacement>.02f&&maxError<.025f;
        Debug.Log($"SCAPE_SLOPE_{(passed?"PASSED":"FAILED")} slopedObjects={slopes} slopedFences={fences} unchangedObjects={unchanged} vertices={verticesChecked} maxReferenceError={maxError:F6} maxDisplacement={maxDisplacement:F4}");
        if(chosen){
            var a=chosen.GetComponent<LostCityPick>().actor;Debug.Log($"SCAPE_SLOPE_FENCE id={a.id} x={a.x} z={a.z} angle={a.angle} heights={string.Join(",",a.hillHeights)}");
            slopeTestFocus=true;view.transform.position=chosen.transform.position+new Vector3(5,5,-7);view.transform.LookAt(chosen.transform.position+Vector3.up*.6f);
            yield return CapturePlay("-after");
            var saved=new Dictionary<Mesh,Vector3[]>();
            foreach(var filter in chosen.GetComponentsInChildren<MeshFilter>()){
                var aPart=Array.Find(a.parts??Array.Empty<Part>(),p=>Array.IndexOf(p.models,int.Parse(filter.name.Substring(6)))>=0);
                var source=models[int.Parse(filter.name.Substring(6))].GetComponent<MeshFilter>().sharedMesh.vertices;
                if(aPart!=null&&aPart.mirror)for(int i=0;i<source.Length;i++)source[i].z=-source[i].z;
                saved[filter.sharedMesh]=filter.sharedMesh.vertices;filter.sharedMesh.vertices=source;filter.sharedMesh.RecalculateBounds();
            }
            yield return CapturePlay("-before");foreach(var pair in saved){pair.Key.vertices=pair.Value;pair.Key.RecalculateBounds();}
        }
        yield return Logout();Application.Quit(passed?0:1);
    }
}
}
