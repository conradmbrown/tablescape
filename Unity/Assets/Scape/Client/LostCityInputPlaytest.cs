using System;
using System.Collections;
using System.IO;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    [Serializable] class InputStep {public string step,kind,key;public int x,y;}
    string inputFile;Vector2 dialogueButtonScreen;int worldHoverSeen;
    void RequestInput(string step,string kind,Vector2 point,string key=null){File.WriteAllText(inputFile,JsonUtility.ToJson(new InputStep{step=step,kind=kind,key=key,x=Mathf.RoundToInt(point.x),y=Mathf.RoundToInt(point.y)}));}
    IEnumerator ClickHansThroughWindow(Actor hans,bool replaceMenu=true){
        distance=18;yield return new WaitForSeconds(2);float until=Time.realtimeSinceStartup+60;int attempt=0;float nextApproach=0;
        while((!menuOpen||!menu.Exists(m=>m.label.StartsWith("Talk-to Hans")))&&Time.realtimeSinceStartup<until){
            var current=Array.Find(state.npcs,n=>n.id==hans.id);
            if(replaceMenu&&current!=null&&Time.realtimeSinceStartup>=nextApproach&&Vector2.Distance(new Vector2(current.x,current.z),new Vector2(state.player.x,state.player.z))>5){
                Send(new Action{kind="move",x=(int)current.x,z=(int)current.z});nextApproach=Time.realtimeSinceStartup+3;
            }
            bool requested=false;
            if(entities.TryGetValue("npc-"+hans.id,out var root)){
                var bounds=new Bounds(root.transform.position,Vector3.zero);foreach(var c in root.GetComponentsInChildren<Collider>())if(c.enabled)bounds.Encapsulate(c.bounds);
                var point=view.WorldToScreenPoint(bounds.center);var gui=new Vector2(point.x,Screen.height-point.y);
                if(point.z>0&&gui.x>245&&gui.x<Screen.width-380&&gui.y>85&&gui.y<ChatRect.y-10&&!MapRect.Contains(gui)){
                    var picks=PointerTargets(new Vector2(point.x,point.y),out var ground);
                    if(picks.Exists(p=>p.actor.id==hans.id&&p.kind=="npc")){RequestInput("npc-menu-"+attempt++,"right",gui);requested=true;}
                }
            }
            if(!requested)yaw+=30;
            yield return new WaitForSeconds(1);
        }
        if(!menuOpen||!menu.Exists(m=>m.label.StartsWith("Talk-to Hans"))){yield return CapturePlay("-input-failed");File.WriteAllText(captureBase+"-input-failed.json",JsonUtility.ToJson(state,true));}
        yield return AwaitState(()=>menuOpen,2,"physical_right_click_menu");if(smokeFailed)yield break;yield return CapturePlay("-menu");
        if(replaceMenu){
            // Finish the approach before choosing fixed screen coordinates for a new target.
            Send(new Action{kind="move",x=(int)state.player.x,z=(int)state.player.z});yield return new WaitForSeconds(2);
            Vector2 target=Vector2.zero;string expected=null;
            for(int y=100;y<ChatRect.y-20&&expected==null;y+=20)for(int x=100;x<Screen.width-380&&expected==null;x+=20){
                var gui=new Vector2(x,y);if(MapRect.Contains(gui)||menuRect.Contains(gui))continue;
                var picks=PointerTargets(new Vector2(x,Screen.height-y),out var ground);
                if(picks.Exists(p=>p.kind=="npc"&&p.actor.id==hans.id))continue;
                var loc=picks.Find(p=>p.kind=="loc"&&Array.Exists(p.actor.ops??Array.Empty<string>(),o=>!string.IsNullOrEmpty(o)));
                if(loc){expected="Examine "+ActorLabel(loc.actor);target=gui;}
            }
            yield return AwaitState(()=>expected!=null,1,"replacement_object_available");if(smokeFailed)yield break;
            int opened=menusOpened;RequestInput("replace-hans-with-object","right",target);
            yield return AwaitState(()=>menuOpen&&menusOpened>opened&&menu.Exists(m=>m.label==expected)&&!menu.Exists(m=>m.label.StartsWith("Talk-to Hans")),5,"physical_right_click_replaces_npc_menu_with_object");
            if(smokeFailed){Debug.LogError("SCAPE_REPLACE_MENU_STATE "+string.Join(" | ",menu.ConvertAll(m=>m.label)));yield return CapturePlay("-replacement-failed");yield break;}yield return CapturePlay("-replacement-object-menu");
            // Keep this menu open while the next physical click targets the moving NPC.
            yield return ClickHansThroughWindow(hans,false);yield break;
        }
        yield return AwaitState(()=>menu.Exists(m=>m.label.StartsWith("Talk-to Hans")),1,"physical_right_click_replaces_object_menu_with_npc");
        int index=menu.FindIndex(m=>m.label.StartsWith("Talk-to Hans"));if(index<0){smokeFailed=true;Debug.LogError("SCAPE_LUMBRIDGE_FAILED physical Hans menu missing");yield break;}
        RequestInput("talk-hans","left",new Vector2(menuRect.x+150,menuRect.y+27+index*24+12));
        yield return AwaitState(()=>!menuOpen,4,"replacement_menu_action_accepts_left_click");
        if(smokeFailed)yield return CapturePlay("-replacement-action-failed");
    }
}
}
