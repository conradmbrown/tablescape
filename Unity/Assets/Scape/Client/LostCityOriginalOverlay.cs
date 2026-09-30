using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Networking;
namespace Scape.Client {
public sealed partial class LostCityClient {
    [Serializable] public class OriginalOverlay {public int root,width,height;public OverlayNode[] nodes;}
    [Serializable] public class OverlayNode {public int id,type,x,y,width,height,button,font,colour,overColour,model;public bool center,shadow;public string text,image;}
    [Serializable] class BitmapGlyph {public int x,y,w,h,offsetX,offsetY,advance;}
    [Serializable] class BitmapFont {public int height;public BitmapGlyph[] glyphs;}
    [Serializable] class BitmapFonts {public BitmapFont[] fonts;}
    BitmapFonts overlayFonts;Texture2D[] overlayFontAtlases;
    readonly Dictionary<string,Texture2D> overlayImages=new Dictionary<string,Texture2D>();
    readonly HashSet<string> overlayLoading=new HashSet<string>();readonly Dictionary<string,float> overlayRetry=new Dictionary<string,float>();
    int originalOverlayDraws;Vector2 overlayCloseScreen;
    bool HasOriginalOverlay=>state?.overlay?.nodes!=null&&state.overlay.root==state.mainRoot;
    Rect OriginalOverlayRect {get {float availableWidth=Mathf.Max(100,Screen.width-390),availableHeight=Mathf.Max(100,ChatRect.y-75);float scale=Mathf.Min(1.5f,availableWidth/512f,availableHeight/334f);return new Rect(10+(availableWidth-512*scale)/2,65+(availableHeight-334*scale)/2,512*scale,334*scale);}}
    void UpdateOriginalOverlay(){
        if(overlayFonts==null){var data=Resources.Load<TextAsset>("Overlays/fonts");if(!data)return;overlayFonts=JsonUtility.FromJson<BitmapFonts>(data.text);overlayFontAtlases=new Texture2D[overlayFonts.fonts.Length];for(int i=0;i<overlayFontAtlases.Length;i++)overlayFontAtlases[i]=Resources.Load<Texture2D>("Overlays/font-"+i);}
        if(!HasOriginalOverlay)return;
        foreach(var node in state.overlay.nodes)if(node.type==6&&!string.IsNullOrEmpty(node.image)&&!overlayImages.ContainsKey(node.image)&&!overlayLoading.Contains(node.image)&&(!overlayRetry.TryGetValue(node.image,out float retry)||Time.unscaledTime>=retry))StartCoroutine(LoadOverlayImage(node.image));
    }
    IEnumerator LoadOverlayImage(string key){int epoch=sessionEpoch;overlayLoading.Add(key);
        using(var request=UnityWebRequestTexture.GetTexture(endpoint+"/v1/overlay/"+key)){request.timeout=15;request.SetRequestHeader("Authorization","Bearer "+token);yield return request.SendWebRequest();overlayLoading.Remove(key);
            if(epoch!=sessionEpoch||token==null)yield break;
            if(request.result!=UnityWebRequest.Result.Success){overlayRetry[key]=Time.unscaledTime+5;Debug.LogWarning("SCAPE_OVERLAY_IMAGE_UNAVAILABLE status="+request.responseCode);yield break;}
            var texture=DownloadHandlerTexture.GetContent(request);texture.filterMode=FilterMode.Point;texture.wrapMode=TextureWrapMode.Clamp;
            if(overlayImages.Count>=32){var keep=new HashSet<string>();foreach(var n in state.overlay?.nodes??Array.Empty<OverlayNode>())if(n.image!=null)keep.Add(n.image);foreach(var old in new List<string>(overlayImages.Keys))if(!keep.Contains(old)){Destroy(overlayImages[old]);overlayImages.Remove(old);}}
            overlayImages[key]=texture;
        }
    }
    static Color OverlayColour(int rgb)=>new Color32((byte)(rgb>>16),(byte)(rgb>>8),(byte)rgb,255);
    int BitmapWidth(string text,BitmapFont font){int width=0;for(int i=0;i<text.Length;i++){if(text[i]=='@'&&i+4<text.Length&&text[i+4]=='@'){i+=4;continue;}width+=font.glyphs[Math.Min(255,(int)text[i])].advance;}return width;}
    void DrawBitmapText(OverlayNode node,bool hovered){
        int id=Mathf.Clamp(node.font,0,overlayFonts.fonts.Length-1);var font=overlayFonts.fonts[id];var atlas=overlayFontAtlases[id];if(!atlas)return;
        float y=node.y;foreach(string line in (node.text??"").Replace("\\n","\n").Split('\n')){
            float x=node.center?node.x+node.width/2-BitmapWidth(line,font)/2:node.x;Color colour=OverlayColour(hovered&&node.overColour!=0?node.overColour:node.colour);bool strike=false;float start=x;
            for(int i=0;i<line.Length;i++){
                if(line[i]=='@'&&i+4<line.Length&&line[i+4]=='@'){string tag=line.Substring(i+1,3);switch(tag){case "red":colour=Color.red;break;case "gre":colour=Color.green;break;case "blu":colour=Color.blue;break;case "yel":colour=Color.yellow;break;case "whi":colour=Color.white;break;case "bla":colour=Color.black;break;case "cya":colour=Color.cyan;break;case "mag":colour=Color.magenta;break;case "lre":colour=OverlayColour(0xff9040);break;case "dre":colour=OverlayColour(0x800000);break;case "str":strike=true;break;case "end":strike=false;break;}i+=4;continue;}
                int c=Math.Min(255,(int)line[i]);var g=font.glyphs[c];if(c!=32&&g.w>0&&g.h>0){var r=new Rect(x+g.offsetX,y+g.offsetY,g.w,g.h);var uv=new Rect(g.x/512f,1-(g.y+g.h)/512f,g.w/512f,g.h/512f);if(node.shadow){GUI.color=Color.black;GUI.DrawTextureWithTexCoords(new Rect(r.x+1,r.y+1,r.width,r.height),atlas,uv,true);}GUI.color=colour;GUI.DrawTextureWithTexCoords(r,atlas,uv,true);}x+=g.advance;
            }GUI.color=Color.white;if(strike)FillRect(new Rect(start,y+font.height*.7f,x-start,1),OverlayColour(0x800000));y+=font.height;
        }
    }
    bool OverlayAssetsReady(){if(!HasOriginalOverlay||overlayFonts==null)return false;foreach(var n in state.overlay.nodes)if(n.type==6&&!overlayImages.ContainsKey(n.image))return false;return true;}
    bool DrawOriginalOverlay(){
        if(!HasOriginalOverlay||overlayFonts==null)return false;
        var area=OriginalOverlayRect;var previous=GUI.matrix;var oldColour=GUI.color;GUI.matrix=Matrix4x4.TRS(new Vector3(area.x,area.y,0),Quaternion.identity,new Vector3(area.width/512f,area.height/334f,1));GUI.color=Color.white;
        foreach(var n in state.overlay.nodes){
            if(n.type==6){if(overlayImages.TryGetValue(n.image,out var texture))GUI.DrawTexture(new Rect(0,0,512,334),texture,ScaleMode.StretchToFill,true);continue;}
            var hit=new Rect(n.x,n.y,n.width,Math.Max(n.height,overlayFonts.fonts[Mathf.Clamp(n.font,0,3)].height));bool hovered=hit.Contains(Event.current.mousePosition);
            DrawBitmapText(n,hovered);GUI.color=Color.white;
            if(n.button>0){if(n.button==3&&Event.current.type==EventType.Repaint)overlayCloseScreen=new Vector2(area.x+hit.center.x*area.width/512f,area.y+hit.center.y*area.height/334f);if(GUI.Button(hit,GUIContent.none,GUIStyle.none)){var widget=Array.Find(state.ui,w=>w.id==n.id);if(widget!=null)WidgetButton(widget);}}
        }
        GUI.matrix=previous;GUI.color=oldColour;if(Event.current.type==EventType.Repaint)originalOverlayDraws++;
        if(Event.current.type==EventType.KeyDown&&Event.current.keyCode==KeyCode.Escape){Send(new Action{kind="close"});Event.current.Use();}
        return true;
    }
}
}
