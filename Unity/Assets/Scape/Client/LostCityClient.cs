using System;
using System.Collections;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;
using UnityEngine;
using UnityEngine.Networking;
using Scape.Assets;

namespace Scape.Client {
public sealed partial class LostCityClient : MonoBehaviour {
    public string endpoint="http://127.0.0.1:8890";
    public LostCityCatalogue catalogue;
    public Shader surfaceShader;
    [Serializable] public class Part {public int slot=-1;public int[] models,recolS,recolD;public float offsetY,yaw,modelOffsetX,modelOffsetZ;public bool mirror;}
    [Serializable] public class Hit {public int id,tick,damage,type,hp,maxHp;}
    [Serializable] public class Actor : Part {public int lightAmbient=64,lightContrast=768;public int gender;public int id,type,angle,shape,width,length,size,hp,maxHp,ready=-1,walk=-1,run=-1,anim=-1,animTick,animEvent,animDelay,deathAnim=-1;public bool animDeath;public float x,y,z,scaleX=1,scaleY=1,scaleZ=1,offsetX,offsetZ;public EffectEvent[] effects;public int[] hillHeights;public string key,name,description;public bool hasFacing;public float faceX,faceZ;public string faceKind;public int faceId=-1;public int combatLevel=-1;public Hit[] hits;public string[] ops;public Part[] parts;}
    [Serializable] public class Widget {public int id,root,button,clientCode,target;public string text,option,action,verb;public bool active;}
    [Serializable] public class Item {public int id,count,slot,component,root;public string name,title,graphic;public string[] ops,buttons;public bool usable;}
    [Serializable] public class Design {public int id,type;}
    [Serializable] public class State {public int musicSetting,soundSetting;public bool running;public DialogueHead dialogueHead;public Sidebar sidebar;public OriginalOverlay overlay;public AudioEvent music;public AudioEvent[] audio;public EffectEvent[] effects;public int revision,tick,regionX,regionZ,level,tutorialProgress,combatStyle;public bool pending,allowDesign,busy;public Actor player;public Actor[] npcDeaths,npcs,locs,backgroundLocs,objects,players;public Widget[] ui;public Item[] inventory;public string[] messages;public int[] levels,experience,baseLevels,tabs,body,colors;public int activeTab,energy,gender,sideRoot=-1,chatRoot=-1,mainRoot=-1,tutorialRoot=-1;public bool countDialog;public Design[] design;public int[] colorCounts;}
    [Serializable] class Login {public string username;public bool startLumbridge=true;}
    [Serializable] class Session {public string token;public int revision;}
    [Serializable] public class Action {public string kind,target;public int id,op=1,x,z,slot,component,useId,useSlot,useComponent,spell,targetSlot,gender;public int[] body,colors;public bool run;}
    [Serializable] class Surface {public int texture;public float[] vertices,colours,uv;}
    [Serializable] class Terrain {public int revision,x,z,level;public Surface[] meshes;public Actor[] locs;}
    readonly Dictionary<int,GameObject> models=new Dictionary<int,GameObject>();
    readonly Dictionary<string,GameObject> entities=new Dictionary<string,GameObject>();
    readonly Queue<Action> actions=new Queue<Action>();
    readonly List<Mesh> ownedMeshes=new List<Mesh>();
    readonly List<Material> ownedMaterials=new List<Material>();
    State state;string token,status="Ready",username="unitytest";bool joining,terrainBusy;int rx=int.MinValue,rz,plane;
    GameObject terrainRoot;Camera view;Vector3 target;float yaw=25,pitch=55,distance=22;Vector2 scroll;
    void Start(){
        if(!catalogue||!surfaceShader){status="Missing client assets";return;}
        for(int i=0;i<catalogue.ids.Length;i++)models[catalogue.ids[i]]=catalogue.models[i];
        var go=new GameObject("Tabletop camera");view=go.AddComponent<Camera>();view.tag="MainCamera";view.cullingMask=~(1<<10);view.backgroundColor=new Color(.06f,.08f,.10f);view.clearFlags=CameraClearFlags.SolidColor;view.farClipPlane=250;view.nearClipPlane=.3f;
        InitializeClientControl();Application.targetFrameRate=60;InitializeMinimap();InitializeFeedback();InitializeMedia();
        foreach(string arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-endpoint="))endpoint=arg.Substring(17);
        foreach(string arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-user="))username=arg.Substring(13);
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--scape-context-test")>=0)StartCoroutine(ContextSmoke());
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--scape-movement-test")>=0)StartCoroutine(MovementSmoke());
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--scape-chathead-test")>=0)StartCoroutine(ChatHeadSmoke());
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--scape-loot-test")>=0)StartCoroutine(GroundItemSmoke());
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--scape-sidebar-test")>=0)StartCoroutine(SidebarSmoke());
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--scape-media-test")>=0)StartCoroutine(MediaSmoke());
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--scape-session-test")>=0)StartCoroutine(SessionSmoke());
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--scape-slope-test")>=0)StartCoroutine(SlopeSmoke());
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--scape-skills-test")>=0)StartCoroutine(SkillsPlaytest());
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--scape-lumbridge-test")>=0)StartCoroutine(LumbridgeSmoke());
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--scape-feedback-test")>=0)StartCoroutine(FeedbackSmoke());
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--scape-render-test")>=0)StartCoroutine(RenderSmoke());
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--scape-parity")>=0)StartCoroutine(ParitySmoke());
        if(Array.IndexOf(Environment.GetCommandLineArgs(),"--scape-smoke")>=0)StartCoroutine(Smoke());
        if(!Array.Exists(Environment.GetCommandLineArgs(),a=>a.StartsWith("--scape-")&&(a.EndsWith("-test")||a=="--scape-parity"||a=="--scape-smoke")))StartCoroutine(Join());
    }
    IEnumerator Smoke(){
        username="unitysmok";StartCoroutine(Join());float deadline=Time.realtimeSinceStartup+60;
        while(state==null&&Time.realtimeSinceStartup<deadline)yield return null;
        if(state==null){Debug.LogError("SCAPE_SMOKE_FAILED: no native session");Application.Quit(1);yield break;}
        foreach(var w in state.ui??Array.Empty<Widget>())if(w.clientCode==326)Send(new Action{kind="appearance",id=w.id});
        yield return new WaitForSeconds(2);
        int originalX=(int)state.player.x,originalZ=(int)state.player.z;
        Send(new Action{kind="move",x=originalX-1,z=originalZ});yield return new WaitForSeconds(3);
        bool moved=state.player.x!=originalX||state.player.z!=originalZ;
        foreach(var n in state.npcs??Array.Empty<Actor>())if(n.name=="RuneScape Guide"){Send(new Action{kind="npc",id=n.id,op=1});break;}
        yield return new WaitForSeconds(3);
        while(terrainBusy&&Time.realtimeSinceStartup<deadline)yield return null;
        yield return new WaitForEndOfFrame();
        string capture=null;foreach(string arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-capture="))capture=arg.Substring(16);
        if(capture!=null){
            var texture=new Texture2D(Screen.width,Screen.height,TextureFormat.RGB24,false);
            texture.ReadPixels(new Rect(0,0,Screen.width,Screen.height),0,0);texture.Apply();System.IO.File.WriteAllBytes(capture,texture.EncodeToPNG());Destroy(texture);
        }
        Debug.Log("SCAPE_NATIVE_SESSION tick="+state.tick+" npcs="+state.npcs.Length+" scenery="+state.locs.Length+" moved="+moved+" terrain="+(terrainRoot!=null));
        yield return Request("/v1/session","DELETE",null,null);token=null;
        Application.Quit(moved&&terrainRoot?0:1);
    }
    void Apply(State next){
        movementClock.Observe(next.tick,Time.unscaledTimeAsDouble);

        var alive=new HashSet<string>();
        Show("player",next.player,false,alive);
        foreach(var a in next.players??Array.Empty<Actor>())Show("player-"+a.id,a,false,alive);
        foreach(var a in next.npcs??Array.Empty<Actor>())Show("npc-"+a.id,a,false,alive);
        foreach(var a in next.locs??Array.Empty<Actor>())Show("loc-"+a.key,a,true,alive);
        foreach(var a in next.backgroundLocs??Array.Empty<Actor>()){string key="lower-loc-"+a.key;Show(key,a,true,alive);foreach(var collider in entities[key].GetComponentsInChildren<Collider>())collider.enabled=false;}
        foreach(var a in next.objects??Array.Empty<Actor>())Show("obj-"+a.key,a,false,alive);
        ApplyDepartedDeaths(next,alive);
        var remove=new List<string>();foreach(var kv in entities)if(!kv.Key.StartsWith("static-")&&!alive.Contains(kv.Key)){RetireActor(kv.Value);remove.Add(kv.Key);}foreach(var k in remove)entities.Remove(k);
        // Resolve targets after all actors have been placed, including the local player.
        foreach(var key in alive){var pick=entities[key].GetComponent<LostCityPick>();pick.facingTarget=null;
            var actor=pick.actor;if(string.IsNullOrEmpty(actor.faceKind))continue;
            string faceKey=actor.faceKind=="player"&&actor.faceId==next.player.id?"player":actor.faceKind+"-"+actor.faceId;
            if(entities.TryGetValue(faceKey,out var face)&&face!=entities[key])pick.facingTarget=face.transform;
        }
        UpdateCombatFeedback();UpdateChunkRequests();UpdateMediaEvents();UpdateOriginalOverlay();UpdateDialogueHead();runEnabled=state.running;
    }
    void Show(string key,Actor actor,bool scenery,HashSet<string> alive){
        alive.Add(key);
        string signature=JsonUtility.ToJson(new Part{models=actor.models,recolS=actor.recolS,recolD=actor.recolD});
        if(scenery)signature+=JsonUtility.ToJson(actor);
        if(actor.parts!=null)foreach(var part in actor.parts)signature+=JsonUtility.ToJson(part);
        if(entities.TryGetValue(key,out var old)&&old.GetComponent<LostCityPick>().signature!=signature){Destroy(old);entities.Remove(key);}
        bool created=!entities.TryGetValue(key,out var root);
        if(created){
            root=new GameObject(actor.name??key);root.transform.SetParent(transform);entities[key]=root;
            var parts=actor.parts??new[]{new Part{models=actor.models,recolS=actor.recolS,recolD=actor.recolD}};
            foreach(var part in parts)foreach(int id in part.models??Array.Empty<int>()){
                if(!models.TryGetValue(id,out var prefab)){Debug.LogWarning("Original model unavailable: "+id);continue;}
                var child=Instantiate(prefab,root.transform);child.name="model-"+id;
                if(!scenery&&!key.StartsWith("obj-"))child.AddComponent<LostCityAnimationPart>().slot=part.slot;
                var filter=child.GetComponent<MeshFilter>();
                if(filter&&filter.sharedMesh){
                    Recolour(child,part,id);child.transform.localPosition=new Vector3(part.modelOffsetX,-part.offsetY,part.modelOffsetZ);child.transform.localRotation=Quaternion.Euler(0,part.yaw,0);if(part.mirror)MirrorScenery(child);child.transform.localScale=Vector3.one;child.layer=scenery?8:9;
                    var collider=child.AddComponent<MeshCollider>();collider.sharedMesh=filter.sharedMesh;
                }
            }
            var pick=root.AddComponent<LostCityPick>();pick.client=this;pick.kind=scenery?"loc":key.StartsWith("obj-")?"obj":key.StartsWith("player-")?"player":"npc";pick.actor=actor;pick.signature=signature;pick.enabled=!scenery&&!key.StartsWith("obj-");if(key=="player")pick.kind="player";
            if(!scenery&&!key.StartsWith("obj-")){var bounds=new Bounds(Vector3.zero,Vector3.zero);foreach(var renderer in root.GetComponentsInChildren<Renderer>())bounds.Encapsulate(renderer.bounds);var capsule=root.AddComponent<CapsuleCollider>();capsule.center=bounds.center;capsule.height=Mathf.Max(.4f,bounds.size.y);capsule.radius=Mathf.Clamp(Mathf.Min(bounds.extents.x,bounds.extents.z),.18f,.65f);foreach(var collider in root.GetComponentsInChildren<MeshCollider>())collider.enabled=false;}
        }
        else root.GetComponent<LostCityPick>().actor=actor;
        if(!scenery&&!key.StartsWith("obj-")){var animator=root.GetComponent<LostCityAnimator>()??root.AddComponent<LostCityAnimator>();animator.client=this;animator.actor=actor;if(actor.deathAnim>=0)Sequence(actor.deathAnim);}
        int width=scenery?Math.Max(1,actor.width):Math.Max(1,actor.size),length=scenery?Math.Max(1,actor.length):width;
        if(scenery&&(actor.angle&1)==1){int t=width;width=length;length=t;}
        var position=new Vector3(actor.x+width*.5f+actor.offsetX,actor.y-actor.offsetY+(scenery&&actor.shape==22?.006f:0),actor.z+length*.5f+actor.offsetZ);
        if(key.StartsWith("obj-")){
            // Small original item meshes must rest on the rendered terrain, not a tile's
            // corner or a bilinear height below its actual triangulated surface.
            float closest=float.MaxValue,surface=position.y;
            foreach(var hit in Physics.RaycastAll(position+Vector3.up,Vector3.down,2,1<<8)){
                if(!hit.collider.name.StartsWith("Ground texture "))continue;
                float delta=Mathf.Abs(hit.point.y-position.y);if(delta<closest){closest=delta;surface=hit.point.y;}
            }
            float bottom=0;foreach(var renderer in root.GetComponentsInChildren<Renderer>())bottom=Mathf.Min(bottom,renderer.bounds.min.y-root.transform.position.y);
            position.y=surface-bottom+.02f;
        }
        root.GetComponent<LostCityPick>().Place(position,scenery||key.StartsWith("obj-"),state?.tick??0);
        if(scenery)root.transform.rotation=Quaternion.Euler(0,90*actor.angle+(actor.shape==11?45:0),0);
        root.transform.localScale=new Vector3(actor.scaleX>0?actor.scaleX:1,actor.scaleY>0?actor.scaleY:1,actor.scaleZ>0?actor.scaleZ:actor.scaleX>0?actor.scaleX:1);
        if(created&&scenery){LightScenery(root,actor);ContourScenery(root,actor);}
    }
    void Update(){PollClientControl();TickMedia();if(!view||state==null)return;if(!connectionPaused&&!disconnecting)UpdateInteraction();CameraInput();}
    void Send(Action a){if(token==null||state==null||connectionPaused||disconnecting){SetNotice("Connection unavailable. Please reconnect before acting.");return;}if(actions.Count<20){actions.Enqueue(a);SetNotice("Queued: "+a.kind);}else SetNotice("Please wait: action queue is full");}
    static string Plain(string text)=>Regex.Replace(text??"","@[a-zA-Z0-9]{3}@|<[^>]*>","").Replace("|","\n");

}
public sealed class LostCityPick : MonoBehaviour {
    public string kind,signature;public LostCityClient.Actor actor;public Transform facingTarget;
    public LostCityClient client;
    readonly LostCityMovementTrack movement=new LostCityMovementTrack();
    Quaternion desiredRotation;bool placed;
    public bool IsMoving=>movement.Moving;
    public bool IsRunning=>movement.Running;
    public void Place(Vector3 p,bool snap,int tick){
        if(movement.Add(p,tick,snap)){transform.position=p;desiredRotation=transform.rotation;}
        placed=true;
    }
    void Update(){
        if(!placed||!client)return;
        transform.position=movement.Evaluate(client.MovementTick);
        if(IsMoving&&(actor==null||!actor.hasFacing))desiredRotation=Quaternion.LookRotation(-movement.Direction.normalized);
    }
    void LateUpdate(){
        if(!placed||(kind!="npc"&&kind!="player"))return;
        if(actor!=null&&actor.hasFacing){
            // Follow the rendered target between server ticks; use authoritative coordinates
            // when that target is outside the visible actor set. Original models face -Z.
            var point=facingTarget?facingTarget.position:new Vector3(actor.faceX,transform.position.y,actor.faceZ);
            var direction=point-transform.position;direction.y=0;
            if(direction.sqrMagnitude>.0001f)desiredRotation=Quaternion.LookRotation(-direction.normalized);
        }
        transform.rotation=Quaternion.Slerp(transform.rotation,desiredRotation,1-Mathf.Exp(-Time.deltaTime/0.10f));
    }
}
}
