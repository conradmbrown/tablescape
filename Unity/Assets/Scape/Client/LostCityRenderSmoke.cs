using System;
using System.Collections;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    IEnumerator RenderSmoke(){
        username="unityplay";StartCoroutine(Join());float deadline=Time.realtimeSinceStartup+150;
        while((state==null||terrainBusy||chunks.Count<49)&&Time.realtimeSinceStartup<deadline)yield return null;
        if(state==null){Debug.LogError("SCAPE_RENDER_FAILED no state");Application.Quit(1);yield break;}
        int walls=0,statics=0,textures=0;foreach(var p in entities)if(p.Key.StartsWith("static-")){statics++;if(p.Value.GetComponent<LostCityPick>().actor.shape<=3)walls++;}foreach(var c in chunks.Values)foreach(var m in c.materials)if(m.mainTexture)textures++;
        var player=entities["player"];Vector3 start=player.transform.position;int frames=LostCityAnimator.AppliedFrames;
        Send(new Action{kind="move",x=(int)state.player.x+3,z=(int)state.player.z});
        float until=Time.realtimeSinceStartup+7,maxStep=0;Vector3 previousCamera=view.transform.position;bool moved=false;float facing=-1;
        while(Time.realtimeSinceStartup<until){yield return null;float step=Vector3.Distance(view.transform.position,previousCamera);maxStep=Mathf.Max(maxStep,step);previousCamera=view.transform.position;if(Vector3.Distance(start,player.transform.position)>.5f){moved=true;facing=Vector3.Dot(-player.transform.forward,(player.transform.position-start).normalized);}}
        yaw+=35;distance=35;yield return new WaitForSeconds(2);yield return new WaitForEndOfFrame();
        foreach(string arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-capture=")){var capture=new Texture2D(Screen.width,Screen.height,TextureFormat.RGB24,false);capture.ReadPixels(new Rect(0,0,Screen.width,Screen.height),0,0);capture.Apply();System.IO.File.WriteAllBytes(arg.Substring(16),capture.EncodeToPNG());Destroy(capture);}
        bool passed=chunks.Count>=49&&walls>0&&statics>100&&textures>0&&moved&&facing>.8f&&LostCityAnimator.AppliedFrames>frames;
        Debug.Log($"SCAPE_RENDER_{(passed?"PASSED":"FAILED")} chunks={chunks.Count} staticScenery={statics} walls={walls} texturedBatches={textures} moved={moved} facing={facing:F3} maxCameraFrameStep={maxStep:F3} animationFrames={LostCityAnimator.AppliedFrames-frames}");
        yield return Request("/v1/session","DELETE",null,null);token=null;Application.Quit(passed?0:1);
    }
}
}
