using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    sealed class SkillAnimationObservation {
        public bool running=true,captured;public int heldModels,poseChanges;
        public HashSet<string> frames=new HashSet<string>();public HashSet<int> sequences=new HashSet<int>();
    }
    IEnumerator ObserveSkillAnimation(SkillAnimationObservation result,string capture,bool agility){
        Vector3 previous=Vector3.zero;distance=10;
        while(result.running){
            yield return new WaitForEndOfFrame();
            if(!entities.TryGetValue("player",out var player))continue;
            var animator=player.GetComponent<LostCityAnimator>();if(!animator)continue;
            // Log balancing changes the original base walk sequence, not the primary action.
            bool obstacleGait=agility&&state.player.walk!=819&&animator.CurrentSequence==state.player.walk;
            if(!animator.PlayingAction&&!obstacleGait)continue;
            result.frames.Add(animator.CurrentSequence+":"+animator.CurrentFrame);result.sequences.Add(animator.CurrentSequence);
            result.heldModels=Mathf.Max(result.heldModels,animator.HeldModelCount);
            Vector3 pose=Vector3.zero;foreach(var mesh in player.GetComponentsInChildren<MeshFilter>())pose+=mesh.sharedMesh.bounds.center+mesh.sharedMesh.bounds.size;
            if((pose-previous).sqrMagnitude>.0000001f)result.poseChanges++;previous=pose;
            if(!result.captured&&result.frames.Count>=3&&result.poseChanges>2){
                result.captured=true;var image=new Texture2D(Screen.width,Screen.height,TextureFormat.RGB24,false);image.ReadPixels(new Rect(0,0,Screen.width,Screen.height),0,0);image.Apply();File.WriteAllBytes(capture+".png",image.EncodeToPNG());Destroy(image);
                Debug.Log("SCAPE_SKILL_ANIMATION "+capture+" sequence="+animator.CurrentSequence+" held="+animator.HeldModelCount);
            }
        }
    }
}
}
