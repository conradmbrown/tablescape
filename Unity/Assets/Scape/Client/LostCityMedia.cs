using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Networking;
namespace Scape.Client {
public sealed partial class LostCityClient {
    [Serializable] public class AudioEvent {public int @event,id,tick,loops;public string kind;public float delay,resumeAfter;}
    [Serializable] public class EffectEvent {public int @event,type,model,sequence,tick,level,target,peak,angle;public string kind;public float x,y,z,dstX,dstY,dstZ,dstHeight,height,delay,duration,scaleH=1,scaleV=1,arc;public int[] recolS,recolD;public CacheSequence sequenceData;}
    sealed class LiveEffect {public EffectEvent data;public GameObject root;public Transform anchor;public LostCityAnimator animator;public float born,lastElapsed;public Vector3 position,velocity,destination;public bool launched;}
    readonly List<LiveEffect> liveEffects=new List<LiveEffect>();readonly HashSet<int> seenEffects=new HashSet<int>(),seenAudio=new HashSet<int>();
    readonly Queue<int> effectHistory=new Queue<int>(),audioHistory=new Queue<int>();
    readonly Dictionary<string,AudioClip> audioClips=new Dictionary<string,AudioClip>();readonly Queue<string> clipHistory=new Queue<string>();readonly HashSet<string> audioLoading=new HashSet<string>();
    AudioSource musicSource,jingleSource;readonly List<AudioSource> soundSources=new List<AudioSource>();float musicVolume=.25f,soundVolume=.65f,jingleUntil;int currentMusic=-2,musicRequest,mediaGeneration;int effectsSpawned,projectilesSpawned,attachedSpawned,effectFrames,soundsPlayed,musicPlayed,jinglesPlayed;float audioPeak;readonly float[] audioSamples=new float[512];
    void InitializeMedia(){view.gameObject.AddComponent<AudioListener>();musicSource=gameObject.AddComponent<AudioSource>();musicSource.loop=true;jingleSource=gameObject.AddComponent<AudioSource>();musicVolume=PlayerPrefs.GetFloat("scape.musicVolume",.25f);soundVolume=PlayerPrefs.GetFloat("scape.soundVolume",.65f);}
    static bool Remember(HashSet<int> set,Queue<int> history,int id){if(!set.Add(id))return false;history.Enqueue(id);while(history.Count>512)set.Remove(history.Dequeue());return true;}
    void UpdateMediaEvents(){
        musicVolume=state.musicSetting>=4?0:Mathf.Pow(10,-state.musicSetting*4/20f);soundVolume=state.soundSetting>=4?0:Mathf.Pow(10,-state.soundSetting*4/20f);musicSource.volume=jingleSource.volume=musicVolume;foreach(var sound in soundSources)if(sound)sound.volume=soundVolume;
        if(state.music!=null&&state.music.id!=currentMusic){currentMusic=state.music.id;musicRequest++;if(currentMusic<0){musicSource.Stop();}else StartCoroutine(PlayMusic(currentMusic,musicRequest));}
        foreach(var e in state.audio??Array.Empty<AudioEvent>())if(Remember(seenAudio,audioHistory,e.@event))StartCoroutine(PlaySoundEvent(e));
        foreach(var e in state.effects??Array.Empty<EffectEvent>())SpawnEffect(e,null);
        foreach(var pair in entities){var pick=pair.Value.GetComponent<LostCityPick>();if(pick==null)continue;foreach(var e in pick.actor.effects??Array.Empty<EffectEvent>())SpawnEffect(e,pair.Value.transform);}
    }
    IEnumerator LoadAudio(string kind,int id,int loops,System.Action<AudioClip> done){
        string key=kind+"/"+id+"?loops="+Mathf.Clamp(loops,1,8);int generation=mediaGeneration,epoch=sessionEpoch;
        if(audioClips.TryGetValue(key,out var cached)){done(cached);yield break;}
        while(audioLoading.Contains(key)&&generation==mediaGeneration){yield return null;if(audioClips.TryGetValue(key,out cached)){done(cached);yield break;}}
        if(generation!=mediaGeneration||token==null){done(null);yield break;}audioLoading.Add(key);
        using(var request=UnityWebRequestMultimedia.GetAudioClip(endpoint+"/v1/audio/"+key,AudioType.WAV)){
            request.timeout=60;request.SetRequestHeader("Authorization","Bearer "+token);yield return request.SendWebRequest();audioLoading.Remove(key);
            if(generation!=mediaGeneration||epoch!=sessionEpoch){done(null);yield break;}
            if(request.result!=UnityWebRequest.Result.Success){Debug.LogWarning("SCAPE_AUDIO_UNAVAILABLE "+kind+" id="+id+" status="+request.responseCode);SetNotice("Audio is temporarily unavailable.");done(null);yield break;}
            AudioClip clip=null;try{clip=DownloadHandlerAudioClip.GetContent(request);}catch(Exception){Debug.LogWarning("SCAPE_AUDIO_INVALID "+key);}
            if(clip){audioClips[key]=clip;clipHistory.Enqueue(key);int evictionBudget=clipHistory.Count;while(clipHistory.Count>24&&evictionBudget-->0){string old=clipHistory.Dequeue();if(audioClips.TryGetValue(old,out var prior)&&old!=key&&prior!=musicSource.clip&&prior!=jingleSource.clip&&!soundSources.Exists(a=>a&&a.clip==prior)){Destroy(prior);audioClips.Remove(old);}else clipHistory.Enqueue(old);}}
            done(clip);
        }
    }
    IEnumerator PlayMusic(int id,int requestId){int generation=mediaGeneration;AudioClip clip=null;yield return LoadAudio("music",id,1,c=>clip=c);if(!clip||generation!=mediaGeneration||requestId!=musicRequest)yield break;float initial=musicSource.volume;for(float t=0;t<.35f;t+=Time.unscaledDeltaTime){if(requestId!=musicRequest||generation!=mediaGeneration)yield break;musicSource.volume=Mathf.Lerp(initial,0,t/.35f);yield return null;}musicSource.clip=clip;musicSource.volume=musicVolume;musicSource.Play();if(Time.unscaledTime<jingleUntil)musicSource.Pause();musicPlayed++;Debug.Log("SCAPE_MUSIC_PLAY id="+id+" seconds="+clip.length);}
    IEnumerator PlaySoundEvent(AudioEvent e){int generation=mediaGeneration;float due=Time.unscaledTime+e.delay-Math.Max(0,state.tick-e.tick)*.6f;AudioClip clip=null;yield return LoadAudio(e.kind=="sound"?"sound":"music",e.id,e.loops,c=>clip=c);if(!clip||generation!=mediaGeneration)yield break;
        if(due>Time.unscaledTime)yield return new WaitForSecondsRealtime(due-Time.unscaledTime);if(generation!=mediaGeneration)yield break;
        if(e.kind=="jingle"){musicSource.Pause();jingleSource.clip=clip;jingleSource.volume=musicVolume;jingleSource.Play();jingleUntil=Time.unscaledTime+Mathf.Max(clip.length,e.resumeAfter);jinglesPlayed++;}
        else{float late=Mathf.Max(0,Time.unscaledTime-due);if(late>clip.length+1)yield break;var source=gameObject.AddComponent<AudioSource>();source.clip=clip;source.volume=soundVolume;source.Play();soundSources.Add(source);soundsPlayed++;}
        Debug.Log("SCAPE_AUDIO_PLAY kind="+e.kind+" id="+e.id+" seconds="+clip.length);
    }
    void SpawnEffect(EffectEvent e,Transform anchor){
        if(!Remember(seenEffects,effectHistory,e.@event))return;float age=(state.tick-e.tick)*.6f-e.delay;if(e.sequenceData?.frames!=null&&e.kind!="projectile"){e.duration=0;foreach(var f in e.sequenceData.frames)e.duration+=(Math.Max(1,f.delay)+1)/50f;}
        if(age>e.duration||!models.TryGetValue(e.model,out var prefab))return;
        var root=new GameObject("Original effect "+e.type);var child=Instantiate(prefab,root.transform);Recolour(child,new Part{recolS=e.recolS,recolD=e.recolD},e.model);child.transform.localScale=new Vector3(e.scaleH,e.scaleV,e.scaleH);child.transform.localRotation=Quaternion.Euler(0,e.angle,0);var animator=child.AddComponent<LostCityAnimator>();
        var live=new LiveEffect{data=e,root=root,anchor=anchor,animator=animator,born=Time.unscaledTime-age,position=new Vector3(e.x,e.y,e.z),destination=new Vector3(e.dstX,e.dstY,e.dstZ)};root.SetActive(age>=0);liveEffects.Add(live);effectsSpawned++;if(e.kind=="projectile")projectilesSpawned++;if(e.kind=="attached")attachedSpawned++;Debug.Log("SCAPE_EFFECT_SPAWN kind="+e.kind+" type="+e.type+" model="+e.model);
    }
    void TickMedia(){
        if(!musicSource)return;
        if(jingleUntil>0&&Time.unscaledTime>=jingleUntil){jingleUntil=0;musicSource.UnPause();}
        for(int i=soundSources.Count-1;i>=0;i--)if(!soundSources[i]||!soundSources[i].isPlaying){if(soundSources[i])Destroy(soundSources[i]);soundSources.RemoveAt(i);}
        if(musicSource.isPlaying||jingleSource.isPlaying||soundSources.Count>0){AudioListener.GetOutputData(audioSamples,0);foreach(float sample in audioSamples)audioPeak=Mathf.Max(audioPeak,Mathf.Abs(sample));}
        for(int i=liveEffects.Count-1;i>=0;i--){var live=liveEffects[i];var e=live.data;float age=Time.unscaledTime-live.born;if(age<0)continue;if(age>e.duration||e.kind=="attached"&&!live.anchor){Destroy(live.root);liveEffects.RemoveAt(i);continue;}live.root.SetActive(true);
            if(e.kind=="attached")live.root.transform.position=live.anchor.position+Vector3.up*e.height;
            else if(e.kind=="projectile"){
                Transform target=null;if(e.target>0&&entities.TryGetValue("npc-"+(e.target-1),out var npc))target=npc.transform;else if(e.target<0){int id=-e.target-1;string key=state!=null&&id==state.player.id?"player":"player-"+id;if(entities.TryGetValue(key,out var player))target=player.transform;}
                if(target)live.destination=target.position+Vector3.up*e.dstHeight;
                if(!live.launched){var direction=live.destination-live.position;direction.y=0;if(direction.sqrMagnitude>.0001f)live.position+=direction.normalized*e.arc;float remaining=Mathf.Max(.02f,e.duration);live.velocity=(live.destination-live.position)/remaining;live.velocity.y=new Vector2(live.velocity.x,live.velocity.z).magnitude*Mathf.Tan(e.peak*Mathf.PI/128);live.launched=true;}
                float dt=Mathf.Max(0,age-live.lastElapsed),left=Mathf.Max(.02f,e.duration-live.lastElapsed);live.velocity.x=(live.destination.x-live.position.x)/left;live.velocity.z=(live.destination.z-live.position.z)/left;float acceleration=2*(live.destination.y-live.position.y-live.velocity.y*left)/(left*left);live.position+=live.velocity*dt+Vector3.up*(acceleration*.5f*dt*dt);live.velocity.y+=acceleration*dt;live.lastElapsed=age;live.root.transform.position=live.position;if(live.velocity.sqrMagnitude>.00001f)live.root.transform.rotation=Quaternion.LookRotation(-live.velocity.normalized,Vector3.up);
            }else live.root.transform.position=live.position;
            live.animator.SampleEffect(e.sequenceData,age,e.kind=="projectile");effectFrames++;
        }
    }
    void DrawAudioSettings(){GUILayout.Label("Music volume");float m=GUILayout.HorizontalSlider(musicVolume,0,1);GUILayout.Label("Sound effects volume");float s=GUILayout.HorizontalSlider(soundVolume,0,1);if(m!=musicVolume||s!=soundVolume){musicVolume=m;soundVolume=s;PlayerPrefs.SetFloat("scape.musicVolume",m);PlayerPrefs.SetFloat("scape.soundVolume",s);musicSource.volume=jingleSource.volume=m;foreach(var sound in soundSources)if(sound)sound.volume=s;}}
    void ResetMedia(){mediaGeneration++;musicRequest++;foreach(var fx in liveEffects)Destroy(fx.root);liveEffects.Clear();seenEffects.Clear();effectHistory.Clear();seenAudio.Clear();audioHistory.Clear();if(musicSource)musicSource.Stop();if(jingleSource)jingleSource.Stop();foreach(var source in soundSources)if(source)Destroy(source);soundSources.Clear();currentMusic=-2;jingleUntil=0;}
}
}
