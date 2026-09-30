using System;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    [Serializable] public class DialogueHead {public int root,component,npc,sequence=-1,xan,yan,zoom;public string kind;public Part[] parts;}
    GameObject dialogueHeadModel;Camera dialogueHeadCamera;RenderTexture dialogueHeadTexture;
    string dialogueHeadSignature;int dialogueHeadDraws;
    void ClearDialogueHead(){if(dialogueHeadModel){dialogueHeadModel.SetActive(false);Destroy(dialogueHeadModel);}dialogueHeadModel=null;dialogueHeadSignature=null;if(dialogueHeadCamera)dialogueHeadCamera.enabled=false;}
    void DisposeDialogueHead(){ClearDialogueHead();if(dialogueHeadCamera)Destroy(dialogueHeadCamera.gameObject);if(dialogueHeadTexture){dialogueHeadTexture.Release();Destroy(dialogueHeadTexture);}}
    void UpdateDialogueHead(){
        var head=state?.dialogueHead;if(head==null||string.IsNullOrEmpty(head.kind)||state.chatRoot<0||head.root!=state.chatRoot){ClearDialogueHead();return;}
        string signature=JsonUtility.ToJson(head);if(signature==dialogueHeadSignature)return;
        ClearDialogueHead();dialogueHeadSignature=signature;
        if(!dialogueHeadCamera){
            dialogueHeadTexture=new RenderTexture(256,256,24,RenderTextureFormat.ARGB32);dialogueHeadTexture.name="Original dialogue portrait";dialogueHeadTexture.Create();
            dialogueHeadCamera=new GameObject("Dialogue portrait camera").AddComponent<Camera>();dialogueHeadCamera.targetTexture=dialogueHeadTexture;dialogueHeadCamera.cullingMask=1<<10;
            dialogueHeadCamera.clearFlags=CameraClearFlags.SolidColor;dialogueHeadCamera.backgroundColor=Color.clear;dialogueHeadCamera.nearClipPlane=.01f;dialogueHeadCamera.farClipPlane=20;dialogueHeadCamera.orthographic=true;
        }
        dialogueHeadModel=new GameObject("Original "+head.kind+" chat head");dialogueHeadModel.transform.position=new Vector3(0,-1000,0);
        foreach(var part in head.parts??Array.Empty<Part>())foreach(int id in part.models??Array.Empty<int>()){
            if(!models.TryGetValue(id,out var prefab)){Debug.LogWarning("Dialogue head model unavailable: "+id);continue;}
            var child=Instantiate(prefab,dialogueHeadModel.transform);Recolour(child,part,id);
            foreach(var t in child.GetComponentsInChildren<Transform>())t.gameObject.layer=10;
        }
        // Cache models face -Z. Original interface angles turn NPC and player heads
        // inward from opposite sides of the chat box; keep their authentic head meshes.
        dialogueHeadModel.transform.rotation=Quaternion.Euler(0,head.yan*360f/2048f,0);
        var renderers=dialogueHeadModel.GetComponentsInChildren<Renderer>();if(renderers.Length==0){ClearDialogueHead();return;}
        var bounds=renderers[0].bounds;foreach(var renderer in renderers)bounds.Encapsulate(renderer.bounds);
        dialogueHeadCamera.orthographicSize=Mathf.Max(bounds.extents.y,bounds.extents.x)*1.3f;
        dialogueHeadCamera.transform.rotation=Quaternion.Euler(head.xan*360f/2048f,0,0);
        dialogueHeadCamera.transform.position=bounds.center-dialogueHeadCamera.transform.forward*5;
        var animator=dialogueHeadModel.AddComponent<LostCityAnimator>();animator.client=this;animator.actor=new Actor{ready=head.sequence};
        dialogueHeadCamera.enabled=true;
    }
    float DrawDialogueHead(Rect chat){
        if(!dialogueHeadModel||!dialogueHeadTexture||state?.dialogueHead==null)return 0;
        float size=Mathf.Min(chat.height-12,146);bool player=state.dialogueHead.kind=="player";
        var rect=new Rect(player?chat.xMax-size-6:chat.x+6,chat.y+(chat.height-size)/2,size,size);
        GUI.DrawTexture(rect,dialogueHeadTexture,ScaleMode.ScaleToFit,true);if(Event.current.type==EventType.Repaint)dialogueHeadDraws++;
        return size+6;
    }
}
}
