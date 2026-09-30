using System;
using System.Collections;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    bool GroundItemVisible(Actor item){
        if(item==null||!entities.TryGetValue("obj-"+item.key,out var root))return false;
        var renderers=root.GetComponentsInChildren<Renderer>();bool geometry=false,visible=false;
        foreach(var r in renderers){geometry|=r.bounds.size.sqrMagnitude>.00001f;visible|=r.isVisible;}
        float surface=float.MinValue;foreach(var hit in Physics.RaycastAll(root.transform.position+Vector3.up,Vector3.down,2,1<<8))if(hit.collider.name.StartsWith("Ground texture "))surface=Mathf.Max(surface,hit.point.y);
        bool above=surface>float.MinValue&&root.transform.position.y>=surface+.009f;
        Debug.Log($"SCAPE_GROUND_ITEM id={item.id} tile={item.x},{item.z} serverY={item.y} renderedY={root.transform.position.y} terrainY={surface} geometry={geometry} visible={visible} above={above}");
        return geometry&&visible&&above;
    }
    IEnumerator GroundItemSmoke(){
        foreach(string arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-test-user="))username=arg.Substring("--scape-test-user=".Length);
        foreach(string arg in Environment.GetCommandLineArgs())if(arg.StartsWith("--scape-capture="))captureBase=arg.Substring("--scape-capture=".Length);
        StartCoroutine(Join());yield return AwaitState(()=>state!=null&&!terrainBusy&&chunks.Count>=49,150,"loot_world_ready");
        if(smokeFailed){Application.Quit(1);yield break;}
        distance=9;pitch=65;yaw=0;
        var victim=SkillTarget(new SkillStep{target="npc",name="Man",operation="Attack"});
        if(victim==null){Debug.LogError("SCAPE_LOOT_FAILED no combat target");Application.Quit(1);yield break;}
        int npcId=victim.id;Target("npc",victim,Array.IndexOf(victim.ops,"Attack")+1);
        yield return AwaitState(()=>!Array.Exists(state.npcs,n=>n.id==npcId)&&Array.Exists(state.objects,o=>o.id==526),75,"npc_death_produces_bones");
        if(smokeFailed){Application.Quit(1);yield break;}
        var bones=Array.Find(state.objects,o=>o.id==526);yield return new WaitForSeconds(1);
        bool deathVisible=GroundItemVisible(bones);Debug.Log("SCAPE_LOOT_DEATH_VISIBLE "+deathVisible);
        captureBase=System.IO.Path.Combine(System.IO.Path.GetDirectoryName(captureBase??"/tmp/loot"),"loot-death");yield return CapturePlay("");
        Target("obj",bones,3);yield return AwaitState(()=>FindItem(526)!=null,20,"take_npc_bones");
        Send(new Action{kind="move",x=3242,z=3241});yield return AwaitState(()=>state.player.x==3242&&state.player.z==3241&&!state.busy,45,"reach_sloped_drop_tile");
        var held=FindItem(526);if(held!=null)Held(held,5);
        yield return AwaitState(()=>FindItem(526)==null&&Array.Exists(state.objects,o=>o.id==526&&o.x==3242&&o.z==3241),15,"drop_bones_on_slope");
        Send(new Action{kind="move",x=3240,z=3241});yield return AwaitState(()=>state.player.x==3240&&state.player.z==3241,20,"step_away_from_drop");yield return new WaitForSeconds(1);
        bones=Array.Find(state.objects,o=>o.id==526&&o.x==3242&&o.z==3241);bool slopeVisible=GroundItemVisible(bones);
        bool pickable=false;if(bones!=null&&entities.TryGetValue("obj-"+bones.key,out var itemRoot)){
            var renderer=itemRoot.GetComponentInChildren<Renderer>();var screen=view.WorldToScreenPoint(renderer.bounds.center);
            pickable=PointerTargets(new Vector2(screen.x,screen.y),out var point).Exists(p=>p.kind=="obj"&&p.actor.id==526);
        }
        yield return CapturePlay("-slope");if(bones!=null)Target("obj",bones,3);yield return AwaitState(()=>FindItem(526)!=null&&!Array.Exists(state.objects,o=>o.id==526&&o.x==3242&&o.z==3241),20,"take_sloped_bones");
        bool pass=!smokeFailed&&deathVisible&&slopeVisible&&pickable;Debug.Log($"SCAPE_LOOT_{(pass?"PASSED":"FAILED")} deathVisible={deathVisible} slopeVisible={slopeVisible} pickable={pickable}");
        yield return Logout();Application.Quit(pass?0:1);
    }
}
}
