using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
namespace Scape.Client {
[Serializable] public class CacheTransform {public int type,x,y,z;public int[] labels;}
[Serializable] public class CacheFrame {public int delay;public CacheTransform[] transforms;}
[Serializable] public class CacheSequence {public int id,loops,maxloops=99,duplicatebehaviour,postanim_move,replaceheldleft=-1,replaceheldright=-1;public LostCityClient.Part leftMale,leftFemale,rightMale,rightFemale;public CacheFrame[] frames;}
public sealed partial class LostCityClient {
    readonly Dictionary<int,CacheSequence> sequences=new Dictionary<int,CacheSequence>();
    readonly HashSet<int> sequenceRequests=new HashSet<int>();
    public CacheSequence Sequence(int id){if(id<0)return null;if(sequences.TryGetValue(id,out var seq))return seq;if(token==null||connectionPaused||disconnecting)return null;if(sequenceRequests.Add(id))StartCoroutine(FetchSequence(id));return null;}
    IEnumerator FetchSequence(int id){yield return Request("/v1/sequence/"+id,"GET",null,text=>{if(text!=null)sequences[id]=JsonUtility.FromJson<CacheSequence>(text);});sequenceRequests.Remove(id);}
}
public sealed class LostCityAnimator:MonoBehaviour {
    public static int AppliedFrames,ActionFrames;
    public LostCityClient client;public LostCityClient.Actor actor;
    sealed class Skin {public GameObject owner;public int slot;public bool temporary;public Mesh mesh;public Vector3[] original,work,a,b,display,transition;public Vector2[] labels;public Color[] originalColors,colors;}
    readonly List<Skin> skins=new List<Skin>();Vector3 previous;float movingUntil,actionUntil,started,blendStarted;int sequenceId=-1,lastFrame=-1,actionId=-1,lastActionTick=-1;
    bool initialized,pendingAction,deathHeld;int lastActionEvent,heldSequenceId=-2;float actionDelayUntil;Vector2 actionTile;
    public int CurrentSequence=>sequenceId;public int CurrentFrame=>lastFrame;public int DeathFramesSeen{get;private set;}public bool DeathStarted=>deathHeld;public bool DeathFinished{get;private set;}
    public int ActionFramesSeen{get;private set;}
    public int HeldModelCount=>skins.FindAll(s=>s.temporary&&s.owner.activeSelf).Count;
    public bool PlayingAction=>Time.time<actionUntil||deathHeld&&!pendingAction;
    public bool NeedsDeathCompletion=>deathHeld&&!DeathFinished||actor!=null&&actor.animDeath&&actor.animEvent!=lastActionEvent;
    void Start(){
        if(initialized)return;initialized=true;
        previous=transform.position;
        foreach(var f in GetComponentsInChildren<MeshFilter>())AddSkin(f,false);
    }
    void AddSkin(MeshFilter f,bool temporary){
        var clone=Instantiate(f.sharedMesh);var owner=f.GetComponent<LostCityOwnedMesh>()??f.gameObject.AddComponent<LostCityOwnedMesh>();if(owner.mesh)Destroy(owner.mesh);owner.mesh=clone;f.sharedMesh=clone;var collider=f.GetComponent<MeshCollider>();if(collider)collider.sharedMesh=clone;
        var vertices=clone.vertices;var work=new Vector3[vertices.Length];var offset=f.transform.localPosition;f.transform.localPosition=Vector3.zero;
        for(int i=0;i<vertices.Length;i++)vertices[i]+=offset;clone.vertices=vertices;
        var display=(Vector3[])vertices.Clone();
        for(int i=0;i<vertices.Length;i++)vertices[i]=new Vector3(vertices[i].x,-vertices[i].y,vertices[i].z)*128;
        var part=f.GetComponent<LostCityAnimationPart>();
        skins.Add(new Skin{owner=f.gameObject,slot=part?part.slot:-1,temporary=temporary,mesh=clone,original=vertices,work=work,a=new Vector3[vertices.Length],b=new Vector3[vertices.Length],display=display,transition=(Vector3[])display.Clone(),labels=clone.uv2,originalColors=clone.colors,colors=new Color[vertices.Length]});
    }
    void SetHeldSequence(CacheSequence seq){
        int id=seq?.id??-1;if(id==heldSequenceId)return;heldSequenceId=id;
        foreach(var skin in skins)if(skin.temporary){skin.owner.SetActive(false);Destroy(skin.owner);}
        skins.RemoveAll(s=>s.temporary);
        foreach(var skin in skins)skin.owner.SetActive(seq==null||!((skin.slot==3&&seq.replaceheldright>=0)||(skin.slot==5&&seq.replaceheldleft>=0)));
        if(seq!=null&&actor.parts!=null){
            if(seq.replaceheldleft>=512)foreach(var child in client.CreateAnimationHeld(transform,actor.gender==0?seq.leftMale:seq.leftFemale,5,actor))AddSkin(child.GetComponent<MeshFilter>(),true);
            if(seq.replaceheldright>=512)foreach(var child in client.CreateAnimationHeld(transform,actor.gender==0?seq.rightMale:seq.rightFemale,3,actor))AddSkin(child.GetComponent<MeshFilter>(),true);
        }
        lastFrame=-1;
    }
    public static int SequenceCycles(CacheSequence seq){
        int total=0;foreach(var f in seq.frames)total+=Math.Max(1,f.delay);
        if(seq.loops>0&&seq.loops<=seq.frames.Length){int tail=0;for(int i=seq.frames.Length-seq.loops;i<seq.frames.Length;i++)tail+=Math.Max(1,seq.frames[i].delay);total+=tail*Math.Max(0,seq.maxloops-1);}
        return total;
    }
    static int LoopCursor(CacheSequence seq,int cycle,int total){
        if(cycle<total)return cycle;
        if(seq.loops<=0||seq.loops>seq.frames.Length)return total-1;
        int tail=0;for(int i=seq.frames.Length-seq.loops;i<seq.frames.Length;i++)tail+=Math.Max(1,seq.frames[i].delay);
        return total-tail+(cycle-total)%Math.Max(1,tail);
    }
    void LateUpdate(){
        if(actor==null||client==null)return;
        if((transform.position-previous).sqrMagnitude>.00001f)movingUntil=Time.time+.22f;previous=transform.position;
        bool newEvent=actor.animEvent>0?actor.animEvent!=lastActionEvent:actor.anim>=0&&actor.animTick!=lastActionTick;
        if(newEvent){
            var existing=actionId>=0?client.Sequence(actionId):null;
            bool retain=actor.anim==actionId&&PlayingAction&&existing!=null&&existing.duplicatebehaviour!=1;
            lastActionEvent=actor.animEvent;lastActionTick=actor.animTick;actionTile=new Vector2(actor.x,actor.z);
            if(retain)actionUntil=Time.time+SequenceCycles(existing)*.02f;
            else{
                actionId=actor.anim;pendingAction=actionId>=0;
                deathHeld=actor.animDeath&&pendingAction;DeathFinished=false;DeathFramesSeen=0;
                actionDelayUntil=Time.time+Math.Max(0,actor.animDelay)*.02f;actionUntil=0;sequenceId=-1;
            }
        }
        if(deathHeld&&actor.hp>0&&!actor.animDeath){deathHeld=false;DeathFinished=false;pendingAction=false;actionUntil=0;}
        // A cold sequence request must not consume a guessed playback window.
        // Start its clock only once the original frames have actually arrived.
        if(pendingAction&&Time.time>=actionDelayUntil){var loaded=client.Sequence(actionId);if(loaded?.frames!=null&&loaded.frames.Length>0){
            float duration=SequenceCycles(loaded)*.02f;
            actionUntil=Time.time+duration;pendingAction=false;sequenceId=-1;
        }}
        var pick=GetComponent<LostCityPick>();if(pick&&pick.IsMoving)movingUntil=Time.time+.22f;
        if(actionId>=0&&!deathHeld&&new Vector2(actor.x,actor.z)!=actionTile&&client.Sequence(actionId)?.postanim_move==1){actionUntil=0;pendingAction=false;}
        bool action=PlayingAction;
        int id=action?actionId:Time.time<movingUntil?(pick&&pick.IsRunning&&actor.run>=0?actor.run:actor.walk):actor.ready;
        var seq=client.Sequence(id);if(seq?.frames==null||seq.frames.Length==0)return;
        SetHeldSequence(action?seq:null);
        if(sequenceId!=id){sequenceId=id;started=Time.time;lastFrame=-1;blendStarted=Time.time;foreach(var skin in skins)Array.Copy(skin.display,skin.transition,skin.display.Length);}
        // The original secondary (idle/walk/run) loop resets its counter only
        // after it exceeds the frame delay, so each frame includes one extra cycle.
        int extra=action?0:1;
        int total=0;foreach(var f in seq.frames)total+=Math.Max(1,f.delay)+extra;
        float cycle=(Time.time-started)*50;int cursor=action?LoopCursor(seq,(int)cycle,total):(int)cycle%Math.Max(1,total),index=0;
        while(index<seq.frames.Length-1&&cursor>=Math.Max(1,seq.frames[index].delay)+extra){cursor-=Math.Max(1,seq.frames[index].delay)+extra;index++;}
        int next=action?(index+1<seq.frames.Length?index+1:!deathHeld&&seq.loops>0&&seq.loops<=seq.frames.Length&&cycle+1<SequenceCycles(seq)?seq.frames.Length-seq.loops:index):(index+1)%seq.frames.Length;
        if(index!=lastFrame){lastFrame=index;if(action){ActionFrames++;ActionFramesSeen++;}if(action&&deathHeld)DeathFramesSeen++;
            Apply(seq.frames[index]);foreach(var skin in skins)Array.Copy(skin.work,skin.a,skin.work.Length);Apply(seq.frames[next]);foreach(var skin in skins)Array.Copy(skin.work,skin.b,skin.work.Length);}
        // Deaths intentionally hold their last pose for thousands of cache cycles.
        // Completion means that pose has been reached and displayed, not waiting out its hold.
        if(action&&deathHeld&&index==seq.frames.Length-1&&cycle>=total-Math.Max(1,seq.frames[index].delay)+1){DeathFinished=true;}
        float fraction=(cursor+(cycle%1))/(Math.Max(1,seq.frames[index].delay)+extra),blend=Mathf.Clamp01((Time.time-blendStarted)/.14f);
        foreach(var skin in skins){if(!skin.owner.activeSelf)continue;for(int i=0;i<skin.display.Length;i++)skin.display[i]=Vector3.Lerp(skin.transition[i],Vector3.Lerp(skin.a[i],skin.b[i],fraction),blend);skin.mesh.vertices=skin.display;skin.mesh.colors=skin.colors;skin.mesh.RecalculateBounds();}
    }
    public void SampleEffect(CacheSequence sequence,float seconds,bool loop){
        Start();if(sequence?.frames==null||sequence.frames.Length==0)return;
        int total=0;foreach(var f in sequence.frames)total+=Math.Max(1,f.delay)+1;
        int cycle=Math.Max(0,(int)(seconds*50));if(loop)cycle%=total;else cycle=Math.Min(cycle,total-1);
        int index=0;while(index<sequence.frames.Length-1&&cycle>=Math.Max(1,sequence.frames[index].delay)+1){cycle-=Math.Max(1,sequence.frames[index].delay)+1;index++;}
        Apply(sequence.frames[index]);foreach(var skin in skins){skin.mesh.vertices=skin.work;skin.mesh.colors=skin.colors;skin.mesh.RecalculateBounds();}
    }
    static bool Has(int[] labels,int label)=>Array.IndexOf(labels,label)>=0;
    void Apply(CacheFrame frame){
        AppliedFrames++;
        foreach(var s in skins){Array.Copy(s.original,s.work,s.work.Length);Array.Copy(s.originalColors,s.colors,s.colors.Length);}
        Vector3 origin=Vector3.zero;
        foreach(var t in frame.transforms){
            if(t.type==0){var unique=new HashSet<Vector3>();Vector3 sum=Vector3.zero;foreach(var s in skins)for(int i=0;i<s.work.Length;i++)if(s.owner.activeSelf&&i<s.labels.Length&&Has(t.labels,(int)s.labels[i].x-1)&&unique.Add(s.work[i]))sum+=s.work[i];origin=(unique.Count>0?sum/unique.Count:Vector3.zero)+new Vector3(t.x,t.y,t.z);continue;}
            foreach(var s in skins)for(int i=0;i<s.work.Length;i++){
                if(!s.owner.activeSelf||i>=s.labels.Length)continue;
                if(t.type==5){if(Has(t.labels,(int)s.labels[i].y-1)){var c=s.colors[i];c.a=Mathf.Clamp01(c.a-t.x*8/255f);s.colors[i]=c;}continue;}
                if(!Has(t.labels,(int)s.labels[i].x-1))continue;
                var v=s.work[i];
                if(t.type==1)v+=new Vector3(t.x,t.y,t.z);
                else if(t.type==3)v=Vector3.Scale(v-origin,new Vector3(t.x,t.y,t.z)/128)+origin;
                else if(t.type==2){
                    v-=origin;float a=(t.z&255)*Mathf.PI/128,c=Mathf.Cos(a),sn=Mathf.Sin(a);v=new Vector3(v.y*sn+v.x*c,v.y*c-v.x*sn,v.z);
                    a=(t.x&255)*Mathf.PI/128;c=Mathf.Cos(a);sn=Mathf.Sin(a);v=new Vector3(v.x,v.y*c-v.z*sn,v.y*sn+v.z*c);
                    a=(t.y&255)*Mathf.PI/128;c=Mathf.Cos(a);sn=Mathf.Sin(a);v=new Vector3(v.z*sn+v.x*c,v.y,v.z*c-v.x*sn);v+=origin;
                }
                s.work[i]=v;
            }
        }
        foreach(var s in skins){for(int i=0;i<s.work.Length;i++)s.work[i]=new Vector3(s.work[i].x,-s.work[i].y,s.work[i].z)/128;}
    }
}
}
