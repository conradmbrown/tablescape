using System;
using System.Collections.Generic;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    sealed class FloatingHit {public Hit hit;public float until;}
    sealed class CombatView {public int seen;public float until;public List<FloatingHit> hits=new List<FloatingHit>();}
    sealed class MenuEntry {public string label;public System.Action invoke;}
    readonly Dictionary<string,CombatView> combatViews=new Dictionary<string,CombatView>();
    readonly List<MenuEntry> menu=new List<MenuEntry>();
    List<LostCityPick> rightTargets=new List<LostCityPick>();Vector3 rightPoint;
    Texture2D hitSprites,crossSprites;GUIStyle overheadStyle,hoverStyle;LostCityPick hover;Vector3 hoverPoint;Vector2 rightStart,menuOrigin,clickPoint;Rect menuRect;bool rightDragging,menuOpen;float clickAt=-10,noticeUntil;bool clickAction;int receivedHits,drawnHits,drawnBars,clickMarkers,menusOpened;string hoverText="";
    void InitializeFeedback(){hitSprites=ReadFeedbackSprite("hitmarks");crossSprites=ReadFeedbackSprite("cross");}
    Texture2D ReadFeedbackSprite(string name){
        var source=Resources.Load<TextAsset>("Feedback/"+name+"-source");if(!source)return null;
        var texture=new Texture2D(2,2,TextureFormat.RGBA32,false);texture.LoadImage(source.bytes,false);var pixels=texture.GetPixels32();
        for(int i=0;i<pixels.Length;i++)if(pixels[i].r==255&&pixels[i].g==0&&pixels[i].b==255)pixels[i]=new Color32(0,0,0,0);
        // Explicit RGBA output prevents import-time opaque-image optimisation dropping the key's alpha.
        var keyed=new Texture2D(texture.width,texture.height,TextureFormat.RGBA32,false){filterMode=FilterMode.Point,wrapMode=TextureWrapMode.Clamp};keyed.SetPixels32(pixels);keyed.Apply(false,false);Destroy(texture);return keyed;
    }
    void SetNotice(string text){notice=text;noticeUntil=Time.unscaledTime+4;}
    void MarkClick(Vector2 point,bool action){clickPoint=point;clickAction=action;clickAt=Time.unscaledTime;clickMarkers++;}
    void ResetFeedback(){combatViews.Clear();menu.Clear();menuOpen=false;hover=null;hoverText="";notice="";}
    void UpdateCombatFeedback(){
        foreach(var pair in entities){if(pair.Key!="player"&&!pair.Key.StartsWith("npc-")&&!pair.Key.StartsWith("player-"))continue;var a=pair.Value.GetComponent<LostCityPick>().actor;
            if(!combatViews.TryGetValue(pair.Key,out var c)){c=new CombatView();combatViews[pair.Key]=c;}
            foreach(var hit in a.hits??Array.Empty<Hit>()){if(hit.id<=c.seen)continue;c.seen=hit.id;int age=state.tick-hit.tick;if(age>6)continue;c.until=Time.unscaledTime+Mathf.Max(.1f,4.2f-age*.6f);c.hits.Add(new FloatingHit{hit=hit,until=Time.unscaledTime+Mathf.Max(.1f,1.8f-age*.6f)});receivedHits++;}
            c.hits.RemoveAll(h=>h.until<Time.unscaledTime);if(c.hits.Count>4)c.hits.RemoveRange(0,c.hits.Count-4);
        }
        var remove=new List<string>();foreach(var p in combatViews)if(!entities.ContainsKey(p.Key))remove.Add(p.Key);foreach(var key in remove)combatViews.Remove(key);
    }
    string ActorLabel(Actor a)=>Plain(a.name)+(a.combatLevel>0?" (level-"+a.combatLevel+")":"");
    string HoverLabel(LostCityPick pick){if(!pick)return "Walk here";var a=pick.actor;if(selectedItem!=null)return "Use "+selectedItem.name+" → "+ActorLabel(a);if(selectedSpell!=null)return "Cast "+Plain(selectedSpell.action)+" → "+ActorLabel(a);int op=Array.FindIndex(a.ops??Array.Empty<string>(),v=>!string.IsNullOrEmpty(v));return (op<0?"Walk here ·":a.ops[op])+" "+ActorLabel(a);}
    List<LostCityPick> PointerTargets(Vector2 mouse,out Vector3 ground){
        var hits=Physics.RaycastAll(view.ScreenPointToRay(mouse),250);Array.Sort(hits,(a,b)=>a.distance.CompareTo(b.distance));var result=new List<LostCityPick>();ground=Vector3.zero;float nearest=hits.Length>0?hits[0].distance:0;
        foreach(var hit in hits){if(ground==Vector3.zero)ground=hit.point;var pick=hit.collider.GetComponentInParent<LostCityPick>();if(!pick){ground=hit.point;break;}if(hit.distance>nearest+3)break;if(pick.gameObject==entities["player"]||result.Contains(pick))continue;result.Add(pick);if(result.Count>=4)break;}return result;
    }
    void UpdateInteraction(){
        Vector2 mouse=Input.mousePosition,gui=new Vector2(mouse.x,Screen.height-mouse.y);bool world=!PointerOverInterface();
        if(menuOpen){
            hover=null;hoverText="";
            if(Input.GetMouseButtonDown(1)){menuOpen=false;menu.Clear();} // Retarget this same click below.
            else{if(Input.GetKeyDown(KeyCode.Escape)||(Input.GetMouseButtonDown(0)&&!menuRect.Contains(gui)))menuOpen=false;return;}
        }
        var picks=world?PointerTargets(mouse,out hoverPoint):new List<LostCityPick>();hover=picks.Count>0?picks[0]:null;hoverText=world?HoverLabel(hover):"";if(hover&&world)worldHoverSeen++;
        if(Input.GetMouseButtonDown(1)){rightStart=mouse;rightDragging=false;rightTargets=picks;rightPoint=hoverPoint;}
        if(Input.GetMouseButton(1)&&Vector2.Distance(mouse,rightStart)>5)rightDragging=true;
        if(Input.GetMouseButtonUp(1)){if(world&&!rightDragging)OpenMenu(rightTargets.FindAll(p=>p),rightPoint,gui);rightDragging=false;}
        if(world&&Input.GetMouseButtonDown(0)){if(hoverPoint==Vector3.zero)return;if(hover&&(selectedItem!=null||selectedSpell!=null||Array.Exists(hover.actor.ops??Array.Empty<string>(),v=>!string.IsNullOrEmpty(v)))){int op=Array.FindIndex(hover.actor.ops??Array.Empty<string>(),v=>!string.IsNullOrEmpty(v));MarkClick(gui,true);string label=HoverLabel(hover);Target(hover.kind,hover.actor,Math.Max(1,op+1));SetNotice("Queued: "+label);}else{MarkClick(gui,false);Send(new Action{kind="move",x=Mathf.FloorToInt(hoverPoint.x),z=Mathf.FloorToInt(hoverPoint.z),run=runEnabled});}}
    }
    void OpenMenu(List<LostCityPick> picks,Vector3 point,Vector2 origin){
        menu.Clear();menuOrigin=origin;
        foreach(var pick in picks){var saved=pick;var actor=pick.actor;string label=ActorLabel(actor);
            if(selectedItem!=null||selectedSpell!=null)menu.Add(new MenuEntry{label=HoverLabel(pick),invoke=()=>{if(saved){MarkClick(menuOrigin,true);Target(saved.kind,saved.actor,1);}}});
            else for(int i=0;i<(actor.ops?.Length??0);i++){int op=i+1;string verb=actor.ops[i];if(string.IsNullOrEmpty(verb))continue;menu.Add(new MenuEntry{label=verb+" "+label,invoke=()=>{if(saved){MarkClick(menuOrigin,true);Target(saved.kind,saved.actor,op);SetNotice("Queued: "+verb+" "+label);}else SetNotice("That target is no longer here");}});}
            menu.Add(new MenuEntry{label="Examine "+label,invoke=()=>SetNotice(string.IsNullOrEmpty(actor.description)?label:Plain(actor.description))});
        }
        if(point!=Vector3.zero)menu.Add(new MenuEntry{label="Walk here",invoke=()=>{selectedItem=null;selectedSpell=null;MarkClick(menuOrigin,false);Send(new Action{kind="move",x=Mathf.FloorToInt(point.x),z=Mathf.FloorToInt(point.z),run=runEnabled});}});
        ShowContextMenu(origin);
    }
    void DrawFeedback(){
        if(state==null||!view)return;if(overheadStyle==null){overheadStyle=new GUIStyle(GUI.skin.label){alignment=TextAnchor.MiddleCenter,fontSize=13,fontStyle=FontStyle.Bold};overheadStyle.normal.textColor=Color.white;hoverStyle=new GUIStyle(GUI.skin.box){alignment=TextAnchor.MiddleLeft,fontSize=14};}
        foreach(var pair in combatViews){if(!entities.TryGetValue(pair.Key,out var actor))continue;var pick=actor.GetComponent<LostCityPick>();var c=pair.Value;if(Time.unscaledTime>=c.until&&c.hits.Count==0)continue;var bounds=new Bounds(actor.transform.position,Vector3.zero);foreach(var renderer in actor.GetComponentsInChildren<Renderer>())bounds.Encapsulate(renderer.bounds);Vector3 p=view.WorldToScreenPoint(new Vector3(bounds.center.x,bounds.max.y+.25f,bounds.center.z));if(p.z<0||p.x<0||p.x>Screen.width-370)continue;float y=Screen.height-p.y;
            if(pick.actor.maxHp>0&&Time.unscaledTime<c.until){var rect=new Rect(p.x-24,y-9,48,6);GUI.color=Color.black;GUI.DrawTexture(new Rect(rect.x-1,rect.y-1,50,8),Texture2D.whiteTexture);GUI.color=new Color(.65f,0,0);GUI.DrawTexture(rect,Texture2D.whiteTexture);GUI.color=Color.green;GUI.DrawTexture(new Rect(rect.x,rect.y,48*Mathf.Clamp01((float)pick.actor.hp/pick.actor.maxHp),6),Texture2D.whiteTexture);GUI.color=Color.white;drawnBars++;}
            int slot=0;foreach(var hit in c.hits){if(hit.until<Time.unscaledTime)continue;var rect=new Rect(p.x-16+(slot%2)*23-10,y+6+(slot/2)*23,32,32);if(hitSprites)GUI.DrawTextureWithTexCoords(rect,hitSprites,new Rect(Mathf.Clamp(hit.hit.type,0,2)/3f,0,1/3f,1));GUI.Label(rect,hit.hit.damage.ToString(),overheadStyle);slot++;drawnHits++;}
        }
        if(hoverText.Length>0&&!menuOpen)GUI.Box(new Rect(12,10,Mathf.Min(600,Screen.width-24),26),hoverText,hoverStyle);
        if(Time.unscaledTime<noticeUntil)GUI.Box(new Rect(18,ChatRect.y-30,Screen.width-400,26),notice,hoverStyle);
        float elapsed=Time.unscaledTime-clickAt;if(elapsed>=0&&elapsed<.6f&&crossSprites)GUI.DrawTextureWithTexCoords(new Rect(clickPoint.x-16,clickPoint.y-16,32,32),crossSprites,new Rect(Mathf.Min(3,(int)(elapsed/.15f))*.25f,clickAction?0:.5f,.25f,.5f));
        if(menuOpen){GUI.depth=-50;FillRect(menuRect,new Color32(93,84,71,255));FillRect(new Rect(menuRect.x+2,menuRect.y+2,menuRect.width-4,23),Color.black);GUI.Label(new Rect(menuRect.x+8,menuRect.y+3,314,24),"Choose option",classicMenuHeader);for(int i=0;i<menu.Count;i++){var row=new Rect(menuRect.x+5,menuRect.y+27+i*24,320,23);var style=row.Contains(Event.current.mousePosition)?classicMenuHover:classicMenuItem;GUI.Label(row,menu[i].label,style);}GUI.depth=0;}

    }
}
}
