using System;
using System.Collections;
using System.IO;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    bool capturedProjectile,capturedTeleport;
    IEnumerator WatchMediaCaptures(){while(token!=null){if(!capturedProjectile&&liveEffects.Exists(f=>f.data.kind=="projectile"&&f.root.activeSelf)){capturedProjectile=true;yield return CapturePlay("-projectile");}if(!capturedTeleport&&liveEffects.Exists(f=>f.data.type==111&&f.root.activeSelf)){capturedTeleport=true;yield return CapturePlay("-teleport");}yield return null;}}
    IEnumerator MediaSmoke(){
        foreach(string arg in Environment.GetCommandLineArgs()){if(arg.StartsWith("--scape-capture="))captureBase=arg.Substring(16);if(arg.StartsWith("--scape-test-user="))username=arg.Substring(18);}
        StartCoroutine(Join());yield return AwaitState(()=>state!=null,40,"media_login");if(smokeFailed){Application.Quit(1);yield break;}
        yield return AwaitState(()=>chunks.Count>=9&&!connectionPaused,60,"media_world");StartCoroutine(WatchMediaCaptures());
        yield return AwaitState(()=>musicPlayed>0&&musicSource.isPlaying&&audioPeak>.00001f,60,"original_music_mixed_output");
        int magicXp=state.experience[6];var man=SkillTarget(new SkillStep{target="npc",name="Man",operation="Attack"});var spell=Array.Find(state.ui,w=>w.id==1152);
        if(man==null||spell==null){Debug.LogError("SCAPE_MEDIA_FAILED missing normal spell target");yield return Logout();Application.Quit(1);yield break;}
        File.WriteAllText(captureBase+"-before.json",JsonUtility.ToJson(state,true));
        Debug.Log("SCAPE_MEDIA_TARGET npc="+man.id+" x="+man.x+" z="+man.z);
        FocusTestWidget(spell);WidgetButton(spell);Target("npc",man,Array.IndexOf(man.ops,"Attack")+1);
        yield return AwaitState(()=>projectilesSpawned>0&&attachedSpawned>0&&effectFrames>5&&state.experience[6]>magicXp&&soundsPlayed>0,35,"wind_strike_original_effects_and_sound");
        Send(new Action{kind="move",x=(int)state.player.x-10,z=(int)state.player.z-8});yield return new WaitForSeconds(15);
        int law=ItemCount(563),fx=attachedSpawned,sounds=soundsPlayed;var teleport=Array.Find(state.ui,w=>w.id==1167);FocusTestWidget(teleport);WidgetButton(teleport);
        yield return AwaitState(()=>state.player.x>=3218&&state.player.x<=3225&&state.player.z>=3215&&state.player.z<=3222&&ItemCount(563)==law-1&&attachedSpawned>fx&&soundsPlayed>sounds&&capturedTeleport,25,"lumbridge_teleport_runes_effect_and_sound");
        yield return AwaitState(()=>!state.busy,8,"teleport_action_complete");
        yield return AwaitState(()=>state.tutorialRoot<0&&!Array.Exists(state.ui,w=>(w.text??"").Contains("Unhandled Tutorial")),5,"completed_tutorial_stays_closed_after_tab_changes");
        int beforeJingle=jinglesPlayed;
        for(int i=0;i<20&&state.baseLevels[5]<2;i++){var bone=FindItem(526);if(bone==null)break;int count=ItemCount(526);Held(bone,1);yield return AwaitState(()=>ItemCount(526)<count,5,"bury_bone_"+i);yield return new WaitForSeconds(.65f);}
        yield return AwaitState(()=>state.baseLevels[5]>=2&&jinglesPlayed>beforeJingle&&jingleSource.isPlaying,45,"original_level_up_jingle");yield return CapturePlay("-level-up");
        yield return AwaitState(()=>jingleUntil==0&&musicSource.isPlaying,35,"music_resumes_after_jingle");
        File.WriteAllText(captureBase+"-metrics.json",$"{{\"passed\":{(!smokeFailed).ToString().ToLowerInvariant()},\"effects\":{effectsSpawned},\"projectiles\":{projectilesSpawned},\"attached\":{attachedSpawned},\"effectFrames\":{effectFrames},\"sounds\":{soundsPlayed},\"songs\":{musicPlayed},\"jingles\":{jinglesPlayed},\"audioPeak\":{audioPeak.ToString(System.Globalization.CultureInfo.InvariantCulture)},\"capturedProjectile\":{capturedProjectile.ToString().ToLowerInvariant()},\"capturedTeleport\":{capturedTeleport.ToString().ToLowerInvariant()}}}");
        Debug.Log("SCAPE_MEDIA_"+(smokeFailed?"FAILED":"PASSED")+" effects="+effectsSpawned+" projectiles="+projectilesSpawned+" sounds="+soundsPlayed+" music="+musicPlayed+" jingles="+jinglesPlayed+" audioPeak="+audioPeak);
        yield return Logout();Application.Quit(smokeFailed?1:0);
    }
}
}
