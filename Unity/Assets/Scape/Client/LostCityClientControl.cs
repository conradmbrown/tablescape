using System;
using System.IO;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    // Explicit opt-in local IPC. The private directory is accessible through SSH;
    // there is no public socket, browser API or second game session.
    [Serializable] class ClientCommand {public string command,key,operation;public Action action;public int id,pid;public float yaw,pitch,distance;}
    [Serializable] class ClientTarget {public string key,kind;public Actor actor;public float distance;public bool visible,dying;public int sequence,frame,deathFrames;}
    [Serializable] class ClientSnapshot {public bool ok=true,connected,canAct;public string username,status;public ClientTarget[] nearby;public int completedDeaths,deathFramesRendered;public float yaw,pitch,distance;}
    [Serializable] class ClientReply {public bool ok;public string status,error,key,operation,path;public int tick;}
    string controlDirectory,lastServerStateJson;float nextControlPoll;
    void InitializeClientControl(){
        foreach(var arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-control-dir="))controlDirectory=Path.GetFullPath(arg.Substring("--scape-control-dir=".Length));
        if(controlDirectory==null)return;Directory.CreateDirectory(controlDirectory);Directory.CreateDirectory(Path.Combine(controlDirectory,"requests"));Directory.CreateDirectory(Path.Combine(controlDirectory,"responses"));
        File.WriteAllText(Path.Combine(controlDirectory,"client.json"),"{\"pid\":"+System.Diagnostics.Process.GetCurrentProcess().Id+"}");
        Debug.Log("SCAPE_CLIENT_CONTROL_READY");
    }
    void CloseClientControl(){if(controlDirectory!=null){var file=Path.Combine(controlDirectory,"client.json");if(File.Exists(file))File.Delete(file);}}
    bool ClientCanAct=>state!=null&&token!=null&&!connectionPaused&&!disconnecting&&actions.Count<20;
    string ClientSnapshotJson(){
        var nearby=new List<ClientTarget>();
        foreach(var pair in entities){var pick=pair.Value.GetComponent<LostCityPick>();if(!pick||pair.Key.StartsWith("lower-"))continue;
            var animator=pair.Value.GetComponent<LostCityAnimator>();var actor=pick.actor;
            bool visible=false;foreach(var renderer in pair.Value.GetComponentsInChildren<Renderer>())visible|=renderer.isVisible;
            nearby.Add(new ClientTarget{key=pair.Key,kind=pick.kind,actor=actor,distance=state==null?0:Vector2.Distance(new Vector2(actor.x,actor.z),new Vector2(state.player.x,state.player.z)),visible=visible,sequence=animator?animator.CurrentSequence:-1,frame=animator?animator.CurrentFrame:-1,deathFrames=animator?animator.DeathFramesSeen:0,dying=animator&&animator.DeathStarted});
        }
        foreach(var root in dyingActors)if(root){var a=root.GetComponent<LostCityAnimator>();nearby.Add(new ClientTarget{key="dying-"+root.GetInstanceID(),kind="visual",actor=a.actor,dying=true,sequence=a.CurrentSequence,frame=a.CurrentFrame,deathFrames=a.DeathFramesSeen,visible=root.GetComponentInChildren<Renderer>().isVisible});}
        nearby.Sort((a,b)=>a.distance.CompareTo(b.distance));
        var metadata=JsonUtility.ToJson(new ClientSnapshot{connected=state!=null,canAct=ClientCanAct,username=username,status=status,nearby=nearby.ToArray(),completedDeaths=completedDeaths,deathFramesRendered=deathFramesRendered,yaw=yaw,pitch=pitch,distance=distance});
        // Preserve recursive original interface data without Unity's serializer depth limit.
        return metadata.Substring(0,metadata.Length-1)+",\"state\":"+(state!=null?lastServerStateJson??"null":"null")+"}";
    }
    void PollClientControl(){
        if(controlDirectory==null||Time.unscaledTime<nextControlPoll)return;nextControlPoll=Time.unscaledTime+.05f;
        var files=Directory.GetFiles(Path.Combine(controlDirectory,"requests"),"*.json");Array.Sort(files,StringComparer.Ordinal);
        for(int i=0;i<Math.Min(8,files.Length);i++){
            string result;try{
                var file=files[i];if(new FileInfo(file).Length>65536)throw new ArgumentException("Command exceeds 64 KiB");
                if(DateTime.UtcNow-File.GetLastWriteTimeUtc(file)>TimeSpan.FromSeconds(15))throw new ArgumentException("Command expired; inspect state before retrying");
                var command=JsonUtility.FromJson<ClientCommand>(File.ReadAllText(file));
                if(command.pid!=System.Diagnostics.Process.GetCurrentProcess().Id)throw new InvalidOperationException("Command belongs to a previous client process");
                result=command.command=="state"?ClientSnapshotJson():JsonUtility.ToJson(ExecuteClientCommand(command));
            }catch(Exception e){result=JsonUtility.ToJson(new ClientReply{ok=false,error=e.Message});}
            string response=Path.Combine(controlDirectory,"responses",Path.GetFileName(files[i])),temporary=response+".tmp";
            File.WriteAllText(temporary,result);File.Move(temporary,response);File.Delete(files[i]);
        }
    }
    IEnumerator CaptureClientFrame(string path){yield return new WaitForEndOfFrame();var image=new Texture2D(Screen.width,Screen.height,TextureFormat.RGB24,false);image.ReadPixels(new Rect(0,0,Screen.width,Screen.height),0,0);image.Apply();File.WriteAllBytes(path,image.EncodeToPNG());Destroy(image);}
    static string OperationKey(string value)=>(value??"").Replace("-","").Replace(" ","").ToLowerInvariant();
    ClientReply ExecuteClientCommand(ClientCommand command){
        if(!ClientCanAct)throw new InvalidOperationException("Client is disconnected, recovering, or its action queue is full");
        var reply=new ClientReply{ok=true,status="queued",tick=state.tick};
        switch(command.command){
            case "act":
                if(string.IsNullOrEmpty(command.key)||!entities.TryGetValue(command.key,out var root))throw new ArgumentException("Target is no longer present; inspect nearby again");
                var pick=root.GetComponent<LostCityPick>();if(!pick||command.key=="player"||command.key.StartsWith("lower-"))throw new ArgumentException("Target is not interactive on this floor");
                int op=Array.FindIndex(pick.actor.ops??Array.Empty<string>(),x=>OperationKey(x)==OperationKey(command.operation));
                if(op<0||string.IsNullOrWhiteSpace(command.operation))throw new ArgumentException("That operation is not available on this target");
                selectedItem=null;selectedSpell=null;Target(pick.kind,pick.actor,op+1);reply.key=command.key;reply.operation=pick.actor.ops[op];break;
            case "button":
                var widget=Array.Find(state.ui??Array.Empty<Widget>(),w=>w.id==command.id&&w.button>0);
                if(widget==null)throw new ArgumentException("Interactive widget is not available");FocusTestWidget(widget);WidgetButton(widget);break;
            case "action":
                if(command.action==null||string.IsNullOrEmpty(command.action.kind))throw new ArgumentException("Action required");
                if(command.action.kind=="tab")activeTab=Mathf.Clamp(command.action.id,0,13);
                Send(command.action);break;
            case "camera":yaw=command.yaw;pitch=Mathf.Clamp(command.pitch,20,85);distance=Mathf.Clamp(command.distance,5,65);reply.status="applied";break;
            case "capture":
                string path=Path.Combine(controlDirectory,"capture-"+DateTime.UtcNow.Ticks+".png");StartCoroutine(CaptureClientFrame(path));reply.path=path;break;
            case "logout":StartCoroutine(Logout());break;
            default:throw new ArgumentException("Commands: state, act, button, action, camera, capture, logout");
        }
        // Queued is deliberately not reported as gameplay success: read state for
        // the server-confirmed inventory, XP, dialogue or world change afterward.
        return reply;
    }
}
}
