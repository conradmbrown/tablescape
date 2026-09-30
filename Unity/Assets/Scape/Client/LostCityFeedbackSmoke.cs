using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    bool facingRegression;
    IEnumerator CheckFacingRegression(){
        var subject=new GameObject("Facing regression");var target=new GameObject("Facing target");
        var pick=subject.AddComponent<LostCityPick>();pick.kind="player";pick.actor=new Actor{hasFacing=true};pick.Place(Vector3.zero,false,1);
        bool pass=true;int checks=0;
        foreach(var direction in new[]{Vector3.forward,Vector3.back,Vector3.left,Vector3.right,new Vector3(1,0,1),new Vector3(-1,0,1),new Vector3(1,0,-1),new Vector3(-1,0,-1)}){
            pick.actor.faceX=direction.x;pick.actor.faceZ=direction.z;pick.Place(Vector3.zero,false,2);
            yield return new WaitForSeconds(.65f);pass&=Vector3.Dot(-subject.transform.forward,direction.normalized)>.995f;checks++;
        }
        pick.facingTarget=target.transform;target.transform.position=Vector3.left*3;
        yield return new WaitForSeconds(.65f);pass&=Vector3.Dot(-subject.transform.forward,Vector3.left)>.995f;checks++;
        target.transform.position=Vector3.right*3;
        yield return new WaitForSeconds(.65f);pass&=Vector3.Dot(-subject.transform.forward,Vector3.right)>.995f;checks++;
        target.transform.position=Vector3.zero;var held=subject.transform.rotation;
        yield return new WaitForSeconds(.2f);pass&=Quaternion.Angle(held,subject.transform.rotation)<1;checks++;
        pick.facingTarget=null;pick.actor.hasFacing=false;pick.client=this;
        movementClock=new LostCityMovementClock();movementClock.Observe(3,Time.unscaledTimeAsDouble);pick.Place(Vector3.forward,false,3);
        yield return new WaitForSeconds(.7f);pass&=Vector3.Dot(-subject.transform.forward,Vector3.forward)>.995f;checks++;
        Destroy(subject);Destroy(target);facingRegression=pass;Debug.Log($"SCAPE_FACING_REGRESSION_{(pass?"PASSED":"FAILED")} checks={checks}");
    }
    IEnumerator FeedbackSmoke(){
        yield return CheckFacingRegression();
        username="unityfb"+Guid.NewGuid().ToString("N").Substring(0,4);StartCoroutine(Join());float deadline=Time.realtimeSinceStartup+150;while((state==null||terrainBusy||chunks.Count<49)&&Time.realtimeSinceStartup<deadline)yield return null;
        if(state==null){Debug.LogError("SCAPE_FEEDBACK_FAILED no session");Application.Quit(1);yield break;}
        LostCityPick victim=null;float nearest=float.MaxValue;foreach(var pair in entities){if(!pair.Key.StartsWith("npc-"))continue;var pick=pair.Value.GetComponent<LostCityPick>();if(pick.actor.name!="Man"&&pick.actor.name!="Goblin")continue;if(Array.IndexOf(pick.actor.ops??Array.Empty<string>(),"Attack")<0)continue;float d=Vector3.Distance(pair.Value.transform.position,entities["player"].transform.position);if(d<nearest){victim=pick;nearest=d;}}
        if(!victim){Debug.LogError("SCAPE_FEEDBACK_FAILED no nearby combat NPC");Application.Quit(1);yield break;}
        distance=13;hover=victim;hoverText=HoverLabel(victim);bool hoverWorks=hoverText.Contains(victim.actor.name);OpenMenu(new List<LostCityPick>{victim},victim.transform.position,new Vector2(550,350));
        var attack=menu.Find(m=>m.label.StartsWith("Attack "));bool npcMenu=attack!=null&&menu.Exists(m=>m.label.StartsWith("Examine "));menuOpen=false;attack?.invoke();
        int initial=receivedHits;deadline=Time.realtimeSinceStartup+75;bool damageSeen=false,playerFacing=false,npcFacing=false;while((!damageSeen||!playerFacing||!npcFacing)&&Time.realtimeSinceStartup<deadline){
            if(victim&&entities.TryGetValue("player",out var player)){
                var pp=player.GetComponent<LostCityPick>();var toward=victim.transform.position-player.transform.position;toward.y=0;
                if(toward.sqrMagnitude>.01f&&!pp.IsMoving&&!victim.IsMoving){
                    playerFacing|=pp.actor.hasFacing&&pp.actor.faceKind=="npc"&&pp.actor.faceId==victim.actor.id&&Vector3.Dot(-player.transform.forward,toward.normalized)>.98f;
                    npcFacing|=victim.actor.hasFacing&&victim.actor.faceKind=="player"&&victim.actor.faceId==state.player.id&&Vector3.Dot(-victim.transform.forward,-toward.normalized)>.98f;
                }
            }foreach(var c in combatViews.Values)if(c.hits.Exists(h=>h.hit.damage>0))damageSeen=true;yield return null;}
        hover=victim;hoverText=victim?HoverLabel(victim):"";
        if(victim)OpenMenu(new List<LostCityPick>{victim},victim.transform.position,new Vector2(700,330));
        MarkClick(new Vector2(600,450),true);yield return new WaitForEndOfFrame();
        foreach(string arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-capture=")){var capture=new Texture2D(Screen.width,Screen.height,TextureFormat.RGB24,false);capture.ReadPixels(new Rect(0,0,Screen.width,Screen.height),0,0);capture.Apply();System.IO.File.WriteAllBytes(arg.Substring(16),capture.EncodeToPNG());Destroy(capture);}
        bool locMenu=false;foreach(var pair in entities){var pick=pair.Value.GetComponent<LostCityPick>();if(pick.kind!="loc")continue;OpenMenu(new List<LostCityPick>{pick},pick.transform.position,new Vector2(500,300));locMenu=menu.Exists(m=>m.label.StartsWith("Examine "))&&menu.Exists(m=>m.label=="Walk here");break;}
        bool transparency=hitSprites&&crossSprites&&hitSprites.GetPixel(0,0).a==0&&crossSprites.GetPixel(0,0).a==0;
        Debug.Log($"SCAPE_COMBAT_FACING player={playerFacing} npc={npcFacing}");
        bool pass=facingRegression&&playerFacing&&npcFacing&&damageSeen&&transparency&&receivedHits>initial&&drawnBars>0&&drawnHits>0&&npcMenu&&locMenu&&hoverWorks&&clickMarkers>0&&hitSprites&&crossSprites;
        Debug.Log($"SCAPE_FEEDBACK_{(pass?"PASSED":"FAILED")} hits={receivedHits-initial} drawnHits={drawnHits} drawnBars={drawnBars} npcMenu={npcMenu} objectMenu={locMenu} hover={hoverWorks} clickMarkers={clickMarkers} realSprites={(hitSprites&&crossSprites)} transparency={transparency} positiveDamage={damageSeen}");
        menuOpen=false;Send(new Action{kind="move",x=(int)state.player.x+5,z=(int)state.player.z});yield return new WaitForSeconds(3);yield return Request("/v1/session","DELETE",null,null);token=null;Application.Quit(pass?0:1);
    }
}
}
