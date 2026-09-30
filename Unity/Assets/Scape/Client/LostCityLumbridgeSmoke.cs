using System;
using System.Collections;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    int dialogueDraws;string captureBase;
    IEnumerator CapturePlay(string suffix){yield return new WaitForEndOfFrame();if(captureBase==null)yield break;var image=new Texture2D(Screen.width,Screen.height,TextureFormat.RGB24,false);image.ReadPixels(new Rect(0,0,Screen.width,Screen.height),0,0);image.Apply();System.IO.File.WriteAllBytes(captureBase+suffix+".png",image.EncodeToPNG());Destroy(image);}
    bool DoorTextureMatches(int id,int texture){
        foreach(var pair in entities){
            var pick=pair.Value.GetComponent<LostCityPick>();if(!pick||pick.actor.id!=id||pick.kind!="loc")continue;
            var renderer=pair.Value.GetComponentInChildren<MeshRenderer>();if(!renderer)return false;
            bool found=false;foreach(var material in renderer.sharedMaterials)if(material.name=="cache-texture-"+texture&&material.mainTexture==catalogue.textures[texture])found=true;
            // Recolouring one instance must not change the shared wall/door slab prefab.
            foreach(var material in models[634].GetComponent<MeshRenderer>().sharedMaterials)if(material.name=="cache-texture-2"&&material.mainTexture!=catalogue.textures[2])return false;
            return found;
        }
        return false;
    }
    bool StatueHasOriginalShading(){
        int found=0;
        foreach(var pair in entities){
            var pick=pair.Value.GetComponent<LostCityPick>();if(!pick||pick.actor.id!=563||pick.kind!="loc")continue;
            var mesh=pair.Value.GetComponentInChildren<MeshFilter>().sharedMesh;float low=1,high=0;
            var colours=mesh.colors;var source=catalogue.modelMetadata[Array.IndexOf(catalogue.ids,1527)];
            for(int i=0;i<colours.Length;i++){var c=colours[i];if(source.faceColours[i/3]!=61)continue;low=Mathf.Min(low,c.grayscale);high=Mathf.Max(high,c.grayscale);if(c.a<.99f)return false;}
            if(high-low<.2f)return false;found++;
        }
        return found>=2;
    }
    bool DiagonalSlitsPlaced(){
        int count=0;
        foreach(var pair in entities){var pick=pair.Value.GetComponent<LostCityPick>();if(!pick||pick.actor.id!=1938||pick.actor.shape!=8)continue;
            if(pair.Value.transform.childCount!=2)return false;
            var a=pair.Value.transform.GetChild(0);var b=pair.Value.transform.GetChild(1);
            if(Mathf.Abs(Mathf.DeltaAngle(a.localEulerAngles.y,45))>.01f||Mathf.Abs(Mathf.DeltaAngle(b.localEulerAngles.y,225))>.01f)return false;
            if(a.localPosition.sqrMagnitude<.1f||b.localPosition.sqrMagnitude<.1f)return false;
            GameObject wall=null;foreach(var candidate in entities.Values){var other=candidate.GetComponent<LostCityPick>().actor;if(other.shape==9&&other.x==pick.actor.x&&other.z==pick.actor.z){wall=candidate;break;}}
            if(!wall)return false;
            foreach(Transform face in pair.Value.transform){var normal=face.TransformDirection(Vector3.right).normalized;var origin=pair.Value.transform.position;
                ProjectMeshes(wall,origin,normal,out _,out float surface);ProjectMeshes(face.gameObject,origin,normal,out float backing,out _);
                if(Mathf.Abs(backing-surface)>.003f)return false;
            }
            count++;
        }
        return count>=2;
    }
    IEnumerator LumbridgeSmoke(){
        foreach(string arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-capture="))captureBase=arg.Substring(16);
        foreach(string arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-input-file="))inputFile=arg.Substring(19);
        username="unitylb"+Guid.NewGuid().ToString("N").Substring(0,4);StartCoroutine(Join());yield return AwaitState(()=>state!=null,45,"lumbridge_login");if(smokeFailed){Application.Quit(1);yield break;}
        yield return AwaitState(()=>state.level==0&&Mathf.Abs(state.player.x-3222)<2&&Mathf.Abs(state.player.z-3218)<2,10,"default_lumbridge_spawn");
        yield return AwaitState(()=>chunks.Count>=49&&!terrainBusy,100,"surrounding_chunks");
        yield return AwaitState(DiagonalSlitsPlaced,5,"diagonal_arrow_slits_have_both_rotated_wall_faces");
        yield return AwaitState(StatueHasOriginalShading,5,"both_lumbridge_statues_have_surface_shading");
        yield return AwaitState(()=>DoorTextureMatches(1536,4)&&DoorTextureMatches(1530,0),5,"original_door_wood_textures_and_shared_wall_unchanged");
        yield return AwaitState(()=>Array.Exists(state.npcs,n=>n.name=="Hans"),35,"hans_enters_view");
        var hans=Array.Find(state.npcs,n=>n.name=="Hans");if(hans==null){Debug.LogError("SCAPE_LUMBRIDGE_FAILED Hans missing");Application.Quit(1);yield break;}
        if(inputFile!=null)yield return ClickHansThroughWindow(hans);else Target("npc",hans,Array.IndexOf(hans.ops,"Talk-to")+1);yield return AwaitState(()=>state.chatRoot>=0&&Array.Exists(state.ui,w=>w.root==state.chatRoot&&!string.IsNullOrWhiteSpace(w.text)),30,"talk_to_hans_dialogue");
        if(smokeFailed){Application.Quit(1);yield break;}distance=12;yield return new WaitForSeconds(1);yield return CapturePlay("-dialogue");
        string dialogue=string.Join("\n",Array.ConvertAll(Array.FindAll(state.ui,w=>w.root==state.chatRoot),w=>w.id+":"+w.text));var resume=Array.Find(state.ui,w=>w.root==state.chatRoot&&w.button==6);if(resume!=null){if(inputFile!=null)RequestInput("continue-dialogue","left",dialogueButtonScreen);else WidgetButton(resume);}else{var choice=Array.Find(state.ui,w=>w.root==state.chatRoot&&w.button>0);if(choice!=null)WidgetButton(choice);}
        yield return AwaitState(()=>string.Join("\n",Array.ConvertAll(Array.FindAll(state.ui,w=>w.root==state.chatRoot),w=>w.id+":"+w.text))!=dialogue,15,"dialogue_continue_or_choice");yield return CapturePlay("-choices");Send(new Action{kind="close"});yield return AwaitState(()=>state.chatRoot<0,8,"dialogue_close");
        if(inputFile!=null){float beforeYaw=yaw;RequestInput("camera-right","key",Vector2.zero,"Right");yield return AwaitState(()=>yaw<beforeYaw-5,5,"physical_right_arrow_direction");yield return AwaitState(()=>worldHoverSeen>0,1,"physical_world_hover");}
        Actor door=null;float near=float.MaxValue;foreach(var a in state.locs){if(a.name.IndexOf("door",StringComparison.OrdinalIgnoreCase)<0||Array.IndexOf(a.ops,"Open")<0)continue;float d=Mathf.Abs(a.x-3217)+Mathf.Abs(a.z-3218);if(d<near){near=d;door=a;}}
        if(door==null){Debug.LogError("SCAPE_LUMBRIDGE_FAILED no door");Application.Quit(1);yield break;}
        float doorX=door.x,doorZ=door.z;int doorId=door.id;Target("loc",door,Array.IndexOf(door.ops,"Open")+1);
        yield return AwaitState(()=>Array.Exists(state.locs,a=>Mathf.Abs(a.x-doorX)<=2&&Mathf.Abs(a.z-doorZ)<=2&&Array.IndexOf(a.ops,"Close")>=0),45,"door_open");
        if(smokeFailed){Application.Quit(1);yield break;}var opened=Array.Find(state.locs,a=>Mathf.Abs(a.x-doorX)<=2&&Mathf.Abs(a.z-doorZ)<=2&&Array.IndexOf(a.ops,"Close")>=0);yield return new WaitForSeconds(1);yield return CapturePlay("-door-open");Target("loc",opened,Array.IndexOf(opened.ops,"Close")+1);
        yield return AwaitState(()=>Array.Exists(state.locs,a=>a.id==doorId&&a.x==doorX&&a.z==doorZ&&Array.IndexOf(a.ops,"Open")>=0),20,"door_close");yield return new WaitForSeconds(1);yield return CapturePlay("-door-closed");
        var bucket=FindItem(1925);if(bucket!=null){Held(bucket,5);yield return AwaitState(()=>FindItem(1925)==null&&Array.Exists(state.objects,a=>a.id==1925),12,"drop_bucket");var ground=Array.Find(state.objects,a=>a.id==1925);if(ground!=null)Target("obj",ground,3);yield return AwaitState(()=>FindItem(1925)!=null,15,"pickup_bucket");}
        Debug.Log("SCAPE_LUMBRIDGE_"+(smokeFailed?"FAILED":"PASSED")+" dialogueDraws="+dialogueDraws+" chunks="+chunks.Count+" player="+state.player.x+","+state.player.z);
        yield return Logout();Application.Quit(smokeFailed?1:0);
    }
}
}
