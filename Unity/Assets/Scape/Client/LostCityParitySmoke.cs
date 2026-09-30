using System;
using System.Collections;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    bool smokeFailed;
    Item FindItem(int id)=>Array.Find(state?.inventory??Array.Empty<Item>(),i=>i.id==id&&i.component==3214);
    IEnumerator AwaitState(Func<bool> predicate,float seconds,string label){float end=Time.realtimeSinceStartup+seconds;while(!predicate()&&Time.realtimeSinceStartup<end)yield return new WaitForSeconds(.2f);if(!predicate()){smokeFailed=true;Debug.LogError("SCAPE_PARITY_FAILED "+label+" "+status);if(state!=null)Debug.LogError(string.Join(" | ",state.messages));}else Debug.Log("SCAPE_PARITY_CHECK "+label);}
    void Held(Item item,int op){Send(new Action{kind="inventory",id=item.id,slot=item.slot,component=item.component,op=op});}
    IEnumerator ParitySmoke(){
        username="unityplay";StartCoroutine(Join());yield return AwaitState(()=>state!=null,45,"login");if(smokeFailed){Application.Quit(1);yield break;}
        foreach(var w in state.ui)if(w.clientCode==326)Send(new Action{kind="appearance",id=w.id});yield return new WaitForSeconds(2);
        if(state.player.x<3200){
            var guide=Array.Find(state.npcs,n=>n.name=="RuneScape Guide");if(guide!=null)Target("npc",guide,1);
            float end=Time.realtimeSinceStartup+35;
            while(state.player.x<3200&&Time.realtimeSinceStartup<end){
                var resume=Array.Find(state.ui,w=>w.button==6);var yes=Array.Find(state.ui,w=>w.button==1&&w.text.StartsWith("Yes"));
                if(resume!=null)Send(new Action{kind="resume",id=resume.id});else if(yes!=null)Send(new Action{kind="button",id=yes.id});
                yield return new WaitForSeconds(1.5f);
            }
        }
        yield return AwaitState(()=>state.player.x>3200&&FindItem(1925)!=null,10,"tutorial_dialogue_to_lumbridge");if(smokeFailed){Application.Quit(1);yield break;}
        string before=JsonUtility.ToJson(state.player.parts[0]);var weapon=FindItem(1351)??FindItem(1277);if(weapon!=null)Held(weapon,2);
        yield return AwaitState(()=>JsonUtility.ToJson(state.player.parts[0])!=before,10,"equipment_model_changes");if(smokeFailed){Application.Quit(1);yield break;}
        Held(FindItem(1925),5);yield return AwaitState(()=>FindItem(1925)==null&&Array.Exists(state.objects,o=>o.id==1925),10,"drop_item");if(smokeFailed){Application.Quit(1);yield break;}
        Target("obj",Array.Find(state.objects,o=>o.id==1925),3);yield return AwaitState(()=>FindItem(1925)!=null,15,"pick_up_item");if(smokeFailed){Application.Quit(1);yield break;}
        Actor tree=null;float nearest=float.MaxValue;foreach(var loc in state.locs)if(loc.name=="Tree"&&Array.IndexOf(loc.ops,"Chop down")>=0){float d=Mathf.Abs(loc.x-state.player.x)+Mathf.Abs(loc.z-state.player.z);if(d<nearest){nearest=d;tree=loc;}}
        int woodXp=state.experience[8];if(tree!=null)Target("loc",tree,Array.IndexOf(tree.ops,"Chop down")+1);
        yield return AwaitState(()=>FindItem(1511)!=null&&state.experience[8]>woodXp,80,"woodcutting_logs_and_xp");if(smokeFailed){Application.Quit(1);yield break;}
        var logs=FindItem(1511);selectedItem=FindItem(590);int fireXp=state.experience[11];TargetAction(new Action{kind="inventory",id=logs.id,slot=logs.slot,component=logs.component});
        yield return AwaitState(()=>state.experience[11]>fireXp,70,"firemaking_xp");if(smokeFailed){Application.Quit(1);yield break;}
        activeTab=3;yield return new WaitForSeconds(2);yield return new WaitForEndOfFrame();
        foreach(string arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-capture=")){var texture=new Texture2D(Screen.width,Screen.height,TextureFormat.RGB24,false);texture.ReadPixels(new Rect(0,0,Screen.width,Screen.height),0,0);texture.Apply();System.IO.File.WriteAllBytes(arg.Substring(16),texture.EncodeToPNG());Destroy(texture);}
        Debug.Log("SCAPE_PARITY_PASSED unity_native=true woodcuttingXP="+state.experience[8]+" firemakingXP="+state.experience[11]+" animationFrames="+LostCityAnimator.AppliedFrames+" actionFrames="+LostCityAnimator.ActionFrames);
        yield return Logout();Application.Quit(LostCityAnimator.AppliedFrames>0&&LostCityAnimator.ActionFrames>0?0:1);
    }
}
}
