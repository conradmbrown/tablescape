using System.Collections;
using System.Collections.Generic;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    readonly List<GameObject> dyingActors=new List<GameObject>();
    readonly HashSet<int> processedDeaths=new HashSet<int>();
    void ApplyDepartedDeaths(State next,HashSet<string> alive){
        foreach(var actor in next.npcDeaths??System.Array.Empty<Actor>()){
            if(!actor.animDeath||!processedDeaths.Add(actor.animEvent))continue;
            string key="npc-"+actor.id;if(alive.Contains(key))continue;
            Show(key,actor,false,alive);alive.Remove(key);
        }
    }
    int completedDeaths,deathFramesRendered;
    void RetireActor(GameObject root){
        var animator=root.GetComponent<LostCityAnimator>();
        if(animator&&animator.NeedsDeathCompletion){
            // The server owns drops/respawns. Keep only the non-interactive visual
            // long enough to finish the death it already instructed us to play.
            foreach(var collider in root.GetComponentsInChildren<Collider>())collider.enabled=false;
            var pick=root.GetComponent<LostCityPick>();if(pick)pick.enabled=false;
            dyingActors.Add(root);StartCoroutine(FinishDeath(root,animator));
        }else{if(animator&&animator.DeathFinished){completedDeaths++;deathFramesRendered+=animator.DeathFramesSeen;}Destroy(root);}
    }
    IEnumerator FinishDeath(GameObject root,LostCityAnimator animator){
        float deadline=Time.unscaledTime+10;
        while(root&&animator&&!animator.DeathFinished&&Time.unscaledTime<deadline)yield return null;
        if(root&&animator){
            if(animator.DeathFinished){completedDeaths++;deathFramesRendered+=animator.DeathFramesSeen;Debug.Log($"SCAPE_DEATH_COMPLETE sequence={animator.CurrentSequence} frames={animator.DeathFramesSeen}");}
            else Debug.LogWarning("Death sequence unavailable before visual cleanup timeout");
            // Present the terminal pose for a frame before releasing its meshes.
            yield return new WaitForEndOfFrame();dyingActors.Remove(root);Destroy(root);
        }
    }
    void ClearDyingActors(){processedDeaths.Clear();foreach(var root in dyingActors)if(root)Destroy(root);dyingActors.Clear();}
}
}
