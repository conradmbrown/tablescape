using System;
using System.Collections;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    IEnumerator CheckPortrait(string kind){
        yield return AwaitState(()=>state?.dialogueHead?.kind==kind&&dialogueHeadModel&&dialogueHeadCamera.enabled&&Sequence(state.dialogueHead.sequence)!=null,45,kind+"_head_and_sequence");if(smokeFailed)yield break;
        yield return new WaitForSeconds(.5f);yield return new WaitForEndOfFrame();
        var old=RenderTexture.active;RenderTexture.active=dialogueHeadTexture;var image=new Texture2D(256,256,TextureFormat.RGBA32,false);image.ReadPixels(new Rect(0,0,256,256),0,0);image.Apply();RenderTexture.active=old;
        int visible=0;foreach(var c in image.GetPixels32())if(c.a>128)visible++;Destroy(image);
        yield return AwaitState(()=>visible>1000&&visible<60000&&dialogueHeadDraws>0,1,kind+"_visible_transparent_portrait");
        var filters=dialogueHeadModel.GetComponentsInChildren<MeshFilter>();var before=Array.ConvertAll(filters,f=>f.sharedMesh.vertices);bool changed=false;
        float until=Time.time+2;while(Time.time<until&&!changed){yield return new WaitForEndOfFrame();for(int m=0;m<filters.Length;m++){var current=filters[m].sharedMesh.vertices;for(int i=0;i<current.Length;i++)if((before[m][i]-current[i]).sqrMagnitude>.00000001f){changed=true;break;}}}
        yield return AwaitState(()=>changed,1,kind+"_original_facial_animation");yield return CapturePlay("-"+kind);
        Debug.Log($"SCAPE_CHATHEAD_RENDER kind={kind} npc={state.dialogueHead.npc} sequence={state.dialogueHead.sequence} visiblePixels={visible} models={filters.Length}");
    }
    IEnumerator ChatHeadSmoke(){
        foreach(string arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-capture="))captureBase=arg.Substring(16);
        username="unitych"+Guid.NewGuid().ToString("N").Substring(0,5);StartCoroutine(Join());yield return AwaitState(()=>state!=null,45,"chathead_login");if(smokeFailed){Application.Quit(1);yield break;}
        yield return AwaitState(()=>chunks.Count>=49&&!terrainBusy,100,"chathead_world_loaded");
        yield return AwaitState(()=>Array.Exists(state.npcs,n=>n.name=="Hans"),35,"chathead_hans_visible");
        var hans=Array.Find(state.npcs,n=>n.name=="Hans");if(hans==null){Application.Quit(1);yield break;}
        Target("npc",hans,Array.IndexOf(hans.ops,"Talk-to")+1);yield return CheckPortrait("npc");if(smokeFailed){yield return Logout();Application.Quit(1);yield break;}
        int firstRoot=state.chatRoot;WidgetButton(Array.Find(state.ui,w=>w.root==state.chatRoot&&w.button==6));
        yield return AwaitState(()=>state.chatRoot>=0&&state.chatRoot!=firstRoot&&string.IsNullOrEmpty(state.dialogueHead?.kind)&&!dialogueHeadModel,15,"choice_hides_head");if(smokeFailed){yield return Logout();Application.Quit(1);yield break;}
        var choice=Array.Find(state.ui,w=>w.root==state.chatRoot&&w.button>0&&w.text!=null&&w.text.Contains("in charge"));if(choice==null){Debug.LogError("SCAPE_CHATHEAD_FAILED choice missing");yield return Logout();Application.Quit(1);yield break;}
        WidgetButton(choice);yield return CheckPortrait("player");if(smokeFailed){yield return Logout();Application.Quit(1);yield break;}
        WidgetButton(Array.Find(state.ui,w=>w.root==state.chatRoot&&w.button==6));yield return CheckPortrait("npc");
        Send(new Action{kind="close"});yield return AwaitState(()=>state.chatRoot<0&&!dialogueHeadModel&&!dialogueHeadCamera.enabled,12,"close_clears_head");
        hans=Array.Find(state.npcs,n=>n.name=="Hans");if(hans!=null){Target("npc",hans,Array.IndexOf(hans.ops,"Talk-to")+1);yield return AwaitState(()=>state.dialogueHead?.kind=="npc"&&dialogueHeadModel,30,"reopen_restores_head");}
        yield return Logout();yield return AwaitState(()=>!dialogueHeadModel&&!dialogueHeadCamera.enabled,2,"logout_clears_head");
        Debug.Log("SCAPE_CHATHEAD_"+(smokeFailed?"FAILED":"PASSED"));Application.Quit(smokeFailed?1:0);
    }
}
}
